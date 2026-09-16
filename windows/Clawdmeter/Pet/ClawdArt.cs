using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Clawdmeter.Usage;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;
using Size = System.Windows.Size;

namespace Clawdmeter.Pet;

public enum ClawdLook { Clawd, WindowsLogo, Folder, WindowButton, WebSuit, PopStar }

public enum ClawdPose { Stand, Walk, Fall, Sit, Sleep, Happy, Work, Dance }

public enum ClawdEyes { Open, Closed, Happy }

/// One piece of Clawd the poses can move: the shape plus the two transforms they drive.
public sealed class ClawdPart
{
    public ClawdPart(Path shape, Point center)
    {
        Shape = shape;
        Scale = new ScaleTransform(1, 1, center.X, center.Y);
        shape.RenderTransform = new TransformGroup { Children = { Scale, Shift } };
    }

    public Path Shape { get; }
    public TranslateTransform Shift { get; } = new();
    public ScaleTransform Scale { get; }

    public void Rest()
    {
        Shift.BeginAnimation(TranslateTransform.XProperty, null);
        Shift.BeginAnimation(TranslateTransform.YProperty, null);
        Scale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
        Scale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
        Shift.X = 0;
        Shift.Y = 0;
        Scale.ScaleX = 1;
        Scale.ScaleY = 1;
        Shape.Visibility = Visibility.Visible;
    }
}

/// The layers of one drawn look, handed back so the sprite can animate them.
public sealed class ClawdPieces
{
    public required Canvas Content { get; init; }
    public required Size Size { get; init; }
    /// Rows added above Clawd's head for hats and hair.
    public double BodyTop { get; init; }
    public bool HasBody { get; init; }
    public ClawdPart? LeftArm { get; init; }
    public ClawdPart? RightArm { get; init; }
    public ClawdPart? LegsA { get; init; }
    public ClawdPart? LegsB { get; init; }
    public ClawdPart? Eyes { get; init; }
}

/// Clawd and his disguises, drawn as rectangles on a pixel grid.
public static class ClawdArt
{
    /// The pixel size Clawd is drawn at while he walks around the desktop.
    public const double RoamUnit = 2.5;

    private static readonly Rect Core = new(2, 0, 12, 8);
    private static readonly Rect LeftArm = new(0, 4, 2, 2);
    private static readonly Rect RightArm = new(14, 4, 2, 2);
    private static readonly Rect[] LegsA = { new(3, 7, 1, 3), new(10, 7, 1, 3) };
    private static readonly Rect[] LegsB = { new(5, 7, 1, 3), new(12, 7, 1, 3) };

    private static readonly Rect[] HeartCells =
    {
        new(1, 0, 2, 1), new(4, 0, 2, 1),
        new(0, 1, 7, 2),
        new(1, 3, 5, 1),
        new(2, 4, 3, 1),
        new(3, 5, 1, 1),
    };

    private static readonly Rect[] ZCells =
    {
        new(0, 0, 5, 1),
        new(3, 1, 1, 1),
        new(2, 2, 1, 1),
        new(1, 3, 1, 1),
        new(0, 4, 5, 1),
    };

    public static ClawdPieces Build(ClawdLook look) => look switch
    {
        ClawdLook.Folder => BuildFolder(),
        ClawdLook.WindowsLogo => BuildWindowsLogo(),
        ClawdLook.WindowButton => BuildWindowButton(),
        _ => BuildBody(look),
    };

    public static bool HasBody(ClawdLook look)
        => look is ClawdLook.Clawd or ClawdLook.WebSuit or ClawdLook.PopStar;

    /// Clawd's eyes for one expression, in the grid of the given unit.
    public static Geometry EyeShape(ClawdEyes style, double unit, double top)
    {
        var cells = new List<Rect>(6);
        foreach (var column in new double[] { 4, 11 })
        {
            switch (style)
            {
                case ClawdEyes.Closed:
                    cells.Add(new Rect(column - 0.5, 3, 2, 0.5));
                    break;
                case ClawdEyes.Happy:
                    cells.Add(new Rect(column - 0.5, 2.75, 0.5, 1));
                    cells.Add(new Rect(column, 2.25, 1, 0.5));
                    cells.Add(new Rect(column + 1, 2.75, 0.5, 1));
                    break;
                default:
                    cells.Add(new Rect(column, 2, 1, 2));
                    break;
            }
        }
        return Pixels(cells.Select(cell => new Rect(cell.X, cell.Y + top, cell.Width, cell.Height)), unit);
    }

    public static Geometry Pixels(IEnumerable<Rect> cells, double unit)
    {
        var group = new GeometryGroup();
        foreach (var cell in cells)
        {
            group.Children.Add(new RectangleGeometry(
                new Rect(cell.X * unit, cell.Y * unit, cell.Width * unit, cell.Height * unit)));
        }
        group.Freeze();
        return group;
    }

    public static Geometry HeartShape(double unit) => Pixels(HeartCells, unit);

    public static Geometry ZShape(double unit) => Pixels(ZCells, unit);

    private static Path Shape(IEnumerable<Rect> cells, Color color, double unit)
        => new() { Data = Pixels(cells, unit), Fill = Palette.Brush(color) };

    // MARK: Clawd himself

    private static ClawdPieces BuildBody(ClawdLook look)
    {
        const double u = RoamUnit;
        var top = look == ClawdLook.PopStar ? 4.5 : 0;
        var suit = look == ClawdLook.WebSuit;
        var skin = suit ? Ink.SuitRed : Palette.Clay;
        var limbs = suit ? Ink.SuitBlue : Palette.Clay;
        var size = new Size(16 * u, (10 + top) * u);
        var canvas = new Canvas { Width = size.Width, Height = size.Height, IsHitTestVisible = false };
        var feet = new Point(size.Width / 2, size.Height);

        IEnumerable<Rect> Down(IEnumerable<Rect> cells)
            => cells.Select(cell => new Rect(cell.X, cell.Y + top, cell.Width, cell.Height));

        var legsA = new ClawdPart(Shape(Down(LegsA), limbs, u), feet);
        var legsB = new ClawdPart(Shape(Down(LegsB), limbs, u), feet);
        var left = new ClawdPart(Shape(Down(new[] { LeftArm }), limbs, u), feet);
        var right = new ClawdPart(Shape(Down(new[] { RightArm }), limbs, u), feet);
        foreach (var part in new[] { legsA, legsB, left, right })
        {
            canvas.Children.Add(part.Shape);
        }
        canvas.Children.Add(Shape(Down(new[] { Core }), skin, u));

        ClawdPart? eyes = null;
        switch (look)
        {
            case ClawdLook.WebSuit:
                canvas.Children.Add(Shape(Down(new Rect[] { new(2, 5, 2, 3), new(12, 5, 2, 3) }), Ink.SuitBlue, u));
                canvas.Children.Add(WebLines(u));
                var lenses = new Path
                {
                    Data = Lenses(u),
                    Fill = Palette.Brush(Ink.White),
                    Stroke = Palette.Brush(Ink.Eye),
                    StrokeThickness = 1.2,
                };
                eyes = new ClawdPart(lenses, new Point(8 * u, 2.7 * u));
                canvas.Children.Add(lenses);
                break;

            case ClawdLook.PopStar:
                // Platinum hair with the famous bow, and dark glasses.
                canvas.Children.Add(Shape(
                    new Rect[] { new(1.5, 2.5, 13, 2.5), new(1, 4, 2.2, 4.5), new(12.8, 4, 2.2, 4.5) }, Ink.Hair, u));
                canvas.Children.Add(Shape(
                    new Rect[] { new(4.5, 0, 3, 2.5), new(8.5, 0, 3, 2.5), new(7.2, 0.7, 1.6, 1.6) }, Ink.HairShade, u));
                canvas.Children.Add(Shape(
                    Down(new Rect[] { new(3.4, 1.7, 3.8, 2), new(8.8, 1.7, 3.8, 2), new(7.2, 2.1, 1.6, 0.5) }), Ink.Eye, u));
                canvas.Children.Add(Shape(
                    Down(new Rect[] { new(3.9, 2, 0.8, 0.5), new(9.3, 2, 0.8, 0.5) }), Ink.Glint, u));
                break;

            default:
                var plain = new Path { Data = EyeShape(ClawdEyes.Open, u, top), Fill = Palette.Brush(Ink.Eye) };
                eyes = new ClawdPart(plain, new Point(8 * u, (3 + top) * u));
                canvas.Children.Add(plain);
                break;
        }

        return new ClawdPieces
        {
            Content = canvas,
            Size = size,
            BodyTop = top,
            HasBody = true,
            LeftArm = left,
            RightArm = right,
            LegsA = legsA,
            LegsB = legsB,
            Eyes = eyes,
        };
    }

    private static Path WebLines(double unit)
    {
        var group = new GeometryGroup();
        foreach (var x in new double[] { 5, 8, 11 })
        {
            group.Children.Add(new LineGeometry(new Point(x * unit, 0), new Point(x * unit, 8 * unit)));
        }
        foreach (var y in new double[] { 2.5, 5.5 })
        {
            group.Children.Add(new LineGeometry(new Point(2 * unit, y * unit), new Point(14 * unit, y * unit)));
        }
        group.Freeze();
        return new Path { Data = group, Stroke = Palette.Brush(Ink.SuitLine), StrokeThickness = 0.6 };
    }

    private static Geometry Lenses(double unit)
    {
        var group = new GeometryGroup();
        group.Children.Add(new EllipseGeometry(new Rect(3 * unit, 1.4 * unit, 3.2 * unit, 2.6 * unit)));
        group.Children.Add(new EllipseGeometry(new Rect(9.8 * unit, 1.4 * unit, 3.2 * unit, 2.6 * unit)));
        group.Freeze();
        return group;
    }

    // MARK: Disguises

    /// Four orange panes with Clawd's eyes in them. Drawn here, not borrowed from anybody.
    private static ClawdPieces BuildWindowsLogo()
    {
        const double u = 2.2;
        var size = new Size(11 * u, 11 * u);
        var canvas = new Canvas { Width = size.Width, Height = size.Height, IsHitTestVisible = false };
        canvas.Children.Add(Shape(new Rect[] { new(0, 0, 5, 5), new(6, 0, 5, 5) }, Palette.ClayLight, u));
        canvas.Children.Add(Shape(new Rect[] { new(0, 6, 5, 5), new(6, 6, 5, 5) }, Palette.Clay, u));
        var eyes = new Path
        {
            Data = Pixels(new Rect[] { new(2, 2, 1, 2), new(8, 2, 1, 2) }, u),
            Fill = Palette.Brush(Ink.Eye),
        };
        canvas.Children.Add(eyes);
        return new ClawdPieces
        {
            Content = canvas,
            Size = size,
            Eyes = new ClawdPart(eyes, new Point(5.5 * u, 3 * u)),
        };
    }

    private static ClawdPieces BuildFolder()
    {
        const double u = RoamUnit;
        var size = new Size(14 * u, 11.5 * u);
        var canvas = new Canvas { Width = size.Width, Height = size.Height, IsHitTestVisible = false };
        canvas.Children.Add(Shape(new Rect[] { new(1, 0, 5, 1.5), new(0, 1, 14, 9) }, Ink.FolderBack, u));
        canvas.Children.Add(Shape(new Rect[] { new(0, 3, 14, 7) }, Ink.Folder, u));
        canvas.Children.Add(Shape(new Rect[] { new(3, 10, 1, 1.5), new(10, 10, 1, 1.5) }, Palette.Clay, u));
        var eyes = new Path
        {
            Data = Pixels(new Rect[] { new(4, 5, 1, 2), new(9, 5, 1, 2) }, u),
            Fill = Palette.Brush(Ink.Eye),
        };
        canvas.Children.Add(eyes);
        return new ClawdPieces
        {
            Content = canvas,
            Size = size,
            Eyes = new ClawdPart(eyes, new Point(7 * u, 6 * u)),
        };
    }

    /// A fourth caption button in Clawd orange, to sit beside the real three.
    private static ClawdPieces BuildWindowButton()
    {
        var size = new Size(34, 24);
        var canvas = new Canvas { Width = size.Width, Height = size.Height, IsHitTestVisible = false };
        var plate = new Path
        {
            Data = new RectangleGeometry(new Rect(0.5, 0.5, size.Width - 1, size.Height - 1), 4, 4),
            Fill = Palette.Brush(Palette.Clay),
            Stroke = Palette.Brush(Palette.ClayDeep),
            StrokeThickness = 0.8,
        };
        canvas.Children.Add(plate);
        var eyes = new Path
        {
            Data = Pixels(new Rect[] { new(12, 8, 3, 8), new(19, 8, 3, 8) }, 1),
            Fill = Palette.Brush(Ink.Eye),
        };
        canvas.Children.Add(eyes);
        return new ClawdPieces
        {
            Content = canvas,
            Size = size,
            Eyes = new ClawdPart(eyes, new Point(17, 12)),
        };
    }
}

/// The few colors Clawd needs that the usage palette does not carry.
internal static class Ink
{
    public static readonly Color Eye = Color.FromRgb(20, 16, 14);
    public static readonly Color White = Color.FromRgb(255, 255, 255);
    public static readonly Color Glint = Color.FromArgb(217, 255, 255, 255);
    public static readonly Color Folder = Color.FromRgb(97, 179, 245);
    public static readonly Color FolderBack = Color.FromRgb(71, 148, 224);
    public static readonly Color SuitRed = Color.FromRgb(214, 41, 43);
    public static readonly Color SuitBlue = Color.FromRgb(43, 84, 204);
    public static readonly Color SuitLine = Color.FromArgb(230, 115, 13, 18);
    public static readonly Color Hair = Color.FromRgb(247, 237, 199);
    public static readonly Color HairShade = Color.FromRgb(230, 212, 153);
    public static readonly Color Dust = Color.FromArgb(242, 245, 245, 245);
    public static readonly Color DustEdge = Color.FromArgb(64, 0, 0, 0);
    public static readonly Color Web = Color.FromArgb(242, 247, 247, 247);
    public static readonly Color Ball = Color.FromRgb(184, 184, 184);
    public static readonly Color BallShade = Color.FromRgb(115, 115, 115);
    public static readonly Color Cord = Color.FromArgb(230, 204, 204, 204);
}

/// A small breathing Clawd for the usage panel. Draws itself, so it costs one
/// element and one slow timer rather than a tree of animated shapes.
public sealed class ClawdBadge : FrameworkElement
{
    private const double Columns = 20;
    private const double Rows = 13;
    /// Rows kept free above Clawd for the z's and the heart.
    private const double Top = 3;

    public static readonly DependencyProperty MoodProperty = DependencyProperty.Register(
        nameof(Mood),
        typeof(ClawdMood),
        typeof(ClawdBadge),
        new FrameworkPropertyMetadata(ClawdMood.Idle, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty UnitProperty = DependencyProperty.Register(
        nameof(Unit),
        typeof(double),
        typeof(ClawdBadge),
        new FrameworkPropertyMetadata(
            3.0,
            FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsRender));

    private static readonly Brush Body = Palette.Brush(Palette.Clay);
    private static readonly Brush EyeInk = Palette.Brush(Ink.Eye);
    private static readonly Brush HeartInk = Palette.Brush(Palette.Heart);
    private static readonly Brush SweatInk = Palette.Brush(Palette.Sweat);
    private static readonly Brush Snore = Palette.Brush(Ink.Glint);
    private static readonly Geometry DropShape = BuildDrop();

    private readonly DispatcherTimer timer = new(DispatcherPriority.Render)
    {
        Interval = TimeSpan.FromMilliseconds(33),
    };

    private readonly System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();

    public ClawdBadge()
    {
        IsHitTestVisible = false;
        timer.Tick += (_, _) => InvalidateVisual();
        IsVisibleChanged += (_, _) => Follow();
        Loaded += (_, _) => Follow();
        Unloaded += (_, _) => timer.Stop();
    }

    public ClawdMood Mood
    {
        get => (ClawdMood)GetValue(MoodProperty);
        set => SetValue(MoodProperty, value);
    }

    public double Unit
    {
        get => (double)GetValue(UnitProperty);
        set => SetValue(UnitProperty, value);
    }

    private void Follow()
    {
        if (IsVisible) timer.Start();
        else timer.Stop();
    }

    protected override Size MeasureOverride(Size available) => new(Columns * Unit, Rows * Unit);

    protected override void OnRender(DrawingContext context)
    {
        var unit = Unit;
        var time = clock.Elapsed.TotalSeconds;
        var motion = BadgeMotion.For(Mood);

        var legLift = -motion.FeetLift * Wave(time, 1, 0);
        var legLiftB = -motion.FeetLift * Wave(time, 1, Math.PI);
        Cells(context, Body, unit, 0, Top + legLift, ClawdBadgeCells.LegsA);
        Cells(context, Body, unit, 0, Top + legLiftB, ClawdBadgeCells.LegsB);

        var leftLift = -motion.ArmLift * Wave(time, motion.ArmPeriod, motion.LeftArmPhase);
        var rightLift = -motion.ArmLift * Wave(time, motion.ArmPeriod, motion.RightArmPhase);
        Cells(context, Body, unit, 0, Top + leftLift, ClawdBadgeCells.LeftArm);
        Cells(context, Body, unit, 0, Top + rightLift, ClawdBadgeCells.RightArm);

        var bodyLift = -motion.BodyLift * Wave(time, motion.BodyPeriod, 0);
        Cells(context, Body, unit, 0, Top + bodyLift, ClawdBadgeCells.Core);
        DrawEyes(context, unit, Top + bodyLift, motion, time);
        DrawExtras(context, unit, time);
    }

    private void DrawEyes(DrawingContext context, double unit, double top, BadgeMotion motion, double time)
    {
        var squash = motion.Blinks ? Blink(time, motion.DoubleBlink) : 1;
        var glance = motion.Glance <= 0
            ? 0
            : motion.Glance * (Math.Cos(2 * Math.PI * time / 12) + 0.12 * Math.Cos(2 * Math.PI * time / 4));

        foreach (var cell in EyeCells(Mood))
        {
            var height = cell.Height * squash;
            var slack = (cell.Height - height) / 2;
            context.DrawRectangle(EyeInk, null, new Rect(
                (cell.X + glance) * unit,
                (cell.Y + top + slack) * unit,
                cell.Width * unit,
                height * unit));
        }
    }

    private void DrawExtras(DrawingContext context, double unit, double time)
    {
        switch (Mood)
        {
            case ClawdMood.Sleeping:
                for (var index = 0; index < 3; index++)
                {
                    var step = ((time + index) % 3) / 3;
                    var scale = (0.3 + step * 0.26) * unit;
                    var alpha = step < 0.2 ? step / 0.2 : Math.Min(1, (1 - step) / 0.3);
                    Glyph(context, ClawdArt.ZShape(scale), Snore, alpha,
                        (15.2 + step * 2) * unit, (3.4 - step * 3.2) * unit);
                }
                break;

            case ClawdMood.Busy:
            case ClawdMood.Tired:
                var period = Mood == ClawdMood.Busy ? 2 : 3;
                var slide = (time % period) / period;
                var fade = slide < 0.25 ? slide / 0.25 : Math.Min(1, (1 - slide) / 0.45);
                var shape = new TransformGroup();
                shape.Children.Add(new ScaleTransform(1.6 * unit, 2.2 * unit));
                shape.Children.Add(new TranslateTransform(
                    (14.3 + slide * 1.3) * unit, (Top - 0.5 + slide * 2.4) * unit));
                context.PushOpacity(fade);
                context.PushTransform(shape);
                context.DrawGeometry(SweatInk, null, DropShape);
                context.Pop();
                context.Pop();
                break;

            case ClawdMood.Happy:
                var float1 = -0.7 * Wave(time, 1.5, 0);
                Glyph(context, ClawdArt.HeartShape(0.55 * unit), HeartInk, 1,
                    15.4 * unit, (0.9 + float1) * unit);
                break;
        }
    }

    private static void Glyph(DrawingContext context, Geometry glyph, Brush brush, double alpha, double x, double y)
    {
        if (alpha <= 0.01) return;
        context.PushOpacity(Math.Clamp(alpha, 0, 1));
        context.PushTransform(new TranslateTransform(x, y));
        context.DrawGeometry(brush, null, glyph);
        context.Pop();
        context.Pop();
    }

    private static void Cells(DrawingContext context, Brush brush, double unit, double dx, double dy, Rect[] cells)
    {
        foreach (var cell in cells)
        {
            context.DrawRectangle(brush, null, new Rect(
                (cell.X + dx) * unit, (cell.Y + dy) * unit, cell.Width * unit, cell.Height * unit));
        }
    }

    private static Rect[] EyeCells(ClawdMood mood)
    {
        var cells = new List<Rect>(6);
        foreach (var column in new double[] { 4, 11 })
        {
            switch (mood)
            {
                case ClawdMood.Tired:
                    cells.Add(new Rect(column, 3, 1, 1));
                    break;
                case ClawdMood.Sleeping:
                    cells.Add(new Rect(column - 0.5, 3, 2, 0.5));
                    break;
                case ClawdMood.Happy:
                    cells.Add(new Rect(column - 0.5, 2.75, 0.5, 1));
                    cells.Add(new Rect(column, 2.25, 1, 0.5));
                    cells.Add(new Rect(column + 1, 2.75, 0.5, 1));
                    break;
                default:
                    cells.Add(new Rect(column, 2, 1, 2));
                    break;
            }
        }
        return cells.ToArray();
    }

    /// Zero at the start of the cycle, one in the middle, back to zero at the end.
    private static double Wave(double time, double period, double phase)
        => (1 - Math.Cos(2 * Math.PI * time / period + phase)) / 2;

    /// Eyes stay open most of the cycle and snap shut near the end of it.
    private static double Blink(double time, bool twice)
    {
        var step = time % 5.2 / 5.2;
        var shut = Pinch(step, 0.85);
        return twice ? Math.Min(shut, Pinch(step, 0.91)) : shut;
    }

    private static double Pinch(double step, double at)
    {
        var gap = Math.Abs(step - at);
        return gap > 0.02 ? 1 : 0.1 + 0.9 * (gap / 0.02);
    }

    private static Geometry BuildDrop()
    {
        var drop = new StreamGeometry();
        using (var sink = drop.Open())
        {
            sink.BeginFigure(new Point(0.5, 0), true, true);
            sink.QuadraticBezierTo(new Point(1, 0.4), new Point(1, 0.7), true, false);
            sink.ArcTo(new Point(0, 0.7), new Size(0.5, 0.3), 0, false, SweepDirection.Clockwise, true, false);
            sink.QuadraticBezierTo(new Point(0, 0.4), new Point(0.5, 0), true, false);
        }
        drop.Freeze();
        return drop;
    }
}

internal static class ClawdBadgeCells
{
    public static readonly Rect[] Core = { new(2, 0, 12, 8) };
    public static readonly Rect[] LeftArm = { new(0, 4, 2, 2) };
    public static readonly Rect[] RightArm = { new(14, 4, 2, 2) };
    public static readonly Rect[] LegsA = { new(3, 7, 1, 3), new(10, 7, 1, 3) };
    public static readonly Rect[] LegsB = { new(5, 7, 1, 3), new(12, 7, 1, 3) };
}

/// How each mood moves. Every period divides twelve seconds, so the loops line up.
internal readonly struct BadgeMotion
{
    public double BodyLift { get; private init; }
    public double BodyPeriod { get; private init; }
    public double ArmLift { get; private init; }
    public double ArmPeriod { get; private init; }
    public double LeftArmPhase { get; private init; }
    public double RightArmPhase { get; private init; }
    public double FeetLift { get; private init; }
    public double Glance { get; private init; }
    public bool Blinks { get; private init; }
    public bool DoubleBlink { get; private init; }

    public static BadgeMotion For(ClawdMood mood)
    {
        var motion = new BadgeMotion
        {
            BodyLift = 0.6,
            BodyPeriod = 3,
            ArmLift = 0.6,
            ArmPeriod = 3,
            LeftArmPhase = 0.7,
            RightArmPhase = 0.7,
            Blinks = true,
        };
        return mood switch
        {
            ClawdMood.Busy => motion with
            {
                BodyLift = 0.45,
                BodyPeriod = 1.5,
                ArmLift = 0.7,
                ArmPeriod = 0.5,
                LeftArmPhase = 0,
                RightArmPhase = Math.PI,
                FeetLift = 0.35,
            },
            ClawdMood.Tired => motion with
            {
                BodyLift = 0.3,
                ArmLift = 0.35,
                LeftArmPhase = 1,
                RightArmPhase = 1,
            },
            ClawdMood.Sleeping => motion with
            {
                BodyLift = 0.35,
                BodyPeriod = 6,
                ArmLift = 0.3,
                ArmPeriod = 6,
                LeftArmPhase = 0.6,
                RightArmPhase = 0.6,
                Blinks = false,
            },
            ClawdMood.Happy => motion with
            {
                BodyLift = 1,
                BodyPeriod = 0.75,
                ArmLift = 1.1,
                ArmPeriod = 0.75,
                LeftArmPhase = 0.9,
                RightArmPhase = 0.9,
                Blinks = false,
            },
            _ => motion with { Glance = 0.4, DoubleBlink = true },
        };
    }
}
