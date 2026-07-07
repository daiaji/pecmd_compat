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

仍需补齐：
- `capture` 暂由 `process.popen.run` 提供，尚未合并进 `exec(opts)` 返回模型。
- 线程/句柄目标终止是否需要支持需再决策。

## `win-utils.reg`

已对齐：
- `RegKey:enum_values()`。
- `RegKey:enum_keys()`。
- `reg.export(root, sub, path, opts)`，输出 UTF-16 `.reg` 文本。
- `create_key` / `open_existing_key` 已新增；`open_key` 保留 create/open 兼容语义。

仍需补齐：
- `.reg` 导入或与 `win-kit.registry.import` 的职责边界。
- 继续核验 `HIVE -super`：`load_hive + reg.acl.reset + with_hive` 是否等价。

## `win-utils.net`

需要补齐：
- `adapter.set_ipv4(adapter, opts)`，覆盖 DHCP/静态 IP/网关/掩码。
- `dns.set_servers(adapter, servers)`。
- `adapter.enable/disable(adapter)`。
- `ntp.sync(server, opts)` 或 `sys.time.sync_ntp`。
- `SOCK` 完整对象系统当前默认不做；不复刻 socket/pipe/mailslot/shared memory/event/mutex/semaphore 混合 DSL。现代替代按用途拆分：TCP/UDP 可进 `win-utils.net.tcp/udp`，HTTP 可进 `win-utils.net.http`，子进程管道归入 `win-utils.process.exec/popen`，IPC 原语仅在真实需求出现时设计 `win-utils.ipc.*` 子集。

## `win-utils.fs` / `win-utils.text` / codec

已对齐：
- `fs.read(path, opts)`，支持基础 text/binary 与 `bytes`。
- `fs.write(path, data, opts)`，支持基础 text/binary、append。
- `text.base64_encode/decode`，标准 Base64。
- `fs.hash(data, "crc32")` 与 `fs.hash_file(path, "crc32")`。
- `crypto.hash/hash_file` 已补 MD5/SHA1/SHA256/SHA384/SHA512。
- `text.convert_file(src, dst, from_cp, to_cp)`。

仍需补齐：
- `fs.read/write` 的 encoding、offset/length、atomic。
- PECMD 变异 Base64 账号密码算法是否需要保留需按真实用途确认。

## `win-utils.disk` / `win-kit.partition_tools`

需要补齐或对齐：
- 破坏性 API 统一 `dry_run` / `confirm`，包括 `PART/FORM/DISK clean/apply`。
- `PAGE` 查询/删除/禁用页面文件能力；当前只有 `NtCreatePagingFile` 创建和 `win-kit.smart_pagefile` 策略。
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
- 更完整的虚拟键常量表和旧 PECMD 发送语法映射不做兼容，仅按现代 API 需要扩展。

## `win-utils.ui` / `win-utils.sys.shell`

需要补齐：
- `ui.message_box`，覆盖 `MESS` 最小替代。
- `ui.open_file_dialog` / `ui.save_file_dialog`，补齐 `BROW` 文件选择。
- `ui.select_folder_dialog` 已可由 `sys.shell.browse_folder` 承担，后续可转发。
- `screenshot.capture(opts)`，覆盖 `SCRN`。

## `win-utils.sys`

已对齐：
- `sys.user` 已实现当前用户名、SAM/UPN、计算机名、DNS 名称、elevated 状态，修复 `sys/init.lua` 预留模块断点。

仍需补齐：
- `sys.autorun` 或 `sys.run_keys`，封装启动项 `RUNS`。
- `sys.recycle`，若确认 PE 场景需要回收站能力。
- `sys.time`，覆盖系统时间/时区/NTP。

## `win-kit`

需要对齐：
- `win-kit` 中 recipes 应只调用 `win-utils`，不直接新增底层 FFI。
- `win-kit.pecmd_logic.lua` 名称仍会误导，应拆分：`exec_capture` 下沉到 `win-utils.process`，`with_super_hive` 合并到 `win-kit.registry` 或下沉通用部分到 `win-utils.reg`。
- `win-kit.partition_tools` 里 `win.core.ioctl` 调用需核验：`win-utils.core` 当前是 `win-utils.core.util`，是否导出 `ioctl` 取决于 util，建议显式使用底层模块避免误读。

## `peshell_minimal`

后置对齐：
- Shell/CLI 入口、菜单、用户交互、任务进度、日志查看。
- 旧 WinCMD 控件 DSL 不迁移，只做现代 UI。
- `customization_and_drag_drop` 属最终 Shell 体验，待 `win-utils` 稳定后再决策。
