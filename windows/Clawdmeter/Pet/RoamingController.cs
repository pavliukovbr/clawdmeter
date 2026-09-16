using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using Clawdmeter.Activity;
using Clawdmeter.Usage;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;

namespace Clawdmeter.Pet;

/// Lets Clawd out onto the desktop. He climbs up from the taskbar next to the clock,
/// drops onto windows, rides them when you drag them, falls when they close, jumps
/// between them and now and then pretends to be something else on the screen.
/// There is only ever one Clawd: while he is out, his spot on the taskbar stays empty.
public sealed class RoamingController : IDisposable
{
    private enum Mode { Away, Falling, Walking, Idle, Jumping, Disguised, Resting, Swinging, Partying }

    private sealed class Jump
    {
        public Point From;
        public Point To;
        public int Target;
        public double Start;
        public double Duration;
        public double Height;
    }

    private sealed class Disguise
    {
        public ClawdLook Look;
        public double Until;
        public Point Return;
        public int? WindowId;
        public Point From;
        public double Start;
        public double Travel;
    }

    /// Web slinging: a pendulum from an anchor under the top of the screen, then the next one.
    private sealed class Swing
    {
        public double Direction;
        public Point Anchor;
        public double Length;
        public double Angle;
        public double Start;
        public Point? ZipFrom;
        public int Count;
    }

    private const double CaptionButton = 46;
    private const double WalkSpeed = 36;
    private const double HurrySpeed = 110;
    private const double ScanEvery = 0.5;
    private const double StuckAfter = 2;

    private readonly ClaudeActivityWatcher watcher;
    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    private readonly Stopwatch clock = new();
    private readonly DispatcherTimer presence = new(DispatcherPriority.Background)
    {
        Interval = TimeSpan.FromSeconds(1),
    };

    private readonly LineGeometry rope = new();
    private readonly LineGeometry[] spokes = { new(), new(), new(), new() };
    private readonly List<UIElement> partyProps = new();

    private PetWindow? window;
    private RoamingSprite? sprite;
    private Path? web;
    private List<Surface> surfaces = new();
    private Surface? standing;

    private Mode mode = Mode.Away;
    private Point position;
    private double fallSpeed;
    private double driftX;
    private double direction = 1;
    private double walkTarget;
    private double walkSpeed = WalkSpeed;
    private double decideAt;
    private double lastScan;
    private double lastFrame;
    private double homeDeadline;
    private double partyUntil;
    private double nextDisguise;
    private double nextLogo;
    private double pettedUntil;
    private double? hoverSince;
    private double? stuckSince;

    private Jump? jump;
    private Disguise? disguise;
    private Swing? swing;
    private bool finishingEgg;
    private bool partyPending;
    private bool goingHome;
    private bool leaving;
    private bool stepping;
    private bool running;

    private DateTimeOffset quietSince = DateTimeOffset.Now;
    private DateTimeOffset stayHomeUntil = DateTimeOffset.MinValue;
    private DateTimeOffset lastTransition = DateTimeOffset.MinValue;
    private DateTimeOffset easterEggUntil = DateTimeOffset.MinValue;
    private DateTimeOffset? busySince;

    public RoamingController(ClaudeActivityWatcher watcher)
    {
        this.watcher = watcher;
        nextDisguise = 40;
        nextLogo = 30;
    }

    public void Start()
    {
        if (running) return;
        running = true;
        clock.Start();
        presence.Tick += OnPresenceTick;
        presence.Start();
        Settings.Changed += OnSettingsChanged;
        watcher.TurnFinished += OnTurnFinished;
        watcher.EasterEggSpotted += OnEasterEgg;
        Evaluate();
    }

    public void Stop()
    {
        if (!running) return;
        running = false;
        presence.Stop();
        presence.Tick -= OnPresenceTick;
        Settings.Changed -= OnSettingsChanged;
        watcher.TurnFinished -= OnTurnFinished;
        watcher.EasterEggSpotted -= OnEasterEgg;
        Teardown();
        clock.Stop();
    }

    public void Dispose() => Stop();

    private double Now => clock.Elapsed.TotalSeconds;

    // MARK: Out or home

    private void OnPresenceTick(object? sender, EventArgs args) => Evaluate();

    private void OnSettingsChanged() => dispatcher.BeginInvoke(new Action(Evaluate));

    private void OnTurnFinished(FinishedTurn turn)
        => dispatcher.BeginInvoke(new Action(() => Celebrate(turn)));

    private void OnEasterEgg(EasterEgg egg)
        => dispatcher.BeginInvoke(new Action(() => PlayEasterEgg(egg)));

    /// Decides once a second whether Clawd is out on the desktop or resting on the taskbar.
    private void Evaluate()
    {
        if (!running) return;
        if (!Settings.Current.PetWalksAround)
        {
            Teardown();
            return;
        }
        if (window is null) Build();
        if (window is null || sprite is null) return;
        if (window.Refresh()) Scan();

        var now = DateTimeOffset.Now;
        var busy = watcher.IsClaudeWorking(TimeSpan.FromSeconds(30));
        var away = ScreenSurfaces.IdleTime() > TimeSpan.FromMinutes(5);
        busySince = busy ? busySince ?? now : null;
        if (busy || away) quietSince = now;

        var covered = IsFullScreenInFront();
        window.Visibility = covered ? Visibility.Hidden : Visibility.Visible;
        if (covered)
        {
            // Nobody can see him behind a full screen window, so the frame loop stops as well.
            StopStepping();
            return;
        }
        if (mode != Mode.Away) StartStepping();
        if (now < easterEggUntil) return;

        if (mode == Mode.Away)
        {
            var settled = (now - quietSince).TotalSeconds > 8;
            var rested = now >= stayHomeUntil && (now - lastTransition).TotalSeconds > 10;
            if (settled && !busy && !away && rested) ComeOut();
            return;
        }

        if (away)
        {
            GoAway(true);
            return;
        }
        if (busySince is { } since && (now - since).TotalSeconds > 20)
        {
            GoAway(true);
            return;
        }

        if (mode is not (Mode.Idle or Mode.Walking or Mode.Resting) || standing is null) return;
        if (busy && mode != Mode.Resting)
        {
            // He stops to watch Claude work before heading home.
            sprite.SetPose(ClawdPose.Work);
            mode = Mode.Resting;
        }
        else if (!busy && mode == Mode.Resting)
        {
            sprite.SetPose(ClawdPose.Stand);
            mode = Mode.Idle;
            decideAt = Now + 1;
        }
    }

    /// Climbs up from behind the taskbar and sits down for a moment.
    private void ComeOut()
    {
        if (window is null || sprite is null) return;
        Scan();
        lastTransition = DateTimeOffset.Now;
        leaving = false;
        goingHome = false;
        finishingEgg = false;
        partyPending = false;
        fallSpeed = 0;
        driftX = 0;
        jump = null;
        disguise = null;
        swing = null;
        HideWeb();

        sprite.Reset();
        sprite.Hidden = false;
        position = HomeSpot();
        standing = Floor();
        direction = -1;
        sprite.FacingLeft = true;
        sprite.SetPose(ClawdPose.Sit);
        sprite.Position = position;
        mode = Mode.Idle;
        decideAt = Now + 2;
        StartStepping();
        sprite.RiseUp();
    }

    /// Walks back to the taskbar and slips behind its edge, or puffs away if he is far off.
    private void GoAway(bool animated)
    {
        if (window is null || sprite is null || mode == Mode.Away || leaving) return;
        leaving = true;
        jump = null;
        disguise = null;
        swing = null;
        partyPending = false;
        HideWeb();
        ClearProps();

        if (!animated)
        {
            Settle();
            return;
        }

        var home = HomeSpot();
        if (standing is { IsFloor: true } && Math.Abs(home.X - position.X) < 460)
        {
            goingHome = true;
            walkTarget = home.X;
            walkSpeed = HurrySpeed;
            direction = home.X > position.X ? 1 : -1;
            sprite.FacingLeft = direction < 0;
            sprite.SetPose(ClawdPose.Walk);
            homeDeadline = Now + 7;
            mode = Mode.Walking;
        }
        else
        {
            mode = Mode.Resting;
            sprite.Vanish(Settle);
        }
    }

    private void Settle()
    {
        mode = Mode.Away;
        leaving = false;
        goingHome = false;
        walkSpeed = WalkSpeed;
        standing = null;
        lastTransition = DateTimeOffset.Now;
        if (sprite is not null) sprite.Hidden = true;
        StopStepping();
    }

    private void Celebrate(FinishedTurn turn)
    {
        if (sprite is null || mode is not (Mode.Idle or Mode.Walking or Mode.Resting)) return;
        if (DateTimeOffset.Now - turn.Date > TimeSpan.FromSeconds(60)) return;
        sprite.SetPose(ClawdPose.Happy);
        sprite.Sparkle();
        mode = Mode.Idle;
        decideAt = Now + 2.5;
    }

    // MARK: Window

    private void Build()
    {
        Teardown();
        var host = new PetWindow();
        host.Show();

        var strands = new GeometryGroup();
        strands.Children.Add(rope);
        foreach (var spoke in spokes)
        {
            strands.Children.Add(spoke);
        }
        var strand = new Path
        {
            Data = strands,
            Stroke = Palette.Brush(Ink.Web),
            StrokeThickness = 1.4,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            Visibility = Visibility.Hidden,
            IsHitTestVisible = false,
        };
        host.Effects.Children.Add(strand);

        var pet = new RoamingSprite(host.Sprites) { Hidden = true };
        window = host;
        web = strand;
        sprite = pet;
        mode = Mode.Away;
        Scan();
    }

    private void Teardown()
    {
        StopStepping();
        ClearProps();
        sprite?.Retire();
        sprite = null;
        web = null;
        window?.Close();
        window = null;
        mode = Mode.Away;
        leaving = false;
        goingHome = false;
        standing = null;
    }

    private void StartStepping()
    {
        if (stepping) return;
        stepping = true;
        lastFrame = Now;
        CompositionTarget.Rendering += Step;
    }

    private void StopStepping()
    {
        if (!stepping) return;
        stepping = false;
        CompositionTarget.Rendering -= Step;
    }

    // MARK: Every frame

    private void Step(object? sender, EventArgs args)
    {
        if (window is null || sprite is null || mode == Mode.Away) return;
        var now = Now;
        var delta = Math.Clamp(now - lastFrame, 0, 1.0 / 20);
        lastFrame = now;

        // The full sweep of every window is expensive, so between sweeps only the
        // window under his feet is read, which is what he needs to ride it.
        if (now - lastScan > ScanEvery)
        {
            Scan();
            lastScan = now;
        }
        else
        {
            TrackStanding();
        }
        WatchPointer(now);

        switch (mode)
        {
            case Mode.Falling:
                Fall(delta, now);
                break;

            case Mode.Walking:
                Stroll(delta, now);
                break;

            case Mode.Jumping:
                Hop(now);
                break;

            case Mode.Idle:
                if (now >= decideAt && now >= pettedUntil) Decide(now);
                break;

            case Mode.Disguised:
                UpdateDisguise(now);
                break;

            case Mode.Swinging:
                UpdateSwing(now);
                break;

            case Mode.Partying:
                if (now >= partyUntil) FinishParty(now);
                break;
        }

        Unstick(now);

        if (mode is Mode.Walking or Mode.Idle or Mode.Resting or Mode.Partying && standing is null && !leaving)
        {
            fallSpeed = 0;
            mode = Mode.Falling;
            sprite.SetPose(ClawdPose.Fall);
        }
        sprite.Position = position;
    }

    /// Several moves hand over to an animation and wait to be called back. If that call never
    /// comes Clawd would stand there for good, so after a couple of seconds he just drops.
    private void Unstick(double now)
    {
        if (sprite is null) return;
        var waiting = mode switch
        {
            Mode.Jumping => jump is null,
            Mode.Disguised => disguise is null,
            Mode.Swinging => swing is null,
            Mode.Resting => leaving,
            _ => false,
        };
        if (!waiting || sprite.Morphing)
        {
            stuckSince = null;
            return;
        }

        stuckSince ??= now;
        if (now - stuckSince.Value < StuckAfter) return;
        stuckSince = null;

        if (leaving)
        {
            Settle();
            return;
        }
        jump = null;
        disguise = null;
        swing = null;
        standing = null;
        fallSpeed = 0;
        mode = Mode.Falling;
        HideWeb();
        if (sprite.Look == ClawdLook.Clawd) sprite.SetPose(ClawdPose.Fall);
        else sprite.Morph(ClawdLook.Clawd, () => sprite?.SetPose(ClawdPose.Fall));
    }

    private void Fall(double delta, double now)
    {
        if (window is null || sprite is null) return;
        var screen = window.Screen;
        fallSpeed = Math.Min(fallSpeed + 1700 * delta, 1100);
        var next = position.Y + fallSpeed * delta;
        position.X = Math.Clamp(position.X + driftX * delta, screen.Left + 12, screen.Right - 12);
        driftX *= Math.Max(0, 1 - 1.4 * delta);

        if (fallSpeed > 0 && Landing(position.Y, next, position.X) is { } spot)
        {
            Land(spot, now);
            return;
        }
        position.Y = next;
        if (position.Y > screen.Bottom + 80)
        {
            position = new Point(Between(screen.Left + 80, screen.Right - 80), screen.Top);
        }
    }

    private void Stroll(double delta, double now)
    {
        if (sprite is null) return;
        if (standing is not { } surface)
        {
            // The ground went away on the way home, so he just puffs out instead.
            if (!goingHome) return;
            goingHome = false;
            mode = Mode.Resting;
            sprite.Vanish(Settle);
            return;
        }

        position.X += direction * walkSpeed * delta;
        var reached = direction > 0 ? position.X >= walkTarget : position.X <= walkTarget;
        var atEdge = position.X <= surface.MinX + 4 || position.X >= surface.MaxX - 4;

        if (goingHome)
        {
            if (!reached && !atEdge && now < homeDeadline) return;
            goingHome = false;
            walkSpeed = WalkSpeed;
            mode = Mode.Resting;
            sprite.SetPose(ClawdPose.Sit);
            sprite.SinkAway(Settle);
            return;
        }

        if (atEdge && !surface.IsFloor && Random.Shared.NextDouble() < 0.4)
        {
            standing = null;
            fallSpeed = -120;
            driftX = direction * 40;
            mode = Mode.Falling;
            sprite.SetPose(ClawdPose.Fall);
        }
        else if (reached || atEdge)
        {
            position.X = Math.Clamp(position.X, surface.MinX + 4, surface.MaxX - 4);
            sprite.SetPose(ClawdPose.Stand);
            mode = Mode.Idle;
            decideAt = now + Between(1.5, 4);
        }
    }

    private void Hop(double now)
    {
        if (sprite is null || jump is not { } arc) return;
        var step = Math.Min((now - arc.Start) / arc.Duration, 1);
        position = new Point(
            arc.From.X + (arc.To.X - arc.From.X) * step,
            arc.From.Y + (arc.To.Y - arc.From.Y) * step - arc.Height * 4 * step * (1 - step));
        if (step < 1) return;

        jump = null;
        if (Find(arc.Target, position.X, 4) is { } landed)
        {
            Land(landed, now);
        }
        else
        {
            standing = null;
            fallSpeed = 0;
            mode = Mode.Falling;
            sprite.SetPose(ClawdPose.Fall);
        }
    }

    private void Land(Surface surface, double now)
    {
        if (sprite is null) return;
        position.Y = surface.Y;
        standing = surface;
        fallSpeed = 0;
        driftX = 0;
        sprite.SetPose(finishingEgg ? ClawdPose.Happy : ClawdPose.Stand);
        sprite.Land();
        mode = Mode.Idle;
        decideAt = now + (finishingEgg ? 1.6 : Between(0.8, 2));
        if (partyPending) BeginParty();
    }

    // MARK: Surfaces

    private void Scan()
    {
        if (window is null) return;
        surfaces = ScreenSurfaces.Current(window.Scale, Environment.ProcessId);
        if (standing is not { } current) return;

        // Ride along when the window underneath moves, and fall when it goes away.
        Surface? best = null;
        var shortest = double.MaxValue;
        foreach (var candidate in surfaces)
        {
            if (candidate.Id != current.Id) continue;
            var reach = Math.Abs(candidate.Y - position.Y) + (candidate.Contains(position.X) ? 0 : 50);
            if (reach >= shortest) continue;
            shortest = reach;
            best = candidate;
        }
        if (best is not { } moved)
        {
            standing = null;
            return;
        }
        if (current.WindowRect is { } old && moved.WindowRect is { } fresh) position.X += fresh.Left - old.Left;
        position.Y = moved.Y;
        standing = moved.Contains(position.X, 2) ? moved : null;
    }

    /// One window read, so he keeps up with the one he is standing on between full sweeps.
    private void TrackStanding()
    {
        if (window is null || standing is not { WindowRect: { } old } current) return;
        if (ScreenSurfaces.WindowRect((nint)current.Id, window.Scale) is not { } fresh)
        {
            standing = null;
            return;
        }

        var dx = fresh.Left - old.Left;
        var dy = fresh.Top - old.Top;
        if (dx == 0 && dy == 0) return;
        position.X += dx;
        position.Y = current.Y + dy;
        var moved = current with
        {
            Y = current.Y + dy,
            MinX = current.MinX + dx,
            MaxX = current.MaxX + dx,
            WindowRect = fresh,
        };
        standing = moved.Contains(position.X, 2) ? moved : null;
    }

    private Surface? Floor()
    {
        foreach (var surface in surfaces)
        {
            if (surface.IsFloor) return surface;
        }
        return null;
    }

    private Surface? Find(int id, double x, double margin)
    {
        foreach (var surface in surfaces)
        {
            if (surface.Id == id && surface.Contains(x, margin)) return surface;
        }
        return null;
    }

    private Rect? FrameOf(int? id)
    {
        if (id is not { } key) return null;
        foreach (var surface in surfaces)
        {
            if (surface.Id != key || surface.WindowRect is not { } frame) continue;
            // The sweep only runs twice a second, so this one window is read again here
            // to keep a disguise pinned to it while it is being dragged.
            return window is null ? frame : ScreenSurfaces.WindowRect((nint)key, window.Scale) ?? frame;
        }
        return null;
    }

    private Surface? Landing(double from, double to, double x)
    {
        Surface? best = null;
        foreach (var surface in surfaces)
        {
            if (surface.Y < from - 1 || surface.Y > to || !surface.Contains(x)) continue;
            if (best is { } found && found.Y <= surface.Y) continue;
            best = surface;
        }
        return best;
    }

    /// His spot on the taskbar, at the right end near the clock.
    private Point HomeSpot()
    {
        if (window is null) return position;
        var bar = ScreenSurfaces.Taskbar(window.Scale);
        var x = bar.Right - 56;
        var floor = Floor();
        if (floor is { } strip)
        {
            x = Math.Clamp(x, strip.MinX + 10, Math.Max(strip.MinX + 10, strip.MaxX - 10));
            return new Point(x, strip.Y);
        }
        return new Point(x, bar.Top);
    }

    // MARK: Choices

    private void Decide(double now)
    {
        if (window is null || sprite is null || standing is not { } surface) return;

        if (finishingEgg)
        {
            finishingEgg = false;
            easterEggUntil = DateTimeOffset.MinValue;
            sprite.Morph(ClawdLook.Clawd);
            decideAt = now + 1.2;
            return;
        }

        var roll = Random.Shared.NextDouble();
        var costumes = Disguises(surface);
        if (roll < 0.07)
        {
            stayHomeUntil = DateTimeOffset.Now.AddSeconds(Between(15, 40));
            GoAway(true);
        }
        else if (now >= nextLogo && roll < 0.25)
        {
            nextLogo = now + Between(120, 240);
            StartDisguise(ClawdLook.WindowsLogo, now);
        }
        else if (now >= nextDisguise && roll < 0.35 && costumes.Count > 0)
        {
            nextDisguise = now + Between(45, 90);
            StartDisguise(costumes[Random.Shared.Next(costumes.Count)], now);
        }
        else if (roll < 0.62)
        {
            Walk(surface, Between(surface.MinX + 10, surface.MaxX - 10), now);
        }
        else if (roll < 0.78 && JumpTarget() is { } target)
        {
            var x = Math.Clamp(
                position.X + Between(-60, 60),
                target.MinX + 12,
                Math.Max(target.MinX + 12, target.MaxX - 12));
            var to = new Point(x, target.Y);
            var rise = Math.Max(position.Y - to.Y, 0);
            jump = new Jump
            {
                From = position,
                To = to,
                Target = target.Id,
                Start = now,
                Duration = 0.55 + rise / 900,
                Height = rise + 36,
            };
            sprite.FacingLeft = to.X < position.X;
            sprite.SetPose(ClawdPose.Fall);
            standing = null;
            mode = Mode.Jumping;
        }
        else if (roll < 0.88)
        {
            Walk(surface, ScreenSurfaces.Cursor(window.Scale).X, now);
        }
        else
        {
            sprite.SetPose(Random.Shared.Next(2) == 0 ? ClawdPose.Sit : ClawdPose.Stand);
            decideAt = now + Between(3, 7);
        }
    }

    private void Walk(Surface surface, double x, double now)
    {
        if (sprite is null) return;
        var target = Math.Clamp(x, surface.MinX + 8, Math.Max(surface.MinX + 8, surface.MaxX - 8));
        if (Math.Abs(target - position.X) <= 12)
        {
            decideAt = now + 1.5;
            return;
        }
        walkTarget = target;
        walkSpeed = WalkSpeed;
        direction = target > position.X ? 1 : -1;
        sprite.FacingLeft = direction < 0;
        sprite.SetPose(ClawdPose.Walk);
        mode = Mode.Walking;
    }

    private Surface? JumpTarget()
    {
        var options = new List<Surface>();
        foreach (var surface in surfaces)
        {
            if (standing is { } current && surface.Id == current.Id) continue;
            if (Math.Abs(surface.Y - position.Y) >= 260) continue;
            var nearest = Math.Clamp(position.X, surface.MinX, Math.Max(surface.MinX, surface.MaxX));
            if (Math.Abs(nearest - position.X) >= 140) continue;
            options.Add(surface);
        }
        return options.Count == 0 ? null : options[Random.Shared.Next(options.Count)];
    }

    // MARK: Disguises

    /// What Clawd can pretend to be from where he is standing.
    private static List<ClawdLook> Disguises(Surface surface)
    {
        var options = new List<ClawdLook>(2);
        if (surface.IsFloor) options.Add(ClawdLook.Folder);
        if (surface.WindowRect is { } frame && frame.Width > 260 && surface.MaxX >= frame.Right - 12)
        {
            options.Add(ClawdLook.WindowButton);
        }
        return options;
    }

    private void StartDisguise(ClawdLook look, double now)
    {
        if (window is null || sprite is null) return;
        int? owner = null;
        if (look == ClawdLook.WindowButton)
        {
            if (standing is not { WindowRect: not null } host) return;
            owner = host.Id;
        }

        mode = Mode.Disguised;
        var next = new Disguise
        {
            Look = look,
            Until = now + Between(6, 12),
            Return = position,
            WindowId = owner,
            From = position,
            Start = now + 0.15,
        };
        if (look == ClawdLook.WindowsLogo)
        {
            var spot = ScreenSurfaces.StartButton(window.Scale);
            var reach = Math.Sqrt(Square(spot.X - position.X) + Square(spot.Y - position.Y));
            next.Travel = Math.Clamp(0.6 + reach / 1400, 0.7, 1.3);
            next.Until = next.Start + next.Travel + Between(6, 12);
            // He turns back into Clawd just above the taskbar and drops onto it.
            next.Return = new Point(spot.X + 8, ScreenSurfaces.Taskbar(window.Scale).Top - 30);
        }
        disguise = next;
        standing = null;
        sprite.Morph(look, () =>
        {
            if (look == ClawdLook.WindowsLogo && sprite is not null) sprite.FacingLeft = false;
            UpdateDisguise(Now);
        });
    }

    private void UpdateDisguise(double now)
    {
        if (window is null || sprite is null || disguise is not { } current) return;

        switch (current.Look)
        {
            case ClawdLook.WindowsLogo:
                // A visible hop over to the Start button, then he settles on it.
                var spot = ScreenSurfaces.StartButton(window.Scale);
                var feet = new Point(spot.X, spot.Y + sprite.Size.Height / 2);
                var step = Math.Clamp((now - current.Start) / Math.Max(current.Travel, 0.01), 0, 1);
                var eased = step * step * (3 - 2 * step);
                var height = 70 * 4 * step * (1 - step);
                position = new Point(
                    current.From.X + (feet.X - current.From.X) * eased,
                    Math.Max(current.From.Y + (feet.Y - current.From.Y) * eased - height, window.Screen.Top + 12));
                break;

            case ClawdLook.WindowButton:
                if (FrameOf(current.WindowId) is { } frame)
                {
                    // One slot past the close, maximize and minimize buttons.
                    var slot = frame.Right - 3 * CaptionButton - 22;
                    position = new Point(slot, frame.Top + 16 + sprite.Size.Height / 2);
                    current.Return = new Point(slot, frame.Top);
                }
                else
                {
                    current.Until = now;
                }
                break;
        }

        if (now < current.Until || sprite.Look != current.Look) return;
        disguise = null;
        var back = current.Return;
        mode = Mode.Jumping;
        sprite.Morph(ClawdLook.Clawd, () =>
        {
            if (sprite is null) return;
            position = back;
            standing = null;
            fallSpeed = 0;
            mode = Mode.Falling;
            sprite.SetPose(ClawdPose.Fall);
            sprite.Position = position;
        });
    }

    // MARK: Easter eggs

    private void PlayEasterEgg(EasterEgg egg)
    {
        if (!Settings.Current.PetWalksAround || window is null || sprite is null) return;
        if (DateTimeOffset.Now - egg.Date > TimeSpan.FromSeconds(60)) return;
        if (mode is Mode.Swinging or Mode.Partying) return;

        easterEggUntil = DateTimeOffset.Now.AddSeconds(40);
        disguise = null;
        jump = null;
        leaving = false;
        goingHome = false;
        if (mode == Mode.Away)
        {
            sprite.Reset();
            sprite.Hidden = false;
            position = new Point(HomeSpot().X, window.Screen.Top + 60);
            StartStepping();
        }
        Scan();

        if (egg.Kind == EasterEggKind.WebSlinger) StartSwinging();
        else StartParty();
    }

    /// Suits up and swings across the screen on webs hung from the top of it.
    private void StartSwinging()
    {
        if (window is null || sprite is null) return;
        var screen = window.Screen;
        var length = Math.Min(240, screen.Height * 0.32);
        const double angle = 0.85;
        var heading = position.X < screen.Left + screen.Width / 2 ? 1 : -1;
        var edge = heading > 0 ? screen.Left + 50 : screen.Right - 50;

        swing = new Swing
        {
            Direction = heading,
            Anchor = new Point(edge + heading * length * Math.Sin(angle), screen.Top + 6),
            Length = length,
            Angle = angle,
            Start = Now,
            ZipFrom = position,
        };
        standing = null;
        mode = Mode.Swinging;
        sprite.FacingLeft = heading < 0;
        sprite.Morph(ClawdLook.WebSuit, () => sprite?.SetPose(ClawdPose.Fall));
    }

    private void UpdateSwing(double now)
    {
        if (window is null || sprite is null || swing is not { } arc) return;
        var screen = window.Screen;
        var reach = new Point(
            arc.Anchor.X - arc.Direction * arc.Length * Math.Sin(arc.Angle),
            arc.Anchor.Y + arc.Length * Math.Cos(arc.Angle));
        Point hand;

        if (arc.ZipFrom is { } from)
        {
            // Pulled up along the first web to where the swing starts.
            var step = Math.Min((now - arc.Start) / 0.7, 1);
            var eased = step * step * (3 - 2 * step);
            var start = new Point(from.X, from.Y - sprite.Size.Height);
            hand = new Point(
                start.X + (reach.X - start.X) * eased,
                start.Y + (reach.Y - start.Y) * eased);
            if (step >= 1)
            {
                arc.ZipFrom = null;
                arc.Start = now;
            }
        }
        else
        {
            var step = Math.Min((now - arc.Start) / 1.05, 1);
            var theta = -arc.Angle * Math.Cos(Math.PI * step);
            hand = new Point(
                arc.Anchor.X + arc.Direction * arc.Length * Math.Sin(theta),
                arc.Anchor.Y + arc.Length * Math.Cos(theta));
            sprite.Tilt(-theta * arc.Direction * 0.5);
            if (step >= 1)
            {
                arc.Count++;
                var next = new Point(hand.X + arc.Direction * arc.Length * Math.Sin(arc.Angle), arc.Anchor.Y);
                var offscreen = arc.Direction > 0 ? next.X > screen.Right - 30 : next.X < screen.Left + 30;
                if (offscreen || arc.Count >= 7)
                {
                    // Lets go and flies off the last swing.
                    swing = null;
                    HideWeb();
                    sprite.Tilt(0);
                    position = new Point(hand.X, hand.Y + sprite.Size.Height);
                    fallSpeed = -260;
                    driftX = arc.Direction * 240;
                    finishingEgg = true;
                    mode = Mode.Falling;
                    return;
                }
                arc.Anchor = next;
                arc.Start = now;
            }
        }

        position = new Point(hand.X, hand.Y + sprite.Size.Height);
        DrawWeb(arc.Anchor, hand);
    }

    private void DrawWeb(Point anchor, Point hand)
    {
        if (web is null) return;
        rope.StartPoint = anchor;
        rope.EndPoint = hand;
        for (var index = 0; index < spokes.Length; index++)
        {
            var angle = index * Math.PI / 4;
            var dx = Math.Cos(angle) * 5;
            var dy = Math.Sin(angle) * 5;
            spokes[index].StartPoint = new Point(anchor.X - dx, anchor.Y - dy);
            spokes[index].EndPoint = new Point(anchor.X + dx, anchor.Y + dy);
        }
        web.Visibility = Visibility.Visible;
    }

    private void HideWeb()
    {
        if (web is not null) web.Visibility = Visibility.Hidden;
    }

    /// A disco ball drops, the platinum hair and the bow come out, and it is paws up for a while.
    private void StartParty()
    {
        if (sprite is null) return;
        if (standing is null)
        {
            // Dance once he lands.
            partyPending = true;
            fallSpeed = 0;
            mode = Mode.Falling;
            sprite.SetPose(ClawdPose.Fall);
        }
        else
        {
            BeginParty();
        }
    }

    private void BeginParty()
    {
        if (sprite is null) return;
        partyPending = false;
        mode = Mode.Partying;
        partyUntil = Now + 10;
        sprite.Morph(ClawdLook.PopStar, () => sprite?.SetPose(ClawdPose.Dance));
        DropDiscoBall(position);
        FloatNotes(position);
    }

    private void FinishParty(double now)
    {
        if (sprite is null) return;
        ClearProps();
        sprite.SetPose(ClawdPose.Stand);
        mode = Mode.Idle;
        finishingEgg = true;
        decideAt = now + 0.3;
    }

    private void DropDiscoBall(Point spot)
    {
        if (window is null) return;
        var top = window.Screen.Top + 2;
        var hang = Math.Clamp(spot.Y - top - 90, 60, 260);
        const double radius = 16;

        var cord = new Line
        {
            X1 = spot.X,
            Y1 = top,
            X2 = spot.X,
            Y2 = top + hang,
            Stroke = Palette.Brush(Ink.Cord),
            StrokeThickness = 1,
            IsHitTestVisible = false,
        };
        AddProp(cord);

        var shine = new RadialGradientBrush
        {
            GradientOrigin = new Point(0.35, 0.3),
            Center = new Point(0.45, 0.4),
            RadiusX = 0.7,
            RadiusY = 0.7,
        };
        shine.GradientStops.Add(new GradientStop(Ink.White, 0));
        shine.GradientStops.Add(new GradientStop(Ink.Ball, 0.55));
        shine.GradientStops.Add(new GradientStop(Ink.BallShade, 1));
        shine.Freeze();

        var ball = new Ellipse
        {
            Width = radius * 2,
            Height = radius * 2,
            Fill = shine,
            IsHitTestVisible = false,
        };
        Canvas.SetLeft(ball, spot.X - radius);
        Canvas.SetTop(ball, top + hang);
        var fall = new TranslateTransform(0, -(hang + radius * 2));
        ball.RenderTransform = fall;
        AddProp(ball);
        fall.BeginAnimation(
            TranslateTransform.YProperty,
            new DoubleAnimation(0, TimeSpan.FromSeconds(0.6))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
                FillBehavior = FillBehavior.HoldEnd,
            });

        // Colored spots of light sweeping around the dance floor.
        var colors = new[]
        {
            Color.FromRgb(255, 105, 180), Color.FromRgb(90, 210, 220), Color.FromRgb(255, 214, 90),
            Color.FromRgb(180, 120, 255), Color.FromRgb(255, 150, 70), Color.FromRgb(110, 160, 255),
        };
        var center = new Point(spot.X, spot.Y - 20);
        for (var index = 0; index < colors.Length; index++)
        {
            var tint = colors[index];
            tint.A = 140;
            var light = new Ellipse
            {
                Width = 10,
                Height = 10,
                Fill = Palette.Brush(tint),
                IsHitTestVisible = false,
            };
            Canvas.SetLeft(light, center.X - 5);
            Canvas.SetTop(light, center.Y - 5);
            var slide = new TranslateTransform();
            light.RenderTransform = slide;
            AddProp(light);

            var phase = index / (double)colors.Length;
            slide.BeginAnimation(TranslateTransform.XProperty, Ring(70, phase, 3, false));
            slide.BeginAnimation(TranslateTransform.YProperty, Ring(30, phase, 3, true));
            light.BeginAnimation(
                UIElement.OpacityProperty,
                new DoubleAnimation(0.35, 1, TimeSpan.FromSeconds(0.4))
                {
                    AutoReverse = true,
                    RepeatBehavior = RepeatBehavior.Forever,
                });
        }
    }

    private void FloatNotes(Point spot)
    {
        for (var index = 0; index < 6; index++)
        {
            var side = index % 2 == 0 ? -1 : 1;
            var note = new TextBlock
            {
                Text = index % 2 == 0 ? "♪" : "♫",
                FontSize = 14,
                Foreground = Palette.Brush(Ink.White),
                IsHitTestVisible = false,
            };
            Canvas.SetLeft(note, spot.X + side * 26);
            Canvas.SetTop(note, spot.Y - 30);
            var rise = new TranslateTransform();
            note.RenderTransform = rise;
            note.Opacity = 0;
            AddProp(note);

            var delay = TimeSpan.FromSeconds(index * 0.27);
            var span = TimeSpan.FromSeconds(1.6);
            rise.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(0, side * 18, span)
            {
                BeginTime = delay,
                RepeatBehavior = RepeatBehavior.Forever,
            });
            rise.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0, -50, span)
            {
                BeginTime = delay,
                RepeatBehavior = RepeatBehavior.Forever,
            });

            var fade = new DoubleAnimationUsingKeyFrames
            {
                Duration = span,
                BeginTime = delay,
                RepeatBehavior = RepeatBehavior.Forever,
            };
            fade.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromPercent(0)));
            fade.KeyFrames.Add(new LinearDoubleKeyFrame(1, KeyTime.FromPercent(0.2)));
            fade.KeyFrames.Add(new LinearDoubleKeyFrame(1, KeyTime.FromPercent(0.7)));
            fade.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromPercent(1)));
            note.BeginAnimation(UIElement.OpacityProperty, fade);
        }
    }

    private static DoubleAnimationUsingKeyFrames Ring(double radius, double phase, double seconds, bool vertical)
    {
        const int steps = 16;
        var animation = new DoubleAnimationUsingKeyFrames
        {
            Duration = TimeSpan.FromSeconds(seconds),
            RepeatBehavior = RepeatBehavior.Forever,
        };
        for (var index = 0; index <= steps; index++)
        {
            var angle = (index / (double)steps + phase) * 2 * Math.PI;
            var value = radius * (vertical ? Math.Sin(angle) : Math.Cos(angle));
            animation.KeyFrames.Add(new LinearDoubleKeyFrame(
                value,
                KeyTime.FromTimeSpan(TimeSpan.FromSeconds(seconds * index / steps))));
        }
        return animation;
    }

    private void AddProp(UIElement prop)
    {
        window?.Effects.Children.Add(prop);
        partyProps.Add(prop);
    }

    private void ClearProps()
    {
        foreach (var prop in partyProps)
        {
            // The ball, the lights and the notes all loop forever until they are stopped.
            ClawdMotion.Stop(prop);
            window?.Effects.Children.Remove(prop);
        }
        partyProps.Clear();
    }

    // MARK: Pointer and screen

    /// Resting the pointer on Clawd for a moment counts as petting him.
    private void WatchPointer(double now)
    {
        if (window is null || sprite is null
            || sprite.Look != ClawdLook.Clawd
            || mode is not (Mode.Idle or Mode.Walking))
        {
            hoverSince = null;
            return;
        }

        var pointer = ScreenSurfaces.Cursor(window.Scale);
        var box = new Rect(
            position.X - sprite.Size.Width / 2 - 6,
            position.Y - sprite.Size.Height - 6,
            sprite.Size.Width + 12,
            sprite.Size.Height + 12);
        if (!box.Contains(pointer))
        {
            hoverSince = null;
            return;
        }

        hoverSince ??= now;
        if (hoverSince is not { } since || now - since <= 0.5 || now <= pettedUntil + 4) return;
        pettedUntil = now + 2;
        hoverSince = null;
        sprite.SetPose(ClawdPose.Happy);
        mode = Mode.Idle;
        decideAt = now + 2;
    }

    private bool IsFullScreenInFront()
    {
        if (window is null) return false;
        var front = ScreenSurfaces.Foreground();
        if (front == 0 || front == window.Handle) return false;
        if (ScreenSurfaces.ClassOf(front) is "Progman" or "WorkerW" or "Shell_TrayWnd") return false;
        if (ScreenSurfaces.WindowRect(front, window.Scale) is not { } frame) return false;
        var screen = window.Screen;
        return frame.Left <= screen.Left + 2
               && frame.Top <= screen.Top + 2
               && frame.Right >= screen.Right - 2
               && frame.Bottom >= screen.Bottom - 2;
    }

    private static double Between(double from, double to)
        => to <= from ? from : from + Random.Shared.NextDouble() * (to - from);

    private static double Square(double value) => value * value;
}
