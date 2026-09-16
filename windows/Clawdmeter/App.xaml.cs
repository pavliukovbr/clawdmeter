using System.Drawing;
using System.Windows;
using System.Windows.Forms;
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
    private ClaudeActivityWatcher? watcher;
    private UsageStore? store;
    private PanelWindow? panel;
    private RoamingController? roaming;
    private KeepAwake? keepAwake;
    private FinishedAlert? alert;
    private Updater? updater;

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

        watcher = new ClaudeActivityWatcher();
        store = new UsageStore();
        store.Updated += snapshot => Dispatcher.Invoke(() => panel?.Show(snapshot));

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
        updater.UpdateReady += info => Dispatcher.Invoke(() => OfferUpdate(info, quiet: true));
        updater.StartAutomaticChecks();

        BuildTray();
        store.Start();
    }

    private void BuildTray()
    {
        tray = new NotifyIcon
        {
            Icon = TrayArt.Icon(),
            Text = "Clawdmeter",
            Visible = true,
        };
        tray.MouseClick += (_, args) =>
        {
            if (args.Button == MouseButtons.Left) TogglePanel();
            else ShowMenu();
        };
        tray.ContextMenuStrip = BuildMenu();
    }

    private ContextMenuStrip BuildMenu()
    {
        var settings = Settings.Current;
        var menu = new ContextMenuStrip { ShowImageMargin = false };

        menu.Items.Add(Check("Show the panel", settings.ShowPanel, value =>
        {
            settings.ShowPanel = value;
            settings.Save();
            TogglePanel(value);
        }));
        menu.Items.Add(Check("Keep the panel on top", settings.PanelAlwaysOnTop, value =>
        {
            settings.PanelAlwaysOnTop = value;
            settings.Save();
            if (panel is not null) panel.Topmost = value;
        }));
        menu.Items.Add(Check("Clawd walks around", settings.PetWalksAround, value =>
        {
            settings.PetWalksAround = value;
            settings.Save();
        }));
        menu.Items.Add(Check("Tell me when Claude finishes", settings.NotifyWhenClaudeFinishes, value =>
        {
            settings.NotifyWhenClaudeFinishes = value;
            settings.Save();
        }));
        menu.Items.Add(new ToolStripSeparator());

        var awake = new ToolStripMenuItem("Keep the PC awake");
        foreach (var mode in new[] { KeepAwakeMode.Off, KeepAwakeMode.WhileClaudeWorks, KeepAwakeMode.Always })
        {
            var title = mode switch
            {
                KeepAwakeMode.WhileClaudeWorks => "While Claude works",
                KeepAwakeMode.Always => "Always",
                _ => "Off",
            };
            awake.DropDownItems.Add(Check(title, settings.KeepAwake == mode, _ =>
            {
                settings.KeepAwake = mode;
                settings.Save();
                RefreshMenu();
            }));
        }
        awake.DropDownItems.Add(new ToolStripSeparator());
        awake.DropDownItems.Add(Check("Keep the screen on too", settings.KeepDisplayOn, value =>
        {
            settings.KeepDisplayOn = value;
            settings.Save();
        }));
        menu.Items.Add(awake);

        menu.Items.Add(Check("Open at login", StartupItem.IsEnabled, value =>
        {
            StartupItem.SetEnabled(value);
            settings.RunAtStartup = value;
            settings.Save();
        }));
        menu.Items.Add(Check("Update automatically", settings.UpdateAutomatically, value =>
        {
            settings.UpdateAutomatically = value;
            settings.Save();
        }));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Item("Check for updates", async () => await CheckForUpdates().ConfigureAwait(false)));
        menu.Items.Add(Item("Refresh now", () => _ = store?.Refresh()));
        menu.Items.Add(Item("Quit Clawdmeter", Quit));
        return menu;
    }

    private void RefreshMenu()
    {
        if (tray is null) return;
        var old = tray.ContextMenuStrip;
        tray.ContextMenuStrip = BuildMenu();
        old?.Dispose();
    }

    private static ToolStripMenuItem Check(string title, bool state, Action<bool> change)
    {
        var item = new ToolStripMenuItem(title) { Checked = state, CheckOnClick = true };
        item.CheckedChanged += (_, _) => change(item.Checked);
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
        RefreshMenu();
        tray?.ContextMenuStrip?.Show(Control.MousePosition);
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
        var info = await updater.Check(CancellationToken.None).ConfigureAwait(false);
        await Dispatcher.InvokeAsync(() =>
        {
            if (info is null)
            {
                System.Windows.MessageBox.Show("Clawdmeter is up to date.", "Clawdmeter");
                return;
            }
            OfferUpdate(info, quiet: false);
        });
    }

    private void OfferUpdate(UpdateInfo info, bool quiet)
    {
        var answer = System.Windows.MessageBox.Show(
            $"Clawdmeter {info.Version} is ready. Install it now?",
            "Clawdmeter",
            MessageBoxButton.YesNo);
        if (answer != MessageBoxResult.Yes) return;
        _ = updater?.Install(info, CancellationToken.None);
    }

    private void Quit()
    {
        tray?.Dispose();
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
    public static Icon Icon()
    {
        using var bitmap = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.None;
            using var body = new SolidBrush(Color.FromArgb(215, 119, 87));
            using var eyes = new SolidBrush(Color.FromArgb(20, 16, 14));
            var unit = 4;
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
        return System.Drawing.Icon.FromHandle(bitmap.GetHicon());
    }
}
