using System.Windows.Media;

namespace Clawdmeter.Usage;

public static class Palette
{
    /// Clawd's own color.
    public static readonly Color Clay = Color.FromRgb(215, 119, 87);
    public static readonly Color ClayLight = Color.FromRgb(236, 150, 118);
    public static readonly Color ClayDeep = Color.FromRgb(190, 92, 62);

    public static readonly Color Amber = Color.FromRgb(245, 178, 76);
    public static readonly Color AmberDeep = Color.FromRgb(222, 140, 44);
    public static readonly Color Red = Color.FromRgb(255, 105, 94);
    public static readonly Color RedDeep = Color.FromRgb(226, 62, 58);

    public static readonly Color Sweat = Color.FromRgb(140, 204, 255);
    public static readonly Color Heart = Color.FromRgb(255, 110, 128);
    public static readonly Color Spark = Color.FromRgb(255, 214, 140);

    public static readonly Color BackgroundTop = Color.FromRgb(52, 43, 39);
    public static readonly Color BackgroundBottom = Color.FromRgb(29, 25, 23);

    public static LinearGradientBrush Background()
    {
        var brush = new LinearGradientBrush(BackgroundTop, BackgroundBottom, 90);
        brush.Freeze();
        return brush;
    }

    public static LinearGradientBrush Fill(Severity severity)
    {
        var (from, to) = severity switch
        {
            Severity.Warning => (AmberDeep, Amber),
            Severity.Critical => (RedDeep, Red),
            _ => (ClayDeep, ClayLight),
        };
        var brush = new LinearGradientBrush(from, to, 0);
        brush.Freeze();
        return brush;
    }

    public static Color Tint(Severity severity) => severity switch
    {
        Severity.Warning => Amber,
        Severity.Critical => Red,
        _ => ClayLight,
    };

    public static SolidColorBrush Brush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
