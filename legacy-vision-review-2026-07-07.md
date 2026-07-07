# 旧版本愿景复核

日期：2026-07-07

本文档记录对旧版 `win-utils`、`win-kit`、`peshell_minimal`、`proc_utils` 相关愿景材料的补充复核。目标是识别当前 `integrated-vision-plan.md`、`matrix.md`、`missing-alignment.md` 和 `win-utils-status-2026-07-07.md` 是否遗漏了值得保留的方向。

结论：大多数旧愿景已被当前方案吸收或明确降级；仍有少量候选项应进入“后续决策/实机核验”清单，但不改变当前主线。

## 复核材料

重点阅读了以下历史材料：

- `Win-Utils_ Features Lost`
- `Streamline Win-Utils For Modern Windows`
- `Win-Utils Abstraction Leakage Solution`
- `Extending Win-Utils for PECMD`
- `Integrate ProcUtils Into WinUtils`
- `Win-Utils_Win-Kit PECMD Analysis`
- `Win-Utils Missing Dependencies`
- ``peshell_minimal` LuaJIT 评估`
- `peshell_minimal 模块化参数化已经完成`
- `Peshell Minimal FFI Compliance Review`

## 已吸收的旧愿景

这些内容已经在当前方案中体现，不需要新增路线图：

- 仅支持 Windows 10 Enterprise LTSC 2019+ / WinPE，放弃 NT5、BartPE 和旧系统兼容。
- `win-utils` 是底层 Windows/NT 能力库，`win-kit` 是 Lua 封装、策略和 recipes 层。
- 旧 PECMD 语法不兼容，Lua 作为主脚本语言。
- `peshell_minimal` 只作为最终 Shell/Host 候选，不再承载底层 Windows API。
- `proc_utils` 是历史来源，普通进程能力迁入 `win-utils.process`，不继续作为依赖。
- WIM、VHD、disk、driver、display、Hive、input/window、service、shortcut、font、wallpaper 等核心能力已经被矩阵追踪。
- `SOCK` 完整对象系统不复刻；未来通信能力按 `net/process/ipc` 拆分。
- FFI 定义集中到 `lua-ffi-bindings`，`win-utils` 不再新增内联 `ffi.cdef`。
- `peshell_minimal` 的 Host + LuaJIT + event loop + thread pool + UI glue 方向保留为后续 Shell 层愿景。
- `LOGO` 只是 UX，不是 PE 初始化必要能力。
- 推荐最小 PE 启动链路是 `wpeinit -> init_pe -> shell supervise`，不是恢复 `INIT/SHEL/LOGO` 旧命令。

## 值得补充的候选遗漏

这些旧愿景材料中出现过，但当前文档还不够显式。它们应进入后续决策或核验清单，不代表立即实现。

### BitLocker 状态检测

旧材料指出：Win10+ PE 中对磁盘做布局、格式化、挂载、读写前，检测 BitLocker 状态很重要。

当前状态：

- `win-utils.disk.bitlocker` 模块已经存在，但完成度和路线图描述不足。

建议：

- 将 BitLocker 状态检测纳入 `disk.safety` 的只读前置检查。
- 优先目标是“识别并阻止危险操作”，不是完整 BitLocker 管理器。
- 可选后端包括 FVEAPI、WMI 或分区头部特征检测；具体实现需按 WinPE 可用性决定。

### BCD / 引导修复

旧材料指出：装机维护离不开 BCD/boot repair。

当前状态：

- 当前方案有 ESP、VHD、分区和启动盘安全讨论，但没有明确 `bcdboot` / BCD 修复定位。

建议：

- 不重写 BCD 解析器。
- 短期用 `process.exec` 调用 `bcdboot.exe` / `bootrec.exe` / `bcdedit.exe`，由 `win-kit.tasks.boot_repair` 封装流程。
- 若后续确实需要底层能力，再评估 BCD Hive 读写或专用 binding。

### Shell32 依赖回退

旧材料提醒：极简 WinPE 可能缺失或裁剪 `shell32` 子系统，`SHFileOperationW`、文件对话框、ShellExecute、快捷方式等能力可能不可用。

当前状态：

- 当前方案已将复杂 UI 后置，但没有显式要求 Shell32 依赖可探测和降级。

建议：

- `win-utils.fs` 的基础 copy/move/delete 应优先有 Kernel32/NtAPI 路径。
- `sys.shell`、shortcut、dialog、recycle 等依赖 Shell32/COM 的 API 应提供可用性检测和清晰错误。
- 不为极简 PE 做复杂 polyfill，但失败路径必须明确。

### Windows 10 LTSC 2019+ 精简基线

旧材料多次建议将基线明确为 Windows 10 1809 / Server 2019 或更高，以删除旧回退逻辑。当前产品兼容性目标进一步收敛为 Windows 10 Enterprise LTSC 2019+。

当前状态：

- 当前方案已从泛泛的 Win10+ 收敛为 LTSC 2019+，最低内部版本号应明确写入工程文档。

建议：

- 后续实现以 Windows 10 Enterprise LTSC 2019+ 作为工程基线，即 Windows 10 1809 / build 10.0.17763。
- Windows 10 Enterprise LTSC 2021 对应 Windows 10 21H2 / build 10.0.19044，可作为更高验证目标。
- 产品描述可以简写为 LTSC 2019+ / WinPE，但代码层不为 Win7/8/NT5 增加 fallback。
- 对依赖新特性的 API，例如 POSIX delete、现代 WIM/WOF/WCIFS、现代 process handle snapshot，应明确最低版本假设。

### 测试环境分级

旧材料强调 GitHub Actions / 普通 Windows / WinPE / 真实硬件能力差异。

当前状态：

- 当前方案要求最小测试或 dry-run，但没有明确测试分层。

建议：

- 测试分为：纯 Lua/离线、Windows CI、管理员权限、WinPE 实机、真实磁盘/USB destructive。
- 每个高风险 API 应声明最低可验证层级。
- CI 中应跳过 GUI、真实磁盘、USB hub reset、驱动安装等不可稳定验证项。

### GUID 常量集中

旧材料建议将分散 GUID 数据集中到 `lua-ffi-bindings/Windows/const/guids.lua`。

当前状态：

- 当前方案强调 FFI 定义集中，但没有明确 GUID 常量集中。

建议：

- 这不是 P0，但适合作为 FFI 收敛的一部分。
- 适合集中：设备接口 GUID、Virtual Storage vendor GUID、EFI Global Variable GUID、常见电源/固件 GUID。

### LuaJIT/Host 细节约束

旧 `peshell_minimal` 评估指出一些 Host 层约束：

- LuaJIT C API 应使用 Lua 5.1 兼容形式，例如 `lua_resume` 参数。
- C++ 与 LuaJIT FFI `cdata` 交互要显式检查 `LUA_TCDATA`。
- 构建 LuaJIT 应独立构建，不把 LuaJIT 源码直接混进主工程。
- FFI 调用性能上应缓存 DLL namespace，不要误以为缓存单个 C 函数或 wrapper 一定更快。
- 协程池策略要明确：要么真正接入 scheduler，要么删除死代码。

当前状态：

- 当前 integrated plan 已保留 Host + LuaJIT + event loop + thread pool 的方向，但没有列出这些具体约束。

建议：

- 这些规则只影响最终 Shell/Host 阶段，不影响当前 `win-utils` 主线。
- 可在未来 `peshell_minimal` 收敛时作为 Host 验收清单。

## 仍然不纳入路线图的旧愿景

这些旧愿景或历史提法不应重新拉回当前范围：

- `pesh_core.dll` 作为底层核心库。
- `proc_utils` 继续作为运行依赖。
- System/UAC/服务到桌面/跨 session 启动用户桌面进程作为首期能力。
- VDS 作为唯一或主磁盘后端。
- ImDisk/RAMD 旧命令兼容。
- UDM/U+ / OnlyApp / SetOnlyApp / Server 旧生态兼容。
- PECMD `SOCK` 对象系统。
- 完整声明式状态引擎作为当前阶段要求。
- 完整 ImGui UI 作为当前阶段要求。
- mailslot、shared memory、event/mutex/semaphore 兼容层。

## 对当前文档的影响

应补充到当前文档中的只有这些定位：

- `win-utils-status-2026-07-07.md`：增加 BitLocker、BCD/boot repair、Shell32 fallback、测试分级、GUID 常量集中为后续候选。
- `integrated-vision-plan.md`：在 P1/P2 或 Phase 4 中补充上述候选，但明确不改变当前主线。
- `README.md`：加入本文档入口。

## 当前结论

旧愿景没有推翻当前方案。当前路线仍应保持：

1. `win-utils` 收敛 FFI、安全、返回值和缺失底层 API。
2. `win-kit` 承接 PE recipes 和策略。
3. `peshell_minimal` 或后续 Shell 承接 Host/UI/profile/日志/进度/任务调度。
4. 旧 PECMD 语法、旧对象系统和历史生态兼容不进入当前实现。
