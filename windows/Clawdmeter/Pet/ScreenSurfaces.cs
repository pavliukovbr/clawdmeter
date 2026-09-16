using System.Runtime.InteropServices;
using System.Windows;
using Point = System.Windows.Point;
using Screen = System.Windows.Forms.Screen;

namespace Clawdmeter.Pet;

/// Something Clawd can stand on: the visible part of a window's top edge, or the floor.
public readonly record struct Surface(int Id, double Y, double MinX, double MaxX, Rect? WindowRect)
{
    public const int FloorId = 0;

    public bool IsFloor => Id == FloorId;

    public double Width => MaxX - MinX;

    public bool Contains(double x, double margin = 0) => x >= MinX - margin && x <= MaxX + margin;
}

/// The walkable edges of the desktop. Window positions are read, their contents never are.
public static class ScreenSurfaces
{
    private const int GwlExStyle = -20;
    private const long WsExToolWindow = 0x00000080;
    private const int ExtendedFrameBounds = 9;
    private const int Cloaked = 14;
    private const uint GetTaskbarPos = 5;
    private const double MinWindowWidth = 160;
    private const double MinWindowHeight = 80;
    private const double MinSegment = 44;

    /// Every top edge a window leaves uncovered, plus the strip just above the taskbar.
    public static List<Surface> Current(double scale, int ignoreProcess, IReadOnlyCollection<nint>? ignoreWindows = null)
    {
        var screen = ScreenBounds(scale);
        var work = WorkArea(scale);
        var surfaces = new List<Surface>
        {
            new(Surface.FloorId, work.Bottom, work.Left + 8, work.Right - 8, null),
        };

        var top = work.Top + 4;
        var windows = TopLevelWindows(scale, ignoreProcess, ignoreWindows);
        var inFront = new List<Rect>(windows.Count);
        foreach (var (id, frame) in windows)
        {
            var visible = frame;
            visible.Intersect(screen);
            if (visible.Width < MinWindowWidth || visible.Height < MinWindowHeight)
            {
                inFront.Add(frame);
                continue;
            }
            if (frame.Top <= top || frame.Top >= work.Bottom - 40)
            {
                inFront.Add(frame);
                continue;
            }

            // Keep only the parts of the top edge that no window in front is covering.
            var segments = new List<(double From, double To)>
            {
                (Math.Max(frame.Left, screen.Left), Math.Min(frame.Right, screen.Right)),
            };
            foreach (var cover in inFront)
            {
                if (cover.Top > frame.Top + 2 || cover.Bottom < frame.Top) continue;
                segments = segments.SelectMany(segment => Subtract(segment, cover.Left, cover.Right)).ToList();
            }
            foreach (var segment in segments)
            {
                if (segment.To - segment.From < MinSegment) continue;
                surfaces.Add(new Surface(id, frame.Top, segment.From, segment.To, frame));
            }
            inFront.Add(frame);
        }
        return surfaces;
    }

    /// The taskbar strip, which is where Clawd goes home to.
    public static Rect Taskbar(double scale)
    {
        var data = new AppBarData { Size = Marshal.SizeOf<AppBarData>() };
        if (SHAppBarMessage(GetTaskbarPos, ref data) != 0)
        {
            var bar = ToRect(data.Rect, scale);
            if (bar.Width > 0 && bar.Height > 0) return bar;
        }

        // Without the shell answering, take whatever the work area does not cover.
        var screen = ScreenBounds(scale);
        var work = WorkArea(scale);
        if (work.Bottom < screen.Bottom - 1)
        {
            return new Rect(screen.Left, work.Bottom, screen.Width, screen.Bottom - work.Bottom);
        }
        return new Rect(screen.Left, screen.Bottom - 40, screen.Width, 40);
    }

    /// Where the Start button sits, so Clawd can stand on it pretending to be a logo.
    public static Point StartButton(double scale)
    {
        var bar = Taskbar(scale);
        var tray = FindWindow("Shell_TrayWnd", null);
        if (tray != 0)
        {
            var start = FindWindowEx(tray, 0, "Start", null);
            if (start != 0 && WindowRect(start, scale) is { } found && found.Width is > 8 and < 140)
            {
                return new Point(found.Left + found.Width / 2, found.Top + found.Height / 2);
            }
        }

        // Windows 11 parks the buttons in the middle, older ones at the left end.
        var x = Environment.OSVersion.Version.Build >= 22000 ? bar.Left + bar.Width / 2 - 116 : bar.Left + 26;
        return new Point(Math.Clamp(x, bar.Left + 16, bar.Right - 16), bar.Top + bar.Height / 2);
    }

    public static Rect ScreenBounds(double scale)
    {
        var bounds = Screen.PrimaryScreen?.Bounds;
        return bounds is null
            ? new Rect(0, 0, 1280, 800)
            : new Rect(bounds.Value.X / scale, bounds.Value.Y / scale, bounds.Value.Width / scale, bounds.Value.Height / scale);
    }

    public static Rect WorkArea(double scale)
    {
        var area = Screen.PrimaryScreen?.WorkingArea;
        if (area is null) return SystemParameters.WorkArea;
        return new Rect(area.Value.X / scale, area.Value.Y / scale, area.Value.Width / scale, area.Value.Height / scale);
    }

    /// The frame the user sees, which is smaller than the window when it has a drop shadow.
    public static Rect? WindowRect(nint window, double scale)
    {
        if (DwmGetWindowAttribute(window, ExtendedFrameBounds, out NativeRect frame, Marshal.SizeOf<NativeRect>()) == 0
            && frame.Right > frame.Left && frame.Bottom > frame.Top)
        {
            return ToRect(frame, scale);
        }
        if (!GetWindowRect(window, out var plain)) return null;
        if (plain.Right <= plain.Left || plain.Bottom <= plain.Top) return null;
        return ToRect(plain, scale);
    }

    public static nint Foreground() => GetForegroundWindow();

    public static string ClassOf(nint window)
    {
        var name = new System.Text.StringBuilder(96);
        var length = GetClassName(window, name, name.Capacity);
        return length > 0 ? name.ToString(0, length) : "";
    }

    public static Point Cursor(double scale)
        => GetCursorPos(out var point) ? new Point(point.X / scale, point.Y / scale) : new Point(-1, -1);

    /// How long the user has left the keyboard and mouse alone.
    public static TimeSpan IdleTime()
    {
        var info = new LastInput { Size = (uint)Marshal.SizeOf<LastInput>() };
        if (!GetLastInputInfo(ref info)) return TimeSpan.Zero;
        var milliseconds = unchecked((uint)Environment.TickCount - info.Time);
        return TimeSpan.FromMilliseconds(milliseconds);
    }

    private static List<(int Id, Rect Frame)> TopLevelWindows(
        double scale,
        int ignoreProcess,
        IReadOnlyCollection<nint>? ignoreWindows)
    {
        var found = new List<(int, Rect)>(32);
        EnumWindows((window, _) =>
        {
            if (found.Count >= 64) return false;
            if (!IsWindowVisible(window) || IsIconic(window)) return true;
            if (ignoreWindows is not null && ignoreWindows.Contains(window)) return true;
            if ((WindowLong(window, GwlExStyle) & WsExToolWindow) != 0) return true;
            if (ignoreProcess != 0)
            {
                GetWindowThreadProcessId(window, out var owner);
                if (owner == ignoreProcess) return true;
            }
            // Store apps keep dead windows around, cloaked rather than hidden.
            if (DwmGetWindowAttribute(window, Cloaked, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            if (WindowRect(window, scale) is { } frame) found.Add(((int)window, frame));
            return true;
        }, 0);
        return found;
    }

    private static IEnumerable<(double From, double To)> Subtract((double From, double To) span, double from, double to)
    {
        if (to <= span.From || from >= span.To)
        {
            yield return span;
            yield break;
        }
        if (from > span.From) yield return (span.From, from);
        if (to < span.To) yield return (to, span.To);
    }

    private static Rect ToRect(NativeRect rect, double scale) => new(
        rect.Left / scale,
        rect.Top / scale,
        Math.Max(rect.Right - rect.Left, 0) / scale,
        Math.Max(rect.Bottom - rect.Top, 0) / scale);

    private static long WindowLong(nint window, int index)
        => nint.Size == 8 ? GetWindowLongPtr(window, index) : GetWindowLong(window, index);

    // MARK: Win32

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LastInput
    {
        public uint Size;
        public uint Time;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AppBarData
    {
        public int Size;
        public nint Window;
        public uint CallbackMessage;
        public uint Edge;
        public NativeRect Rect;
        public nint Param;
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private delegate bool EnumWindowsProc(nint window, nint parameter);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsProc callback, nint parameter);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(nint window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(nint window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(nint window, out NativeRect rect);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out NativePoint point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetLastInputInfo(ref LastInput info);

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(nint window, System.Text.StringBuilder name, int max);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint window, out int process);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(nint window, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern long GetWindowLongPtr(nint window, int index);

    [DllImport("user32.dll", EntryPoint = "FindWindowW", CharSet = CharSet.Unicode)]
    private static extern nint FindWindow(string? className, string? title);

    [DllImport("user32.dll", EntryPoint = "FindWindowExW", CharSet = CharSet.Unicode)]
    private static extern nint FindWindowEx(nint parent, nint after, string? className, string? title);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(nint window, int attribute, out NativeRect value, int size);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(nint window, int attribute, out int value, int size);

    [DllImport("shell32.dll")]
    private static extern nint SHAppBarMessage(uint message, ref AppBarData data);
}
