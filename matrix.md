# PECMD Lua 重构兼容矩阵

本文档是对象级初始矩阵，覆盖 `features.json` 的 138 个对象。详细子功能仍以 `chunks/*.md` 为准。

状态含义：
- `implemented`: 已有实现基本覆盖，后续只需核验。
- `partial`: 已有模块覆盖一部分，需要逐项补齐。
- `modern_replacement`: 不保留 PECMD 语法，用 Lua 或现代 API 替代。
- `deprecated`: 明确不做。
- `needs_decision`: 需要真实需求或风险评估后再定。

分层原则：
- `win-utils`: 优先承接可复用 Windows/NT 底层能力。
- `win-kit`: 承接 PE recipes、demo、高级策略，不作为首期硬依赖。
- `peshell_minimal`: 最终 PE Shell/CLI/用户交互集成产物，暂缓推进。
- `lua`: 普通 Lua 语言能力或 Lua 配置替代。

| 对象 | Chunk | 状态 | 层 | 目标模块 / 替代 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `global_script_and_command_mechanism` | `001-global-to-envi` | `modern_replacement` | `lua` | Lua 脚本入口、Lua 配置表 | 不实现旧命令解析器。 |
| `wincmd_control_overview` | `001-global-to-envi` | `modern_replacement` | `peshell_minimal` | Shell/UI runtime | 不兼容 WinCMD 控件 DSL。 |
| `builtin_variables` | `001-global-to-envi` | `modern_replacement` | `lua` | Lua 变量、配置表、`os.getenv` | 不实现 PE 变量语义。 |
| `_END` | `001-global-to-envi` | `modern_replacement` | `lua` | Lua 函数/块结构 | 旧脚本结束标记废弃。 |
| `_ENDFILE` | `001-global-to-envi` | `modern_replacement` | `lua` | Lua 模块返回/入口控制 | 旧脚本结束标记废弃。 |
| `_SUB` | `001-global-to-envi` | `modern_replacement` | `lua` | Lua 函数、table、模块 | 不实现类/窗口/函数 DSL。 |
| `POS` | `001-global-to-envi` | `modern_replacement` | `peshell_minimal` | Shell/UI 布局 API | 只保留现代 UI 布局能力。 |
| `message_mapping` | `001-global-to-envi` | `modern_replacement` | `peshell_minimal` | UI 事件回调 | 不实现 PECMD 消息映射语法。 |
| `code_block` | `001-global-to-envi` | `modern_replacement` | `lua` | Lua block/function | 旧 `{}` 代码段废弃。 |
| `LAMBDA` | `001-global-to-envi` | `modern_replacement` | `lua` | Lua 闭包 | 不实现旧 lambda 语法。 |
| `ADSL` | `001-global-to-envi` | `deprecated` | `none` | 无 | PPPoE 旧场景，除非有真实需求。 |
| `BASE` | `001-global-to-envi` | `partial` | `win-utils` | `win-utils.text.base64_encode/decode` | 已有标准 Base64 encode/decode；PECMD 变异 Base64 账号密码算法仍需按文档/样本核验。 |
| `BROW` | `001-global-to-envi` | `partial` | `win-utils` / `peshell_minimal` | `win-utils.sys.shell.browse_folder` | 目录选择已有；文件打开/保存对话框未见实现。 |
| `CALC` | `001-global-to-envi` | `modern_replacement` | `lua` | Lua 表达式 | 不实现 PECMD 表达式语言。 |
| `CALL` | `001-global-to-envi` | `modern_replacement` | `lua` | Lua 函数调用 | 旧子过程调用废弃。 |
| `CHEK` | `001-global-to-envi` | `modern_replacement` | `peshell_minimal` | 现代 UI checkbox | 不兼容旧控件 DSL。 |
| `CODE` | `001-global-to-envi` | `partial` | `win-utils` | `win-utils.text` | 已有 GBK/BIG5/UTF-8/ACP 字符串转换与 `convert_file` 文件级转换；BOM/自动识别/PECMD 源格式细节仍需核验。 |
| `COME_NOTE` | `001-global-to-envi` | `deprecated` | `none` | 无 | 旧注释开关随脚本解析器废弃。 |
| `CMPS` | `001-global-to-envi` | `deprecated` | `none` | 无 | 旧压缩/加密格式默认不做。 |
| `DATE` | `001-global-to-envi` | `modern_replacement` | `lua` / `win-utils` | Lua date/time、必要时 Win32 time | 普通日期时间用 Lua，系统时间另映射。 |
| `DEVI` | `001-global-to-envi` | `partial` | `win-utils` / `win-kit` | `win-utils.sys.inf/dev_info/dev_ctrl/driver`, `win-kit.devi` | 已有 INF/CAB 安装、驱动存储、设备枚举、缺失驱动 ID、启用/禁用/重启/移除/重扫和智能安装流程；离线注入/全部 PECMD 参数仍需核验。 |
| `DFMT` | `001-global-to-envi` | `partial` | `win-utils` | `win-utils.disk.format` | 安全格式化能力需补 dry-run/confirm。 |
| `DIR` | `001-global-to-envi` | `partial` | `win-utils` | `win-utils.fs` | 已有 mkdir/copy/delete/move/find/scandir/stat/link/read/write；部分 PECMD 选项仍需核验。 |
| `DISK` | `001-global-to-envi` | `partial` | `win-utils` / `win-kit` | `win-utils.disk.*`, `win-kit.automount` | 已有 physical/layout/mount/volume/format/vhd/fbwf/safety/image/sync；旧策略和危险操作需逐项确认。 |
| `DISP` | `001-global-to-envi` | `partial` | `win-utils` / `win-kit` | `win-utils.sys.display`, `win-kit.auto_display` | 已有 set_res/set_topology/get_modes；多显示器细节和自动策略仍需核验。 |
| `DTIM` | `001-global-to-envi` | `partial` | `win-utils` | 待新增 `win-utils.sys.time` | 未看到系统时间/时区设置 API；Lua 普通时间不能覆盖系统时间操作。 |
| `EDIT` | `001-global-to-envi` | `modern_replacement` | `peshell_minimal` | 现代 UI text input | 不兼容旧控件 DSL。 |
| `EJEC` | `001-global-to-envi` | `partial` | `win-utils` | `win-utils.disk` / `win-utils.sys.shell` | 弹出/卸载介质需核验。 |
| `ENVI_SET` | `001-global-to-envi` | `modern_replacement` | `win-utils` / `lua` | `win-utils.sys.env`, Lua table | 环境变量保留，PE 变量/递归解释废弃。 |
| `ENVI_SET_tail` | `002-exec-to-page` | `modern_replacement` | `win-utils` / `lua` | `win-utils.sys.env`, Lua table | 同 `ENVI_SET`，保留系统环境能力。 |
| `EXEC` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.process.exec/popen/job` | 已有 CreateProcessW、show/workdir、参数数组、env、priority、wait_input、Job 绑定、timeout kill、popen 捕获与 timeout；窗口目标/右键/内存执行等 PECMD 特殊模式不在首期，System/UAC 不迁移。 |
| `EXIT` | `002-exec-to-page` | `modern_replacement` | `lua` | `return`, `error`, coroutine 控制 | 旧流程控制语义废弃。 |
| `FBWF` | `002-exec-to-page` | `implemented` | `win-utils` | `win-utils.disk.fbwf` | 已有可用性检测、启停、阈值、保护/取消保护、排除项、commit/restore、cache info。 |
| `FDIR` | `002-exec-to-page` | `partial` | `win-utils` / `peshell_minimal` | `win-utils.fs`, folder dialog | 目录枚举已有；目录选择对话框应归 UI/Shell，需补文件夹选择 API。 |
| `FDRV` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.disk.volume/mount` | 已有盘符列表、空闲盘符、卷枚举、mount/query/unmount；PECMD 查找规则需核验。 |
| `FEXT` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.fs.path` | 扩展名/路径处理可底层化。 |
| `FILE` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.fs`, `win-utils.fs.raw` | 已有 copy/move/delete/wipe/stat/ACL/times/attributes/link/read/write；offset/atomic/全部 PECMD 开关仍需核验。 |
| `FIND` | `002-exec-to-page` | `modern_replacement` | `lua` | Lua if/string/table | 不实现旧条件语法。 |
| `FLNK` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.fs` / `win-utils.sys.shortcut` | 文件链接/快捷方式需分清。 |
| `FONT` | `002-exec-to-page` | `implemented` | `win-utils` | `win-utils.sys.font` | 已有 AddFontResourceEx/RemoveFontResourceEx、private/not_enum、字体变更广播。 |
| `FORM` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.disk.format`, `format.fmifs`, `format.fat32` | 已有格式化后端；仍需统一安全确认、dry-run 和 PECMD 参数映射。 |
| `FORX` | `002-exec-to-page` | `modern_replacement` | `lua` | Lua loops | 不实现旧循环语法。 |
| `GETF` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.fs`, `win-utils.net` | 下载/读取来源需按文档细分。 |
| `GROU` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | UI group/container | 不兼容旧控件 DSL。 |
| `HASH` | `002-exec-to-page` | `implemented` | `win-utils` | `win-utils.crypto`, `win-utils.fs.hash` | 已有 CRC32/MD5/SHA1/SHA256/SHA384/SHA512 数据与文件哈希；需 Windows 实机核验 CryptoAPI 可用性。 |
| `HELP` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | Shell help/CLI help | 不兼容旧帮助命令语义。 |
| `HIDE` | `002-exec-to-page` | `deprecated` | `none` | 无 | 进程隐藏不做。 |
| `HIVE` | `002-exec-to-page` | `partial` | `win-utils` / `win-kit` | `win-utils.reg`, `win-utils.reg.acl`, `win-kit.registry` | 底层已有 save/load/unload/with_hive 和注册表 ACL reset；`win-kit.pecmd_logic.with_super_hive` 已改用 `win.reg.acl.reset`，仍需实机核验 PECMD `-super` 等价性。 |
| `HKEY` | `002-exec-to-page` | `partial` | `win-utils` / `peshell_minimal` | `win-utils.sys.hotkey` | 热键底层保留，控件 DSL 废弃。 |
| `HOME` | `002-exec-to-page` | `partial` | `win-utils` / `win-kit` | `win-utils.sys.shell`, `win-kit.env_manager` | Shell 路径/用户目录能力需核验。 |
| `HOTK` | `002-exec-to-page` | `implemented` | `win-utils` | `win-utils.sys.hotkey` | 已有 RegisterHotKey/UnregisterHotKey、自动 ID、回调分发、clear。 |
| `IFEX` | `002-exec-to-page` | `modern_replacement` | `lua` | Lua if/assert | 不实现旧条件语法。 |
| `IMAG` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | 现代 UI image 控件 | 不兼容旧控件 DSL/GIF 细节。 |
| `IMPORT` | `002-exec-to-page` | `modern_replacement` | `lua` | `require`, Lua modules | 不实现机械 include 语义。 |
| `INIT` | `002-exec-to-page` | `partial` | `win-kit` / `peshell_minimal` | PE init recipe / Shell startup | 先补底层，再沉淀 recipe。 |
| `IPAD` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | 现代 UI input | 不兼容旧控件 DSL。 |
| `ITEM` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | Shell menu/list item | 不兼容旧控件 DSL。 |
| `KILL` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.process`, `win-utils.window` | 已有 pid/name 查找、普通 kill、soft WM_CLOSE、tree kill、SeDebugPrivilege、窗口查找/关闭公开 API；线程/句柄目标和 PECMD 特殊模式未覆盖。 |
| `LABE` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | 现代 UI label | 不兼容旧控件 DSL。 |
| `LINK` | `002-exec-to-page` | `implemented` | `win-utils` | `win-utils.sys.shortcut` | 已有创建和解析 .lnk，覆盖 target/args/work_dir/desc/icon/show/hotkey。 |
| `LIST` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | 现代 UI list | 不兼容旧控件 DSL。 |
| `LOAD` | `002-exec-to-page` | `modern_replacement` | `lua` | `require`, `dofile`, Lua config | 不运行旧 PECMD 脚本。 |
| `LOCK` | `002-exec-to-page` | `needs_decision` | `win-utils` / `peshell_minimal` | workstation/input lock | PE 场景价值需确认。 |
| `LOGO` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | 启动画面/进度 UI | 不兼容旧 LOGO 语法。 |
| `LOGS` | `002-exec-to-page` | `partial` | `win-utils` / `win-kit` | logger | 底层日志接口和高层任务日志需统一。 |
| `LOOP` | `002-exec-to-page` | `modern_replacement` | `lua` | Lua loops | 不实现旧循环语法。 |
| `LPOS` | `002-exec-to-page` | `modern_replacement` | `lua` | Lua string | 字符串定位用 Lua 替代。 |
| `LSTR` | `002-exec-to-page` | `modern_replacement` | `lua` | Lua string | 字符串截取用 Lua 替代。 |
| `MAIN` | `002-exec-to-page` | `modern_replacement` | `lua` / `peshell_minimal` | Lua entrypoint / Shell main | 不兼容旧 MAIN 语法。 |
| `MDIR` | `002-exec-to-page` | `implemented` | `win-utils` | `win-utils.fs.mkdir` | 已有普通创建和 parents 递归创建。 |
| `MEMO` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | 现代 UI multiline text | 不兼容旧控件 DSL。 |
| `MENU` | `002-exec-to-page` | `modern_replacement` | `peshell_minimal` | Shell menu | 不兼容旧控件 DSL。 |
| `MESS` | `002-exec-to-page` | `partial` | `win-utils` / `peshell_minimal` | message box, task dialogs | 底层对话框进 `win-utils`，交互流程进 Shell。 |
| `MOUN` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.wim`, `win-utils.disk.vhd`, `win-utils.disk.mount` | WIM mount/unmount/list、VHD/ISO create/open/attach/detach/expand、盘符挂载已有；UDM/U+/OnlyApp/SetOnlyApp/Server 旧生态兼容默认不做。 |
| `MSTR` | `002-exec-to-page` | `modern_replacement` | `lua` | Lua string/pattern | 字符串匹配用 Lua 替代。 |
| `NAME_FNAM` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.fs.path` | 文件名/路径处理需补齐。 |
| `NTPC` | `002-exec-to-page` | `partial` | `win-utils` | 待新增 `win-utils.net.ntp` 或 `win-utils.sys.time` | 未看到 NTP 同步 API；当前 net 只有 adapter list、DNS flush、ICMP、TCP stat。 |
| `NUMK` | `002-exec-to-page` | `partial` | `win-utils` | `win-utils.input` | 已有 GetKeyState、toggle key、SendInput/keybd_event 基础，可覆盖 NumLock；实机键盘状态行为仍需核验。 |
| `PAGE` | `002-exec-to-page` | `partial` | `win-utils` / `win-kit` | `win-utils.sys.pagefile`, `win-kit.smart_pagefile` | 底层已有 NtCreatePagingFile；查询/删除/策略细节仍需核验。 |
| `PART` | `003-part-to-regi` | `partial` | `win-utils` / `win-kit` | `win-utils.disk.layout`, `win-kit.partition_tools` | 已有布局读取/应用、clean、set_active、set_partition_type/attributes，以及 ID/active/hidden/readonly 高层封装；仍需安全确认、dry-run 和 PECMD 参数对齐。 |
| `PATH` | `003-part-to-regi` | `partial` | `win-utils` | `win-utils.sys.path`, `win-utils.fs.path`, `win-utils.sys.env` | 路径 join/basename/dirname/splitext/abspath/which/环境变量已有；PATH 编辑策略待核验。 |
| `PBAR` | `003-part-to-regi` | `modern_replacement` | `peshell_minimal` | 现代 UI progress bar | 不兼容旧控件 DSL。 |
| `PCIP` | `003-part-to-regi` | `partial` | `win-utils` | `win-utils.net.adapter/dns` | 当前仅见网卡枚举、DNS flush、ping/TCP stat；静态 IP/DHCP/DNS 设置未见实现。 |
| `PINT` | `003-part-to-regi` | `modern_replacement` | `peshell_minimal` | 现代 UI paint/custom draw | 不兼容旧控件 DSL。 |
| `PUTF` | `003-part-to-regi` | `partial` | `win-utils` | `win-utils.fs`, `win-utils.net` | 写入/上传目标需按文档核验。 |
| `RADI` | `003-part-to-regi` | `modern_replacement` | `peshell_minimal` | 现代 UI radio | 不兼容旧控件 DSL。 |
| `RAMD` | `003-part-to-regi` | `deprecated` | `none` | 无 | ImDisk/Ramdriv 旧虚拟盘命令兼容当前默认不做；优先使用 Windows 原生 VHD/VHDX/WIM/ISO 能力。 |
| `RAND` | `003-part-to-regi` | `modern_replacement` | `lua` | `math.random` 或 crypto random | 普通随机用 Lua，安全随机另补底层。 |
| `READ` | `003-part-to-regi` | `partial` | `win-utils` | `win-utils.fs.read` | 已有统一文本/二进制读取入口；encoding、offset/length、INI/注册表等 PECMD 语义需继续拆分。 |
| `RECY` | `003-part-to-regi` | `partial` | `win-utils` | 待新增 shell/recycle API | 绑定里有 SHFileOperation，但未看到回收站封装；PE 场景价值仍需确认。 |
| `REGI` | `003-part-to-regi` | `partial` | `win-utils` / `win-kit` | `win-utils.reg`, `win-kit.registry` | 底层已有 open/read/write/delete_value/delete_key、create/open_existing、enum_values/enum_keys、UTF-16 `.reg` export 和常见值类型；`win-kit.registry.import` 支持 Lua table 导入；`.reg` 导入和全部 PECMD 参数仍需核验。 |
| `RPOS` | `004-rpos-to-writ` | `modern_replacement` | `lua` | Lua string | 字符串定位用 Lua 替代。 |
| `RSTR` | `004-rpos-to-writ` | `modern_replacement` | `lua` | Lua string | 字符串截取用 Lua 替代。 |
| `RUNS` | `004-rpos-to-writ` | `partial` | `win-utils` | `win-utils.reg`, 待新增 autorun helper | 可用注册表底层实现 Run 项；未看到启动项专用封装。 |
| `SCRN` | `004-rpos-to-writ` | `partial` | `win-utils` / `peshell_minimal` | 待新增 screenshot/display helper | 未看到 BitBlt/截图封装；Shell 展示后置。 |
| `SED` | `004-rpos-to-writ` | `modern_replacement` | `lua` | Lua string/gsub | 文本替换用 Lua 替代。 |
| `SEND` | `004-rpos-to-writ` | `partial` | `win-utils` | `win-utils.input` | 已有 send_key/send_combo/send_text/mouse move/click/wheel；PECMD 全部发送语法不兼容，需实机核验焦点/桌面环境。 |
| `SERV` | `004-rpos-to-writ` | `implemented` | `win-utils` | `win-utils.sys.service` | 已有 list/query/start/stop/wait/set_start_mode/dependents/stop_recursive/create/delete。 |
| `SHEL` | `004-rpos-to-writ` | `implemented` | `win-utils` | `win-utils.sys.shell` | 已有 CommandLineToArgvW、get_args、SHBrowseForFolder、ShellExecuteEx、restart_self。 |
| `SHOW` | `004-rpos-to-writ` | `partial` | `win-utils` / `win-kit` | `win-utils.disk.mount/volume`, `win-kit.automount` | 已有盘符挂载/卸载/查询和自动挂载 recipe；PECMD 显示/隐藏/过滤策略需核验。 |
| `SHUT` | `004-rpos-to-writ` | `partial` | `win-utils` / `win-kit` | `win-utils.sys.power`, `win-utils.disk.sync`, `win-kit.poweroff` | 已有 shutdown/reboot/boot_to_firmware 和磁盘 sync；关机前 PE 清理策略仍在 `win-kit`。 |
| `SITE` | `004-rpos-to-writ` | `partial` | `win-utils` | `win-utils.fs.stat`, `win-utils.fs.raw` | 已有 stat/get_file_info/physical size；偏移类读写语义需核验。 |
| `SIZE` | `004-rpos-to-writ` | `implemented` | `win-utils` | `win-utils.fs.get_space_info`, `win-utils.fs.get_usage_info`, `win-utils.fs.stat` | 已有文件/目录用量和磁盘空间信息。 |
| `SLID` | `004-rpos-to-writ` | `modern_replacement` | `peshell_minimal` | 现代 UI slider | 不兼容旧控件 DSL。 |
| `SOCK` | `004-rpos-to-writ` | `deprecated` | `none` | 无 | 不复刻 PECMD `SOCK` 对象系统；socket/pipe/mailslot/shared memory/event/mutex/semaphore 混合 DSL 默认不做。现代替代按用途拆分到 `win-utils.net.tcp/udp/http`、`win-utils.process.exec/popen` 或未来 `win-utils.ipc.*`。 |
| `SPIN` | `004-rpos-to-writ` | `modern_replacement` | `peshell_minimal` | 现代 UI spinner | 不兼容旧控件 DSL。 |
| `SSTR` | `004-rpos-to-writ` | `modern_replacement` | `lua` | Lua string | 字符串能力用 Lua 替代。 |
| `STRL` | `004-rpos-to-writ` | `modern_replacement` | `lua` | Lua string | 字符串长度用 Lua 替代。 |
| `SUBJ` | `004-rpos-to-writ` | `partial` | `win-utils` / `win-kit` | `win-utils.disk.volume`, `win-utils.disk.mount`, `win-kit.automount` | 已有卷枚举、卷标设置、盘符分配/移除；自动整理策略需继续核验。 |
| `SWIN` | `004-rpos-to-writ` | `partial` | `win-utils` / `peshell_minimal` | `win-utils.window` | 已有窗口枚举、按 title/class/pid 查找、wait、show/hide/activate/close/move/resize；旧语法和复杂窗口规则不兼容。 |
| `TABL` | `004-rpos-to-writ` | `modern_replacement` | `peshell_minimal` | 现代 UI table | 不兼容旧控件 DSL。 |
| `TABS` | `004-rpos-to-writ` | `modern_replacement` | `peshell_minimal` | 现代 UI tabs | 不兼容旧控件 DSL。 |
| `TEAM` | `004-rpos-to-writ` | `modern_replacement` | `lua` | Lua table/function composition | 不实现旧命令组语法。 |
| `TEMP` | `004-rpos-to-writ` | `partial` | `win-utils` / `win-kit` | `win-utils.sys.env`, temp path helpers | 临时目录底层和 PE 策略分层。 |
| `TEXT` | `004-rpos-to-writ` | `modern_replacement` | `peshell_minimal` | 现代 UI text/static display | 不兼容旧控件 DSL。 |
| `THREAD_THRD` | `004-rpos-to-writ` | `modern_replacement` | `lua` / `win-utils` | Lua coroutine / process jobs | 旧线程命令语法废弃；并发按现代 API 设计。 |
| `TIME` | `004-rpos-to-writ` | `partial` | `win-utils` / `lua` | Lua time, `win-utils.sys.time` | 系统时间设置需底层能力。 |
| `TIPS` | `004-rpos-to-writ` | `modern_replacement` | `peshell_minimal` | notification/toast/status UI | 不兼容旧提示语法。 |
| `UPNP` | `004-rpos-to-writ` | `deprecated` | `none` | 无 | BartPE/NT5 legacy。 |
| `USER` | `004-rpos-to-writ` | `partial` | `win-utils` / `win-kit` | `win-utils.sys.user`, `win-kit.oem` | 已补当前用户名、SAM/UPN、计算机名、DNS 名称、elevated 状态；OEM 信息读写已有；账户创建/删除/密码等高风险管理能力暂未补。 |
| `WALL` | `004-rpos-to-writ` | `implemented` | `win-utils` | `win-utils.sys.desktop` | 已有 set_wallpaper，支持 fill/fit/stretch/tile/center/span 并刷新桌面。 |
| `WAIT` | `004-rpos-to-writ` | `partial` | `win-utils` | `win-utils.process`, `win-utils.window` | 进程出现/退出等待、sleep、WaitForInputIdle、窗口查找等待已有；任意条件等待和旧语法不兼容。 |
| `WRIT` | `004-rpos-to-writ` | `partial` | `win-utils` | `win-utils.fs.write` | 已有统一文本/二进制写入入口；encoding、offset/atomic、INI/注册表等 PECMD 语义需继续拆分。 |
| `line_continuation_backslash` | `004-rpos-to-writ` | `deprecated` | `none` | 无 | 旧脚本续行/并行符随解析器废弃。 |
| `pecmd_dll_entry` | `004-rpos-to-writ` | `deprecated` | `none` | 无 | 不兼容 DLL 版 PECMD 入口。 |
| `windows_virtual_key_table` | `005-appendices-and-meta` | `partial` | `win-utils` | `win-utils.sys.hotkey` 或新增常量表 | 热键 API 已有，完整 VKey 常量表未见独立导出。 |
| `mbr_partition_type_table` | `005-appendices-and-meta` | `implemented` | `win-utils` | `win-utils.disk.types` | 已有 MBR 分区类型常量表。 |
| `gpt_partition_type_guid_table` | `005-appendices-and-meta` | `implemented` | `win-utils` | `win-utils.disk.types` | 已有 GPT GUID 常量表。 |
| `disk_media_type_table` | `005-appendices-and-meta` | `partial` | `win-utils` | `win-utils.disk.types` | 未在 `disk.types` 看到完整 media type 常量表。 |
| `script_to_command_line` | `005-appendices-and-meta` | `deprecated` | `none` | 无 | 旧脚本转命令行废弃。 |
| `comment_rules` | `005-appendices-and-meta` | `deprecated` | `none` | 无 | 旧注释语法废弃。 |
| `init_and_embedded_scripts` | `005-appendices-and-meta` | `modern_replacement` | `peshell_minimal` / `lua` | Lua entrypoint, Shell startup | 不运行内置 PECMD 脚本。 |
| `icon_numbering` | `005-appendices-and-meta` | `partial` | `win-utils` / `peshell_minimal` | `win-utils.sys.shortcut`, shell resources | 图标编号可转为资源/快捷方式 API。 |
| `plugin_system` | `005-appendices-and-meta` | `deprecated` | `none` | 无 | 旧插件 ABI 不做。 |
| `customization_and_drag_drop` | `005-appendices-and-meta` | `needs_decision` | `peshell_minimal` | Shell customization/drag-drop | 属最终 Shell 体验，后置决策。 |
| `pe_build_notes` | `005-appendices-and-meta` | `needs_decision` | `peshell_minimal` / docs | PE build docs/tasks | 构建资料不等同运行 API。 |
| `thanks_notes` | `005-appendices-and-meta` | `deprecated` | `docs` | 无 | 非功能对象。 |
| `license_notes` | `005-appendices-and-meta` | `needs_decision` | `docs` | license tracking | 需要保留合规记录，不是运行功能。 |
