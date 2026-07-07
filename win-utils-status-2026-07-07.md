# win-utils 当前完成度快照

日期：2026-07-07

本文档记录当前 `win-utils` 相对 PECMD Lua 重构目标的阶段性完成度。它不是测试覆盖率报告，而是基于 `matrix.md`、`missing-alignment.md` 和 `/home/daiaji/repo/pecmd_compat/win-utils` 实际模块结构的工程评估。

产品兼容性目标：Windows 10 Enterprise LTSC 2019+ / WinPE。最低工程基线为 Windows 10 1809 / build 10.0.17763；Windows 10 Enterprise LTSC 2021 对应 Windows 10 21H2 / build 10.0.19044。

## 总体判断

`win-utils` 已经不是空架子，已经覆盖 WinPE 自动化所需的大部分底层能力；但它仍是“功能丰富的半成品底座”，需要继续做工程收敛。

粗略判断：

- 核心骨架完成度：约 60-70%。
- PECMD/WinPE 自动化首期可用度：约 50-60%。
- 当前主要问题不是缺少全部模块，而是大量对象仍是 `partial`，需要补安全闸门、参数边界、返回值模型、实机核验和少数缺失 API。

## 矩阵口径统计

当前 `matrix.md` 覆盖 138 个对象：

| 状态 | 数量 |
| --- | ---: |
| `implemented` | 12 |
| `partial` | 53 |
| `modern_replacement` | 56 |
| `deprecated` | 13 |
| `needs_decision` | 4 |

其中直接涉及 `win-utils` 的对象约 69 个：

| 状态 | 数量 |
| --- | ---: |
| `implemented` | 12 |
| `partial` | 52 |
| `modern_replacement` | 4 |
| `needs_decision` | 1 |

这说明 `win-utils` 已经承接了大部分底层系统能力，但多数仍处在部分覆盖状态。

## 已比较强的模块

### `process`

当前已有：

- `exec(opts)` table API。
- 参数数组、环境变量、工作目录、窗口显示、优先级、`WaitForInputIdle`、timeout、job、kill tree。
- `popen.run` capture 和 timeout。
- `token`、`job`、`memory`、`module`、`handles` 子模块。

仍需补齐：

- `capture` 仍由 `process.popen.run` 提供，尚未合并进统一 `process.exec(opts)` 返回模型。
- 线程/句柄目标终止是否需要支持仍需决策。
- `process/init.lua`、`process/popen.lua` 仍有内联 `ffi.cdef`，应迁入 `lua-ffi-bindings`。

### `reg`

当前已有：

- 注册表 open/read/write/delete。
- `create_key` / `open_existing_key`。
- `RegKey:enum_keys()` / `RegKey:enum_values()`。
- 常见类型：string、expand_sz、binary、dword、qword、multi_sz。
- Hive load/unload/save/with_hive。
- 注册表 ACL reset。
- UTF-16 `.reg` export。

仍需补齐：

- `.reg` import 或与 `win-kit.registry.import` 的职责边界。
- `HIVE -super` 等价行为需要实机核验。
- `reg/init.lua` 仍有内联 `ffi.cdef`，应迁入 `lua-ffi-bindings`。

### `disk`

当前已有：

- `physical`、`layout`、`geometry`、`mount`、`volume`、`format`、`vhd`、`surface`、`image`、`esp`、`types`、`safety`、`info`、`fbwf`、`bitlocker` 等模块。
- WIM/VHD/ISO/盘符/卷/分区/格式化/FBWF 基础能力。
- `prepare_drive`、`clean_all`、`check_health`、`sync` 等高层入口。

仍需补齐：

- 所有破坏性 API 统一 `dry_run`、`confirm`、日志和错误返回。
- `PART/FORM/DISK clean/apply` 需要统一安全闸门。
- `PAGE` 查询、删除、禁用页面文件能力仍缺。
- `UDM/U+`、`ImDisk/RAMD` 旧生态兼容默认不做；不要把这些重新纳入当前路线图。
- BitLocker 状态检测应进入 `disk.safety` 的只读前置检查，目标是识别风险并阻止危险操作。
- BCD/boot repair 应先由 `win-kit` recipe 调用系统工具，不在 `win-utils` 首期重写 BCD 解析器。

### `fs` / `text` / `crypto`

当前已有：

- 文件/目录 copy、move、delete、mkdir、scandir、stat、link、raw、ACL 基础。
- `fs.read(path, opts)` / `fs.write(path, data, opts)` 基础文本/二进制读写。
- 标准 Base64。
- CRC32、MD5、SHA1、SHA256、SHA384、SHA512。
- 字符串和文件级编码转换。

仍需补齐：

- `fs.read/write` 的 encoding、offset/length、atomic。
- PECMD 变异 Base64 账号密码算法是否保留，需要真实样本或用途再决策。
- `crypto.lua`、`fs/acl.lua` 仍有内联 FFI，应迁入 `lua-ffi-bindings`。

### `sys`

当前已有：

- `service`、`driver`、`power`、`desktop`、`display`、`shortcut`、`hotkey`、`info`、`shell`、`io`、`path`、`env`、`pagefile`、`dism`、`inf`、`dev_info`、`font`、`user`、`dev_ctrl`。
- 已覆盖很多 PECMD 的 `SERV`、`LINK`、`FONT`、`HOTK`、`WALL`、`SHEL`、`DEVI` 基础场景。

仍需补齐：

- `sys.time`：系统时间、时区、NTP 同步。
- `sys.autorun` 或 `sys.run_keys`：封装启动项 `RUNS`。
- `sys.recycle`：若确认 PE 场景需要回收站能力。
- `sys/user.lua`、`sys/dev_ctrl.lua` 仍有内联 FFI，应迁入 `lua-ffi-bindings`。

### `input` / `window`

当前已有：

- 键盘、鼠标输入。
- NumLock 等 key state/toggle 基础。
- 窗口枚举、按标题/类名/PID 查找、等待、显示/隐藏、激活、关闭、移动、缩放。

仍需补齐：

- Windows/PE 实机核验 `SendInput`、`keybd_event`、`mouse_event` 在目标桌面和焦点下的行为。
- 完整虚拟键常量表可按现代 API 需要补，不做旧 PECMD 发送语法兼容。
- `input.lua`、`window.lua` 仍有内联 FFI，应迁入 `lua-ffi-bindings`。

## 明显薄弱的模块

### `net`

当前只有：

- `adapter`。
- `dns`。
- `icmp`。
- `stat`。

仍需补齐：

- `adapter.set_ipv4(adapter, opts)`。
- DHCP/静态 IP/网关/掩码。
- `dns.set_servers(adapter, servers)`。
- `adapter.enable/disable(adapter)`。
- `ntp.sync(server, opts)` 或 `sys.time.sync_ntp`。

`SOCK` 完整对象系统默认不做。现代通信能力如果需要，应按用途拆分到：

- `win-utils.net.tcp` / `win-utils.net.udp`。
- `win-utils.net.http`。
- `win-utils.process.exec/popen` 的管道模型。
- 未来真实需要时的 `win-utils.ipc.*`。

### `ui`

当前还没有明确的 `win-utils.ui` 模块。

仍需补齐：

- `ui.message_box`。
- `ui.open_file_dialog`。
- `ui.save_file_dialog`。
- `screenshot.capture(opts)`。

复杂 UI、旧 WinCMD 控件 DSL、ImGui 集成都不应进入 `win-utils`，应放到 `peshell_minimal` 或后续 Shell 阶段。

### Shell32 / COM 依赖

极简 WinPE 可能缺失或裁剪 Shell 子系统。`sys.shell`、shortcut、dialog、recycle 等依赖 Shell32/COM 的能力应提供可用性检测和清晰错误。基础 copy/move/delete 应优先保留 Kernel32/NtAPI 路径，不能因为 Shell32 不可用而完全失效。

## FFI 边界问题

当前仍有内联 `ffi.cdef` 的重点文件：

- `/home/daiaji/repo/pecmd_compat/win-utils/input.lua`
- `/home/daiaji/repo/pecmd_compat/win-utils/window.lua`
- `/home/daiaji/repo/pecmd_compat/win-utils/crypto.lua`
- `/home/daiaji/repo/pecmd_compat/win-utils/sys/user.lua`
- `/home/daiaji/repo/pecmd_compat/win-utils/sys/dev_ctrl.lua`
- `/home/daiaji/repo/pecmd_compat/win-utils/reg/init.lua`
- `/home/daiaji/repo/pecmd_compat/win-utils/fs/acl.lua`
- `/home/daiaji/repo/pecmd_compat/win-utils/process/init.lua`
- `/home/daiaji/repo/pecmd_compat/win-utils/process/popen.lua`

目标状态：

- `win-utils` 不新增内联 `ffi.cdef`。
- 缺失 Windows SDK 声明先补到 `lua-ffi-bindings`。
- `win-utils` 只消费集中 binding，并提供稳定 Lua API。

## 下一步优先级

建议按以下顺序推进：

1. 清理 `win-utils` 内联 `ffi.cdef`，集中迁到 `lua-ffi-bindings`。
2. 给 `disk` 破坏性 API 建立统一 `confirm` / `dry_run` / 日志安全闸门。
3. 把 `process.popen.run` 的 capture 模型合并进 `process.exec(opts)`。
4. 补 `net` 的 IPv4/DNS/NTP 设置能力。
5. 补 `fs.read/write` 的 encoding、offset/length、atomic。
6. 补最小 `ui.message_box`、open/save file dialog、screenshot capture。
7. 对 `reg.with_hive` / `HIVE -super`、input/window、disk destructive path 做 Windows/PE 实机核验。
8. 补 BitLocker 只读检测、BCD/boot repair recipe 定位、Shell32/COM 依赖探测。
9. 建立测试分层：纯 Lua/离线、Windows CI、管理员权限、WinPE 实机、真实磁盘/USB destructive。

## 当前阶段结论

`win-utils` 已经可以作为 WinPE 自动化重构的主底座继续推进；当前不需要重写方向，也不需要引入 PECMD 语法兼容层。

最重要的工作是收敛：FFI 分层、安全默认、统一返回值、缺失 API 和实机验证。
