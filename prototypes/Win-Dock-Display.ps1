# Win-Dock 显示原型，可丢弃。用 Windows PowerShell 运行本文件。
# 测试 Windows 置顶浮层、底边唤出和全屏显示。

[CmdletBinding()]
param([string]$DiagnosticFile)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $prototypeArguments = @('-NoProfile', '-STA', '-File', $PSCommandPath)
    if ($DiagnosticFile) { $prototypeArguments += @('-DiagnosticFile', $DiagnosticFile) }
    & $windowsPowerShell @prototypeArguments
    exit $LASTEXITCODE
}

$source = @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class Desktop
{
    public const uint GetState = 4, GetTaskbarPosition = 5, GetAutoHideBar = 11;
    public const uint Bottom = 3;
    public const int ToolWindow = 0x80, NoActivate = 0x08000000;
    public const uint KeepSize = 0x0001, KeepPosition = 0x0002, SetWithoutActivation = 0x0010;
    public static readonly IntPtr Topmost = new IntPtr(-1);

    [StructLayout(LayoutKind.Sequential)]
    public struct Rect
    {
        public int Left, Top, Right, Bottom;

        public Rect(Rectangle bounds)
        {
            Left = bounds.Left;
            Top = bounds.Top;
            Right = bounds.Right;
            Bottom = bounds.Bottom;
        }

        public Rectangle Bounds
        {
            get { return Rectangle.FromLTRB(Left, Top, Right, Bottom); }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Bar
    {
        public int Size;
        public IntPtr Window;
        public uint Callback, Edge;
        public Rect Position;
        public IntPtr Param;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Monitor
    {
        public int Size;
        public Rect Screen, Work;
        public uint Flags;
    }

    public static Bar BarAt(Rectangle bounds)
    {
        return new Bar {
            Size = Marshal.SizeOf(typeof(Bar)),
            Edge = Bottom, Position = new Rect(bounds)
        };
    }

    public static Monitor ReadMonitor(IntPtr handle)
    {
        var info = new Monitor { Size = Marshal.SizeOf(typeof(Monitor)) };
        if (!GetMonitorInfo(handle, ref info))
            throw new InvalidOperationException("无法读取 Windows 显示器工作区。");
        return info;
    }

    [DllImport("shell32.dll")]
    public static extern UIntPtr SHAppBarMessage(uint message, ref Bar bar);
    [DllImport("shell32.dll")]
    public static extern int SHQueryUserNotificationState(out int state);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref Monitor info);
    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll")]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr window);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    public static extern int GetWindowStyle(IntPtr window, int index);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr window, out Rect bounds);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(
        IntPtr window, int attribute, out Rect bounds, int size);
}

internal sealed class DockSurface : Form
{
    public int Clicks { get; private set; }

    public DockSurface(Point origin)
    {
        Text = "Win-Dock 程序坞原型";
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        Location = origin;
        TopMost = true;
        BackColor = Color.FromArgb(22, 35, 49);
        ForeColor = Color.White;
        Font = new Font("Microsoft YaHei UI", 11);
        Padding = new Padding(7);
        var sample = new Button {
            Text = "示例应用", Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(28, 88, 101), ForeColor = Color.White
        };
        sample.Click += delegate {
            Clicks++;
            sample.Text = "示例应用 · 点击 " + Clicks;
        };
        Controls.Add(sample);
    }

    public void RaiseWithoutActivation()
    {
        Desktop.SetWindowPos(Handle, Desktop.Topmost, 0, 0, 0, 0,
            Desktop.KeepSize | Desktop.KeepPosition | Desktop.SetWithoutActivation);
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams
    {
        get
        {
            var settings = base.CreateParams;
            settings.ExStyle |= Desktop.ToolWindow | Desktop.NoActivate;
            return settings;
        }
    }
}

internal sealed class DisplayPanel : Form
{
    private enum Scene { Desktop, Fullscreen, Exclusive }

    private readonly CheckBox autoHide = new CheckBox { Text = "自动隐藏", AutoSize = true };
    private readonly ComboBox zone = new ComboBox {
        DropDownStyle = ComboBoxStyle.DropDownList, Width = 145, AccessibleName = "触发范围"
    };
    private readonly NumericUpDown dwell = new NumericUpDown {
        Minimum = 0, Maximum = 1200, Increment = 50, Value = 200,
        Width = 74, AccessibleName = "触底停留毫秒"
    };
    private readonly NumericUpDown grace = new NumericUpDown {
        Minimum = 100, Maximum = 1500, Increment = 50, Value = 450,
        Width = 74, AccessibleName = "离开后收起毫秒"
    };
    private readonly TextBox status = new TextBox {
        Dock = DockStyle.Fill, ReadOnly = true, Multiline = true,
        ScrollBars = ScrollBars.Vertical, AccessibleName = "实测状态"
    };
    private readonly DockSurface dock;
    private readonly IntPtr monitor;
    private readonly Timer timer = new Timer { Interval = 40 };
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly string windows;
    private readonly TextWriter output;
    private Form sample;
    private Scene previousScene;
    private IntPtr fullscreenWindow, shellBar;
    private int taskbarInset, dpi;
    private string insetSource = "";
    private long nextShellRead, enteredAt = -1, lastOnPath;
    private bool shellAutoHide, temporary, previousAutoHide;

    public DisplayPanel(string windowsVersion, TextWriter diagnosticOutput)
    {
        windows = windowsVersion;
        output = diagnosticOutput;
        Text = "Win-Dock 显示验证台 · 原型";
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10);
        ClientSize = new Size(750, 381);
        MinimumSize = new Size(666, 330);
        Padding = new Padding(16);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4 };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(new Label {
            AutoSize = true, Margin = new Padding(3, 0, 3, 12),
            Text = "验证程序坞浮在窗口上方，窗口可以铺满屏幕。"
        }, 0, 0);
        var controls = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        zone.Items.AddRange(new object[] { "底边中段", "整条底边" });
        zone.SelectedIndex = 0;
        controls.Controls.AddRange(new Control[] {
            autoHide, zone, Prompt("停留"), dwell, Prompt("收起"), grace, Prompt("毫秒")
        });
        layout.Controls.Add(controls, 0, 1);
        var steps = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        var open = new Button { Text = "打开测试窗口", AutoSize = true };
        open.Click += delegate { OpenSample(); };
        steps.Controls.Add(open);
        steps.Controls.Add(Prompt("最大化或按 F11，观察窗口底边和程序坞。"));
        layout.Controls.Add(steps, 0, 2);
        layout.Controls.Add(status, 0, 3);
        Controls.Add(layout);

        var primary = Screen.PrimaryScreen.Bounds;
        dock = new DockSurface(primary.Location);
        monitor = Desktop.MonitorFromWindow(dock.Handle, 1);
        dpi = Math.Max(96, (int)Desktop.GetDpiForWindow(dock.Handle));
        autoHide.CheckedChanged += delegate { RefreshDesktop(); };
        zone.SelectedIndexChanged += delegate { enteredAt = -1; RefreshDesktop(); };
        dwell.ValueChanged += delegate { RefreshDesktop(); };
        grace.ValueChanged += delegate { RefreshDesktop(); };
        timer.Tick += delegate { RefreshDesktop(); };
        Shown += delegate { RefreshDesktop(); timer.Start(); };
    }

    private static Label Prompt(string text)
    {
        return new Label { Text = text, AutoSize = true, Margin = new Padding(6, 8, 3, 3) };
    }

    private int Pixels(int at96Dpi)
    {
        return (at96Dpi * dpi + 48) / 96;
    }

    private void ReadShell(Rectangle screen)
    {
        var bar = Desktop.BarAt(screen);
        shellAutoHide = (Desktop.SHAppBarMessage(Desktop.GetState, ref bar).ToUInt64() & 1) != 0;
        if (Desktop.SHAppBarMessage(Desktop.GetTaskbarPosition, ref bar) != UIntPtr.Zero)
        {
            Rectangle position = bar.Position.Bounds;
            int inset = screen.Bottom - position.Top;
            if (position.Width >= screen.Width / 2 && inset >= Pixels(24) &&
                inset <= Pixels(140) && Math.Abs(position.Bottom - screen.Bottom) <= 2)
            {
                taskbarInset = inset;
                insetSource = "Shell 矩形";
            }
        }
        bar = Desktop.BarAt(screen);
        shellBar = new IntPtr(unchecked((long)Desktop.SHAppBarMessage(
            Desktop.GetAutoHideBar, ref bar).ToUInt64()));
        if (taskbarInset == 0)
        {
            taskbarInset = Pixels(48);
            insetSource = "估计 48 DIP";
        }
    }

    private Scene DetectScene(Rectangle screen)
    {
        IntPtr foreground = Desktop.GetForegroundWindow();
        if (foreground == IntPtr.Zero || foreground == Handle) return Scene.Desktop;
        if ((foreground == shellBar || foreground == dock.Handle) && fullscreenWindow != IntPtr.Zero)
            foreground = fullscreenWindow;
        if (Desktop.MonitorFromWindow(foreground, 2) != monitor) return Scene.Desktop;

        int notificationState;
        if (Desktop.SHQueryUserNotificationState(out notificationState) == 0 && notificationState == 3)
            return Scene.Exclusive;

        Desktop.Rect frame;
        const int extendedFrameBounds = 9, styleIndex = -16, caption = 0x00C00000;
        if (Desktop.DwmGetWindowAttribute(foreground, extendedFrameBounds,
            out frame, Marshal.SizeOf(typeof(Desktop.Rect))) != 0 &&
            !Desktop.GetWindowRect(foreground, out frame))
            return Scene.Desktop;

        bool hasCaption = (Desktop.GetWindowStyle(foreground, styleIndex) & caption) == caption;
        if (!(hasCaption && Desktop.IsZoomed(foreground)) &&
            frame.Left <= screen.Left + 2 && frame.Top <= screen.Top + 2 &&
            frame.Right >= screen.Right - 2 && frame.Bottom >= screen.Bottom - 2)
        {
            fullscreenWindow = foreground;
            return Scene.Fullscreen;
        }
        fullscreenWindow = IntPtr.Zero;
        return Scene.Desktop;
    }

    private void RefreshDesktop()
    {
        Rectangle screen = Desktop.ReadMonitor(monitor).Screen.Bounds;
        long now = clock.ElapsedMilliseconds;
        if (now >= nextShellRead)
        {
            ReadShell(screen);
            nextShellRead = now + 250;
        }
        IntPtr previousFullscreenWindow = fullscreenWindow;
        Scene scene = DetectScene(screen);
        bool sceneChanged = scene != previousScene;
        bool exclusiveChanged = (scene == Scene.Exclusive) != (previousScene == Scene.Exclusive);
        if (exclusiveChanged || autoHide.Checked != previousAutoHide)
        {
            temporary = false;
            enteredAt = -1;
        }
        previousScene = scene;
        previousAutoHide = autoHide.Checked;

        int width = Pixels(310), height = Pixels(52);
        int top = screen.Bottom - taskbarInset - Pixels(8) - height;
        bool mayShow = scene != Scene.Exclusive;

        var bounds = new Rectangle(screen.Left + (screen.Width - width) / 2, top, width, height);
        var horizontal = zone.SelectedIndex == 0 ? Rectangle.Inflate(bounds, Pixels(18), 0) : screen;
        var edge = Rectangle.FromLTRB(horizontal.Left, screen.Bottom - Pixels(4), horizontal.Right, screen.Bottom);
        var path = Rectangle.FromLTRB(bounds.Left - Pixels(18), bounds.Top, bounds.Right + Pixels(18), screen.Bottom);
        var pointer = Cursor.Position;
        bool onEdge = edge.Contains(pointer);

        if (mayShow && autoHide.Checked)
        {
            if (onEdge && enteredAt < 0) enteredAt = now;
            if (!onEdge) enteredAt = -1;
            if (enteredAt >= 0 && now - enteredAt >= (long)dwell.Value)
            {
                temporary = true;
                lastOnPath = now;
            }
            if (temporary && (onEdge || path.Contains(pointer))) lastOnPath = now;
            if (now - lastOnPath >= (long)grace.Value) temporary = false;
        }

        if (dock.Bounds != bounds) dock.Bounds = bounds;
        bool show = mayShow && (!autoHide.Checked || temporary);
        if (show)
        {
            bool newlyVisible = !dock.Visible;
            if (newlyVisible) dock.Show();
            if (newlyVisible || (scene == Scene.Fullscreen &&
                (sceneChanged || fullscreenWindow != previousFullscreenWindow)))
                dock.RaiseWithoutActivation();
        }
        else if (dock.Visible)
        {
            dock.Hide();
        }
        bool nearEdge = screen.Contains(pointer) && pointer.Y >= edge.Top;
        ShowState(scene, bounds, onEdge, nearEdge, screen);
    }

    private void ShowState(Scene scene, Rectangle bounds, bool onEdge, bool nearEdge, Rectangle screen)
    {
        Rectangle work = Desktop.ReadMonitor(monitor).Work.Bounds;
        string sceneText = scene == Scene.Desktop ? "桌面／普通窗口" :
            scene == Scene.Fullscreen ? "全屏窗口" : "Direct3D 独占全屏";
        string pointerText = onEdge ? "在触发区" : nearEdge ? "底边触发区外" : "离开底边";
        Desktop.Rect shellFrame;
        string shellVisibility = "实时位置不可读";
        if (shellBar != IntPtr.Zero && Desktop.GetWindowRect(shellBar, out shellFrame))
            shellVisibility = shellFrame.Top <= screen.Bottom - taskbarInset / 2 ? "展开" : "收起";
        string summary = string.Format(
            "显示模式  {0}    场景  {1}    程序坞  {2}\r\n" +
            "工作区底边  {3}px    置顶浮层\r\n" +
            "任务栏自动隐藏  {4}    任务栏上沿  {5}px（{6}）\r\n" +
            "触发范围  {7}    停留 {8} ms    收起 {9} ms    鼠标  {10}\r\n" +
            "程序坞  {11},{12}  {13}×{14} px    点中  {15} 次\r\n" +
            "主显示器  {16}×{17} px    缩放  {18}%    Windows  {19}\r\n" +
            "系统任务栏  {20}",
            autoHide.Checked ? "自动隐藏" : "常驻", sceneText, dock.Visible ? "可见" : "收起",
            work.Bottom,
            shellAutoHide ? "开启" : "关闭", screen.Bottom - taskbarInset, insetSource,
            zone.Text, dwell.Value, grace.Value, pointerText,
            bounds.X, bounds.Y, bounds.Width, bounds.Height, dock.Clicks,
            screen.Width, screen.Height, (int)Math.Round(dpi * 100 / 96.0), windows, shellVisibility);
        if (sample != null && !sample.IsDisposed)
        {
            Desktop.Rect frame;
            if (Desktop.DwmGetWindowAttribute(sample.Handle, 9, out frame,
                Marshal.SizeOf(typeof(Desktop.Rect))) == 0)
                summary += "\r\n测试窗口底边  " + frame.Bottom + " px";
        }
        if (summary == status.Text) return;
        status.Text = summary;
        output.WriteLine("{0} ms | {1}", clock.ElapsedMilliseconds, summary.Replace("\r\n", " | "));
    }

    private void OpenSample()
    {
        if (sample != null && !sample.IsDisposed)
        {
            sample.Activate();
            return;
        }
        var window = new Form {
            Text = "Win-Dock 测试窗口", Size = new Size(690, 430),
            StartPosition = FormStartPosition.CenterScreen, KeyPreview = true,
            Font = Font, BackColor = Color.FromArgb(239, 244, 245)
        };
        var maximize = new Button { Text = "最大化／还原", AutoSize = true };
        var fullScreen = new Button { Text = "全屏／退出全屏", AutoSize = true };
        var caption = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(8) };
        var bottomControl = new Label {
            Text = "窗口内容的真实底边", Dock = DockStyle.Bottom,
            Height = Pixels(35), TextAlign = ContentAlignment.MiddleCenter,
            BackColor = Color.FromArgb(191, 226, 219)
        };
        caption.Controls.Add(maximize);
        caption.Controls.Add(fullScreen);
        window.Controls.Add(caption);
        window.Controls.Add(bottomControl);
        bool full = false;
        Rectangle normal = Rectangle.Empty;
        FormWindowState previous = FormWindowState.Normal;
        Action toggle = delegate {
            if (!full)
            {
                previous = window.WindowState;
                normal = previous == FormWindowState.Normal ? window.Bounds : window.RestoreBounds;
                window.WindowState = FormWindowState.Normal;
                window.FormBorderStyle = FormBorderStyle.None;
                window.Bounds = Desktop.ReadMonitor(monitor).Screen.Bounds;
            }
            else
            {
                window.FormBorderStyle = FormBorderStyle.Sizable;
                window.Bounds = normal;
                window.WindowState = previous;
            }
            full = !full;
        };
        maximize.Click += delegate {
            if (full) toggle();
            window.WindowState = window.WindowState == FormWindowState.Maximized ?
                FormWindowState.Normal : FormWindowState.Maximized;
        };
        fullScreen.Click += delegate { toggle(); };
        window.KeyDown += delegate(object sender, KeyEventArgs input) {
            if (input.KeyCode == Keys.F11 || (full && input.KeyCode == Keys.Escape))
            {
                toggle();
                input.SuppressKeyPress = true;
            }
        };
        sample = window;
        window.Show();
    }

    protected override void OnFormClosed(FormClosedEventArgs eventArgs)
    {
        timer.Dispose();
        dock.Dispose();
        if (sample != null) sample.Dispose();
        output.WriteLine("退出时工作区底边 " + Desktop.ReadMonitor(monitor).Work.Bounds.Bottom + " px");
        base.OnFormClosed(eventArgs);
    }
}

public static class WinDockDisplay
{
    [STAThread]
    public static void Main(string[] args)
    {
        Desktop.SetThreadDpiAwarenessContext(new IntPtr(-4));
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        const string key = @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion";
        string version = string.Format("{0} ({1}.{2})", Registry.GetValue(key, "DisplayVersion", ""),
            Registry.GetValue(key, "CurrentBuildNumber", ""), Registry.GetValue(key, "UBR", ""));
        using (TextWriter output = args.Length == 0 ? TextWriter.Null :
            new StreamWriter(new FileStream(args[0], FileMode.CreateNew, FileAccess.Write, FileShare.Read),
                new System.Text.UTF8Encoding(false)) { AutoFlush = true })
        {
            Application.Run(new DisplayPanel(version, output));
        }
    }
}
'@

$binary = Join-Path ([System.IO.Path]::GetTempPath()) "WinDockDisplayPrototype-$PID.exe"
try {
    Add-Type -ReferencedAssemblies System.dll,System.Drawing.dll,System.Windows.Forms.dll `
        -OutputType WindowsApplication -OutputAssembly $binary -TypeDefinition $source
    $launch = @{ FilePath = $binary; Wait = $true; PassThru = $true }
    if ($DiagnosticFile) {
        $launch.ArgumentList = '"{0}"' -f [System.IO.Path]::GetFullPath($DiagnosticFile)
    }
    $process = Start-Process @launch
    exit $process.ExitCode
} finally {
    if (Test-Path -LiteralPath $binary) { Remove-Item -LiteralPath $binary }
}
