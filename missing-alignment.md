# 缺失功能对齐清单

本文档记录从 `matrix.md` 静态核验出的明确缺口。优先补 `win-utils`，只有流程策略进入 `win-kit`，最终交互进入 `peshell_minimal`。

## 已修复的连通性问题

- `win-utils.process.sleep(ms)`: 已新增，修复 `win-kit.unlocker`、`icon_refresh`、`pecmd_logic` 调用缺失。
- `win.reg.acl`: 已通过 `win-utils.reg` 延迟导出。
- `win-kit.pecmd_logic.with_super_hive`: 已从 `win.fs.acl.reset` 改为 `win.reg.acl.reset`。

## `win-utils.process`

已对齐：
- `exec(opts)` table API，支持 `args = {}`、`env = {}`、`cwd`、`show`、`priority`、`wait_input_idle`、`timeout`、`job`、`kill_tree_on_timeout`。
- `popen.run` timeout 已改为 `PeekNamedPipe + WaitForSingleObject` 轮询，避免静默长任务卡住 timeout。
- `job` 可通过 `exec(opts)` 绑定，支持 `kill_on_close`。

已对齐：
- `capture` / `capture_stdout` / `capture_stderr` 已合并进 `exec(opts)` 返回模型。

仍需补齐：
- 线程/句柄目标终止是否需要支持需再决策。

## `win-utils.reg`

已对齐：
- `RegKey:enum_values()`。
- `RegKey:enum_keys()`。
- `reg.export(root, sub, path, opts)`，输出 UTF-16 `.reg` 文本。
- `create_key` / `open_existing_key` 已新增；`open_key` 保留 create/open 兼容语义。

已对齐：
- `.reg` 文件导入由 `win-utils.reg.import_file(path, opts)` 承担；`win-kit.registry.import` 保留 Lua table 导入职责。

仍需补齐：
- 继续核验 `HIVE -super`：`load_hive + reg.acl.reset + with_hive` 是否等价。

## `win-utils.net`

已对齐：
- `adapter.set_ipv4(adapter, opts)`，覆盖 DHCP/静态 IP/网关/掩码。
- `adapter.list()` 已补连接名、适配器名、接口索引、MAC、MTU、类型、DNS、网关、IPv4 前缀和 DHCP 推断字段。
- `dns.set_servers(adapter, servers)`。
- `adapter.enable/disable(adapter)`。
- `ntp.sync(server, opts)` 与 `sys.time.sync_ntp`。

仍需补齐：
- `SOCK` 完整对象系统当前默认不做；不复刻 socket/pipe/mailslot/shared memory/event/mutex/semaphore 混合 DSL。现代替代按用途拆分：TCP/UDP 可进 `win-utils.net.tcp/udp`，HTTP 可进 `win-utils.net.http`，子进程管道归入 `win-utils.process.exec/popen`，IPC 原语仅在真实需求出现时设计 `win-utils.ipc.*` 子集。

## `win-utils.fs` / `win-utils.text` / codec

已对齐：
- `fs.read(path, opts)`，支持基础 text/binary 与 `bytes`。
- `fs.write(path, data, opts)`，支持基础 text/binary、append。
- `text.base64_encode/decode`，标准 Base64。
- `fs.hash(data, "crc32")` 与 `fs.hash_file(path, "crc32")`。
- `crypto.hash/hash_file` 已补 MD5/SHA1/SHA256/SHA384/SHA512。
- `text.convert_file(src, dst, from_cp, to_cp)`。

已对齐：
- `fs.read/write` 的 encoding、offset/length、atomic。

已决策不做：
- PECMD 变异 Base64 仅服务旧 `ADSL` 账号密码混淆；`ADSL` 已废弃，现代用途保留标准 Base64 即可。

## `win-utils.disk` / `win-kit.partition_tools`

已对齐：
- 破坏性 API 统一 `dry_run` / `confirm`，包括 `PART/FORM/DISK clean/apply` 相关公开入口。
- `PAGE` 查询、配置移除、禁用页面文件配置；`NtCreatePagingFile` 创建保留。

仍需补齐或对齐：
- `PART` 参数对齐：ID、active、hidden、readonly 已有基础，但需要统一安全 API 和日志。
- `MOUN` 明确保留 WIM/VHD/ISO；UDM/U+/OnlyApp/SetOnlyApp/Server 旧生态兼容默认不做。

## `win-utils.input` / `win-utils.window`

已对齐：
- `input.send_key/send_combo/send_text`。
- `input.move_mouse/click/wheel`。
- `input.get_key_state/set_toggle_key`，覆盖 `NUMK` 基础。
- `window.list/find/wait`，按标题/类名/PID 枚举窗口。
- `window.show/hide/move/resize/activate/close`，覆盖 `SWIN` 现代 API。

仍需补齐：
- Windows/PE 实机核验 SendInput/keybd_event/mouse_event 在目标桌面和焦点下的行为。

已对齐：
- `win-utils.vk` 已提供独立虚拟键常量表和 normalize helper；旧 PECMD 发送语法映射不做兼容。

## `win-utils.ui` / `win-utils.sys.shell`

GUI 方向决策：不复刻 PECMD WinCMD 控件 DSL；现代 GUI 能力对齐 AutoHotkey v2 的对象化模型，由 `peshell_minimal` 暴露 Lua API，底层优先使用 ImGui/cimgui。

GUI 复杂度基准以 CGI 类系统部署工具为准：镜像选择、目标分区列表、选项复选框、部署进度、日志和确认/错误弹窗。该级别由 AHK v2-like Lua API + ImGui backend 覆盖即可，不引入 WebView/WinUI/.NET。

已对齐：
- `peshell_minimal` 已提供 ImGui message box view model + draw 层，覆盖 `MESS` 最小替代路径。
- `peshell_minimal` 已提供 ImGui file picker view model + draw 层，覆盖 `BROW`/`FDIR` 现代替代路径。
- `ui.select_folder_dialog` 已可由 `sys.shell.browse_folder` 承担，ImGui file picker 也支持 folder mode。

仍需补齐：
- 上述 ImGui UI 需 Windows/cimgui 实机渲染核验。
- 需要新增 AHK v2-like `ui.gui` 抽象：窗口、控件、事件、value/state、`show/draw` 生命周期。
- 优先控件：`Text/Button/Edit/Checkbox/Radio/DropDownList/ListView/Progress/Tab/StatusBar/LogView/PathPicker/DiskList/ConfirmDialog`。
- `screenshot.capture(opts)`，覆盖 `SCRN`。

## `win-utils.sys`

已对齐：
- `sys.user` 已实现当前用户名、SAM/UPN、计算机名、DNS 名称、elevated 状态，修复 `sys/init.lua` 预留模块断点。
- `sys.autorun` 封装 HKCU/HKLM Run/RunOnce 启动项。
- `sys.time` 提供 Lua 时间查询、Win32 本地/UTC 时间读写、NTP 同步和 `tzutil` 时区查询/设置封装。
- `sys.recycle` 提供移动到回收站、清空回收站、查询回收站信息，并对 Shell32 缺失返回清晰错误。

仍需补齐：
- `sys.time` / `sys.recycle` 仍需 Windows/PE 实机核验。

## `win-kit`

需要对齐：
- `win-kit` 中 recipes 应只调用 `win-utils`，不直接新增底层 FFI。
- `win-kit.pecmd_logic.lua` 名称仍会误导，应拆分：`exec_capture` 下沉到 `win-utils.process`，`with_super_hive` 合并到 `win-kit.registry` 或下沉通用部分到 `win-utils.reg`。
- `win-kit.partition_tools` 里 `win.core.ioctl` 调用需核验：`win-utils.core` 当前是 `win-utils.core.util`，是否导出 `ioctl` 取决于 util，建议显式使用底层模块避免误读。

## `peshell_minimal`

后置对齐：
- Shell/CLI 入口、菜单、用户交互、任务进度、日志查看。
- ImGui native host 已有 Win32/D3D11 contract、`imgui-native-smoke`、message box/file picker draw 层；仍需 Windows/cimgui 编译运行核验。
- 旧 WinCMD 控件 DSL 不迁移，只做现代 UI。
- `customization_and_drag_drop` 属最终 Shell 体验，待 `win-utils` 稳定后再决策。
