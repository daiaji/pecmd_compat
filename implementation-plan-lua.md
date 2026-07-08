# PECMD Lua 重构实施方案

本文档是新的实施方案。旧 `/home/daiaji/repo/PECMD重构方案.md` 仅作历史参考；本方案以已抽取的官方能力清单为边界，优先把 Windows 底层能力补到 `win-utils`，再按需要沉淀 `win-kit` 高级抽象，最终由 `peshell_minimal` 或后续 PE Shell 产物集成。

## 结论

不实现旧 PECMD 语法兼容层。

不实现 PECMD 表达式、`CALC` 语法、`FIND/IFEX/LOOP/TEAM/FORX` 语法、`ENVI/SET` 变量语义、`_SUB/LAMBDA` 类/窗口/函数语法。

目标改为：把 PECMD 官方文档中的“系统能力”迁移成 LuaJIT/FFI 原生 API 和 WinPE 自动化模块。旧脚本迁移方式是人工或工具辅助改写为 Lua，而不是运行旧脚本。

Lua 是这里的主脚本语言，不是 PECMD 语法的宿主。流程控制、变量、函数、模块、配置表和错误处理全部直接使用 Lua；PECMD 只作为能力清单来源，用来确认哪些 WinPE 场景需要现代 API 覆盖。

不保留 PECMD 语法不是单纯偏好问题。PECMD 把参数解析、变量替换、表达式、流程控制、窗口控件和对象生命周期混进字符串命令，导致类型边界、错误返回和测试边界都不清晰。Lua 已经提供更完整的语言能力，系统操作应以命名参数、模块 API、结构化返回值和日志表达，而不是重建 PECMD 的隐式 DSL。

## 成功标准

- WinPE 启动、驱动安装、盘符整理、页面文件、显示设置、注册表、服务、快捷方式、WIM/VHD、关机前处理等核心场景能用 Lua API 完成。
- 所有高风险磁盘/注册表/服务/驱动操作默认有显式参数、日志和失败返回，不用旧 PECMD 的隐式命令行副作用。
- `pecmd_compat/features.json` 中每个对象最终有状态：`implemented`、`partial`、`modern_replacement`、`deprecated`、`needs_decision`。
- 产物优先复用现有模块，不重新造已有能力。
- 新增功能必须有最小可运行示例或离线测试；涉及外部设备/PE 环境的能力至少有 dry-run 或查询模式。

## 架构定位

### 1. `win-utils`: 底层 Win32/NT 能力库

职责：提供稳定、可组合、尽量无业务假设的系统 API 封装。

现状：已经存在并应作为核心底座。

- `win-utils.fs`: 文件、目录、版本信息、NTFS/ACL/raw/path。
- `win-utils.reg`: 注册表、Hive、ACL。
- `win-utils.process`: 进程枚举、执行、等待、终止、job、token、module、memory、handles。
- `win-utils.disk`: physical/layout/geometry/mount/format/vhd/surface/image/esp/types/safety/volume/fbwf。
- `win-utils.net`: adapter/dns/icmp/stat。
- `win-utils.sys`: service/driver/power/desktop/display/shortcut/hotkey/info/shell/io/path/env/pagefile/dism/inf/dev_info/font/dev_ctrl。
- `win-utils.wim`: WIM 挂载/卸载/查询。
- `win-utils.text`: 编码转换。

实施原则：缺底层能力时优先补到 `win-utils`。API 要小、明确、可测试，不带 WinPE 业务流程。

### 2. `win-kit`: 高级抽象、Recipes 与 Demo 层

职责：把 `win-utils` 的底层能力组合成可复用的高级抽象、任务 recipes、示例实现和策略原型。

定位：不是首期必须完成的核心依赖。当前更适合作为 `win-utils` 的真实使用样例和 WinPE 流程孵化区；等某些流程稳定后，再决定是否保留在 `win-kit`，或下沉通用部分到 `win-utils`。

现状：已经存在，可继续作为高级抽象试验场。

- `driver_scanner`、`driver_installer`、`devi`、`smart_devi`、`smart_offline_devi`: 对标 `DEVI` 的现代驱动安装流程。
- `automount`: 对标 `DISK/SHOW/SUBJ` 的自动挂载和盘符整理流程。
- `smart_pagefile`: 对标 `PAGE` 的智能页面文件流程。
- `auto_display`: 对标 `DISP` 的自动显示设置流程。
- `env_manager`: 对标部分 `ENVI` 环境变量场景。
- `icon_refresh`: 对标桌面/图标刷新。
- `oem`: 对标 `USER` 等 OEM 信息设置。
- `poweroff`: 对标 `SHUT` 的关机前刷盘/卸载流程。
- `registry`: 高层注册表封装。
- `pecmd_logic`: 目前有 `exec_capture` 和 `with_super_hive`，后续应改名或拆分，避免暗示旧语法兼容。

边界：
- `win-kit` 不直接承载 Win32/NT FFI 细节；需要系统 API 时先补到 `win-utils`。
- `win-kit` 不做旧 PECMD 语法兼容；只暴露 Lua 函数和 Lua 配置表。
- `win-kit` 不做最终 Shell/Host/UI runtime；最终由 `peshell_minimal` 或后续 PE Shell 产物调用它。
- `win-kit` 可以包含策略判断，例如驱动安装顺序、页面文件放在哪个盘、盘符如何整理、关机前先卸载哪些卷。

实施原则：凡是“单个 Windows 底层能力”的封装优先放 `win-utils`。凡是“把多个底层能力组合成一个 PE 场景流程”的逻辑可以先放 `win-kit`，例如“一键初始化 PE 环境”“自动安装驱动”“智能页面文件”“关机前同步和卸载”。如果某段 `win-kit` 逻辑逐渐变成通用能力，应拆回 `win-utils`。

### 3. `peshell_minimal`: 最终 PE 集成产物，暂缓推进

职责：面向最终用户的 PE Shell/Host/CLI 集成层，负责启动、配置加载、用户交互、CLI、菜单、任务入口和调用 `win-utils`/`win-kit`。

现状：由于底层 Windows 能力还没补齐，继续推进最终 Shell 会被底层缺口拖住。因此当前暂停主线推进，先集中做 `win-utils`。

定位调整：
- 最终产物可以是 `peshell_minimal` 演进而来，也可以是后续新的 PE Shell 项目。
- 可复用的 Windows FFI、路径、资源、启动辅助、CLI 基础能力优先迁入 `win-utils`。
- 与具体 shell 外观、布局、菜单、用户交互强绑定的部分保留在 `peshell_minimal` 或最终 Shell 项目。
- `peshell_minimal` 不反向提供底层能力；它消费 `win-utils`，必要时消费 `win-kit` recipes。

实施原则：先把 `win-utils` 做扎实；`peshell_minimal` 只在需要验证 PE 集成、CLI 用户交互或最终启动体验时推进。

### 4. `proc_utils`: 历史来源，废弃依赖

职责：历史 FFI 进程工具。普通进程能力已由 `win-utils.process` 覆盖。

定位调整：
- 新代码不得依赖 `proc_utils`。
- `exec_as_system` 不迁移：本项目目标是 WinPE，默认高权限运行且无 UAC 分层；跨 session/token 启动用户桌面进程不是首期目标。
- 后续可冻结或删除该仓库。

## 明确废弃范围

这些不是“待实现”，而是设计上废弃。

- 旧 PECMD 命令解析器。
- 旧 PECMD 脚本文件运行能力：`WCS/WCE/WCI/WCX/INI/INF/TXT/LOG` 作为脚本格式。
- `CALC` 表达式语言。
- `FIND/IFEX` 条件语法。
- `LOOP/FORX/TEAM` 命令组语法。
- `_SUB/_END/_ENDFILE/LAMBDA` 函数、类、窗口语法。
- `ENVI/SET` 的 PE 变量、析构、递归解释、`EnviMode`、`EXPORTLOCAL/FORCELOCAL` 语义。
- `COME/NOTE` 注释开关。
- `IMPORT` 机械 include 语义。
- 旧 WinCMD 控件 DSL：`CHEK/EDIT/TABL/...` 的命令语法。GUI 能力改用 AutoHotkey v2-like 的 Lua 对象 API 表达，而不是复刻 PECMD 参数语法。
- DLL 版 PECMD 入口和 `rundll32 PECMD.DLL,main` 兼容。
- 旧插件发现机制：`pecmd.$命令.dll`、`pecmdplugin.*.PEI`、资源脚本插件优先级。
- `HIDE` 进程隐藏。
- `UPNP` BartPE NT5 legacy。
- `ADSL` PPPoE 旧宽带拨号，除非后续有真实需求。
- `CMPS/WCZ/WCM/WZM` 旧加密压缩格式，默认废弃；仅在发现存量资源必须读取时再单独评估。
- `MOUN-udm` 的 UDM/U+/OnlyApp/SetOnlyApp/Server 旧生态兼容，默认不做。
- `RAMD` 的 ImDisk/Ramdriv 旧虚拟盘命令兼容，默认不做；优先使用 Windows 原生 VHD/VHDX/WIM/ISO 能力。
- `SOCK` 完整对象系统及 pipe/mailslot/shared memory/event/mutex/semaphore 兼容，默认不做；未来若有真实 IPC 需求，另行设计现代 `win-utils.ipc` 子集。

## 保留并现代化的能力

这些能力需要保留，但以 Lua API 表达。

### 系统初始化

目标 API：`win_kit.init_pe(opts)` 或拆分的任务函数。

覆盖能力：`INIT`、部分 `ENVI` Shell 目录、`FONT`、`HOTK`、`DISK/SHOW` 设备就绪、`LOGO/TEXT/TIPS` 的现代替代。

优先复用：`win-kit.env_manager`、`win-kit.icon_refresh`、`win-utils.sys.env`、`win-utils.sys.shell`、`win-utils.sys.font`、`win-utils.disk.mount`。

### 进程执行与等待

目标 API：

```lua
local proc = win.process.spawn({
  cmd = {"dism.exe", "/Get-Drivers"},
  cwd = "X:\\Windows\\System32",
  show = "hide",
  capture_stdout = true,
  capture_stderr = true,
  timeout_ms = 30000,
  job = true,
})
local out, code = proc:wait()
```

覆盖能力：`EXEC`、`KILL`、`WAIT`、部分 `FIND` 进程查询。

首期必须补齐：参数数组执行、capture stdout/stderr、timeout、job kill tree、wait input idle、环境变量、cwd、priority、hide/show/min/max、返回 pid/handle。

非首期：WinLogon desktop、服务到桌面、System/UAC 绕过、ExitWindowsEx hook、内存执行、右键菜单执行。

### 注册表与 Hive

目标 API：

```lua
win.reg.set_value("HKLM", [[SOFTWARE\PELOGON]], "FORCESHUTDOWN", "dword", 1)
win_kit.registry.with_hive([[HKLM\OFFLINE_SOFTWARE]], "D:\\Windows\\System32\\config\\SOFTWARE", function(root)
  root:set("...")
end)
```

覆盖能力：`REGI`、`HIVE`、`HOME`、`RUNS`、`USER`、部分 `RECY`、部分 `SITE/FVER`。

首期必须补齐：REG_SZ/DWORD/QWORD/BINARY/MULTI_SZ/EXPAND_SZ、默认值、删除值、删除 key、枚举值/子键、Hive load/unload、权限修复、离线 Hive 自动卸载。

非目标：复刻 REGI 前导符语法和空白字符串边界行为。

### 驱动与设备

目标 API：

```lua
win_kit.smart_devi.install_all({ roots = {"Y:\\Drivers"}, dry_run = false })
win.sys.dev_ctrl.disable(instance_id)
```

覆盖能力：`DEVI`、`EJEC`、部分 `UPNP` 的 PnP 目标。

已存在基础：`win-kit.devi`、`driver_scanner`、`driver_installer`、`smart_devi`、`smart_offline_devi`、`win-utils.sys.inf`、`dev_info`、`dev_ctrl`、`driver`、`device`。

首期必须聚焦：INF/CAB 搜索、驱动安装、设备枚举、启用/禁用/移除/重扫、离线驱动注入、可观测日志。

非目标：NT5 BartPE 特化行为。

### 磁盘、卷、分区、盘符

目标 API：

```lua
win_kit.automount.assign_letters({ include_hidden = false, start = "C" })
win.disk.prepare_drive(1, "GPT", { create_esp = true, data_label = "DATA" })
win.disk.mount.assign(volume_guid, "S:")
```

覆盖能力：`DISK`、`SHOW`、`SUBJ`、`FORM`、`FDRV`、`PART` 安全子集、`DFMT`、`FBWF`、`PAGE`。`RAMD`/ImDisk 旧虚拟盘命令兼容默认不做。

已存在基础：`win-utils.disk.*`、`win-kit.automount`、`win-kit.smart_pagefile`。

分层策略：
- 查询能力优先完整：物理磁盘、卷、分区、文件系统、总线、媒体类型、空间、盘符、Volume GUID。
- 修改能力只做现代安全 API：挂载/卸载盘符、格式化、VHD、prepare_drive、页面文件、FBWF。
- `PART` 的任意 MBR/GPT 条目编辑不做旧式兼容；只提供受保护的 `prepare_drive`、`create_partition_plan`、`apply_partition_plan`。
- 所有破坏性操作必须有 `confirm = true` 或 `dry_run = false` 这类显式参数。

### 文件、路径、文本、二进制

目标 API：

```lua
win.fs.copy(src, dst, { overwrite = true })
win.fs.raw.read(path, offset, length)
win.text.read(path, { encoding = "utf-8" })
win.text.write(path, data, { encoding = "utf-8", bom = false })
```

覆盖能力：`FILE`、`FDIR`、`FEXT`、`NAME/FNAM`、`DIR`、`READ`、`WRIT`、`GETF`、`PUTF`、`SITE`、`SIZE`、`CODE`。

已存在基础：`win-utils.fs`、`win-utils.fs.raw`、`win-utils.fs.path`、`win-utils.text`。

首期必须补齐：长路径、设备路径、编码读写、二进制读写、属性和时间、目录大小、链接识别、版本信息。

非目标：PECMD 的字符串命令 `LPOS/RPOS/MSTR/LSTR/SSTR/STRL`，用 Lua 字符串/UTF-8 工具替代。

### 网络

目标 API：

```lua
win.net.adapter.list()
win.net.adapter.set_ipv4(adapter_id, { dhcp = true })
win.net.dns.set_servers(adapter_id, {"1.1.1.1", "8.8.8.8"})
```

覆盖能力：`PCIP`、`NTPC`、`ADSL` 的现代替代。`SOCK` 完整对象系统默认不做。

已存在基础：`win-utils.net.adapter`、`dns`、`icmp`、`stat`。

首期：网卡查询、DHCP/静态 IP、DNS、启用/禁用、刷新。

默认不做：完整 socket 对象 DSL、mailslot、pipe、shared memory、semaphore、DeviceIoControl 透传。现代替代不是一比一兼容 `SOCK`，而是按用途拆分：TCP/UDP 放到 `win-utils.net.tcp/udp`，HTTP 放到更高层 `win-utils.net.http`，子进程管道放到 `win-utils.process.exec/popen`，命名管道/共享内存/event/mutex/semaphore 只有在真实需要时另行设计 `win-utils.ipc.*` 子集。

### UI 与交互

目标：不保留 WinCMD 控件 DSL，改用普通 Lua UI。

建议方向：
- 从 `peshell_minimal` 抽取可复用 UI/runtime 能力到 `win-utils` 或独立 shell runtime。
- 若没有，先做 CLI/TUI 和 Win32 message box/file dialog 最小替代，不急于引入完整 ImGui。

覆盖能力：`MESS`、`BROW`、`TIPS`、`WALL`、`SCRN`、`SEND`、`HOTK/HKEY`、`NUMK`、旧控件 `CHEK/EDIT/TABL/...` 的现代替代。

保留 API：
- `win.ui.message_box`
- `win.ui.open_file_dialog`
- `win.ui.select_folder_dialog`
- `win.sys.desktop.set_wallpaper`
- `win.sys.hotkey.register`
- `win.input.send_key/send_mouse`

废弃：所有 `ENVI @控件.Property` 兼容语义。

### 日志与可观测性

目标 API：`win_kit.log` 或统一 `logger`。

覆盖能力：`LOGS` 的现代替代。

要求：
- 每个高层任务有开始、关键决策、结果、耗时日志。
- 驱动、磁盘、注册表、服务、关机相关功能必须有 INFO 日志。
- 支持写文件、控制台、内存 ring buffer。
- 支持 dry-run 输出计划。

## 建议目录与模块调整

### 优先补齐 `win-utils`

用途：承接所有可复用 Windows 底层能力，优先级高于 `win-kit` 和 `peshell_minimal`。

优先补齐方向：
- `win-utils.process`: 执行、等待、捕获输出、Job、进程树、窗口目标、退出码、超时。
- `win-utils.reg`: 类型完整性、枚举、删除、Hive guard、离线 Hive。
- `win-utils.disk`: 盘符、卷、分区、格式化、安全挂载、WIM/VHD/FBWF 查询和操作。
- `win-utils.sys`: 服务、驱动、快捷方式、显示、字体、热键、电源、页面文件、shell 路径。
- `win-utils.fs`: 长路径、设备路径、编码读写、二进制读写、属性、时间、目录大小、链接、版本信息。
- `win-utils.net`: 网卡、DHCP/静态 IP、DNS、启用/禁用、刷新。
- `win-utils.ui` 或 `win-utils.sys.ui`: 最小 Win32 交互能力，例如 message box、文件选择、目录选择。

原则：只要能力离开 PE Shell 仍有价值，就应先进入 `win-utils`。

### 可选新增 `win-kit/tasks/`

用途：放可直接用于 PE 启动流程的 recipes。不是首期硬依赖，可在 `win-utils` 能力足够后再推进。

建议模块：
- `tasks/init_pe.lua`
- `tasks/install_drivers.lua`
- `tasks/setup_network.lua`
- `tasks/setup_pagefile.lua`
- `tasks/assign_drive_letters.lua`
- `tasks/setup_display.lua`
- `tasks/shutdown_cleanup.lua`

### 可选新增 `win-kit/profile.lua`

用途：读取 Lua 配置表并执行 recipes，而不是解析 PECMD 脚本。

示例：

```lua
return {
  env = { temp = "X:\\Temp" },
  drivers = { roots = {"Y:\\Drivers"}, offline = false },
  pagefile = { mode = "smart", min_mb = 512, max_mb = 4096 },
  display = { mode = "auto" },
  automount = { include_hidden = false, start_letter = "C" },
}
```

### 重命名或拆分 `win-kit/pecmd_logic.lua`

现名会误导为旧语法兼容。建议：
- `exec_capture` 优先补到 `win-utils.process.popen` 或 `win-utils.process.exec` 的高层封装。
- `with_super_hive` 如果是通用 Hive guard，迁入 `win-utils.reg`；如果只是 PE 策略，再保留为 `win-kit.registry` recipe。
- 保留旧文件一段时间仅作为转发层，后续删除。

### 新增 `pecmd_compat/matrix.md`

用途：不是实现代码，而是跟踪官方能力对象状态。

列建议：
- 对象
- 官方能力范围
- 决策：实现 / 部分 / Lua 替代 / 废弃 / 待确认
- 目标模块
- 已有实现
- 缺口
- 风险
- 首期/二期/三期

## 分阶段实施

### Phase 0: 决策固化与矩阵建立

目标：把“旧语法废弃，Lua API 替代”写进矩阵，避免后续反复摇摆。

任务：
- 生成 `matrix.md`。
- 将所有语法类对象标为 `modern_replacement` 或 `deprecated`。
- 将所有底层能力对象优先映射到 `win-utils`；只有组合流程才映射到 `win-kit`。
- 将 UDM/U+、ImDisk/RAMD、SOCK 完整对象系统、旧压缩、进程隐藏、插件 ABI、BartPE 标为 `deprecated` 或“默认不做”。

验收：
- `features.json` 138 个对象均在 `matrix.md` 有一行。
- 每一行有目标状态和目标模块。

### Phase 1: `win-utils` 底层能力补齐

目标：先补齐 PE 自动化需要的 Windows 底层 API，让后续 Shell 和 recipes 不再被底层缺口卡住。

范围：
- `process`: `EXEC/KILL/WAIT` 现代 API。
- `reg`: `REGI/HIVE` 现代 API。
- `disk`: `DISK/SHOW/SUBJ/FORM/FDRV/PAGE/WIM/VHD/FBWF` 底层能力。
- `sys`: `SERV/LINK/FONT/HOTK/DISP/SHUT/USER` 底层能力。
- `fs/text`: 文件、路径、编码、哈希、版本信息。
- `net`: `PCIP/NTPC` 基础网络能力。

验收：
- 每组能力有最小示例或离线测试。
- 破坏性 API 都有 `dry_run` 或显式确认参数。
- Windows API 返回值、句柄、指针都有失败路径。
- 不引入对 `peshell_minimal` 或 `win-kit` 的反向依赖。

### Phase 2: `win-kit` recipes 与 PE 流程验证

目标：在 `win-utils` 足够稳定后，把常用 PE 流程沉淀成可读 recipes 或 demo。

范围：
- 环境变量和临时目录设置。
- 自动盘符整理。
- 驱动扫描和安装。
- 智能页面文件。
- 显示设置。
- 注册表基础配置。
- 快捷方式/OEM/壁纸/图标刷新。
- 关机前同步和卸载。

验收：
- 能在测试 PE 或模拟环境中执行主流程。
- 每个步骤失败不导致后续不可控崩溃；有日志和返回状态。
- recipes 只调用 `win-utils`，不直接写 Win32 FFI。

### Phase 3: UI 与 Shell 体验

目标：替代 `LOGO/TEXT/MESS/TIPS/BROW/HELP` 和旧控件 DSL。

范围：
- 统一消息框、文件选择、目录选择。
- 启动进度 UI。
- 驱动安装和磁盘操作的任务进度。
- Shell 菜单、托盘或桌面入口。
- 推进 `peshell_minimal` 或后续 PE Shell 产物，作为 `win-utils`/`win-kit` 的最终调用方。
- 从 `peshell_minimal` 迁出可复用底层能力，避免 Shell 反向变成库。

验收：
- UI 不阻塞关键后台任务。
- 任务取消、错误展示、日志查看可用。
- 不要求兼容旧 WinCMD 控件属性语法。

### Phase 4: 高风险/存疑能力决策

目标：处理官方文档里价值低、风险高、生态特化的能力。

候选：
- UDM/U+/OnlyApp/SetOnlyApp/Server 旧生态兼容。
- ImDisk/RAMD 旧虚拟盘命令兼容。
- 旧 CMPS/WCZ/WCM/WZM。
- 内存执行/幽灵进程。
- WinLogon desktop/System/UAC/服务到桌面。
- 右键菜单枚举和执行。
- PECMD `SOCK` 完整对象系统和 IPC 兼容。
- NT5/BartPE。
- 旧插件 ABI。

建议默认：除非有真实存量需求，全部不做。

## 功能对象决策草案

### 直接 Lua 替代

- `_SUB/_END/_ENDFILE/LAMBDA/CALL 子过程/TEAM/LOOP/FORX/FIND/IFEX/EXIT/IMPORT/COME/NOTE`
- `ENVI/SET` 的变量和解释器语义
- `CALC`
- `LPOS/RPOS/LSTR/RSTR/MSTR/SSTR/STRL`
- `RAND`
- `DATE` 的普通日期时间部分

### 现代 API 实现

- `EXEC/KILL/WAIT`
- `REGI/HIVE/HOME/RUNS/USER/RECY`
- `SERV`
- `DEVI/INIT/FONT/HOTK/HKEY/NUMK/SEND`
- `FILE/DIR/FDIR/FDRV/FEXT/NAME/FNAM/READ/WRIT/GETF/PUTF/SITE/SIZE/CODE/HASH/BASE`
- `DISK/PART 安全子集/DFMT/FORM/SHOW/SUBJ/FBWF/PAGE/MOUN WIM/VHD 基础`
- `PCIP/NTPC 部分`
- `LINK/WALL/SCRN/BROW/MESS/TIPS/TEXT/LOGO 现代替代`

### 默认废弃

- 旧语法解析器和脚本格式。
- `HIDE`。
- `UPNP`。
- 旧插件系统。
- DLL 版 PECMD 入口。
- 旧 WinCMD 控件 DSL。
- 旧压缩/加密格式，除非存量资源要求。
- UDM/U+ / ImDisk 旧生态兼容默认不做，除非后续发现真实存量启动方案必须依赖。

## API 风格规范

### 返回值

Lua API 统一使用：

```lua
return result, nil
return nil, err
```

高层任务可返回：

```lua
return {
  ok = true,
  steps = {...},
  warnings = {...},
}
```

### 参数

- 多参数功能优先用 table。
- 布尔危险行为必须显式命名：`force = true`、`confirm = true`、`dry_run = false`。
- 路径 API 接受普通路径、长路径、设备路径，但内部统一规范化。
- 不使用 PECMD 风格前导符表达类型。

### 日志

每个高层任务至少记录：
- start
- selected options
- key decisions
- external command/API failure
- result summary

### 安全

- 从 Windows API 获取句柄、指针、资源对象后必须判空。
- 破坏性磁盘操作默认 dry-run 或 require confirm。
- 注册表 Hive 必须用作用域 guard 自动卸载。
- 服务/驱动操作必须返回状态和 Win32 错误。
- 不在每帧/循环里无条件做 I/O 或持久化。

## 当前已有实现优先映射

| PECMD 能力 | 现有模块 | 状态判断 |
| --- | --- | --- |
| `DEVI` | `win-kit.devi`, `smart_devi`, `driver_scanner`, `driver_installer`, `win-utils.sys.inf/dev_info/dev_ctrl/driver` | partial |
| `DISK/SHOW` | `win-kit.automount`, `win-utils.disk.mount/volume/layout/physical` | partial |
| `PAGE` | `win-kit.smart_pagefile`, `win-utils.sys.pagefile` | partial |
| `DISP` | `win-kit.auto_display`, `win-utils.sys.display` | partial |
| `HIVE` | `win-kit.pecmd_logic.with_super_hive`, `win-utils.reg`, `win-utils.fs.acl` | partial |
| `EXEC*` | `win-kit.pecmd_logic.exec_capture`, `win-utils.process.popen` | partial |
| `LINK` | `win-utils.sys.shortcut` | partial |
| `SERV` | `win-utils.sys.service` | partial |
| `CODE` | `win-utils.text` | partial |
| `MOUN WIM` | `win-utils.wim` | partial |
| `VHD` | `win-utils.disk.vhd` | partial |
| `FBWF` | `win-utils.disk.fbwf` | partial |
| `FONT` | `win-utils.sys.font` | partial |
| `HOTK` | `win-utils.sys.hotkey` | partial |
| `REGI` | `win-utils.reg`, `win-kit.registry` | partial |
| `SHUT` | `win-utils.sys.power`, `win-kit.poweroff` | partial |

## 下一步具体工作

1. 生成 `matrix.md`，用本方案给 138 个对象填初始决策。
2. 在 `matrix.md` 中优先标出应进入 `win-utils` 的底层能力、可放入 `win-kit` 的 recipes、应由 `peshell_minimal` 承担的最终交互能力。
3. 为 `win-utils.process.popen`、`exec`、`job` 做 `EXEC/KILL/WAIT` 现代 API 补齐。
4. 为 `win-utils.reg` 做 `REGI/HIVE` 矩阵补齐，尤其 MULTI_SZ、EXPAND_SZ、枚举、删除、Hive guard。
5. 为 `win-utils.disk` 做 `DISK/SHOW/SUBJ/FORM/FDRV/PAGE/WIM/VHD/FBWF` 查询和安全操作矩阵。
6. 为 `win-utils.sys` 做 `SERV/LINK/FONT/HOTK/DISP/SHUT/USER` 缺口矩阵。
7. 从 `peshell_minimal` 识别可复用底层能力，能通用的迁入 `win-utils`，Shell 专属的暂缓。
8. 等 `win-utils` 缺口收敛后，再决定是否建立 `win-kit/tasks/` 和 `profile.lua`。
