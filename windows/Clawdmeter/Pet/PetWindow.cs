using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using Brushes = System.Windows.Media.Brushes;

namespace Clawdmeter.Pet;

/// A clear sheet over the whole desktop for Clawd to walk on. It never takes a click,
/// never shows in the taskbar and never takes focus away from what you are doing.
public sealed class PetWindow : Window
{
    private const int ExStyle = -20;
    private const long Transparent = 0x00000020;
    private const long ToolWindow = 0x00000080;
    private const long NoActivate = 0x08000000;
    private const uint KeepOrder = 0x0004;
    private const uint KeepFocus = 0x0010;

    private readonly Canvas root = new();
    private System.Drawing.Rectangle bounds;

    public PetWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = false;
        Focusable = false;
        IsHitTestVisible = false;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        Title = "Clawd";

        root.IsHitTestVisible = false;
        Effects.IsHitTestVisible = false;
        Sprites.IsHitTestVisible = false;
        root.Children.Add(Effects);
        root.Children.Add(Sprites);
        Content = root;
        Layout();
    }

    /// Webs, dust and disco lights, drawn behind Clawd himself.
    public Canvas Effects { get; } = new();

    /// Where Clawd lives.
    public Canvas Sprites { get; } = new();

    public nint Handle { get; private set; }

    /// Physical pixels per device independent unit on the primary screen.
    public double Scale { get; private set; } = 1;

    /// The primary screen in the same units as everything Clawd does.
    public Rect Screen { get; private set; }

    protected override void OnSourceInitialized(EventArgs args)
    {
        base.OnSourceInitialized(args);
        if (PresentationSource.FromVisual(this) is HwndSource source) Handle = source.Handle;
        Scale = VisualTreeHelper.GetDpi(this).DpiScaleX;
        if (Scale <= 0) Scale = 1;
        if (Handle != 0)
        {
            var style = GetWindowLong(Handle, ExStyle) | Transparent | ToolWindow | NoActivate;
            SetWindowLong(Handle, ExStyle, style);
        }
        Layout();
    }

    protected override void OnDpiChanged(DpiScale old, DpiScale fresh)
    {
        base.OnDpiChanged(old, fresh);
        Scale = fresh.DpiScaleX > 0 ? fresh.DpiScaleX : 1;
        Layout();
    }

    /// Covers the primary screen again after a resolution or taskbar change.
    /// Returns true when something actually moved.
    public bool Refresh()
    {
        var fresh = System.Windows.Forms.Screen.PrimaryScreen?.Bounds ?? bounds;
        if (fresh == bounds) return false;
        Layout();
        return true;
    }

    public void Layout()
    {
        bounds = System.Windows.Forms.Screen.PrimaryScreen?.Bounds
                 ?? new System.Drawing.Rectangle(0, 0, 1280, 800);
        Screen = new Rect(bounds.X / Scale, bounds.Y / Scale, bounds.Width / Scale, bounds.Height / Scale);

        Left = Screen.Left;
        Top = Screen.Top;
        Width = Screen.Width;
        Height = Screen.Height;
        root.Width = Screen.Width;
        root.Height = Screen.Height;
        Effects.Width = Screen.Width;
        Effects.Height = Screen.Height;
        Sprites.Width = Screen.Width;
        Sprites.Height = Screen.Height;

        // WPF places windows with the system scale, which is not always this screen's.
        if (Handle != 0)
        {
            SetWindowPos(Handle, 0, bounds.X, bounds.Y, bounds.Width, bounds.Height, KeepOrder | KeepFocus);
        }
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern long GetWindowLongPtr(nint window, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern long SetWindowLongPtr(nint window, int index, long style);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong32(nint window, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")]
    private static extern int SetWindowLong32(nint window, int index, int style);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);

    private static long GetWindowLong(nint window, int index)
        => nint.Size == 8 ? GetWindowLongPtr(window, index) : GetWindowLong32(window, index);

    private static void SetWindowLong(nint window, int index, long style)
    {
        if (nint.Size == 8) SetWindowLongPtr(window, index, style);
        else SetWindowLong32(window, index, (int)style);
    }
}
