# Windows 固定应用识别与窗口切换

普通 Windows 桌面程序可以在当前用户的交互会话打开固定应用入口。已有窗口经确认归属后，可以请求恢复和切到前台。Windows 仍可能拒绝前台请求。本文依据公开文档，末尾的样本有待 Windows 原型验证。 [核实 Windows 的应用识别与窗口切换能力](https://github.com/XuMJ0220/Win-Dock/issues/3) · [SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)

## 固定入口与启动

- 常规 Win32 应用可保存用户选中的 `.exe` 完整路径或原始 `.lnk` 入口。`IShellLink` 读取快捷方式的目标、参数和工作目录，`IPropertyStore` 可读取其中显式设置的 `PKEY_AppUserModel_ID`。用 `ShellExecuteExW` 打开原入口，利用 Shell 处理快捷方式的参数和工作目录。调用成功时也可能没有新进程句柄，例如打开请求由已有实例处理。 [Shell Links](https://learn.microsoft.com/en-us/windows/win32/shell/links) · [Application User Model IDs](https://learn.microsoft.com/en-us/windows/win32/shell/appids#where-to-assign-an-appusermodelid) · [SHELLEXECUTEINFOW](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/ns-shellapi-shellexecuteinfow)
- 打包应用保存完整的 AUMID，即 `<PackageFamilyName>!<Application.Id>`。一个包可以声明多个应用。微软示例用 `PackageManager` 查询当前用户的包，再用 `Package.GetAppListEntriesAsync` 取得应用项，按 `AppListEntry.AppUserModelId` 查找并调用 `LaunchAsync`。`Get-StartApps` 可用于核对开始菜单中的条目。对支持 `Windows.Launch` 的 Store 应用，也可用 `IApplicationActivationManager::ActivateApplication` 按 AUMID 发起启动。它返回处理该请求的 PID，窗口仍需另查。 [包与应用标识](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/package-identity-overview#package-identity-vs-application-identity) · [查找已安装应用的 AUMID](https://learn.microsoft.com/en-us/windows/configuration/store/find-aumid) · [按 AUMID 查找并启动的示例](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.core.applistentry.appusermodelid?view=winrt-26100#examples) · [ActivateApplication](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iapplicationactivationmanager-activateapplication)

## 匹配已有窗口

1. 用 `EnumWindows` 枚举顶层窗口，再用 `GetWindowThreadProcessId` 查询创建窗口的进程。Windows 8 起，`EnumWindows` 的文档范围是桌面应用的顶层窗口。对于托管窗口，创建窗口的 PID 只说明窗口由谁创建，目标应用的归属还要用应用标识验证。 [EnumWindows](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumwindows) · [GetWindowThreadProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowthreadprocessid)
2. 用 `SHGetPropertyStoreForWindow` 查询窗口的显式 `PKEY_AppUserModel_ID`。按 Shell 的规则，显式窗口标识优先于进程级标识。`GetApplicationUserModelId` 可查询进程的应用身份，也可能返回 `APPMODEL_ERROR_NO_APPLICATION`。只有归属无歧义时才采用进程身份。Shell 的 `GetCurrentProcessExplicitAppUserModelID` 只读取调用者自己的显式进程标识，系统为传统应用推断的内部标识没有公开读取接口。 [SHGetPropertyStoreForWindow](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shgetpropertystoreforwindow) · [Application User Model IDs](https://learn.microsoft.com/en-us/windows/win32/shell/appids) · [GetApplicationUserModelId](https://learn.microsoft.com/en-us/windows/win32/api/appmodel/nf-appmodel-getapplicationusermodelid) · [GetCurrentProcessExplicitAppUserModelID](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-getcurrentprocessexplicitappusermodelid)
3. 对能确认由目标可执行文件直接创建窗口的常规 Win32 入口，可用 `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` 和 `QueryFullProcessImageNameW` 取得完整路径并比较。路径是有条件的匹配线索。多个入口共用同一 `.exe`、启动器转交给其他进程、进程无法查询等情形，可能只能报告归属无法确认。 [QueryFullProcessImageNameW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew) · [进程访问权限](https://learn.microsoft.com/en-us/windows/win32/procthread/process-security-and-access-rights) · [显式 AppUserModelID 的使用场景](https://learn.microsoft.com/en-us/windows/win32/shell/appids#application-defined-and-system-defined-appusermodelids)
4. 归属确认后，再判断窗口能否切换。`IsWindowVisible` 反映 `WS_VISIBLE`，被其他窗口遮挡也可返回真。结合 `DWMWA_CLOAKED` 和 `IVirtualDesktopManager::IsWindowOnCurrentVirtualDesktop` 筛掉被隐藏或位于其他虚拟桌面的窗口，保留符合条件的最小化窗口。工具窗口样式与拥有关系可作为筛选线索，模态弹窗要实测。程序坞仅展示固定应用，运行提示可定义为「发现可切换窗口」。 [IsWindowVisible](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-iswindowvisible) · [DWM 窗口属性](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute) · [IVirtualDesktopManager](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ivirtualdesktopmanager) · [扩展窗口样式](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles)

## 响应用户点击

- 点击时重新确认 `HWND` 的归属和状态，窗口关闭后句柄可能被重用。单个候选直接作为切换目标。多窗口可优先选择仍有效的最近前台窗口，或让用户选择。`EnumWindows` 的文档没有约定最近使用顺序。对被模态弹窗阻塞的主窗口，可用 `GetLastActivePopup` 查找并验证活动弹窗。查无候选时打开保存的入口。若查询失败或归属有歧义，可以提示用户，再由用户决定是否打开。 [IsWindow 的句柄重用说明](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-iswindow#remarks) · [EnumWindows](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumwindows) · [GetLastActivePopup](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getlastactivepopup)
- 用 `IsIconic` 检测最小化，命中后用 `ShowWindowAsync(hwnd, SW_RESTORE)` 请求恢复。异步调用返回成功只确认恢复请求已经发出。随用户点击调用 `SetForegroundWindow` 请求激活。系统考虑调用者是否在前台或接收了最近输入、前台锁和活动菜单等条件，满足条件也可能被拒绝。记录调用结果，随后用 `GetForegroundWindow` 确认实际切换。激活失败时可用 `FlashWindowEx` 或由程序坞提示用户，保留已有窗口匹配。 [IsIconic](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-isiconic) · [SW_RESTORE](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-showwindow) · [ShowWindowAsync](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-showwindowasync) · [SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow) · [前台激活的异步行为](https://devblogs.microsoft.com/oldnewthing/20161118-00/?p=94745) · [FlashWindowEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-flashwindowex)

## Windows 原型验证矩阵

在计划支持的 Windows 版本上以普通用户执行。对每次点击记录所选入口、窗口级 AUMID、窗口创建进程的身份及路径、候选筛选结果、恢复与前台调用结果，以及实际进入前台的 `HWND`。

| 样本或场景 | 要验证的行为 |
| --- | --- |
| 常规 Win32 `.exe` 和带参数、工作目录的 `.lnk` | 首次点击正确打开入口。已有主窗口时切回该窗口。两个目录中的同名 `.exe` 各自匹配。 |
| 同一个 `.exe` 的两个参数入口、启动器交接或单实例复用 | 查清窗口实际归属与启动结果。身份有歧义时提示无法确认，避免切到另一个入口的窗口。 |
| UWP、MSIX 打包的 Win32 应用，以及含多个应用的包 | 分别验证 AUMID 启动和切回已有窗口。尤其确认系统宿主创建的窗口能否取得目标应用身份。同包不同 `Application.Id` 分别匹配。 |
| 同应用多窗口、最小化、模态弹窗、点击时关闭窗口 | 命中预期的窗口或可交互弹窗。最小化窗口恢复后确认前台，失效候选重新匹配。 |
| 仅托盘或后台进程、工具窗口、被 DWM 隐藏的窗口、其他虚拟桌面 | 核对候选筛选与固定应用的运行提示。记录哪些有匹配身份但当前无可切换窗口。 |
| 真实点击、前台权限拒绝、提升权限的目标、目标无响应 | 分别记录恢复和激活结果。失败时程序坞仍可交互，保留已确认的窗口并提示用户。 |
