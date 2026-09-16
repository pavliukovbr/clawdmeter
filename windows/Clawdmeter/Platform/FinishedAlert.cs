using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Clawdmeter.Activity;
using Clawdmeter.Usage;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;

namespace Clawdmeter.Platform;

/// A small banner above the taskbar when Claude finishes something that took a while, so you
/// can look away while it works. It never takes the focus from whatever you are doing.
public sealed class FinishedAlert : IDisposable
{
    private const int GwlExStyle = -20;
    private const int WsExNoActivate = 0x08000000;
    private const int WsExToolWindow = 0x00000080;

    /// Quick answers do not need a banner.
    private const double MinimumSeconds = 20;

    private static readonly TimeSpan Fresh = TimeSpan.FromMinutes(2);
    private static readonly TimeSpan OnScreen = TimeSpan.FromSeconds(5);

    private readonly ClaudeActivityWatcher watcher;
    private readonly Dispatcher dispatcher;
    private readonly DateTimeOffset launchedAt = DateTimeOffset.Now;
    private DateTimeOffset lastShown = DateTimeOffset.MinValue;
    private Window? current;
    private DispatcherTimer? hide;
    private bool started;
    private bool disposed;

    public FinishedAlert(ClaudeActivityWatcher watcher)
    {
        this.watcher = watcher;
        dispatcher = System.Windows.Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;
    }

    public void Start()
    {
        if (started || disposed) return;
        started = true;
        watcher.TurnFinished += OnTurnFinished;
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (started) watcher.TurnFinished -= OnTurnFinished;
        Post(CloseNow);
    }

    private void OnTurnFinished(FinishedTurn turn)
    {
        if (disposed || !Settings.Current.NotifyWhenClaudeFinishes) return;
        if (turn.Date <= launchedAt || turn.Date <= lastShown) return;
        if (DateTimeOffset.Now - turn.Date > Fresh) return;
        if (turn.Duration is { } duration && duration < MinimumSeconds) return;
        lastShown = turn.Date;
        Post(() => Show(turn));
    }

    private void Show(FinishedTurn turn)
    {
        if (disposed) return;
        CloseNow();

        var window = Build(turn);
        window.SourceInitialized += (_, _) => KeepInactive(window);
        window.Loaded += (_, _) => Place(window);
        window.SizeChanged += (_, _) => Place(window);
        window.PreviewMouseDown += (_, _) => Dismiss();

        current = window;
        try
        {
            window.Show();
        }
        catch (InvalidOperationException)
        {
            current = null;
            return;
        }

        Fade(window, 0, 1, 0.22, null);
        hide = new DispatcherTimer(OnScreen, DispatcherPriority.Normal, (_, _) => Dismiss(), dispatcher);
    }

    private void Dismiss()
    {
        hide?.Stop();
        hide = null;
        var window = current;
        current = null;
        if (window is null) return;
        Fade(window, window.Opacity, 0, 0.22, () => SafeClose(window));
    }

    private void CloseNow()
    {
        hide?.Stop();
        hide = null;
        var window = current;
        current = null;
        if (window is not null) SafeClose(window);
    }

    // MARK: The banner

    private static Window Build(FinishedTurn turn)
    {
        var accent = new Border
        {
            Width = 4,
            CornerRadius = new CornerRadius(2),
            Background = Palette.Brush(Palette.Clay),
            Margin = new Thickness(0, 0, 12, 0),
        };

        var title = new TextBlock
        {
            Text = "Claude finished",
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            Foreground = Palette.Brush(Palette.ClayLight),
        };

        var line = new TextBlock
        {
            Text = Format.Finished(turn),
            FontSize = 12,
            Margin = new Thickness(0, 3, 0, 0),
            TextWrapping = TextWrapping.Wrap,
            Foreground = Palette.Brush(Color.FromRgb(232, 223, 216)),
        };

        var text = new StackPanel();
        text.Children.Add(title);
        text.Children.Add(line);

        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(accent, 0);
        Grid.SetColumn(text, 1);
        row.Children.Add(accent);
        row.Children.Add(text);

        var card = new Border
        {
            CornerRadius = new CornerRadius(12),
            Background = Palette.Background(),
            BorderBrush = Palette.Brush(Color.FromArgb(110, Palette.Clay.R, Palette.Clay.G, Palette.Clay.B)),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(14, 12, 16, 12),
            Margin = new Thickness(12),
            Child = row,
            Effect = new DropShadowEffect
            {
                BlurRadius = 18,
                ShadowDepth = 3,
                Direction = 270,
                Opacity = 0.5,
            },
        };

        return new Window
        {
            Title = "Clawdmeter",
            Width = 320,
            SizeToContent = SizeToContent.Height,
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            ShowInTaskbar = false,
            ShowActivated = false,
            Topmost = true,
            ResizeMode = ResizeMode.NoResize,
            Focusable = false,
            Opacity = 0,
            Content = card,
        };
    }

    /// The bottom right corner of the desktop, which already leaves the taskbar alone.
    private static void Place(Window window)
    {
        var area = SystemParameters.WorkArea;
        if (area.Width <= 0 || area.Height <= 0) return;
        window.Left = area.Right - window.ActualWidth;
        window.Top = area.Bottom - window.ActualHeight;
    }

    /// Clicks still land on the banner, but it never pulls the focus off your work.
    private static void KeepInactive(Window window)
    {
        try
        {
            var handle = new WindowInteropHelper(window).Handle;
            if (handle == IntPtr.Zero) return;
            var style = GetWindowLong(handle, GwlExStyle);
            SetWindowLong(handle, GwlExStyle, style | WsExNoActivate | WsExToolWindow);
        }
        catch (Exception exception) when (exception is InvalidOperationException or EntryPointNotFoundException or DllNotFoundException)
        {
        }
    }

    private static void Fade(Window window, double from, double to, double seconds, Action? done)
    {
        var animation = new DoubleAnimation(from, to, TimeSpan.FromSeconds(seconds))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
        };
        if (done is not null) animation.Completed += (_, _) => done();
        window.BeginAnimation(UIElement.OpacityProperty, animation);
    }

    private static void SafeClose(Window window)
    {
        try
        {
            window.BeginAnimation(UIElement.OpacityProperty, null);
            window.Close();
        }
        catch (InvalidOperationException)
        {
        }
    }

    private void Post(Action action)
    {
        if (dispatcher.CheckAccess())
        {
            action();
            return;
        }
        try
        {
            dispatcher.BeginInvoke(action);
        }
        catch (InvalidOperationException)
        {
        }
        catch (TaskCanceledException)
        {
        }
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr window, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")]
    private static extern int SetWindowLong(IntPtr window, int index, int style);
}
