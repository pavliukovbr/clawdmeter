using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Threading;
using Clawdmeter.Activity;
using Clawdmeter.Pet;
using Clawdmeter.Platform;
using Clawdmeter.Ui;
using Clawdmeter.Usage;
using Application = System.Windows.Application;

namespace Clawdmeter;

public partial class App : Application
{
    private Mutex? single;
    private NotifyIcon? tray;
    private ContextMenuStrip? menu;
    private ClaudeActivityWatcher? watcher;
    private UsageStore? store;
    private PanelWindow? panel;
    private RoamingController? roaming;
    private KeepAwake? keepAwake;
    private FinishedAlert? alert;
    private Updater? updater;
    private bool updatePromptOpen;

    private ToolStripMenuItem? showPanelItem;
    private ToolStripMenuItem? onTopItem;
    private ToolStripMenuItem? walksItem;
    private ToolStripMenuItem? notifyItem;
    private ToolStripMenuItem? displayItem;
    private ToolStripMenuItem? startupItem;
    private ToolStripMenuItem? autoUpdateItem;
    private readonly List<(KeepAwakeMode Mode, ToolStripMenuItem Item)> awakeItems = new();

    protected override void OnStartup(StartupEventArgs args)
    {
        base.OnStartup(args);
        single = new Mutex(true, "Clawdmeter.SingleInstance", out var first);
        if (!first)
        {
            Shutdown();
            return;
        }

        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        DispatcherUnhandledException += OnDispatcherError;
        AppDomain.CurrentDomain.UnhandledException += (_, error) => Log(error.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, error) =>
        {
            Log(error.Exception);
            error.SetObserved();
        };

        // The tray icon comes first, so a failure further down still leaves a way to quit.
        BuildTray();

        try
        {
            watcher = new ClaudeActivityWatcher();
            store = new UsageStore();
            store.Updated += snapshot => Dispatcher.BeginInvoke(() => panel?.Show(snapshot));

            panel = new PanelWindow();
            panel.MenuRequested += ShowMenu;
            panel.Show(store.Snapshot);
            if (Settings.Current.ShowPanel) panel.Show();

            roaming = new RoamingController(watcher);
            roaming.Start();

            keepAwake = new KeepAwake(watcher);
            keepAwake.Start();

            alert = new FinishedAlert(watcher);
            alert.Start();

            updater = new Updater();
            // An update leaves through the same door as Quit, so the tray icon goes with it.
            updater.Shutdown = Quit;
            updater.UpdateReady += info => Dispatcher.BeginInvoke(() => OfferUpdate(info));
            updater.StartAutomaticChecks();

            store.Start();
        }
        catch (Exception exception)
        {
            Log(exception);
            System.Windows.MessageBox.Show(
                "Clawdmeter could not start everything up. The icon in the notification area still works.",
                "Clawdmeter");
        }
    }

    private void BuildTray()
    {
        menu = BuildMenu();
        menu.Opening += (_, _) => SyncMenu();
        tray = new NotifyIcon
        {
            Icon = TrayArt.Icon(),
            Text = "Clawdmeter",
            Visible = true,
            ContextMenuStrip = menu,
        };
        // The notification area shows the menu on right click by itself.
        tray.MouseClick += (_, click) =>
        {
            if (click.Button == MouseButtons.Left) TogglePanel();
        };
    }

    private ContextMenuStrip BuildMenu()
    {
        var settings = Settings.Current;
        var strip = new ContextMenuStrip { ShowImageMargin = false };

        showPanelItem = Toggle("Show the panel", value =>
        {
            settings.ShowPanel = value;
            settings.Save();
            TogglePanel(value);
        });
        onTopItem = Toggle("Keep the panel on top", value =>
        {
            settings.PanelAlwaysOnTop = value;
            settings.Save();
            if (panel is not null) panel.Topmost = value;
        });
        walksItem = Toggle("Clawd walks around", value =>
        {
            settings.PetWalksAround = value;
            settings.Save();
        });
        notifyItem = Toggle("Tell me when Claude finishes", value =>
        {
            settings.NotifyWhenClaudeFinishes = value;
            settings.Save();
        });
        strip.Items.Add(showPanelItem);
        strip.Items.Add(onTopItem);
        strip.Items.Add(walksItem);
        strip.Items.Add(notifyItem);
        strip.Items.Add(new ToolStripSeparator());

        var awake = new ToolStripMenuItem("Keep the PC awake");
        awakeItems.Clear();
        foreach (var mode in new[] { KeepAwakeMode.Off, KeepAwakeMode.WhileClaudeWorks, KeepAwakeMode.Always })
        {
            var title = mode switch
            {
                KeepAwakeMode.WhileClaudeWorks => "While Claude works",
                KeepAwakeMode.Always => "Always",
                _ => "Off",
            };
            var picked = mode;
            var item = new ToolStripMenuItem(title);
            item.Click += (_, _) =>
            {
                settings.KeepAwake = picked;
                settings.Save();
                SyncMenu();
            };
            awakeItems.Add((picked, item));
            awake.DropDownItems.Add(item);
        }
        awake.DropDownItems.Add(new ToolStripSeparator());
        displayItem = Toggle("Keep the screen on too", value =>
        {
            settings.KeepDisplayOn = value;
            settings.Save();
        });
        awake.DropDownItems.Add(displayItem);
        strip.Items.Add(awake);

        startupItem = Toggle("Open at login", value =>
        {
            StartupItem.SetEnabled(value);
            settings.RunAtStartup = value;
            settings.Save();
        });
        autoUpdateItem = Toggle("Update automatically", value =>
        {
            settings.UpdateAutomatically = value;
            settings.Save();
        });
        strip.Items.Add(startupItem);
        strip.Items.Add(autoUpdateItem);
        strip.Items.Add(new ToolStripSeparator());
        strip.Items.Add(Item("Check for updates", () => _ = CheckForUpdates()));
        strip.Items.Add(Item("Refresh now", () => _ = store?.Refresh()));
        strip.Items.Add(Item("Quit Clawdmeter", Quit));
        return strip;
    }

    /// The menu keeps the same items for the life of the app, only the ticks move.
    private void SyncMenu()
    {
        var settings = Settings.Current;
        if (showPanelItem is not null) showPanelItem.Checked = panel?.IsVisible ?? settings.ShowPanel;
        if (onTopItem is not null) onTopItem.Checked = settings.PanelAlwaysOnTop;
        if (walksItem is not null) walksItem.Checked = settings.PetWalksAround;
        if (notifyItem is not null) notifyItem.Checked = settings.NotifyWhenClaudeFinishes;
        if (displayItem is not null) displayItem.Checked = settings.KeepDisplayOn;
        if (startupItem is not null) startupItem.Checked = StartupItem.IsEnabled;
        if (autoUpdateItem is not null) autoUpdateItem.Checked = settings.UpdateAutomatically;
        foreach (var (mode, item) in awakeItems)
        {
            item.Checked = settings.KeepAwake == mode;
        }
    }

    private static ToolStripMenuItem Toggle(string title, Action<bool> change)
    {
        var item = new ToolStripMenuItem(title);
        item.Click += (_, _) => change(!item.Checked);
        return item;
    }

    private static ToolStripMenuItem Item(string title, Action action)
    {
        var item = new ToolStripMenuItem(title);
        item.Click += (_, _) => action();
        return item;
    }

    private void ShowMenu()
    {
        SyncMenu();
        menu?.Show(Control.MousePosition);
    }

    private void TogglePanel(bool? force = null)
    {
        if (panel is null) return;
        var wanted = force ?? !panel.IsVisible;
        if (wanted)
        {
            panel.Show(store?.Snapshot);
            panel.Show();
            panel.Activate();
        }
        else
        {
            panel.Hide();
        }
    }

    private async Task CheckForUpdates()
    {
        if (updater is null) return;
        UpdateInfo? info = null;
        try
        {
            info = await updater.Check(CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            Log(exception);
        }

        await Dispatcher.InvokeAsync(() =>
        {
            if (info is null)
            {
                System.Windows.MessageBox.Show("Clawdmeter is up to date.", "Clawdmeter");
                return;
            }
            OfferUpdate(info);
        });
    }

    private void OfferUpdate(UpdateInfo info)
    {
        if (updatePromptOpen) return;
        updatePromptOpen = true;
        try
        {
            var answer = System.Windows.MessageBox.Show(
                $"Clawdmeter {info.Version} is ready. Install it now?",
                "Clawdmeter",
                MessageBoxButton.YesNo);
            if (answer != MessageBoxResult.Yes) return;
            _ = updater?.Install(info, CancellationToken.None);
        }
        finally
        {
            updatePromptOpen = false;
        }
    }

    private void OnDispatcherError(object sender, DispatcherUnhandledExceptionEventArgs args)
    {
        // A wobble in the pet or the panel should never take the whole app down.
        Log(args.Exception);
        args.Handled = true;
    }

    private static void Log(Exception? exception)
    {
        if (exception is null) return;
        try
        {
            var path = System.IO.Path.Combine(Settings.Folder, "last-error.txt");
            System.IO.Directory.CreateDirectory(Settings.Folder);
            System.IO.File.WriteAllText(path, $"{DateTimeOffset.Now:u}\n{exception}");
        }
        catch (Exception writing) when (writing is System.IO.IOException or UnauthorizedAccessException)
        {
        }
    }

    private void Quit()
    {
        if (tray is not null)
        {
            tray.Visible = false;
            tray.Dispose();
            tray = null;
        }
        roaming?.Dispose();
        keepAwake?.Dispose();
        alert?.Dispose();
        watcher?.Dispose();
        store?.Dispose();
        single?.Dispose();
        Shutdown();
    }
}

/// The little Clawd head that sits in the notification area.
internal static class TrayArt
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(nint handle);

    public static Icon Icon()
    {
        using var bitmap = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.None;
            using var body = new SolidBrush(Color.FromArgb(215, 119, 87));
            using var eyes = new SolidBrush(Color.FromArgb(20, 16, 14));
            const int unit = 4;
            var cells = new (int X, int Y, int W, int H)[]
            {
                (1, 2, 6, 1), (0, 3, 8, 4), (1, 7, 6, 1),
            };
            foreach (var cell in cells)
            {
                graphics.FillRectangle(body, cell.X * unit, cell.Y * unit, cell.W * unit, cell.H * unit);
            }
            graphics.FillRectangle(eyes, 2 * unit, 4 * unit, unit, unit);
            graphics.FillRectangle(eyes, 5 * unit, 4 * unit, unit, unit);
        }

        var handle = bitmap.GetHicon();
        try
        {
            using var shared = System.Drawing.Icon.FromHandle(handle);
            return (Icon)shared.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }
}
