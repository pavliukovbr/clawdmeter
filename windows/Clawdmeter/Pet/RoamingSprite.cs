using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using Clawdmeter.Usage;
using Point = System.Windows.Point;
using Size = System.Windows.Size;

namespace Clawdmeter.Pet;

/// Clawd walking around the desktop, and the things he likes to pretend to be.
/// Everything is anchored at his feet, so moving him moves the point he stands on.
public sealed class RoamingSprite
{
    private const double Unit = ClawdArt.RoamUnit;

    private const double HangSeconds = 7;

    private readonly Canvas host;
    private readonly Canvas root = new();
    private readonly Canvas flipper = new();
    private readonly Canvas gear = new();
    private readonly Canvas extras = new();

    private readonly RotateTransform tilt = new();
    private readonly TranslateTransform sink = new();
    private readonly ScaleTransform squash = new(1, 1);
    private readonly ScaleTransform flip = new(1, 1);
    /// Turns him about his paws, which is what makes a hanging Clawd sway.
    private readonly RotateTransform grip = new();
    private readonly TranslateTransform gearShift = new();

    private RotateTransform lean = new();
    private TranslateTransform bob = new();
    private ClawdPieces pieces;
    private bool facingLeft;
    private Point position;
    private int generation;
    private long morphEnds;

    public RoamingSprite(Canvas host)
    {
        this.host = host;
        root.IsHitTestVisible = false;
        flipper.IsHitTestVisible = false;
        gear.IsHitTestVisible = false;
        extras.IsHitTestVisible = false;
        root.RenderTransform = new TransformGroup { Children = { grip, tilt, sink } };
        flipper.RenderTransform = new TransformGroup { Children = { squash, flip } };
        gear.RenderTransform = gearShift;
        root.Children.Add(flipper);
        root.Children.Add(gear);
        root.Children.Add(extras);

        pieces = ClawdArt.Build(ClawdLook.Clawd);
        Install(pieces);
        host.Children.Add(root);
    }

    public ClawdLook Look { get; private set; } = ClawdLook.Clawd;

    public ClawdPose Pose { get; private set; } = ClawdPose.Stand;

    public Size Size => pieces.Size;

    public bool FacingLeft
    {
        get => facingLeft;
        set
        {
            if (facingLeft == value) return;
            facingLeft = value;
            flip.ScaleX = value ? -1 : 1;
        }
    }

    /// Where his feet are, in the coordinates of the canvas he lives on.
    public Point Position
    {
        get => position;
        set
        {
            position = value;
            Canvas.SetLeft(root, Math.Round(value.X - pieces.Size.Width / 2));
            Canvas.SetTop(root, Math.Round(value.Y - pieces.Size.Height));
        }
    }

    public bool Hidden
    {
        get => root.Visibility != Visibility.Visible;
        set => root.Visibility = value ? Visibility.Hidden : Visibility.Visible;
    }

    // MARK: Changing

    /// What he is holding. It sits outside the flipper, so it never comes out mirrored.
    public ClawdGear Gear { get; private set; } = ClawdGear.None;

    public void SetPose(ClawdPose next)
    {
        if (!pieces.HasBody || next == Pose) return;
        Pose = next;
        ApplyPose();
    }

    /// Puts a gadget in his paws, or takes the last one away.
    public void ShowGear(ClawdGear next)
    {
        if (next == Gear) return;
        Gear = next;
        ClearGear();

        var built = pieces.HasBody ? ClawdArt.Gear(next, Unit) : null;
        if (built is not null)
        {
            gear.Children.Add(built.Content);
            switch (next)
            {
                case ClawdGear.Laptop:
                    Loop(
                        built.Glow,
                        UIElement.OpacityProperty,
                        new[] { 0.55, 1, 0.7, 0.95, 0.55 },
                        new[] { 0, 0.3, 0.5, 0.8, 1.0 },
                        3.2);
                    break;

                case ClawdGear.Book:
                    Loop(built.Drift, TranslateTransform.YProperty, new[] { 0, 0.3 * Unit, 0 }, Thirds, 1.6);
                    break;

                case ClawdGear.Glass:
                    Loop(
                        built.Drift,
                        TranslateTransform.XProperty,
                        new[] { 0, 2.4 * Unit, 0, -2.4 * Unit, 0 },
                        Quarters,
                        5.2);
                    Loop(
                        built.Drift,
                        TranslateTransform.YProperty,
                        new[] { 0, -0.6 * Unit, 0.5 * Unit, -0.6 * Unit, 0 },
                        Quarters,
                        5.2);
                    break;

                case ClawdGear.Tools:
                    Loop(
                        built.Swing,
                        RotateTransform.AngleProperty,
                        new[] { -55.0, -55, 35, 18, -55 },
                        new[] { 0, 0.34, 0.48, 0.58, 1.0 },
                        1.1);
                    break;

                case ClawdGear.Dots:
                    for (var index = 0; index < built.Dots.Count; index++)
                    {
                        Loop(built.Dots[index], UIElement.OpacityProperty, new[] { 0.25, 1, 0.25 }, Thirds, 1.5, (2 - index) * 0.25);
                    }
                    break;
            }
        }

        // He and what he carries pull up together, so both cycles start again here.
        if (Pose == ClawdPose.Hang) HangLift();
    }

    /// True while Clawd is halfway through changing his look. It runs out on its own,
    /// so nothing can hang on it if the animation never reports back.
    public bool Morphing => Environment.TickCount64 < morphEnds;

    /// Shrinks into a little puff of dust and comes back as something else.
    public void Morph(ClawdLook next, Action? done = null)
    {
        if (next == Look)
        {
            done?.Invoke();
            return;
        }
        Puff();
        morphEnds = Environment.TickCount64 + 900;
        var mark = ++generation;
        var shrink = new DoubleAnimation(0.2, TimeSpan.FromSeconds(0.13))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn },
            FillBehavior = FillBehavior.HoldEnd,
        };
        shrink.Completed += (_, _) =>
        {
            if (mark != generation) return;
            Rebuild(next);
            var grow = new DoubleAnimation(0.2, 1, TimeSpan.FromSeconds(0.5))
            {
                EasingFunction = new ElasticEase { EasingMode = EasingMode.EaseOut, Oscillations = 1, Springiness = 5 },
                FillBehavior = FillBehavior.Stop,
            };
            squash.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
            squash.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
            morphEnds = 0;
            done?.Invoke();
        };
        squash.BeginAnimation(ScaleTransform.ScaleXProperty, shrink);
        squash.BeginAnimation(ScaleTransform.ScaleYProperty, shrink);
    }

    /// Back to plain Clawd right away, used when he comes out again.
    public void Reset()
    {
        generation++;
        morphEnds = 0;
        Gear = ClawdGear.None;
        ClearGear();
        squash.BeginAnimation(ScaleTransform.ScaleXProperty, null);
        squash.BeginAnimation(ScaleTransform.ScaleYProperty, null);
        squash.ScaleX = 1;
        squash.ScaleY = 1;
        root.BeginAnimation(UIElement.OpacityProperty, null);
        root.Opacity = 1;
        sink.BeginAnimation(TranslateTransform.YProperty, null);
        sink.Y = 0;
        Tilt(0);
        if (Look != ClawdLook.Clawd) Rebuild(ClawdLook.Clawd);
        Pose = ClawdPose.Stand;
        ApplyPose();
    }

    /// Disappears in a puff of dust.
    public void Vanish(Action? done = null)
    {
        Puff();
        var mark = ++generation;
        var shrink = new DoubleAnimation(0.05, TimeSpan.FromSeconds(0.16))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn },
            FillBehavior = FillBehavior.HoldEnd,
        };
        shrink.Completed += (_, _) =>
        {
            if (mark != generation) return;
            done?.Invoke();
        };
        squash.BeginAnimation(ScaleTransform.ScaleXProperty, shrink);
        squash.BeginAnimation(ScaleTransform.ScaleYProperty, shrink);
    }

    /// Slips down behind the taskbar edge and fades out.
    public void SinkAway(Action? done = null)
    {
        var mark = ++generation;
        var drop = new DoubleAnimation(0, pieces.Size.Height * 0.8, TimeSpan.FromSeconds(0.5))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn },
            FillBehavior = FillBehavior.HoldEnd,
        };
        var fade = new DoubleAnimation(1, 0, TimeSpan.FromSeconds(0.5)) { FillBehavior = FillBehavior.HoldEnd };
        fade.Completed += (_, _) =>
        {
            if (mark != generation) return;
            done?.Invoke();
        };
        sink.BeginAnimation(TranslateTransform.YProperty, drop);
        root.BeginAnimation(UIElement.OpacityProperty, fade);
    }

    /// Climbs back up from behind the taskbar edge.
    public void RiseUp(Action? done = null)
    {
        var mark = ++generation;
        var climb = new DoubleAnimation(pieces.Size.Height * 0.8, 0, TimeSpan.FromSeconds(0.6))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
            FillBehavior = FillBehavior.Stop,
        };
        var fade = new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.45)) { FillBehavior = FillBehavior.Stop };
        fade.Completed += (_, _) =>
        {
            if (mark != generation) return;
            done?.Invoke();
        };
        sink.Y = 0;
        root.Opacity = 1;
        sink.BeginAnimation(TranslateTransform.YProperty, climb);
        root.BeginAnimation(UIElement.OpacityProperty, fade);
    }

    public void Land()
    {
        Once(squash, ScaleTransform.ScaleXProperty, new[] { 1.25, 0.94, 1.0 }, new[] { 0.0, 0.45, 1.0 }, 0.3);
        Once(squash, ScaleTransform.ScaleYProperty, new[] { 0.72, 1.08, 1.0 }, new[] { 0.0, 0.45, 1.0 }, 0.3);
    }

    /// Little stars around Clawd when Claude finishes something.
    public void Sparkle()
    {
        var spots = new[]
        {
            new Point(-6, -8),
            new Point(pieces.Size.Width + 4, -14),
            new Point(pieces.Size.Width + 8, 6),
            new Point(-10, 8),
        };
        var spark = Palette.Brush(Palette.Spark);
        var stars = new List<Path>(spots.Length);
        for (var index = 0; index < spots.Length; index++)
        {
            var spot = spots[index];
            var cross = new GeometryGroup();
            cross.Children.Add(new RectangleGeometry(new Rect(spot.X - 0.75, spot.Y - 3, 1.5, 6)));
            cross.Children.Add(new RectangleGeometry(new Rect(spot.X - 3, spot.Y - 0.75, 6, 1.5)));
            cross.Freeze();

            var star = new Path { Data = cross, Fill = spark, Opacity = 0, IsHitTestVisible = false };
            var grow = new ScaleTransform(0.2, 0.2, spot.X, spot.Y);
            star.RenderTransform = grow;
            extras.Children.Add(star);
            stars.Add(star);

            var delay = TimeSpan.FromSeconds(index * 0.12);
            var pop = Cycle(new[] { 0.2, 1.4, 0.2 }, new[] { 0.0, 0.4, 1.0 }, 0.9);
            var fade = Cycle(new[] { 0.0, 1.0, 0.0 }, new[] { 0.0, 0.35, 1.0 }, 0.9);
            foreach (var animation in new AnimationTimeline[] { pop, fade })
            {
                animation.BeginTime = delay;
                animation.RepeatBehavior = new RepeatBehavior(2);
                animation.FillBehavior = FillBehavior.Stop;
            }
            grow.BeginAnimation(ScaleTransform.ScaleXProperty, pop);
            grow.BeginAnimation(ScaleTransform.ScaleYProperty, pop);
            star.BeginAnimation(UIElement.OpacityProperty, fade);
        }
        After(2.4, () =>
        {
            foreach (var star in stars)
            {
                ClawdMotion.Stop(star);
                extras.Children.Remove(star);
            }
        });
    }

    public void Tilt(double radians)
    {
        tilt.Angle = radians * 180 / Math.PI;
    }

    /// Stops everything and takes Clawd, and any dust still in the air, off the canvas.
    public void Retire()
    {
        generation++;
        morphEnds = 0;
        Gear = ClawdGear.None;
        ClearGear();
        ClearExtras();
        foreach (UIElement leftover in host.Children)
        {
            ClawdMotion.Stop(leftover);
        }
        host.Children.Clear();
    }

    // MARK: Building

    private void Rebuild(ClawdLook next)
    {
        ClawdMotion.Stop(pieces.Content);
        flipper.Children.Remove(pieces.Content);
        Gear = ClawdGear.None;
        ClearGear();
        ClearExtras();
        pieces = ClawdArt.Build(next);
        Look = next;
        Install(pieces);
        Position = position;
    }

    /// The heart, the sleeping Zs and the stars all loop, so they are stopped as they go.
    private void ClearExtras()
    {
        foreach (UIElement extra in extras.Children)
        {
            ClawdMotion.Stop(extra);
        }
        extras.Children.Clear();
    }

    private void ClearGear()
    {
        foreach (UIElement piece in gear.Children)
        {
            ClawdMotion.Stop(piece);
        }
        gear.Children.Clear();
        gearShift.BeginAnimation(TranslateTransform.YProperty, null);
        gearShift.Y = 0;
    }

    private void Install(ClawdPieces next)
    {
        var size = next.Size;
        foreach (var canvas in new[] { root, flipper, gear, extras })
        {
            canvas.Width = size.Width;
            canvas.Height = size.Height;
        }
        grip.CenterX = size.Width / 2;
        grip.CenterY = 0;
        tilt.CenterX = size.Width / 2;
        tilt.CenterY = size.Height;
        squash.CenterX = size.Width / 2;
        squash.CenterY = size.Height;
        flip.CenterX = size.Width / 2;
        flip.CenterY = size.Height;

        lean = new RotateTransform(0, size.Width / 2, size.Height);
        bob = new TranslateTransform();
        next.Content.RenderTransform = new TransformGroup { Children = { lean, bob } };
        flipper.Children.Add(next.Content);

        if (next.HasBody) ApplyPose();
        else Blink();
    }

    // MARK: Poses

    private void ApplyPose()
    {
        const double u = Unit;
        bob.BeginAnimation(TranslateTransform.XProperty, null);
        bob.BeginAnimation(TranslateTransform.YProperty, null);
        bob.X = 0;
        bob.Y = 0;
        lean.BeginAnimation(RotateTransform.AngleProperty, null);
        lean.Angle = 0;
        grip.BeginAnimation(RotateTransform.AngleProperty, null);
        grip.Angle = 0;
        gearShift.BeginAnimation(TranslateTransform.YProperty, null);
        gearShift.Y = 0;
        pieces.LeftArm?.Rest();
        pieces.RightArm?.Rest();
        pieces.LegsA?.Rest();
        pieces.LegsB?.Rest();
        pieces.Eyes?.Rest();
        ClearExtras();
        SetEyes(ClawdEyes.Open);

        switch (Pose)
        {
            case ClawdPose.Walk:
                Loop(pieces.LegsA?.Shift, TranslateTransform.YProperty, new[] { 0, -0.9 * u, 0 }, Thirds, 0.34);
                Loop(pieces.LegsB?.Shift, TranslateTransform.YProperty, new[] { 0, -0.9 * u, 0 }, Thirds, 0.34, 0.5);
                Loop(bob, TranslateTransform.YProperty, new[] { 0, -0.45 * u, 0 }, Thirds, 0.17);
                Blink();
                break;

            case ClawdPose.Fall:
                Set(pieces.LeftArm, 0, -2.4 * u);
                Set(pieces.RightArm, 0, -2.4 * u);
                Set(pieces.LegsA, -0.4 * u, 0);
                Set(pieces.LegsB, 0.4 * u, 0);
                if (pieces.Eyes is { } wide) wide.Scale.ScaleY = 1.25;
                break;

            case ClawdPose.Sit:
                Fold();
                bob.Y = 2 * u;
                Blink();
                break;

            case ClawdPose.Sleep:
                Fold();
                bob.Y = 2 * u;
                SetEyes(ClawdEyes.Closed);
                Loop(bob, TranslateTransform.YProperty, new[] { 2 * u, 1.6 * u, 2 * u }, Thirds, 2.4);
                AddSnoring();
                break;

            case ClawdPose.Happy:
                SetEyes(ClawdEyes.Happy);
                Loop(bob, TranslateTransform.YProperty, new[] { 0, -3 * u, 0, 0 }, new[] { 0, 0.3, 0.6, 1.0 }, 0.5);
                AddHeart();
                break;

            case ClawdPose.Hang:
                // His paws hold an edge just above his head, so the body swings under them.
                Set(pieces.LeftArm, 0.5 * u, -6 * u);
                Set(pieces.RightArm, -0.5 * u, -6 * u);
                HangLift();
                Loop(grip, RotateTransform.AngleProperty, new[] { -5.0, 5, -5 }, Thirds, 3.4);
                Dangle();
                Blink();
                break;

            case ClawdPose.Wave:
                // One paw keeps hold, the other waves.
                SetEyes(ClawdEyes.Happy);
                Set(pieces.LeftArm, 0.5 * u, -6 * u);
                Set(pieces.RightArm, -0.5 * u, -6 * u);
                bob.Y = 1.5 * u;
                gearShift.Y = 1.5 * u;
                Loop(pieces.RightArm?.Shift, TranslateTransform.XProperty, new[] { -0.2 * u, 1.4 * u, -0.2 * u }, Thirds, 0.34);
                Loop(grip, RotateTransform.AngleProperty, new[] { 2.0, 8, 2 }, Thirds, 1.4);
                Dangle();
                break;

            case ClawdPose.Dance:
                // Paws up, one side and then the other, with a little sway.
                var up = new[] { 0, -3.2 * u, -3.2 * u, 0, 0 };
                var beat = new[] { 0, 0.2, 0.45, 0.65, 1.0 };
                Loop(pieces.LeftArm?.Shift, TranslateTransform.YProperty, up, beat, 1.2);
                Loop(pieces.RightArm?.Shift, TranslateTransform.YProperty, up, beat, 1.2, 0.5);
                Loop(lean, RotateTransform.AngleProperty, new[] { -4.0, 4, -4 }, Thirds, 1.2);
                Loop(pieces.LegsA?.Shift, TranslateTransform.YProperty, new[] { 0, -0.8 * u, 0 }, Thirds, 0.6);
                Loop(pieces.LegsB?.Shift, TranslateTransform.YProperty, new[] { 0, -0.8 * u, 0 }, Thirds, 0.6, 0.5);
                Blink();
                break;

            default:
                Blink();
                break;
        }
    }

    /// The odd pull up, driven on his body, his arms and whatever he carries at once,
    /// so his paws stay on the edge and a hard hat stays on his head.
    private void HangLift()
    {
        const double u = Unit;
        var lift = new[] { 1.5 * u, 1.5 * u, -0.7 * u, -0.7 * u, 1.5 * u, 1.5 * u };
        var beat = new[] { 0, 0.62, 0.72, 0.8, 0.9, 1.0 };
        var arms = new double[lift.Length];
        for (var index = 0; index < lift.Length; index++)
        {
            arms[index] = -4.5 * u - lift[index];
        }
        Loop(bob, TranslateTransform.YProperty, lift, beat, HangSeconds);
        Loop(gearShift, TranslateTransform.YProperty, lift, beat, HangSeconds);
        Loop(pieces.LeftArm?.Shift, TranslateTransform.YProperty, arms, beat, HangSeconds);
        Loop(pieces.RightArm?.Shift, TranslateTransform.YProperty, arms, beat, HangSeconds);
    }

    /// Legs swinging under him, one a little behind the other.
    private void Dangle()
    {
        const double u = Unit;
        var swing = new[] { -0.5 * u, 0.5 * u, -0.5 * u };
        Loop(pieces.LegsA?.Shift, TranslateTransform.XProperty, swing, Thirds, 2.6);
        Loop(pieces.LegsB?.Shift, TranslateTransform.XProperty, swing, Thirds, 2.6, 0.12);
    }

    private void Fold()
    {
        if (pieces.LegsA is { } a) a.Shape.Visibility = Visibility.Hidden;
        if (pieces.LegsB is { } b) b.Shape.Visibility = Visibility.Hidden;
    }

    private static void Set(ClawdPart? part, double x, double y)
    {
        if (part is null) return;
        part.Shift.X = x;
        part.Shift.Y = y;
    }

    private void SetEyes(ClawdEyes style)
    {
        if (Look != ClawdLook.Clawd || pieces.Eyes is not { } eyes) return;
        eyes.Shape.Data = ClawdArt.EyeShape(style, Unit, pieces.BodyTop);
    }

    private void Blink()
    {
        if (pieces.Eyes is not { } eyes) return;
        Loop(
            eyes.Scale,
            ScaleTransform.ScaleYProperty,
            new[] { 1, 1, 0.1, 1, 1, 0.1, 1, 1.0 },
            new[] { 0, 0.84, 0.865, 0.89, 0.92, 0.945, 0.97, 1.0 },
            5.2);
    }

    private void AddHeart()
    {
        var heart = new Path
        {
            Data = ClawdArt.HeartShape(1.6),
            Fill = Palette.Brush(Palette.Heart),
            IsHitTestVisible = false,
        };
        var float1 = new TranslateTransform();
        heart.RenderTransform = float1;
        Canvas.SetLeft(heart, pieces.Size.Width - 4);
        Canvas.SetTop(heart, -6);
        extras.Children.Add(heart);
        Loop(float1, TranslateTransform.YProperty, new[] { 0, -4, 0.0 }, Thirds, 1);
    }

    private void AddSnoring()
    {
        for (var index = 0; index < 3; index++)
        {
            var z = new Path
            {
                Data = ClawdArt.ZShape(0.9 + index * 0.35),
                Fill = Palette.Brush(Ink.Glint),
                Opacity = 0,
                IsHitTestVisible = false,
            };
            var drift = new TranslateTransform();
            z.RenderTransform = drift;
            Canvas.SetLeft(z, pieces.Size.Width * 0.85);
            Canvas.SetTop(z, -2);
            extras.Children.Add(z);

            var phase = (2 - index) / 3.0;
            Loop(drift, TranslateTransform.XProperty, new[] { 0, 14.0 }, Ends, 3, phase);
            Loop(drift, TranslateTransform.YProperty, new[] { 0, -18.0 }, Ends, 3, phase);
            Loop(z, UIElement.OpacityProperty, new[] { 0, 1, 1, 0.0 }, new[] { 0, 0.2, 0.7, 1.0 }, 3, phase);
        }
    }

    /// A ring of dust where Clawd was standing.
    private void Puff()
    {
        var center = new Point(position.X, position.Y - pieces.Size.Height / 2);
        var fill = Palette.Brush(Ink.Dust);
        var edge = Palette.Brush(Ink.DustEdge);
        var dots = new List<Path>(7);
        var random = Random.Shared;
        for (var index = 0; index < 7; index++)
        {
            var angle = index / 7.0 * 2 * Math.PI;
            var radius = 3 + random.NextDouble() * 2;
            var dot = new Path
            {
                Data = new EllipseGeometry(center, radius, radius),
                Fill = fill,
                Stroke = edge,
                StrokeThickness = 0.6,
                Opacity = 0,
                IsHitTestVisible = false,
            };
            var move = new TranslateTransform();
            var grow = new ScaleTransform(0.4, 0.4, center.X, center.Y);
            dot.RenderTransform = new TransformGroup { Children = { grow, move } };
            host.Children.Add(dot);
            dots.Add(dot);

            var span = TimeSpan.FromSeconds(0.45);
            var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };
            move.BeginAnimation(TranslateTransform.XProperty,
                new DoubleAnimation(0, Math.Cos(angle) * 16, span) { EasingFunction = ease, FillBehavior = FillBehavior.HoldEnd });
            move.BeginAnimation(TranslateTransform.YProperty,
                new DoubleAnimation(0, Math.Sin(angle) * 16, span) { EasingFunction = ease, FillBehavior = FillBehavior.HoldEnd });
            var swell = new DoubleAnimation(0.4, 1.2, span) { EasingFunction = ease, FillBehavior = FillBehavior.HoldEnd };
            grow.BeginAnimation(ScaleTransform.ScaleXProperty, swell);
            grow.BeginAnimation(ScaleTransform.ScaleYProperty, swell);
            var fade = Cycle(new[] { 0, 1, 0.0 }, new[] { 0, 0.2, 1.0 }, 0.45);
            fade.RepeatBehavior = new RepeatBehavior(1);
            fade.FillBehavior = FillBehavior.HoldEnd;
            dot.BeginAnimation(UIElement.OpacityProperty, fade);
        }
        After(0.55, () =>
        {
            foreach (var dot in dots)
            {
                ClawdMotion.Stop(dot);
                host.Children.Remove(dot);
            }
        });
    }

    // MARK: Animation helpers

    private static readonly double[] Thirds = { 0, 0.5, 1 };
    private static readonly double[] Quarters = { 0, 0.25, 0.5, 0.75, 1 };
    private static readonly double[] Ends = { 0, 1 };

    private static void Loop(
        IAnimatable? target,
        DependencyProperty property,
        double[] values,
        double[] times,
        double seconds,
        double phase = 0)
    {
        target?.BeginAnimation(property, Cycle(values, times, seconds, phase));
    }

    private static void Once(
        IAnimatable target,
        DependencyProperty property,
        double[] values,
        double[] times,
        double seconds)
    {
        var animation = Cycle(values, times, seconds);
        animation.RepeatBehavior = new RepeatBehavior(1);
        animation.FillBehavior = FillBehavior.Stop;
        target.BeginAnimation(property, animation);
    }

    private static DoubleAnimationUsingKeyFrames Cycle(double[] values, double[] times, double seconds, double phase = 0)
    {
        var (steps, stops) = Shift(values, times, phase);
        var animation = new DoubleAnimationUsingKeyFrames
        {
            Duration = TimeSpan.FromSeconds(seconds),
            RepeatBehavior = RepeatBehavior.Forever,
            FillBehavior = FillBehavior.HoldEnd,
        };
        for (var index = 0; index < steps.Length; index++)
        {
            animation.KeyFrames.Add(new LinearDoubleKeyFrame(
                steps[index],
                KeyTime.FromTimeSpan(TimeSpan.FromSeconds(seconds * stops[index]))));
        }
        return animation;
    }

    /// Starts the same loop part way through, which is how two legs end up out of step.
    private static (double[] Values, double[] Times) Shift(double[] values, double[] times, double phase)
    {
        if (phase <= 0) return (values, times);
        var edge = Sample(values, times, phase);
        var points = new List<(double Time, double Value)> { (0, edge), (1, edge) };
        for (var index = 0; index < times.Length; index++)
        {
            var moved = times[index] - phase;
            if (moved < 0) moved += 1;
            if (moved > 0 && moved < 1) points.Add((moved, values[index]));
        }
        points.Sort((left, right) => left.Time.CompareTo(right.Time));
        return (points.Select(point => point.Value).ToArray(), points.Select(point => point.Time).ToArray());
    }

    private static double Sample(double[] values, double[] times, double at)
    {
        for (var index = 1; index < times.Length; index++)
        {
            if (at > times[index]) continue;
            var span = times[index] - times[index - 1];
            var mix = span <= 0 ? 0 : (at - times[index - 1]) / span;
            return values[index - 1] + (values[index] - values[index - 1]) * mix;
        }
        return values[^1];
    }

    private static void After(double seconds, Action action)
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            action();
        };
        timer.Start();
    }
}
