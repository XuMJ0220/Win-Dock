# Windows 程序坞定位与全屏唤出

独立 Win32 窗口可以在目标屏幕底部居中显示。可靠定位取决于能否取得该屏系统任务栏的展开矩形。Windows 提供了工作区预留和全屏通知，两个栏同时响应底边的效果仍需实机验证。本文依据公开文档，实机记录留待原型补充。 [核实 Windows 的程序坞定位与全屏唤出能力](https://github.com/XuMJ0220/Win-Dock/issues/2)

## 系统任务栏与定位

- `SHAppBarMessage(ABM_GETTASKBARPOS)` 通过 `APPBARDATA.rc` 返回系统任务栏的屏幕矩形。这个查询只接收 `cbSize`，文档未定义按显示器选择任务栏的方式，也未约定自动隐藏期间返回的是展开矩形还是当前边界。`ABM_GETSTATE` 的 `ABS_AUTOHIDE` 表示启用了自动隐藏。应在隐藏、动画和展开时分别记录矩形。 [ABM_GETTASKBARPOS](https://learn.microsoft.com/en-us/windows/win32/shell/abm-gettaskbarpos) · [ABM_GETSTATE](https://learn.microsoft.com/en-us/windows/win32/shell/abm-getstate)
- `ABM_GETAUTOHIDEBAREX` 按显示器矩形和边查询已注册的自动隐藏 AppBar，返回通用窗口句柄，空值也可能表示查询失败。副屏能否借此识别系统任务栏并取得展开矩形，需要实测。系统任务栏的位置和高度可能随设置变化，Microsoft 已在部分 Windows 11 更新中逐步推出四边定位和小尺寸。 [ABM_GETAUTOHIDEBAREX](https://learn.microsoft.com/en-us/windows/win32/shell/abm-getautohidebarex) · [Windows 11 更新 KB5120998](https://support.microsoft.com/en-us/servicing/os/windows-11/2026/08/kb5120998-windows-11-24h2-25h2-update)
- 用 `GetMonitorInfo` 读取目标屏幕的 `rcMonitor` 和 `rcWork`。浮层按 `rcMonitor` 水平居中。确认该屏的系统任务栏位于底边且取得展开矩形时，程序坞底边可放在展开矩形上沿和 `rcWork.bottom` 中较靠上的位置，再留出间距。查询得不到可信的展开矩形时，原型可试用已经观测过的同屏展开位置或可配置的底部偏移。工作区边界还受其他 AppBar 影响。 [MONITORINFO](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-monitorinfo) · [ABM_GETTASKBARPOS](https://learn.microsoft.com/en-us/windows/win32/shell/abm-gettaskbarpos)

## 最大化窗口的工作区

- **浮层**通过 `SetWindowPos` 控制独立窗口的位置、显隐和 Z 序，显示时可用 `SWP_NOACTIVATE` 保留当前焦点。它沿用现有工作区，因而可能盖在最大化窗口的内容上。 [SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos) · [AppBar 工作区](https://learn.microsoft.com/en-us/windows/win32/shell/application-desktop-toolbars)
- **预留空间**用 `ABM_NEW` 注册普通 AppBar，再以 `ABM_QUERYPOS` 和 `ABM_SETPOS` 协商底边位置，使用 Shell 返回的矩形。窗口可只在中间绘制程序坞，该屏的矩形工作区沿整条底边收缩，按系统默认规则最大化的窗口使用缩小后的工作区。Shell 把同边的系统任务栏安排在最外侧。收到 `ABN_POSCHANGED` 时重新协商，`ABN_STATECHANGE` 可提示重查自动隐藏状态，停用预留时以 `ABM_REMOVE` 释放空间。隐藏时释放预留会改变工作区，需观察最大化窗口的重排。 [AppBar 注册和位置协商](https://learn.microsoft.com/en-us/windows/win32/shell/application-desktop-toolbars#appbar-size-and-position) · [ABN_STATECHANGE](https://learn.microsoft.com/en-us/windows/win32/shell/abn-statechange) · [ABM_REMOVE](https://learn.microsoft.com/en-us/windows/win32/shell/abm-remove)

## 最大化、全屏与底边唤出

- `IsZoomed` 读取最大化状态。独立程序坞可用 `GetForegroundWindow` 取得前台窗口，以其可见边界或客户区是否覆盖目标屏幕的 `rcMonitor` 作为全屏线索。可用 `SetWinEventHook` 在前台变化及前台窗口尺寸变化时重判。自动隐藏时，某些无边框最大化窗口也可能铺满屏幕，Shell 还允许应用显式声明全屏，几何判断只能作为启发式。 [IsZoomed](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-iszoomed) · [GetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getforegroundwindow) · [SetWinEventHook](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwineventhook) · [WinEvent 事件](https://learn.microsoft.com/en-us/windows/win32/winauto/event-constants) · [Shell 的全屏判定](https://devblogs.microsoft.com/oldnewthing/20250522-00/?p=111211)
- 注册为普通 AppBar 后可收到 `ABN_FULLSCREENAPP`。参数只表示全屏进入或结束，未携带窗口句柄或显示器。文档要求全屏开始时把 AppBar 放到 Z 序底部，结束时恢复。独立浮层可据自己的判断收起，合成桌面上的临时唤出及不同显示器上的处理需实测。 [ABN_FULLSCREENAPP](https://learn.microsoft.com/en-us/windows/win32/shell/abn-fullscreenapp)
- `SHQueryUserNotificationState` 可提供用户级辅助信号。`QUNS_BUSY` 还包含演示设置，`QUNS_RUNNING_D3D_FULL_SCREEN` 描述的是 Direct3D 独占全屏，返回值只有通知状态枚举。 [QUERY_USER_NOTIFICATION_STATE](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/ne-shellapi-query_user_notification_state)
- `ABM_SETAUTOHIDEBAREX` 每屏每边只允许注册一个自动隐藏 AppBar，已被占用时会失败。可用 `GetCursorPos` 观察底边内侧的中段窄带与停留时间，由程序坞自行唤出。任务栏也能响应屏幕底边，需验证两栏是否一起弹出、鼠标移入程序坞途中是否误触或收起。贴底的热区窗口可能收到原本会送往其他窗口的鼠标消息，也需验证。可比较独立热键作为备选触发方式。 [ABM_SETAUTOHIDEBAREX](https://learn.microsoft.com/en-us/windows/win32/shell/abm-setautohidebarex) · [任务栏自动隐藏](https://support.microsoft.com/en-au/windows/experience/personalization/customize-the-taskbar-in-windows) · [GetCursorPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getcursorpos) · [鼠标消息路由](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-movement) · [RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)

## 多显示器、DPI 与独占全屏

- 监视器矩形是虚拟屏幕坐标，可能有负值。原型可用 Per-Monitor V2 DPI 感知统一屏幕坐标，以物理像素比较各矩形，并在 `WM_DPICHANGED` 后重新换算程序坞尺寸、间距和热区。`GetWindowRect` 受 DPI 虚拟化影响，也可能包含不可见的边框。可用 `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` 获取可见窗框的物理像素矩形。 [MONITORINFO](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-monitorinfo) · [Per-Monitor V2](https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows) · [WM_DPICHANGED](https://learn.microsoft.com/en-us/windows/win32/hidpi/wm-dpichanged) · [GetWindowRect](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect)
- 真正的独占全屏可由应用控制显示输出，普通桌面窗口的置顶只能约束桌面 Z 序。无边框全屏与 Windows 全屏优化可以采用 DWM 合成，能否插入程序坞仍取决于实际呈现路径。应用若限制光标范围，底边也可能无法到达。验收全屏唤出时，应将真正独占模式视为可能无法覆盖或触发的情况。 [DirectX 全屏优化](https://devblogs.microsoft.com/directx/demystifying-full-screen-optimizations/) · [DXGI 呈现模式](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model) · [ClipCursor](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-clipcursor)

## 实机原型验证项

| 场景 | 核对项 |
| --- | --- |
| 主屏与副屏 | 记录 Windows 版本与构建号。分别切换自动隐藏、任务栏是否在副屏显示，并比较隐藏、动画和展开时的矩形、句柄和工作区。 |
| 浮层与预留空间 | 比较普通窗口最大化前后及退出预留后的工作区。确认程序坞居中、系统任务栏可访问，并记录切换预留时的重排。 |
| 最大化、浏览器 F11 与游戏 | 对比 F11、视频全屏、无边框游戏和真正独占模式的前台窗口、全屏通知、收起与恢复结果。在全屏内比较底边停留与热键是否唤出、有无焦点变化、两栏是否同时弹出。 |
| 混合缩放与屏幕排列 | 比较 100% 与 150% 缩放、带负坐标的副屏和上下排列时的位置误差，核对副屏全屏是否误影响目标屏，以及鼠标跨屏是否误触。 |
