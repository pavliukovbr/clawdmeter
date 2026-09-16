using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using Clawdmeter.Pet;
using Clawdmeter.Usage;

namespace Clawdmeter.Ui;

/// The little card that floats on the desktop with your plan usage on it.
public sealed class PanelWindow : Window
{
    private const double CardWidth = 306;

    private readonly TextBlock planLabel = Label(11, 0.55);
    private readonly TextBlock primaryValue = new()
    {
        FontSize = 34,
        FontWeight = FontWeights.SemiBold,
        Foreground = Brushes.White,
        Margin = new Thickness(0, 2, 0, 0),
    };
    private readonly TextBlock primaryTitle = Label(12, 0.75);
    private readonly TextBlock primaryDetail = Label(11, 0.45);
    private readonly TextBlock todayLine = Label(11, 0.5);
    private readonly StackPanel meters = new() { Margin = new Thickness(0, 10, 0, 0) };
    private readonly ClawdBadge clawd = new() { Unit = 3, Width = 66, Height = 42 };
    private readonly StackPanel chart = new() { Orientation = Orientation.Horizontal, Height = 26, VerticalAlignment = VerticalAlignment.Bottom };

    public event Action? MenuRequested;

    public PanelWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        Width = CardWidth + 24;
        Title = "Clawdmeter";

        Content = BuildCard();
        MouseLeftButtonDown += OnDragStart;
        MouseRightButtonUp += (_, _) => MenuRequested?.Invoke();
        Loaded += (_, _) => Restore();
        Topmost = Settings.Current.PanelAlwaysOnTop;
    }

    private UIElement BuildCard()
    {
        var card = new Border
        {
            Width = CardWidth,
            CornerRadius = new CornerRadius(16),
            Background = Palette.Background(),
            BorderBrush = new SolidColorBrush(Color.FromArgb(28, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(16, 14, 16, 14),
            Margin = new Thickness(12),
            Effect = new DropShadowEffect
            {
                BlurRadius = 22,
                ShadowDepth = 4,
                Direction = 270,
                Opacity = 0.45,
                Color = Colors.Black,
            },
        };

        var head = new Grid();
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var left = new StackPanel();
        left.Children.Add(planLabel);
        left.Children.Add(primaryValue);
        left.Children.Add(primaryTitle);
        left.Children.Add(primaryDetail);
        head.Children.Add(left);

        var right = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right };
        right.Children.Add(clawd);
        right.Children.Add(chart);
        Grid.SetColumn(right, 1);
        head.Children.Add(right);

        var stack = new StackPanel();
        stack.Children.Add(head);
        stack.Children.Add(meters);
        stack.Children.Add(todayLine);
        todayLine.Margin = new Thickness(0, 10, 0, 0);

        card.Child = stack;
        return card;
    }

    public void Show(UsageSnapshot? snapshot)
    {
        var summary = new UsageSummary(snapshot, DateTimeOffset.Now);
        planLabel.Text = summary.PlanName.ToUpperInvariant();
        primaryValue.Text = summary.Primary.Value;
        primaryValue.Foreground = Palette.Brush(Palette.Tint(summary.Primary.Severity));
        primaryTitle.Text = summary.Primary.Title;
        primaryDetail.Text = summary.Note ?? summary.Primary.Detail ?? "";
        clawd.Mood = summary.Mood;

        meters.Children.Clear();
        foreach (var metric in summary.Secondary.Take(3))
        {
            meters.Children.Add(MeterRow(metric));
        }

        var activity = summary.Activity;
        todayLine.Text = activity is null
            ? ""
            : $"Today  {Format.Tokens(activity.TodayTokens)} tokens  ·  {activity.TodayMessages} requests";
        BuildChart(activity);
    }

    private static UIElement MeterRow(Metric metric)
    {
        var grid = new Grid { Margin = new Thickness(0, 6, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(74) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });

        var title = Label(11, 0.6);
        title.Text = metric.ShortTitle ?? metric.Title;
        title.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(title);

        var track = new Border
        {
            Height = 8,
            CornerRadius = new CornerRadius(4),
            Background = new SolidColorBrush(Color.FromArgb(38, 255, 255, 255)),
            VerticalAlignment = VerticalAlignment.Center,
        };
        var fill = new Rectangle
        {
            RadiusX = 4,
            RadiusY = 4,
            Fill = Palette.Fill(metric.Severity),
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        track.Child = fill;
        track.SizeChanged += (_, args) => fill.Width = Math.Max(6, args.NewSize.Width * Math.Clamp(metric.Fraction, 0, 1));
        Grid.SetColumn(track, 1);
        grid.Children.Add(track);

        var value = Label(11, 0.75);
        value.Text = metric.Value;
        value.HorizontalAlignment = HorizontalAlignment.Right;
        value.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(value, 2);
        grid.Children.Add(value);

        return grid;
    }

    private void BuildChart(ActivityLog? activity)
    {
        chart.Children.Clear();
        if (activity is null || activity.Days.Count == 0) return;
        var busiest = Math.Max(activity.Days.Max(day => day.Tokens), 1);
        foreach (var day in activity.Days)
        {
            var height = Math.Max(3, 26 * (double)day.Tokens / busiest);
            chart.Children.Add(new Rectangle
            {
                Width = 6,
                Height = height,
                RadiusX = 3,
                RadiusY = 3,
                Margin = new Thickness(2, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Bottom,
                Fill = Palette.Brush(day == activity.Days[^1] ? Palette.ClayLight : Color.FromArgb(90, 215, 119, 87)),
            });
        }
    }

    private void OnDragStart(object sender, MouseButtonEventArgs args)
    {
        DragMove();
        var settings = Settings.Current;
        settings.PanelLeft = Left;
        settings.PanelTop = Top;
        settings.Save();
    }

    private void Restore()
    {
        var settings = Settings.Current;
        var area = SystemParameters.WorkArea;
        Left = settings.PanelLeft is { } left && left > area.Left - Width && left < area.Right
            ? left
            : area.Right - Width - 12;
        Top = settings.PanelTop is { } top && top > area.Top - ActualHeight && top < area.Bottom
            ? top
            : area.Top + 24;
    }

    private static TextBlock Label(double size, double opacity) => new()
    {
        FontSize = size,
        Foreground = new SolidColorBrush(Color.FromArgb((byte)(opacity * 255), 255, 255, 255)),
        TextTrimming = TextTrimming.CharacterEllipsis,
    };
}
