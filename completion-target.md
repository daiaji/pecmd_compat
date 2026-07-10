# PECMD Lua 重构完成目标

本文档定义当前项目的完成口径。目标不是运行旧 PECMD 脚本，也不是复刻 PECMD 命令语法，而是把 PECMD 文档中仍有价值的 WinPE 自动化能力迁移为现代 Lua API。

完成状态按能力判断，不按旧语法兼容率判断。`deprecated` 项不计入完成缺口。

## 总目标

- 支持 Windows 10 Enterprise LTSC 2019+ / WinPE。
- Lua 是主脚本语言；流程控制、变量、函数、模块、配置表和错误处理直接使用 Lua。
- `win-utils` 提供可复用 Windows/NT 底层能力。
- `win-kit` 提供 WinPE recipes、任务计划、dry-run、进度、确认和日志结构。
- `peshell_minimal` 提供最终 Shell/CLI/GUI 集成体验。
- GUI 能力对齐 `/home/daiaji/repo/AutoHotkey_H/` 的对象化 GUI 模型，覆盖旧 PECMD GUI/WinCMD 控件能力。
- 不实现旧 PECMD 语法解释器、旧 WinCMD 控件 DSL、旧插件 ABI 或已废弃生态命令。

## GUI 完成目标

GUI 完成标准是对齐 AHK_H 的 `GuiType` / `GuiControlType` 能力模型，而不是复刻 PECMD 控件语法。

参考源码：

- `/home/daiaji/repo/AutoHotkey_H/source/script_gui.h`
- `/home/daiaji/repo/AutoHotkey_H/source/script_gui.cpp`
- `/home/daiaji/repo/AutoHotkey_H/source/lib/Gui.ListView.cpp`
- `/home/daiaji/repo/AutoHotkey_H/source/lib/Gui.TreeView.cpp`
- `/home/daiaji/repo/AutoHotkey_H/source/lib/Gui.StatusBar.cpp`

### GUI API 模型

必须提供：

- `ui.gui.create(opts)` 创建 GUI 对象。
- `Gui:Add(type, opts, text)` 通用添加控件入口。
- `Gui:AddText/AddEdit/AddButton/AddCheckbox/AddRadio/AddDropDownList/AddComboBox/AddListBox`。
- `Gui:AddListView/AddTreeView/AddTab/AddProgress/AddStatusBar/AddPicture/AddLink`。
- PE 部署工具扩展控件：`LogView`、`PathPicker`、`DiskList`、`ConfirmDialog`。
- 控件对象统一支持 `Text`、`Value`、`Enabled`、`Visible`、`Name`、`Type`。
- 控件对象统一支持 `SetText/GetText`、`SetValue/GetValue`、`SetEnabled`、`SetVisible`、`Move`、`Focus`。
- `Gui:Show`、`Gui:Hide`、`Gui:Close`、`Gui:Destroy`、`Gui:Submit`。
- `Gui:Get(name)` 或等价按变量名查找控件。
- AHK-like `vName` option 命名。

### GUI Option Parser

必须覆盖 AHK 常用选项子集：

- 位置和尺寸：`x`、`y`、`w`、`h`。
- 状态：`Hidden`、`Disabled`、`Checked`、`ReadOnly`。
- 选择行为：`AltSubmit`、`Multi`。
- 输入行为：`Password`、`WantTab`、`Limit`、`Number`。
- ListView/TreeView 行为：`WantF2`、多选、网格线、排序标记。
- Tab 归属：控件可归属于当前 Tab page。
- 后续可扩展 Win32 style/exstyle，但首期不要求暴露完整 Win32 bitmask。

### GUI 事件模型

必须提供：

- `Gui:OnEvent(event, callback)`。
- `Control:OnEvent(event, callback)`。
- 窗口事件：`Show`、`Close`、`Escape`、`Size`、`DropFiles`。
- 通用控件事件：`Click`、`Change`、`Focus`、`LoseFocus`。
- ListView 事件：选择变化、双击、右键、列点击、item activate。
- TreeView 事件：选择变化、展开/折叠、item activate、label edit。
- Tab 事件：当前页变化。
- 事件回调必须收到控件对象和事件数据，而不是裸字符串。

### 控件专用能力

`ListView` 必须支持：

- 设置列。
- 添加、删除、清空行。
- 读取/设置单元格。
- 读取/设置选择。
- 排序。
- 获取行数、列数。

`TreeView` 必须支持：

- 添加根节点和子节点。
- 删除节点、清空。
- 展开/折叠。
- 读取/设置选择。
- 读取/设置节点文本和关联数据。

`StatusBar` 必须支持：

- 分区。
- 设置每个 part 的文本。
- 查询文本。

`Tab` 必须支持：

- 添加页面。
- 切换当前页面。
- 控件归属到页面。

`Progress` 必须支持：

- 最小值、最大值、当前值。
- 文本/百分比显示。

`PathPicker` 必须支持：

- 文件选择。
- 目录选择。
- 保存路径。
- filter。

`DiskList` 必须支持：

- 展示磁盘、卷、分区。
- 标记危险目标。
- 返回稳定的目标对象，而不是仅返回显示文本。

`ConfirmDialog` 必须支持：

- 普通确认。
- 危险操作确认。
- 展示计划步骤和风险提示。
- 返回明确的确认/取消结果。

### GUI Backend

必须提供：

- Headless/null backend，用于 Linux CI 和纯模型测试。
- ImGui/cimgui backend，用于真实交互。
- Win32+D3D11 native host 能创建窗口、渲染帧、处理消息、关闭窗口。
- resize、device lost、swap-chain recreate、窗口关闭处理。
- cimgui DLL 构建和打包路径。
- `imgui-native-smoke` 在 Windows 上能真实创建窗口并渲染至少一帧。

### GUI 测试验收

必须覆盖：

- Headless 模型测试：控件创建、命名、值读写、事件触发、Submit。
- 控件专用测试：ListView、TreeView、StatusBar、Tab、Progress。
- PathPicker/FilePicker 模型测试。
- ConfirmDialog 危险确认测试。
- Windows smoke：cimgui 可加载，native window 可创建，至少一帧渲染成功。
- WinPE smoke：Shell 能启动，GUI 初始化失败时有清晰错误，不阻断 CLI/dry-run。

当前进展：

- `ui.gui` 已建立 AHK-like `Gui` / `Control` 模型。
- 已实现 `Text/Button/Edit/Checkbox/Radio/DropDownList/ComboBox/ListBox/ListView/TreeView/GroupBox/Tab/Slider/UpDown/Progress/StatusBar/Picture/Link/Hotkey/DateTime/MonthCal/Custom` 的模型入口。
- 已实现 PE 扩展控件 `LogView/PathPicker/DiskList/ConfirmDialog` 的模型入口和 ImGui 交互路径。
- `Edit` 已接 `igInputText` / `igInputTextMultiline` buffer 路径，支持 readonly/password/number/limit/multi 语义。
- `ListView/TreeView/Tab/Progress/Slider/Checkbox/Radio/ComboBox/ListBox/PathPicker/DiskList/Picture/ConfirmDialog` 已有 ImGui 优先渲染路径和 fallback。
- `ListView/TreeView/StatusBar/Tab` 已有专用模型 API 测试。
- `imgui-native-smoke` 已串入 `ui.gui` 绘制路径。
- 代码侧 GUI 目标已按 AHK-like 模型补齐；仍需 Windows/cimgui 实机验证真实渲染和输入行为。

## 非 GUI 完成目标

非 GUI 部分按现代 WinPE 自动化能力验收。

### 文件、文本、编码、哈希

必须完成：

- 文件/目录 copy、move、delete、mkdir、scandir、stat。
- 读写文本和二进制。
- offset/length 读取。
- offset 写入。
- atomic 写入。
- UTF-8、UTF-16LE、UTF-16BE、ACP/GBK/BIG5 转换。
- BOM 检测和自动识别。
- INI parse/encode/load/save。
- 标准 Base64 encode/decode。
- CRC32、MD5、SHA1、SHA256、SHA384、SHA512 数据和文件哈希。

明确不做：

- PECMD 变异 Base64。它仅服务旧 `ADSL` 账号密码混淆，随 `ADSL` 废弃。
- 旧 PECMD 压缩/加密格式，除非发现必须读取的存量资源。

### 进程和执行

必须完成：

- `exec(opts)` table API。
- 参数数组、工作目录、环境变量、show、priority。
- 等待、timeout、timeout kill。
- stdout/stderr capture。
- `popen.run` capture 和 timeout。
- Job object 绑定和 kill-on-close。
- 进程枚举、pid/name 查找、普通 kill、tree kill。
- `WaitForInputIdle`。
- 进程模块、内存区域、句柄信息。

需要决策：

- 线程目标终止。
- 句柄目标终止。

明确不做：

- 旧 PECMD 内存执行特殊模式。
- System/UAC 旧语义；WinPE 默认高权限，不按旧桌面/UAC 场景设计。

### 注册表和 Hive

必须完成：

- open/create/read/write/delete value/delete key。
- enum keys/values。
- string、expand_sz、multi_sz、binary、dword、qword。
- `.reg` UTF-16 export/import_file。
- load_hive/unload_hive/save/with_hive。
- 注册表 ACL reset。
- `HIVE -super` 现代等价封装或明确迁移方法。

验收重点：

- Windows 实机。
- WinPE 实机。
- 权限失败路径清晰。

### 磁盘、卷、分区、镜像

必须完成：

- 物理磁盘枚举、打开、基础信息。
- layout get/apply/clean。
- 分区 active/hidden/readonly/type/attributes。
- 卷枚举、盘符分配、移除、查询。
- mount/unmount。
- format NTFS/FAT32/exFAT 可用路径。
- VHD/VHDX create/open/attach/detach/expand。
- ISO attach/detach。
- WIM mount/unmount/list。
- pagefile 查询、配置、禁用、移除配置、创建。
- FBWF 可用性检测、启停、保护/排除/commit/restore/cache info。
- disk safety：confirm、dry_run、fixed disk、system disk、BitLocker、pagefile、hiberfil、readonly/offline/write protect。

验收重点：

- dry-run 不接触磁盘。
- destructive API 必须要求 `confirm = true`。
- 真实 destructive 测试只跑 VHD/USB/明确测试盘。
- 日志必须记录目标磁盘、分区、操作、confirm、dry-run、安全阻断原因。

明确不做：

- UDM/U+/OnlyApp/SetOnlyApp/Server 旧生态。
- ImDisk/RAMD 旧命令兼容；优先原生 VHD/VHDX/WIM/ISO。

### 系统能力

必须完成：

- 服务 list/query/start/stop/wait/set_start_mode/dependents/stop_recursive/create/delete。
- driver load/unload/install、INF/CAB 安装、设备枚举、启用/禁用/重启/移除/重扫。
- display get_modes/set_res/set_topology。
- desktop wallpaper。
- shortcut create/resolve。
- shell parse args、browse folder、ShellExecuteEx、restart_self。
- hotkey register/unregister/dispatch。
- env get/set。
- PATH split/join/add/remove/which/temp_dir。
- time now/date/local/UTC set、timezone get/set、NTP dry-run/exec。
- recycle delete/empty/query，Shell32 不可用时返回清晰错误。
- power shutdown/reboot/boot_to_firmware。
- user name、SAM/UPN、computer name、DNS name、elevated。
- OEM 信息读写。
- Shell32/COM 可用性探测统一 helper。

需要决策：

- 用户创建/删除/密码管理。该能力高风险，必须有真实 WinPE 需求后再设计。
- workstation/input lock。

### 输入和窗口

必须完成：

- vk 常量表和 normalize helper。
- key state/toggle。
- send_key/send_combo/send_text。
- mouse move/click/wheel。
- window list/find/wait。
- window show/hide/activate/close/move/resize。

验收重点：

- Windows 桌面实机。
- WinPE 桌面实机。
- 焦点失败、目标窗口不存在、桌面不可交互时返回清晰错误。

### 网络

必须完成：

- adapter list，包含连接名、适配器名、索引、MAC、MTU、类型、DNS、网关、IP 前缀、DHCP 推断。
- DHCP/静态 IPv4/网关设置。
- DNS 设置。
- adapter enable/disable。
- ICMP ping。
- TCP/UDP 连接统计。
- NTP sync。

需要决策：

- HTTP/FTP 下载上传，即 `GETF/PUTF` 的现代网络部分。可选 WinHTTP、URLMon、curl 或外部工具封装，但不能成为核心无条件依赖。

明确不做：

- PECMD `SOCK` 完整对象系统。
- socket/pipe/mailslot/shared memory/event/mutex/semaphore 混合 DSL。

### 截图

必须完成：

- `screenshot.capture(opts)`。
- 支持全屏截图。
- 支持指定窗口截图。
- 支持保存到文件。
- 支持返回内存 buffer 或临时文件路径。
- 首选 GDI BitBlt/PrintWindow 基础路径。
- 可选 Desktop Duplication 高级路径。

参考源码：

- `/home/daiaji/repo/Magpie/src/Magpie.Core/GDIFrameSource.cpp`
- `/home/daiaji/repo/Magpie/src/Magpie.Core/DesktopDuplicationFrameSource.cpp`
- `/home/daiaji/repo/looking-glass/src/looking-glass-B7/host/platform/Windows/capture/DXGI/src/dxgi.c`

### win-kit Recipes

必须完成：

- `init_pe`。
- `install_drivers`。
- `assign_drive_letters`。
- `setup_pagefile`。
- `setup_display`。
- `setup_network`。
- `shutdown_cleanup`。
- `boot_repair`。
- 每个 task 提供 `plan(opts)` 和 `run(opts)`。
- dry-run 结果必须包含 `ok`、`task`、`dry_run`、`changed`、`steps`、`warnings`。
- run 失败必须返回结构化错误：`task`、`code`、`message`。
- recipes 只能调用 `win-utils` 或系统工具，不直接新增底层 FFI。

### Shell 集成

必须完成：

- profile runner。
- 任务顺序执行。
- dry-run plan 展示。
- progress callback。
- confirm callback。
- cancel callback。
- task complete callback。
- 日志查看。
- GUI 与 runner 绑定。
- CLI fallback。

## 测试完成目标

必须建立分层测试：

- Linux/offline：纯 Lua 模型、任务计划、dry-run、语法检查。
- Windows CI：`win-utils` 非破坏性 API、`peshell_minimal` build、GUI smoke。
- Windows admin：服务创建、VHD、格式化、pagefile、driver 相关能力。
- WinPE 实机/QEMU：非破坏性自动化 profile、环境探测、核心枚举能力。
- destructive：只对 VHD/测试盘/明确 USB 测试目标运行。

CI 最低要求：

- 顶层 CI 运行 docs/scripts、`win-kit` offline、`peshell_minimal` Lua smoke。
- `win-utils` Windows CI 运行完整 `tests/run_tests.lua`。
- `peshell_minimal` Windows CI build package，并运行 profile runner、GUI headless test、imgui native smoke。

## 完成判定

项目可判定完成，当且仅当：

- `matrix.md` 中非 `deprecated` 项均为 `implemented`、`modern_replacement` 或明确 `needs_decision` 且有决策记录。
- 所有 `partial` 项清零，或被拆分为明确不做/已实现/待决策。
- GUI 达到本文 AHK_H 对齐目标。
- `win-utils`、`win-kit`、`peshell_minimal` 三层测试均通过。
- Windows/WinPE 实机核验有记录。
- destructive 路径有安全闸门、日志、测试范围说明。
- README、矩阵、缺口清单和状态快照一致。
