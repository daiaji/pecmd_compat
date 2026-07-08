# win-utils 当前完成度快照

日期：2026-07-07

本文档记录当前 `win-utils` 相对 PECMD Lua 重构目标的阶段性完成度。它不是测试覆盖率报告，而是基于 `matrix.md`、`missing-alignment.md` 和 `/home/daiaji/repo/pecmd_compat/win-utils` 实际模块结构的工程评估。

产品兼容性目标：Windows 10 Enterprise LTSC 2019+ / WinPE。最低工程基线为 Windows 10 1809 / build 10.0.17763；Windows 10 Enterprise LTSC 2021 对应 Windows 10 21H2 / build 10.0.19044。

## 总体判断

`win-utils` 已经不是空架子，已经覆盖 WinPE 自动化所需的大部分底层能力；`peshell_minimal` 也已经建立 ImGui/Win32+D3D11 的首个 UI 集成路径。但整体仍是“功能丰富的半成品底座”，需要继续做工程收敛和 Windows/WinPE 实机核验。

粗略判断：

- 核心骨架完成度：约 60-70%。
- PECMD/WinPE 自动化首期可用度：约 50-60%。
- 当前主要问题不是缺少全部模块，而是大量对象仍是 `partial`，需要做实机核验、少数缺失 API、UI 后端打包和 Windows 运行验证。

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
- `exec(opts)` capture / `capture_stdout` / `capture_stderr` 返回模型。
- `token`、`job`、`memory`、`module`、`handles` 子模块。

仍需补齐：

- 线程/句柄目标终止是否需要支持仍需决策。

### `reg`

当前已有：

- 注册表 open/read/write/delete。
- `create_key` / `open_existing_key`。
- `RegKey:enum_keys()` / `RegKey:enum_values()`。
- 常见类型：string、expand_sz、binary、dword、qword、multi_sz。
- Hive load/unload/save/with_hive。
- 注册表 ACL reset。
- UTF-16 `.reg` export。
- `.reg` import_file。

仍需补齐：

- `HIVE -super` 等价行为需要实机核验。

### `disk`

当前已有：

- `physical`、`layout`、`geometry`、`mount`、`volume`、`format`、`vhd`、`surface`、`image`、`esp`、`types`、`safety`、`info`、`fbwf`、`bitlocker` 等模块。
- WIM/VHD/ISO/盘符/卷/分区/格式化/FBWF 基础能力。
- `prepare_drive`、`clean_all`、`check_health`、`sync` 等高层入口。

已补齐/对齐：

- 破坏性 API 已统一接入 `dry_run` / `confirm` 安全闸门，覆盖 `PART/FORM/DISK clean/apply` 相关公开入口。
- `PAGE` 已补 PagingFiles 查询、配置、禁用和移除配置；`NtCreatePagingFile` 创建保留。
- BitLocker、系统盘、固定盘、只读/离线、pagefile/hiberfil、写保护策略等风险已进入 `disk.safety` 前置检查。

仍需补齐：

- 破坏性 API 的 Windows/WinPE 实机验证和日志细节仍需跑通。
- `UDM/U+`、`ImDisk/RAMD` 旧生态兼容默认不做；不要把这些重新纳入当前路线图。
- BCD/boot repair 应先由 `win-kit` recipe 调用系统工具，不在 `win-utils` 首期重写 BCD 解析器。

### `fs` / `text` / `crypto`

当前已有：

- 文件/目录 copy、move、delete、mkdir、scandir、stat、link、raw、ACL 基础。
- `fs.read(path, opts)` / `fs.write(path, data, opts)` 基础文本/二进制读写。
- 标准 Base64。
- CRC32、MD5、SHA1、SHA256、SHA384、SHA512。
- 字符串和文件级编码转换。

- `fs.read/write` 已补 encoding、offset/length、atomic。
- `win-utils.ini` 已补 INI parse/encode/load/save。
- `win-utils.text` 已补 BOM 检测和 UTF-8/UTF-16LE/UTF-16BE 自动识别。

仍需补齐：

- PECMD 变异 Base64 账号密码算法是否保留，需要真实样本或用途再决策。
- PECMD 源格式细节仍需样本核验。

### `sys`

当前已有：

- `service`、`driver`、`power`、`desktop`、`display`、`shortcut`、`hotkey`、`info`、`shell`、`io`、`path`、`env`、`pagefile`、`dism`、`inf`、`dev_info`、`font`、`user`、`dev_ctrl`。
- 已覆盖很多 PECMD 的 `SERV`、`LINK`、`FONT`、`HOTK`、`WALL`、`SHEL`、`DEVI` 基础场景。

已补齐/对齐：

- `sys.time`：Lua 时间查询、Win32 本地/UTC 时间读写、时区、NTP 同步。
- `sys.autorun`：HKCU/HKLM Run/RunOnce list/set/delete。
- `sys.recycle`：移动到回收站、清空回收站、查询回收站信息。
- `sys/user.lua`、`sys/dev_ctrl.lua` 内联 FFI 已迁入 `lua-ffi-bindings`。

仍需补齐：

- 上述系统能力需要 Windows/WinPE 实机核验权限、服务和 Shell32 依赖。

### `input` / `window`

当前已有：

- 键盘、鼠标输入。
- NumLock 等 key state/toggle 基础。
- 窗口枚举、按标题/类名/PID 查找、等待、显示/隐藏、激活、关闭、移动、缩放。

仍需补齐：

- Windows/PE 实机核验 `SendInput`、`keybd_event`、`mouse_event` 在目标桌面和焦点下的行为。
- `input.lua`、`window.lua` 仍有内联 FFI，应在 UI/交互阶段迁入 `lua-ffi-bindings`。

已补齐：

- `win-utils.vk` 已提供独立虚拟键常量表和 normalize helper。

## 明显薄弱的模块

### `net`

当前只有：

- `adapter`。
- `dns`。
- `icmp`。
- `stat`。

已补齐/对齐：

- `adapter.list()` 已补连接名、适配器名、索引、MAC、MTU、类型、DNS、网关、IPv4 前缀、DHCP 推断。
- `adapter.set_ipv4(adapter, opts)` 覆盖 DHCP/静态 IP/网关/掩码。
- `dns.set_servers(adapter, servers)`。
- `adapter.enable/disable(adapter)`。
- `ntp.sync(server, opts)` 和 `sys.time.sync_ntp`。

仍需补齐：

- Windows/WinPE 实机核验 `netsh` / `w32tm` 可用性和适配器定位。

`SOCK` 完整对象系统默认不做。现代通信能力如果需要，应按用途拆分到：

- `win-utils.net.tcp` / `win-utils.net.udp`。
- `win-utils.net.http`。
- `win-utils.process.exec/popen` 的管道模型。
- 未来真实需要时的 `win-utils.ipc.*`。

### `ui`

当前仍不计划把复杂 UI 放进 `win-utils.ui`。现代交互层已转到 `peshell_minimal`：

- `peshell_minimal` 已有 cimgui loader、`imgui-probe`、backend-neutral `ui.runtime`、headless backend。
- `peshell_minimal` 已有 Win32+D3D11 Lua backend skeleton 和 `_G.pesh_native.ui` native host contract。
- `peshell_minimal/src/main.cpp` 已实现 Win32 window、D3D11 swap chain/device/context、frame begin/end、message polling 和 destroy hooks。
- `imgui-native-smoke` 已串起 native host、runtime、message box 和 file picker draw 层。
- `message_box` 和 `file_picker` 已有 view model + ImGui draw，并有 Linux 离线 stub 测试。
- GUI 复杂度基准已收敛到 CGI 类系统部署工具：镜像选择、目标分区列表、部署选项、进度、日志和确认/错误弹窗。AHK v2-like Lua API + ImGui backend 被视为足够覆盖 PECMD GUI 替代目标。

仍需补齐：

- Windows/MSVC 编译 `peshell_minimal`，并在 `cimgui.dll` 到位后运行 `imgui-native-smoke` 做真实渲染核验。
- cimgui DLL 构建/打包路径。
- Win32+D3D11 swap-chain resize、device lost、窗口关闭细节。
- AHK v2-like `ui.gui` 骨架和 CGI 类工具优先控件：ListView/Table、Progress、LogView、PathPicker、DiskList、ConfirmDialog。
- `screenshot.capture(opts)`。

复杂 UI、旧 WinCMD 控件 DSL、ImGui 集成都不应进入 `win-utils`，应放到 `peshell_minimal` 或后续 Shell 阶段。

### Shell32 / COM 依赖

极简 WinPE 可能缺失或裁剪 Shell 子系统。`sys.shell`、shortcut、dialog、recycle 等依赖 Shell32/COM 的能力应提供可用性检测和清晰错误。基础 copy/move/delete 应优先保留 Kernel32/NtAPI 路径，不能因为 Shell32 不可用而完全失效。

## FFI 边界问题

当前仍有内联 `ffi.cdef` 的重点文件：

- `/home/daiaji/repo/pecmd_compat/win-utils/input.lua`
- `/home/daiaji/repo/pecmd_compat/win-utils/window.lua`

已迁移到 `lua-ffi-bindings`：

- `crypto.lua`
- `sys/user.lua`
- `sys/dev_ctrl.lua`
- `reg/init.lua`
- `fs/acl.lua`
- `process/init.lua`
- `process/popen.lua`

目标状态：

- `win-utils` 不新增内联 `ffi.cdef`。
- 缺失 Windows SDK 声明先补到 `lua-ffi-bindings`。
- `win-utils` 只消费集中 binding，并提供稳定 Lua API。

## 下一步优先级

建议按以下顺序推进：

1. 在 Windows/MSVC 环境编译 `peshell_minimal`，打包 `cimgui.dll`，运行 `imgui-native-smoke`。
2. 对 `reg.with_hive` / `HIVE -super`、input/window、disk destructive path 做 Windows/PE 实机核验。
3. 补 Win32+D3D11 resize/device-lost 处理，以及 AHK v2-like `ui.gui` 骨架和 CGI 类工具优先控件。
4. 继续清理剩余 `win-utils/input.lua`、`win-utils/window.lua` 内联 `ffi.cdef`。
5. BCD/boot repair 先落到 `win-kit` recipe，Shell32/COM 依赖补可用性探测。
6. 建立测试分层：纯 Lua/离线、Windows CI、管理员权限、WinPE 实机、真实磁盘/USB destructive。

## 当前阶段结论

`win-utils` 已经可以作为 WinPE 自动化重构的主底座继续推进；当前不需要重写方向，也不需要引入 PECMD 语法兼容层。

最重要的工作是收敛：FFI 分层、安全默认、统一返回值、缺失 API 和实机验证。
