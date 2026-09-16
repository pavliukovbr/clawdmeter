using System.Runtime.InteropServices;
using System.Windows.Threading;
using Clawdmeter.Activity;

namespace Clawdmeter.Platform;

/// Stops Windows from going to sleep on its own, so Claude can keep working while you are
/// away. The hold is dropped as soon as it is not needed or the app quits.
public sealed class KeepAwake : IDisposable
{
    private const uint Continuous = 0x80000000;
    private const uint SystemRequired = 0x00000001;
    private const uint DisplayRequired = 0x00000002;

    /// A quiet moment between two steps still counts as working.
    private static readonly TimeSpan Grace = TimeSpan.FromMinutes(2);

    private readonly ClaudeActivityWatcher watcher;
    private readonly Dispatcher dispatcher;
    private DispatcherTimer? timer;
    private bool holding;
    private bool holdingDisplay;
    private bool started;
    private bool disposed;

    public KeepAwake(ClaudeActivityWatcher watcher)
    {
        this.watcher = watcher;
        dispatcher = System.Windows.Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;
    }

    /// True while Windows is being held awake by us.
    public bool IsActive => holding;

    public void Start()
    {
        if (started || disposed) return;
        started = true;

        Settings.Changed += OnSettingsChanged;
        watcher.ActivityChanged += OnActivityChanged;
        if (System.Windows.Application.Current is { } app) app.Exit += OnExit;

        // The watcher only speaks up when something changes, so look again now and then.
        timer = new DispatcherTimer(TimeSpan.FromSeconds(30), DispatcherPriority.Background, (_, _) => Update(), dispatcher);
        Update();
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;

        if (started)
        {
            Settings.Changed -= OnSettingsChanged;
            watcher.ActivityChanged -= OnActivityChanged;
            if (System.Windows.Application.Current is { } app) app.Exit -= OnExit;
        }

        timer?.Stop();
        timer = null;
        OnDispatcher(Release);
    }

    private void OnSettingsChanged() => Post(Update);

    private void OnActivityChanged(ActivityEvent activity) => Post(Update);

    private void OnExit(object sender, System.Windows.ExitEventArgs e) => Dispose();

    private void Update()
    {
        if (disposed) return;
        var settings = Settings.Current;
        switch (settings.KeepAwake)
        {
            case KeepAwakeMode.Always:
                Hold(settings.KeepDisplayOn);
                break;
            case KeepAwakeMode.WhileClaudeWorks:
                if (watcher.IsClaudeWorking(Grace)) Hold(settings.KeepDisplayOn); else Release();
                break;
            default:
                Release();
                break;
        }
    }

    private void Hold(bool keepDisplay)
    {
        if (holding && holdingDisplay == keepDisplay) return;
        var flags = Continuous | SystemRequired | (keepDisplay ? DisplayRequired : 0u);
        if (SetThreadExecutionState(flags) == 0) return;
        holding = true;
        holdingDisplay = keepDisplay;
    }

    private void Release()
    {
        if (!holding) return;
        SetThreadExecutionState(Continuous);
        holding = false;
        holdingDisplay = false;
    }

    /// The hold belongs to the thread that asked for it, so everything runs on the same one.
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

    private void OnDispatcher(Action action)
    {
        if (dispatcher.CheckAccess())
        {
            action();
            return;
        }
        try
        {
            dispatcher.Invoke(action);
        }
        catch (InvalidOperationException)
        {
        }
        catch (TaskCanceledException)
        {
        }
    }

    [DllImport("kernel32.dll")]
    private static extern uint SetThreadExecutionState(uint flags);
}
