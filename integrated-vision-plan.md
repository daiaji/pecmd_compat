# PECMD Lua 重构融合方案

本文档把最近的 `win-utils` / `win-kit` 愿景、`win-utils.disk` V3.0 Final 架构、FFI 绑定剥离状态，以及当前 `pecmd_compat` 的矩阵和缺口核验融合为一份可执行方案。

## 结论

项目目标不是兼容旧 PECMD 脚本语法，而是构建一个面向 Windows 10 Enterprise LTSC 2019+ / WinPE 的现代 Lua 自动化栈。

最终形态：

- `lua-ffi-bindings`: 只负责 LuaJIT FFI 的 C 类型、常量、结构体、DLL 函数声明和库加载。
- `win-utils`: 核心底层 Windows/NT 能力库，提供稳定、可组合、可测试的系统 API。
- `win-kit`: `win-utils` 的 Lua 封装、策略层和 PE recipes 层，承接 INIT/SHELL/驱动安装/盘符整理/页面文件/显示设置等组合流程。
- `peshell_minimal` 或后续 Shell: 最终 PE Shell/CLI/UI 集成产物，只消费 `win-utils` / `win-kit`，不反向提供底层能力。
- `pecmd_compat`: 官方 PECMD 能力到现代 Lua API 的追踪矩阵，不是旧语法兼容层。

当前主线应继续优先补齐 `win-utils`，再沉淀 `win-kit` recipes，最后推进最终 Shell 体验。

选择 Lua 脚本而不是 PECMD 语法的原因很直接：Lua 已经提供变量、函数、模块、表、错误处理和流程控制，不需要复刻 PECMD 的表达式语言、变量解释器、窗口 DSL 或对象 DSL。PECMD 文档的价值在于列出了 WinPE 自动化需要哪些系统能力；这些能力应以明确的 Lua API 暴露，例如 `win.process.exec(opts)`、`win.reg.set_value(...)`、`win.disk.mount.assign(...)`，而不是继续塞进隐式字符串命令。

## 为什么不保留 PECMD 语法

PECMD 的语法价值主要在历史兼容，而不是现代工程质量。它的问题不是单个命令不够强，而是把参数解析、变量替换、流程控制、表达式、窗口控件和对象生命周期都塞进一套隐式字符串 DSL：

- 参数依赖位置、逗号、前缀、特殊字符和命令内规则，难以静态检查。
- 错误处理和返回值不统一，失败路径容易被日志或副作用掩盖。
- 类型边界不清楚，路径、数值、窗口句柄、注册表值、对象名经常混在字符串中。
- 旧语法自带 NT5/BartPE、WinCMD 控件、UDM、ImDisk、插件 ABI 等历史包袱。
- 对新代码而言，复刻 `CALC`、`FIND/IFEX`、`ENVI/SET`、`SOCK` 对象 DSL 等于重新实现一门更差的小语言。

Lua 已经是完整脚本语言，应该直接承担这些职责：

- 流程控制用 `if`、`for`、函数和模块。
- 配置用 Lua table。
- 字符串处理用 Lua string/pattern 或 UTF-8 辅助库。
- 系统能力用显式命名参数和返回值，例如 `return result, nil` / `return nil, err`。
- 高风险操作用 `dry_run`、`confirm`、日志和结构化错误，而不是隐式命令副作用。

因此本项目继承的是 PECMD 的 WinPE 自动化能力清单，不继承 PECMD 语法。

## 来源与优先级

本方案融合以下材料：

- `implementation-plan-lua.md`: 当前主方案，已明确废弃旧语法兼容，采用 Lua API 替代。
- `matrix.md`: 138 个 PECMD 官方对象的状态矩阵。
- `missing-alignment.md`: 2026-07-07 静态核验后的明确缺口。
- `win-utils-status-2026-07-07.md`: 当前 `win-utils` 完成度和下一步收敛优先级快照。
- `legacy-vision-review-2026-07-07.md`: 对旧版本愿景材料的遗漏复核，记录哪些旧设想吸收、降级或默认不做。
- `audit-2026-07-07.md`: 官方文档二次核验，确认对象级覆盖无明显缺失。
- `Win-Utils_Win-Kit PECMD Analysis`: 最新整体愿景，明确 `win-utils` 是底层核心，`win-kit` 是 Lua 封装/业务层。
- `Ultimate Architecture For Win-Utils`: `win-utils.disk` V3.0 Final，补入 Rufus 级磁盘安全、引导、诊断与统一存储抽象。
- `Win-Utils Missing Dependencies`: FFI 绑定剥离审计，确认 `win-utils` 应只消费 `lua-ffi-bindings`，不再保留内联 `ffi.cdef`。
- `PEShell v3.0/v3.2` 历史愿景：保留“现代 PECMD 精神继承者”“对象化 API”“声明式/幂等状态”“异步优先”“Host + LuaJIT + UI runtime”的方向，但按当前项目现状降级为最终 Shell/Host 参考，不再作为底层架构主线。
- `peshell_minimal` 最小 PE 初始化分析：保留 `wpeinit -> INIT 用户环境 -> SHEL 外壳守护` 的启动链路理解，用于后续 `win-kit.tasks.init_pe` 和最终 Shell profile 设计。

优先级规则：

1. 官方 PECMD 文档定义“能力边界”。
2. `matrix.md` 定义每个能力对象的现代化决策。
3. `missing-alignment.md` 定义当前项目现状下的具体缺口。
4. 最新愿景定义分层方向和中长期架构目标。
5. 若愿景与当前矩阵冲突，以当前矩阵为落地基线，愿景作为后续演进目标。
6. `peshell_minimal` 的历史愿景只吸收仍符合当前分层的部分；凡是与 `win-utils` 优先、`lua-ffi-bindings` 集中绑定、`proc_utils` 废弃相冲突的旧设计均视为过时。

## 滞后实现原则

往期愿景中有不少“终局形态”设计，例如 ImGui UI、完整异步 Host、声明式状态引擎、Rufus 级磁盘写入、UEFI:NTFS、深度 SMART/NVMe 诊断、完整网络配置、Shell 任务进度 UI 等。这些方向不能被解释为当前阶段必须全部实现，其中一部分甚至不属于 PECMD 替代的定位，只能作为可选扩展或默认不做。

本项目采用“愿景保留、阶段滞后”的原则：

- 愿景可以保留在文档中，用于约束长期架构不要走偏。
- 当前实施必须以 `matrix.md`、`missing-alignment.md` 和实际代码现状为准。
- 对底层能力尚未稳定、测试不足、风险较高，或难以用 CLI/离线测试闭环的能力，明确后置，不视为当前方案不可行。
- 对明显不属于 PECMD/WinPE 自动化主线的能力，即使技术上可做，也默认不进入路线图。
- 任何后置能力在进入实现前，都必须先满足分层边界、日志、错误返回、测试和安全默认要求。

### 当前应立即推进

这些是“收敛项目现状”的任务，优先级高于扩展新能力：

- 清理 `win-utils` / `win-kit` 中越层的内联 FFI 定义。
- 将缺失 SDK 绑定集中补到 `lua-ffi-bindings`。
- 给 `win-utils.disk` 破坏性 API 建立统一 `safety + confirm/dry_run` 闸门。
- 统一 `win-utils.process.exec(opts)` 与 capture 返回模型。
- 修正并测试 `win-utils.reg.with_hive` / Hive guard。
- 拆分或重命名 `win-kit.pecmd_logic.lua`。
- 让 `win-kit` recipes 只调用 `win-utils`。
- 将 `peshell_minimal` 的 `proc_utils` 依赖迁移到 `win-utils.process`。

### 明确滞后实现

这些仍可能有价值，但因为不适合当前 CLI/离线测试闭环，或需要最终 Shell/UI 才能合理验证，所以不应进入当前第一批实现：

- ImGui 完整 GUI 和任务进度 UI。
- 完整声明式状态引擎。
- 完整 async-first profile runtime。
- PECMD `SOCK` 完整对象系统。
- System/UAC/服务到桌面/跨 session 启动用户桌面进程。
- 旧压缩/加密格式读取，除非发现真实存量资源。

### 默认不做或另立项目

这些看起来更像 Rufus-like 磁盘工具、硬件诊断工具或历史生态兼容，不是 PECMD 定位的核心功能。默认不做；只有出现明确真实需求时，才另立里程碑或独立项目评估：

- 扩容盘/伪容量 U 盘检测。
- 全盘坏块扫描和 destructive write test。
- SMART/NVMe/ATA 全量健康诊断。
- Rufus MBR/PBR 注入。
- UEFI:NTFS。
- Rufus 兼容隐藏分区。
- 复杂启动盘制作和启动修复。
- UDM/U+ / OnlyApp / SetOnlyApp / Server 旧启动盘生态兼容。
- ImDisk / RAMD 旧虚拟盘命令兼容。
- PECMD `SOCK` 对象系统及其 pipe/mailslot/shared memory/event/mutex/semaphore 兼容。

保留的磁盘能力应聚焦 PECMD/WinPE 自动化需要：磁盘/卷/分区枚举、盘符挂载/卸载、格式化、VHD/WIM/ISO 基础挂载、页面文件、安全分区计划、系统盘保护、fixed/removable 基础识别、日志和错误返回。

### 阶段准入规则

一个历史愿景能力只有在满足以下条件后，才应从“滞后目标”移动到“当前实现”：

- 所依赖的 `lua-ffi-bindings` 声明已集中维护。
- 对应底层能力已在 `win-utils` 中有最小可测试 API。
- 高风险路径有 `dry_run`、`confirm` 或只读查询模式。
- 至少有离线测试、模拟测试或实机验证计划。
- 不会把旧 PECMD 语法兼容偷偷带回来。

## 非目标

明确不做：

- 旧 PECMD 命令解析器。
- 旧 PECMD 脚本文件运行能力。
- `CALC` 表达式语言。
- `FIND/IFEX/LOOP/FORX/TEAM` 等旧流程控制语法。
- `ENVI/SET` 的 PE 变量解释器语义、递归解释、析构和线程复制语义。
- `_SUB/_END/_ENDFILE/LAMBDA` 类/窗口/函数 DSL。
- WinCMD 控件 DSL。
- DLL 版 PECMD 入口和旧插件 ABI。
- `HIDE` 进程隐藏。
- NT5/BartPE 特化能力。
- UDM/U+ / OnlyApp / SetOnlyApp / Server 旧启动盘生态。
- ImDisk / RAMD 旧虚拟盘命令兼容。
- PECMD `SOCK` 对象系统，包括 pipe/mailslot/shared memory/event/mutex/semaphore 兼容。
- 旧压缩/加密格式，除非后续发现必须读取的存量资源。

这些能力在 `matrix.md` 中应保持 `deprecated`、`modern_replacement` 或“默认不做”的明确说明，不得悄悄变成实现任务。

## 分层架构

### `lua-ffi-bindings`

职责：

- 维护 `ffi.cdef`、Windows SDK 类型、结构体、常量、GUID、IOCTL、函数声明。
- 维护 DLL 加载入口，例如 `Windows.sdk.kernel32`、`setupapi`、`ntdll`、`winioctl`、`wimgapi`、`virtdisk`、`fmifs` 等。
- 提供可复用的 SDK 级 binding，不包含 PE 业务逻辑。

当前状态：

- 最近审计显示 FFI 绑定剥离方向正确。
- `win-utils` 中不应再新增内联 `ffi.cdef`。
- 如果 `win-utils` 发现缺少结构体/常量/API，应先补到 `lua-ffi-bindings`。

验收规则：

- `win-utils` 中不得出现新 `ffi.cdef`。
- SDK binding 文件可被独立 require。
- GUID、IOCTL、分区类型、媒体类型、SMART、SetupAPI、VirtDisk、WIMGAPI 等定义集中维护，避免魔法数字散落。

### `win-utils`

职责：

- 封装单个 Windows/NT 底层能力。
- API 小而明确，返回错误而不是静默吞掉失败。
- 不包含 PE 初始化策略，不读取最终 Shell 配置。

当前已覆盖较多能力：

- `process`: exec/popen/job/kill/tree/wait/window 相关基础。
- `reg`: 注册表读写、枚举、删除、Hive、ACL、`.reg` export。
- `disk`: physical/layout/mount/volume/format/vhd/fbwf/safety/image/sync 等基础。
- `sys`: service/driver/display/shortcut/hotkey/shell/env/pagefile/font/power/user 等基础。
- `fs/text/crypto`: 文件、路径、读写、编码、哈希。
- `net`: 当前主要是枚举、DNS flush、ICMP、TCP stat。
- `input/window`: 输入发送、窗口枚举和控制。

短期原则：

- `win-utils` 是当前主战场。
- 所有可离开 PE Shell 独立复用的能力优先进入 `win-utils`。
- 高风险 API 必须有显式参数、日志、错误返回和必要的 `dry_run` / `confirm`。

### `win-kit`

职责：

- 作为 `win-utils` 的 Lua 封装、策略层和 recipes 层。
- 承接 PE 业务流程，而不是底层 Win32 FFI。
- 提供可读、可配置、可测试的自动化任务。

应保留或新增的 recipes：

- `tasks/init_pe.lua`: PE 初始化流程。
- `tasks/install_drivers.lua`: 驱动扫描、排序、安装、离线注入策略。
- `tasks/assign_drive_letters.lua`: 盘符整理。
- `tasks/setup_pagefile.lua`: 智能页面文件。
- `tasks/setup_display.lua`: 自动显示设置。
- `tasks/setup_network.lua`: 网络初始化。
- `tasks/shutdown_cleanup.lua`: 关机前同步、卸载、清理。

需要调整：

- `win-kit.pecmd_logic.lua` 名称会误导为旧 PECMD 语法兼容，应拆分或重命名。
- `exec_capture` 应下沉到 `win-utils.process` 的 capture/exec 返回模型。
- `with_super_hive` 若是通用 Hive guard，应下沉到 `win-utils.reg`；若是 PE 策略，则归入 `win-kit.registry`。

### `peshell_minimal` / 最终 Shell

职责：

- 加载 Lua profile。
- 提供 CLI/UI/menu/task entry。
- 展示日志、进度、错误和用户确认。
- 调用 `win-kit` recipes 或直接调用 `win-utils`。

当前定位：

- 暂缓主线推进。
- 只在需要验证启动入口、CLI、最终用户体验时推进。
- 其中可复用底层能力应迁入 `win-utils`，Shell 专属交互保留。

## 最新整体愿景

现代版 PECMD 的核心不是“运行旧命令”，而是把 PECMD 官方文档背后的系统能力变成 Lua 可组合能力。

核心设定：

- 仅支持 Windows 10 Enterprise LTSC 2019+ / WinPE；最低工程基线为 Windows 10 1809 / build 10.0.17763。
- 复用 Lua/LuaJIT 生态，不重建旧表达式语言和流程控制语言。
- `win-utils` 提供底层系统能力。
- `win-kit` 提供 Lua 封装、业务策略和 PE recipes。
- GUI 后置，但语义目标改为对齐 AutoHotkey v2 的 GUI 能力模型：窗口、控件、事件、列表、输入、进度、文件选择等；不复刻 PECMD WinCMD 控件 DSL。
- 网络功能可以先补基础网卡/DNS/DHCP/NTP；不复刻旧 `SOCK` 对象系统。
- ImDisk/UDM/U+ 生态属于旧生态兼容，不进入当前路线图。

官方 PECMD 能力映射成以下现代模块群：

- 文件、路径、快捷方式: `win-utils.fs`、`win-utils.text`、`win-utils.sys.shortcut`。
- 注册表与 Hive: `win-utils.reg`、`win-kit.registry`。
- 驱动与设备: `win-utils.sys.inf/dev_info/dev_ctrl/driver`、`win-kit.smart_devi`。
- WIM/VHD/磁盘: `win-utils.wim`、`win-utils.disk`、`win-kit.automount`。
- 进程与服务: `win-utils.process`、`win-utils.sys.service`。
- 系统设置: `win-utils.sys.display/font/hotkey/pagefile/power/shell/env/user`。
- 网络: `win-utils.net`，后续补 `adapter.set_ipv4`、DNS 设置、NTP。
- UI/交互: `peshell_minimal` 提供 AHK v2-like Lua GUI API，底层由 ImGui/cimgui/Win32+D3D11 实现。

## `peshell_minimal` 历史愿景的保留与降级

`peshell_minimal` 的历史方案包含一些仍然有价值的产品愿景，但其中不少架构选择已经被当前项目现状替代。因此它不应再作为底层实现蓝图，而应作为最终 Shell/Host 层的参考材料。

### 仍然保留的愿景

保留以下方向：

- **PEShell 是 PECMD 的现代化精神继承者**：继承的是 PE 初始化与自动化能力，不是旧命令语法。
- **LuaJIT 优先**：最终用户脚本、配置和 recipes 仍以 Lua/LuaJIT 为核心。
- **对象化 API**：从 `KILL "notepad.exe"` 这种命令式字符串，转向 `process:kill()`、`drive:format()`、`registry:set()` 这类对象/模块 API。
- **状态/幂等思路**：PE 初始化应尽量描述目标状态，例如“驱动已安装”“页面文件存在”“外壳被守护”“盘符已整理”，由 recipes 做差异检查，而不是盲目重复执行命令。
- **异步优先**：最终 Shell/UI 不应被文件复制、驱动安装、WIM/VHD 挂载、磁盘检测、网络等待阻塞。
- **Host + LuaJIT + Event Loop + Thread Pool**：作为最终 `peshell_minimal` 或后续 Shell 的运行时方向仍然成立。
- **AHK v2-like GUI API + ImGui backend**：最终 GUI 能力按 AutoHotkey v2 的对象化 GUI 模型对齐，底层可用 ImGui/cimgui 实现；这覆盖 PECMD 常见 GUI 能力，但不继承 PECMD 控件语法。

这些方向应该落到以下位置：

- 对象化 API 主要落到 `win-utils` 和 `win-kit`。
- 幂等状态主要落到 `win-kit.tasks/*`。
- 异步、事件循环、线程池、AHK-like GUI API 和 ImGui backend 主要落到最终 Shell/Host。
- Lua profile 加载、任务编排、日志展示和用户确认落到 `peshell_minimal` 或后续 Shell。

### 需要降级或废弃的旧设定

以下 `peshell_minimal` 历史设定不再作为当前主线：

- **`pesh_core.dll` 作为底层核心库**：已被 `lua-ffi-bindings + win-utils` 分层取代。C++ Host 只保留运行时、事件循环、线程池、UI glue，不承载通用 Windows API。
- **`proc_utils` 集成**：当前已定位为历史来源和废弃依赖。普通进程能力由 `win-utils.process` 承担。
- **在 `pesh_ffi_core.lua` 内维护大量 `ffi.cdef`**：已被 `lua-ffi-bindings` 集中定义取代。
- **把 Registry、Shortcut、Encoding IO 等通用能力塞进 Shell runtime**：这些能力应进入 `win-utils` 或更底层通用库，不应绑定在 `peshell_minimal`。
- **“All in LuaJIT FFI” 的无边界解释**：方向上可以减少 C++ 胶水，但不能因此把 FFI 定义、业务逻辑、Host glue 混在同一个文件里。
- **VDS 作为磁盘主后端**：当前 `win-utils.disk` V3.0 更偏向 `DeviceIoControl`、VirtDisk、WIMGAPI、fmifs、直接 MBR/GPT/PBR 控制；VDS 如有价值可作为兼容或辅助，不作为唯一核心。

### `peshell_minimal` 对当前方案的正确定位

当前应把 `peshell_minimal` 看作三个东西：

- **历史原型**：证明 LuaJIT + C++ Host + CI + 单元测试 + 基础脚本层是可行的。
- **最终 Shell 候选**：未来可承接 profile 加载、CLI、UI、任务进度、日志查看、用户确认。
- **能力迁移来源**：其中通用 Windows 能力应迁入 `win-utils`；Host 相关能力保留；Shell 专属 UI/菜单/任务入口后置。

它不再是：

- 底层 Windows API 的归宿。
- FFI 定义的归宿。
- `proc_utils` 继续存在的理由。
- 旧 PECMD 语法兼容层。

### 最小 PE 启动链路的吸收

`peshell_minimal` 历史分析里对 PECMD 最小启动脚本的拆解仍然重要。它指出一个可靠 PE 启动通常至少包含：

```text
wpeinit.exe -> 初始化硬件/PnP/网络栈
INIT        -> 初始化用户环境、Shell 目录、基础环境变量、可选 CD/USB 扫描
SHEL        -> 启动并守护 explorer.exe 或替代 Shell
LOGO        -> 仅是用户体验，不是功能必须项
```

对应到现代 Lua 方案：

```lua
return {
  boot = {
    run_wpeinit = true,
  },
  init = {
    user_environment = true,
    shell_folders = true,
    scan_cdrom = true,
    scan_usb = true,
  },
  shell = {
    command = [[%WinDir%\explorer.exe]],
    supervise = true,
    restart_delay_ms = 1000,
  },
  ui = {
    splash = nil,
  },
}
```

这应成为 `win-kit.tasks.init_pe` 或最终 Shell profile 的第一条主线，而不是恢复 `INIT/SHEL/LOGO` 旧命令。

### Shell/Host 的未来边界

最终 `peshell_minimal` 或后续 Shell 可以包含：

- C++ Host，集成 LuaJIT。
- 基于 `MsgWaitForMultipleObjects` 或等价机制的主事件循环。
- 线程池，执行耗时任务。
- 异步任务结果投递回主线程。
- ImGui 或其他轻量 UI。
- AHK v2-like Lua GUI 层，用 `gui.new()` / `window:add(...)` / `control:on(...)` 这类对象方法表达常见 PE 工具界面。
- profile 加载和任务调度。
- 日志、进度、错误展示。

GUI 复杂度基准以 PECMD/WinPE 圈常见的 CGI 系统部署工具为准：镜像路径选择、目标磁盘/分区表、部署选项、格式化/引导修复复选项、开始/取消按钮、进度条、日志和确认/错误弹窗。这个级别不需要 WebView、WinUI 或 .NET；AHK v2-like Lua API + ImGui backend 足够覆盖，并且保留自绘和主题扩展空间。

优先控件顺序：`Text`、`Button`、`Edit`、`Checkbox`、`Radio`、`DropDownList`、`ListView/Table`、`Progress`、`Tab`、`StatusBar`、`LogView`、`PathPicker`、`DiskList`、`ConfirmDialog`。不优先实现完整布局 DSL、富文本、复杂动画或原生控件像素级兼容。

但它不应包含：

- 通用注册表实现。
- 通用磁盘/分区实现。
- 通用进程库实现。
- 通用文件/编码/快捷方式实现。
- 大块 FFI SDK 声明。

这些全部由 `lua-ffi-bindings` 和 `win-utils` 承担。

## `win-utils.disk` V3.0 融合目标

`win-utils.disk` 是当前方案中最需要吸收最新愿景的部分。目标是从“能做基础磁盘操作”演进到“工业级 Windows 磁盘存储管理栈”。

核心设计哲学：

- 统一存储抽象：物理磁盘和挂载后的 VHD/VHDX 都视为 `PhysicalDrive`。
- 字节级控制：直接使用 `DeviceIoControl`、扇区读写、MBR/GPT/PBR 结构，不依赖 `diskpart.exe`。
- 安全优先：Rufus 级别的系统盘、防误删、页面文件、休眠文件、固定磁盘保护。

建议模块拓扑：

```lua
win-utils/disk/
├── init.lua
├── defs.lua
├── info.lua
├── safety.lua
├── physical.lua
├── vhd.lua
├── layout.lua
├── format.lua
├── boot.lua
├── check.lua
├── image.lua
├── volume.lua
├── mount.lua
├── types.lua
├── fbwf.lua
└── sync.lua
```

当前项目已有 `physical/layout/mount/volume/format/vhd/fbwf/safety/image/sync` 等基础，融合目标不是推倒重写，而是在现有模块上补齐 V3.0 缺口。

### `disk.info`

目标：建立可靠设备指纹，解决设备探测粗糙问题。

能力：

- SetupAPI/CM 设备枚举。
- BusType 识别：USB、NVMe、SCSI、SATA、VHD。
- `VID:PID + SerialNumber + BusType` 指纹。
- SMART 读取，获取真实序列号、健康状态、通电时间。
- 可区分 Removable、Fixed、外置 USB 硬盘。

落地要求：

- 所有 SMART/IOCTL 失败都必须返回可诊断错误。
- PE 环境中 SMART 不可用时降级为 SetupAPI/Storage Query 指纹。

### `disk.layout`

目标：深度解析和构建 MBR/GPT 分区表。

能力：

- `IOCTL_DISK_GET_DRIVE_LAYOUT_EX`。
- `IOCTL_DISK_SET_DRIVE_LAYOUT_EX`。
- `IOCTL_DISK_UPDATE_PROPERTIES`。
- 正确处理 `PARTITION_INFORMATION_EX[1]` 变长数组和 LuaJIT FFI 对齐。
- 识别 ESP、MSR、Basic Data、Recovery、隐藏分区、Rufus 兼容分区。

安全要求：

- 读取操作默认可用。
- 写入操作必须 `confirm = true` 或 `dry_run = false`。
- `apply_partition_plan` 必须先调用 `disk.safety`。

### `disk.physical`

目标：统一扇区 I/O 和独占锁。

能力：

- `CreateFileW([[\\.\PhysicalDriveN]])`。
- RAII/GC 关闭句柄。
- `FSCTL_LOCK_VOLUME`、`FSCTL_DISMOUNT_VOLUME`、`FSCTL_UNLOCK_VOLUME`。
- 4Kn 磁盘页对齐 I/O，必要时用 `VirtualAlloc`。
- 读写扇区、flush、geometry、alignment 查询。

安全要求：

- 任何句柄为空立即失败。
- 锁卷失败时给出占用提示，不强行写入。

### `disk.vhd`

目标：VHD/VHDX 生命周期管理并接入统一 `PhysicalDrive`。

能力：

- `CreateVirtualDisk`。
- `OpenVirtualDisk`。
- `AttachVirtualDisk`。
- `DetachVirtualDisk`。
- `GetVirtualDiskPhysicalPath`。
- attach 后轮询直到系统分配 `PhysicalDriveN`。

### `disk.safety`

目标：所有破坏性磁盘操作的统一入口防线。

必须检查：

- 是否包含当前系统盘 extents。
- 是否包含 `C:\Windows` 所在磁盘。
- 是否包含 `pagefile.sys` / `hiberfil.sys`。
- 是否为 fixed disk，且未显式允许。
- 是否存在只读、offline、BitLocker、组策略禁写等状态。

API 风格：

```lua
local ok, err = disk.safety.check_destructive_target(drive, {
  allow_fixed = false,
  allow_system = false,
  require_confirm = true,
})
```

### `disk.format`

目标：专业格式化后端。

能力：

- `fmifs.dll FormatEx`。
- FAT32 大容量格式化。
- NTFS 格式化和压缩选项。
- 进度回调。
- 格式化前锁卷/卸载，格式化后刷新卷信息。

### `disk.boot`

目标：补齐 Rufus 的核心灵魂能力。

能力：

- MBR 注入：保留分区表，只替换前 440 字节引导代码。
- PBR/VBR 修复：按 FAT32/NTFS BPB 写入正确引导记录。
- UEFI:NTFS：必要时创建微型 FAT 分区并写入 UEFI loader。
- ESP 创建、挂载和引导文件部署。

分期建议：

- Phase A: 只读识别 MBR/PBR/ESP 状态。
- Phase B: 安全写入标准 Windows MBR/PBR。
- Phase C: UEFI:NTFS 和 Rufus 风格兼容。

### `disk.check`

目标：诊断和伪扩容检测。

能力：

- 坏块检测。
- 抽样读测试。
- `0x55/0xAA` 写入校验模式。
- 全盘 destructive write test 必须显式确认。

### `disk.image`

目标：ISO/IMG DD 模式写入。

能力：

- 顺序写入镜像。
- 写入进度和速度。
- 写后 flush。
- 可选写后校验。

## 当前缺口整合

根据 `missing-alignment.md`，当前最实际的补齐顺序如下。

### P0: 保持架构边界

- 禁止在 `win-utils` 新增内联 `ffi.cdef`。
- 新底层定义先进入 `lua-ffi-bindings`。
- `win-kit` recipes 不直接写 Win32 FFI。
- `peshell_minimal` 不提供底层能力。
- `matrix.md` 继续作为官方能力对象状态源。

### P1: `win-utils.process`

已对齐：

- `exec(opts)` table API。
- 参数数组、env、cwd、show、priority、wait_input_idle、timeout、job、kill_tree_on_timeout。
- `popen.run` timeout。
- Job 绑定。

仍需补齐：

- 将 stdout/stderr capture 合并进 `exec(opts)` 返回模型。
- 决策是否支持线程/句柄目标终止。

### P1: `win-utils.reg`

已对齐：

- 枚举值、枚举子键。
- `.reg` UTF-16 export。
- `create_key` / `open_existing_key`。

仍需补齐：

- `.reg` import 与 `win-kit.registry.import` 职责边界。
- 实机核验 `HIVE -super` 等价性：`load_hive + reg.acl.reset + with_hive`。

### P1: `win-utils.fs` / `text` / `crypto`

已对齐：

- 基础 text/binary read/write。
- append。
- Base64。
- CRC32、MD5、SHA 系列。
- 文件编码转换。

仍需补齐：

- read/write 的 encoding、offset/length、atomic。
- PECMD 变异 Base64 是否保留，需要真实样本决策。

### P1: `win-utils.disk`

需要融合 V3.0 目标：

- 破坏性 API 统一 `dry_run` / `confirm`。
- `PAGE` 查询/删除/禁用页面文件。
- `PART` 安全 API 和日志。
- WIM/VHD/ISO 保留；UDM/U+ / ImDisk 旧生态兼容默认不做。
- BitLocker 状态检测应进入 `disk.safety` 的只读前置检查，目标是阻止危险操作，不是完整 BitLocker 管理器。
- BCD/boot repair 不重写解析器；短期由 `win-kit.tasks.boot_repair` 调用 `bcdboot.exe` / `bootrec.exe` / `bcdedit.exe`。
- 引入 `disk.info` 深度指纹、`disk.boot`、`disk.check`、更严格 `disk.safety`。

### P1: `win-utils.net`

仍需补齐：

- `adapter.set_ipv4(adapter, opts)`。
- DHCP/静态 IP/网关/掩码。
- `dns.set_servers(adapter, servers)`。
- `adapter.enable/disable(adapter)`。
- `ntp.sync(server, opts)` 或 `sys.time.sync_ntp`。

`SOCK` 完整对象系统不进入路线图；这不表示永远不需要通信能力，而是不复刻 PECMD 把 socket、pipe、mailslot、shared memory、event、mutex、semaphore 混在一起的对象 DSL。现代替代应按真实用途拆分：

- TCP/UDP 客户端或服务端：未来按需设计 `win-utils.net.tcp` / `win-utils.net.udp`，或评估 LuaSocket/系统组件。
- HTTP 下载/API：优先设计更高层 `win-utils.net.http` 或调用系统工具，不用裸 socket 脚本。
- 子进程 stdin/stdout/stderr：归入 `win-utils.process.exec/popen` 的 capture/pipe 模型。
- 命名管道、事件、互斥量、信号量、共享内存：只有出现真实需求时，另行设计现代 `win-utils.ipc.*` 子集。
- mailslot：默认不做，除非发现明确存量依赖。

### P1/P2: `win-utils.ui` / `sys.shell`

仍需补齐：

- `ui.message_box`。
- `ui.open_file_dialog`。
- `ui.save_file_dialog`。
- `screenshot.capture(opts)`。

Shell32/COM 依赖必须可探测并返回清晰错误；基础文件操作应优先有 Kernel32/NtAPI 路径，避免极简 PE 缺少 Shell 子系统时完全失效。

复杂 UI、旧控件 DSL、ImGui 集成放到后续 Shell 阶段。

### P2: `win-kit`

需要整理：

- recipes 只能调用 `win-utils`。
- 拆分 `pecmd_logic.lua`。
- `partition_tools` 避免依赖不明确的 `win.core.ioctl`，优先走 `win-utils.disk` 公开模块。
- 将已有 `devi`、`automount`、`smart_pagefile`、`auto_display`、`poweroff` 统一纳入 `tasks/` 或明确保持现名。

## 分阶段路线图

### Phase 0: 文档与边界固化

目标：把融合方案写入项目现状。

任务：

- 保留 `implementation-plan-lua.md` 作为详细实施基线。
- 使用本文档作为融合总纲。
- `README.md` 指向本文档。
- 后续修改 `matrix.md` 时不得把明确废弃项改成待实现。

验收：

- 文档能清楚回答：为什么不兼容旧 PECMD 语法、各仓库职责是什么、下一步补什么。

### Phase 1: `win-utils` 底层能力收敛

目标：让 PE 自动化核心场景不再受底层缺口阻塞。

范围：

- process capture 合并。
- reg import / Hive super 实机核验。
- disk safety/confirm/dry-run/boot/check/info 规划落地。
- fs read/write encoding/offset/atomic。
- net IPv4/DNS/NTP。
- ui 最小对话框。
- BitLocker 只读检测和 BCD/boot repair 流程定位。
- Shell32/COM 依赖可用性检测和降级错误。

工程基线：实现层默认以 Windows 10 Enterprise LTSC 2019+ 为最低目标，即 Windows 10 1809 / build 10.0.17763；Windows 10 Enterprise LTSC 2021 对应 Windows 10 21H2 / build 10.0.19044。除非另有真实需求，不为 Win7/8/NT5 增加 fallback。

验收：

- 每个新增 API 有最小示例或离线测试。
- 所有 Windows API 返回值、句柄、指针都有失败路径。
- 破坏性 API 默认安全。
- 无 `win-kit` / `peshell_minimal` 反向依赖。
- 测试按纯 Lua/离线、Windows CI、管理员权限、WinPE 实机、真实磁盘/USB destructive 分层；CI 不强行覆盖不稳定硬件路径。

### Phase 2: `win-kit` recipes

目标：把可复用 PE 流程沉淀为 Lua recipes。

范围：

- init_pe。
- install_drivers。
- assign_drive_letters。
- setup_pagefile。
- setup_display。
- setup_network。
- shutdown_cleanup。

验收：

- recipes 只调用 `win-utils`。
- 每个步骤有日志、错误返回和 dry-run 或查询模式。
- 能在模拟环境或测试 PE 中跑主流程。

### Phase 3: 最终 Shell / UI

目标：替代 PECMD 的用户交互能力，而不是兼容旧控件 DSL。

范围：

- CLI/profile 加载。
- 启动进度。
- 任务进度。
- 日志查看。
- 文件/目录选择、消息框。
- Shell 菜单或桌面入口。

验收：

- UI 不阻塞后台任务。
- 错误和取消路径可见。
- 不要求旧 WinCMD 控件属性兼容。

### Phase 4: 高风险与存疑能力决策

目标：只在有真实需求时处理历史生态。

候选：

- UDM/U+ / OnlyApp / SetOnlyApp / Server。
- ImDisk / RAMD 旧命令兼容。
- 旧压缩/加密格式。
- 内存执行、幽灵进程、System/UAC、服务到桌面。
- PECMD `SOCK` / IPC 对象系统。
- NT5/BartPE。
- 旧插件 ABI。

默认：不做。

## API 风格规范

返回值：

```lua
return result, nil
return nil, err
```

高层任务返回：

```lua
return {
  ok = true,
  steps = {...},
  warnings = {...},
}
```

参数：

- 多参数 API 优先 table。
- 危险行为必须显式命名：`force = true`、`confirm = true`、`dry_run = false`。
- 路径 API 接受普通路径、长路径、设备路径，内部统一规范化。
- 不使用 PECMD 风格前导符表达类型。

日志：

- 高层任务必须记录 start、options、key decisions、failure、summary。
- 驱动、磁盘、注册表、服务、关机相关功能必须有 INFO 日志。
- 支持 dry-run 输出计划。

安全：

- Windows API 指针/句柄/资源对象必须判空。
- 破坏性磁盘操作默认 dry-run 或 require confirm。
- Hive 必须用 guard 自动卸载。
- 服务/驱动操作必须返回状态和 Win32 错误。
- 不在每帧/循环中无条件执行 I/O 或持久化。

## 近期执行清单

按 `missing-alignment.md` 和 `win-utils-status-2026-07-07.md` 的最新状态，当前应从收敛和核验开始：

1. 在 Windows/MSVC 环境编译 `peshell_minimal`，打包 `cimgui.dll`，运行 `imgui-native-smoke` 做真实渲染核验。
2. 对 `reg.with_hive` / `HIVE -super`、`input/window`、`disk` 破坏性路径、`netsh` / `w32tm` 和 Shell32/COM 依赖做 Windows/WinPE 实机核验。
3. 补 Win32+D3D11 resize、device lost、窗口关闭细节，以及 AHK v2-like `ui.gui` 骨架和 CGI 类工具优先控件。
4. 继续清理 `win-utils/input.lua`、`win-utils/window.lua` 剩余内联 `ffi.cdef`，缺失声明先补到 `lua-ffi-bindings`。
5. BCD/boot repair 先落到 `win-kit` recipe，短期调用 `bcdboot.exe` / `bootrec.exe` / `bcdedit.exe`，不在首期重写 BCD 解析器。
6. 建立测试分层：纯 Lua/离线、Windows CI、管理员权限、WinPE 实机、真实磁盘/USB destructive。
7. 拆分或重命名 `win-kit.pecmd_logic.lua`，并将 `win-kit` recipes 整理为明确任务入口。
8. 继续维护 `matrix.md`，每完成或核验一个能力就更新对应对象状态。

## 判定标准

一个新能力应该进入哪一层：

- 如果它是单个 Windows/NT API 能力，进入 `win-utils`。
- 如果它是 C 类型、结构体、常量、GUID、函数声明，进入 `lua-ffi-bindings`。
- 如果它是多个底层能力组合出的 PE 任务，进入 `win-kit`。
- 如果它是最终用户交互、菜单、进度、配置入口，进入 `peshell_minimal` 或最终 Shell。
- 如果它只是旧 PECMD 语法特性，不实现，标记 `modern_replacement` 或 `deprecated`。

## 最终成功标准

- WinPE 启动初始化、驱动安装、盘符整理、页面文件、显示设置、注册表、服务、快捷方式、WIM/VHD、关机前处理等核心场景可以用 Lua API 完成。
- 官方 PECMD 文档中的 138 个对象在 `matrix.md` 中都有明确状态。
- 底层能力集中在 `win-utils`，FFI 定义集中在 `lua-ffi-bindings`。
- `win-kit` recipes 可读、可测试、可 dry-run。
- 最终 Shell 只负责集成和用户体验，不承载底层 Windows 能力。
- 不出现“半兼容旧 PECMD 语法”的中间状态。
