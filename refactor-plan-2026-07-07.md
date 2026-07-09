# Windows PE Lua Automation Refactor Plan - 2026-07-07

## 1. Goal

Build the current fragments into a layered Windows 10 LTSC 2019+ / WinPE Lua automation project.

This project is not a PECMD syntax compatibility layer. PECMD is only a capability baseline. The runtime should be Lua-first, testable, and split into clear projects with narrow ownership.

## 2. Layer Model

### pecmd_compat

Role: planning, capability matrix, audit notes, integration tracking.

It should contain:

- PECMD capability matrix.
- Architecture decisions.
- Migration and validation plans.
- CI/debug helper scripts for the aggregate workspace.

It should not contain runtime policy code except as temporary audit material.

### lua-ffi-bindings

Role: Windows SDK and C ABI declarations.

It should contain:

- `ffi.cdef` declarations.
- Constants, structs, enums, and function declarations.
- Thin library loaders for DLL namespaces.

It should not contain:

- PE automation policy.
- Windows feature recipes.
- User-facing command behavior.

### win-utils

Role: bottom-level Windows/NT Lua API library.

It should contain:

- Stable public APIs for process, fs, registry, disk, sys, net, input, window, shortcut, shell, and related capabilities.
- Defensive wrappers around Windows APIs.
- Structured returns and error propagation.
- Unit and Windows integration tests.

It should not contain:

- PE boot policy.
- Driver-install selection policy.
- User profile orchestration.
- Shell UI behavior.

### win-kit

Role: PE automation recipes and policy layer.

It should contain:

- High-level tasks that combine `win-utils` APIs.
- Dry-run planning for destructive or machine-changing actions.
- Structured results, warnings, and logs.
- PE-oriented policies: driver install, drive-letter assignment, pagefile, display, boot repair, cleanup.

It should not contain:

- Inline `ffi.cdef` declarations.
- Direct DLL loading.
- Raw IOCTL wrappers unless they are temporary shims marked for migration.
- Shell/UI code.
- Require-time side effects.

### peshell_minimal

Role: Host, Shell, UI, profile runner, and task presentation layer.

It should contain:

- C++ LuaJIT host and native UI lifetime management.
- Lua plugin system.
- Async/event loop/thread pool integration.
- ImGui or backend-neutral UI runtime.
- Profile loading.
- Task execution, progress display, cancellation, confirmation, and logs.

It should not contain:

- Generic Windows API wrappers that belong in `win-utils`.
- PE policy recipes that belong in `win-kit`.
- Duplicated driver/disk/pagefile/display automation logic.

## 3. Current Findings

### win-utils

`win-utils` is the strongest base layer. It already has a broad API surface and a Windows CI draft. The recent FFI cleanup moved User32 declarations out of `input.lua` and `window.lua` into `lua-ffi-bindings`.

Remaining risks:

- Many features need real Windows CI coverage.
- Some features require admin or WinPE/manual validation.
- Nested vendor binding changes must be committed carefully.

### win-kit

`win-kit` contains useful PE recipe prototypes but is not yet a clean project layer.

Problems found:

- `smart_devi.lua` and `smart_offline_devi.lua` execute real behavior at require time.
- `hardware.lua` contains inline FFI declarations.
- `partition_tools.lua` contains low-level disk/GPT/IOCTL logic that should mostly move to `win-utils`.
- `poweroff.lua` directly loads kernel32 bindings and flushes volumes.
- `pecmd_logic.lua` has stale naming and mixes process helpers with registry hive policy.
- Several modules print directly instead of returning structured results.
- Most actions lack dry-run planning.
- Several destructive or machine-changing actions lack explicit confirmation boundaries.

### peshell_minimal

`peshell_minimal` mostly matches the intended host/UI role.

Useful pieces:

- Native UI host contract in docs.
- C++ Win32/D3D11 lifetime management.
- Lua UI runtime and ImGui plugin smoke tests.
- Async and plugin scaffolding.

Risks:

- `scripts/init.lua` still owns PE boot sequence decisions.
- Shell profile execution should eventually call `win-kit.tasks.*` instead of embedding recipe policy.
- CI is not yet as mature as `win-utils` needs to become.

## 4. Target Layout

### win-kit

```text
win-kit/
  init.lua
  log.lua
  tasks/
    init.lua
    init_pe.lua
    install_drivers.lua
    assign_drive_letters.lua
    setup_pagefile.lua
    setup_display.lua
    setup_network.lua
    shutdown_cleanup.lua
    boot_repair.lua
  examples/
    run_fix.lua
  tests/
    run_offline.lua
    tasks_spec.lua
```

Temporary legacy modules may remain during migration, but they must not execute behavior at require time.

### peshell_minimal

```text
peshell_minimal/
  src/
  scripts/
    init.lua
    core/
    lib/
      ui/
      tasks/
    plugins/
    profiles/
  docs/
  tests/
```

`scripts/init.lua` should become a thin profile runner. Real PE tasks should come from `win-kit`.

## 5. Public API Shape

Every `win-kit` task should follow this shape:

```lua
local task = require 'win-kit.tasks.install_drivers'

local result, err = task.run({
    roots = { [[X:\Drivers]] },
    mode = 'smart',
    dry_run = true,
    confirm = false,
    logger = logger,
})
```

Success result:

```lua
{
    ok = true,
    task = 'install_drivers',
    dry_run = true,
    steps = {},
    warnings = {},
    changed = false,
}
```

Failure result:

```lua
nil, {
    task = 'install_drivers',
    code = 'driver_source_missing',
    message = 'Driver source directory not found',
    details = {},
}
```

## 6. Migration Phases

### Phase 0 - Stabilize Repositories

Objective: make the current work commit-ready and observable.

Tasks:

- Commit `lua-ffi-bindings` declaration updates first.
- Commit `win-utils` code, tests, vendor pointer, and Windows CI separately.
- Commit `peshell_minimal` Host/UI spike separately.
- Keep `pecmd_compat` commits documentation-only unless explicitly moving workspace files.
- Avoid `git add .` in nested repos.

Validation:

- `win-utils`: offline tests on Linux, Windows CI on GitHub Actions.
- `peshell_minimal`: Lua smoke tests and Windows build smoke.
- `pecmd_compat`: docs/scripts checks.

### Phase 1 - Remove Require-Time Side Effects

Objective: every `win-kit` module is safe to require.

Tasks:

- Convert `smart_devi.lua` to export `install()` / `plan()` functions.
- Convert `smart_offline_devi.lua` to export `inject()` / `plan()` functions.
- Move `run_fix.lua` to examples or keep it clearly marked as a script.
- Add a `win-kit.tasks` entry module.

Validation:

- Loading all `win-kit` modules must not enumerate devices, write registry, install drivers, inject offline images, kill processes, or change disk state.
- Add an offline load test.

### Phase 2 - Establish Task Modules

Objective: expose recipes through stable task names.

Tasks:

- Add `tasks/install_drivers.lua` wrapping `smart_devi` and offline injection behavior.
- Add `tasks/setup_pagefile.lua` wrapping `smart_pagefile`.
- Add `tasks/setup_display.lua` wrapping `auto_display`.
- Add `tasks/assign_drive_letters.lua` wrapping `automount`.
- Add `tasks/shutdown_cleanup.lua` wrapping cleaner/poweroff/unlocker behavior.
- Add `tasks/init_pe.lua` for environment, OEM, shell folders, icon refresh.

Validation:

- Each task supports `dry_run = true`.
- Offline tests assert planned steps without touching the machine.

### Phase 3 - Push Low-Level Leaks Downward

Objective: keep `win-kit` policy-only.

Tasks:

- Move `hardware.lua` FFI into `lua-ffi-bindings` + `win-utils.sys.power/info`.
- Move raw volume flush/dismount calls from `poweroff.lua` into `win-utils.disk.volume`.
- Move reusable GPT/partition helpers from `partition_tools.lua` into `win-utils.disk.layout` or `win-utils.disk.volume`.
- Replace `pecmd_logic.exec_capture` with `win-utils.process.capture` or equivalent.

Validation:

- `rg "ffi\.cdef|ffi\.load|ffi\.req" win-kit` should return no production matches.
- `win-kit` tests run with stubbed `win-utils` where possible.

### Phase 4 - Convert peshell_minimal to Profile Runner

Objective: Shell presents and runs tasks; it does not own PE policy.

Tasks:

- Define profile format under `peshell_minimal/scripts/profiles`.
- Make `scripts/init.lua` load a profile and dispatch `win-kit.tasks`.
- Add progress, cancellation, confirmation, and log event adapters.
- Keep native UI and task presentation in `peshell_minimal`.

Validation:

- A dry-run profile can execute without Windows side effects.
- UI smoke can render planned steps.

### Phase 5 - WinPE Validation Matrix

Objective: prove behavior in the target environment.

Test tiers:

- Offline Lua unit tests.
- Windows GitHub Actions tests.
- Admin Windows integration tests.
- WinPE VM tests.
- Real hardware destructive tests.

Required WinPE scenarios:

- Boot and initialize shell.
- Enumerate hardware.
- Install matching drivers from external media.
- Assign drive letters without touching protected volumes.
- Configure pagefile safely.
- Set display mode.
- Run cleanup and shutdown.

## 7. Immediate Implementation Order

1. Add this refactor plan.
2. Add `win-kit/tasks/init.lua` and `win-kit/tasks/install_drivers.lua` as the first stable task entry.
3. Make `smart_devi.lua` safe to require.
4. Make `smart_offline_devi.lua` safe to require.
5. Update `win-kit/init.lua` to expose `tasks`.
6. Add a minimal offline load test for `win-kit`.
7. Run `luajit` load checks on Linux.

## 8. Non-Goals

- Do not implement old PECMD syntax compatibility.
- Do not add a DSL before the Lua profile/task API stabilizes.
- Do not move all modules at once.
- Do not remove legacy modules until call sites are known.
- Do not add broad backward-compatibility shims without a real consumer.

## 9. Definition of Done

The refactor is done when:

- `win-kit` can be required without side effects.
- `win-kit.tasks.*` provides the canonical recipe API.
- Production `win-kit` modules have no inline FFI declarations or direct DLL loading.
- `peshell_minimal` runs profiles and displays task progress instead of embedding policy.
- `win-utils` owns all reusable Windows API wrappers.
- CI covers offline Lua checks and Windows integration smoke tests.
- WinPE validation has documented pass/fail results for the required scenarios.

## 10. Implementation Status - 2026-07-07

Completed in the first refactor pass:

- Added `win-kit.tasks` as the stable recipe entry point.
- Added task wrappers for driver install, drive-letter assignment, pagefile setup, display setup, shutdown cleanup, and PE initialization.
- Made `smart_devi.lua` and `smart_offline_devi.lua` safe to require.
- Moved `run_fix.lua` demo behavior to `win-kit/examples/run_fix.lua`; the original path is now a safe compatibility stub.
- Added `win-kit/tests/run_offline.lua`.
- Added dry-run plans and structured returns to the major `win-kit` recipes.
- Removed production `win-kit` direct FFI usage.
- Moved power status support to `lua-ffi-bindings` + `win-utils.sys.info`.
- Moved volume flush/dismount support to `win-utils.disk.volume`.
- Moved reusable GPT hidden/read-only attribute manipulation to `win-utils.disk.layout`.
- Renamed the misleading `pecmd_logic` implementation to `repair.lua`; `pecmd_logic.lua` remains as a compatibility shim.
- Changed `win-kit.registry.read()` to use `open_existing_key()` so reads do not create missing keys.
- Added a first-pass `peshell_minimal` profile runner at `scripts/lib/tasks/runner.lua`.
- Added `peshell_minimal/scripts/profiles/default.lua` as a dry-run WinPE profile.
- Changed `peshell_minimal/scripts/init.lua` to dispatch profile tasks through `win-kit.tasks` instead of embedding PE policy directly.
- Added `peshell_minimal/scripts/test_profile_runner.lua` and a Lua smoke CI workflow.

Current local validation:

- `luajit win-kit/tests/run_offline.lua` passes with 20 modules loaded.
- All root-level `win-kit` modules can be required offline without side effects.
- `rg "ffi\\.(cdef|load|req)|local ffi = require" win-kit -g "*.lua"` returns no production matches.
- `luajit tests/run_offline.lua` passes in `win-utils`.
- `luajit scripts/test_profile_runner.lua` passes in `peshell_minimal`.

Still pending:

- ~~Expand `peshell_minimal` profile runner UI/progress/cancel adapters beyond the first dry-run dispatcher.~~ **Done 2026-07-08:** `runner.lua` now supports `on_progress(name, i, total)`, `cancelled` (token or function), `on_confirm(name, plan)`, `on_task_complete(name, result, err)`.
- ~~Add or wire CI for `win-kit` offline checks.~~ **Done 2026-07-08:** `pecmd_compat/.github/workflows/ci.yml` runs `win-kit/tests/run_offline.lua` + `tasks_spec.lua`.
- Run Windows CI for `win-utils` and task wrappers. **Partial:** `win-utils` Windows CI green (56 tests). `win-kit` task wrappers have no Windows CI (peshell smoke uses stubs).
- Run Admin Windows and WinPE validation for destructive or hardware-specific behavior.
- Decide whether `win-kit` becomes a standalone repository or remains a service under `pecmd_compat`.

### Updates - 2026-07-08

- Added `win-kit/tasks/setup_network.lua` (adapter enable/disable, DHCP/static IP, DNS, NTP sync).
- Added `win-kit/tasks/boot_repair.lua` (BCD device/osdevice, bootsect, timeout, default entry, offline hive repair).
- All 8 planned task modules now exist and are registered in `tasks/init.lua`.
- Added `win-kit/tests/tasks_spec.lua` — asserts canonical result schema (`ok`, `task`, `dry_run`, `changed`, `steps`, `warnings`) and `run(dry_run=true) == plan()` for all 8 tasks. 18 assertions, all passing.
- `run_offline.lua` updated to 22 modules (added `setup_network`, `boot_repair`).
- `peshell_minimal/scripts/lib/tasks/runner.lua` upgraded with progress/cancel/confirmation adapters.
- `peshell_minimal/scripts/test_profile_runner.lua` expanded to 6 tests covering progress, cancel, confirm-skip, task-complete.
- `peshell_minimal/scripts/profiles/default.lua` updated with `setup_network` in order (disabled by default).
- `win-utils` CI: all green (56 tests, 0 failures, 2 CI-environment WARNs).
- `peshell_minimal` CI: all green (Windows build + smoke + Ubuntu Lua smoke).
- `.luarc.json` added at workspace root for LuaJIT LSP support.

### Updates - 2026-07-09

Local WinPE validation is now complete for the KuerPE + iPXE/wimboot path.

Completed:

- Switched practical WinPE validation from the fragile ISO/UUP path to a known-booting KuerPE WIM.
- Confirmed the KuerPE image starts through `SYSTEM\Setup\CmdLine`; the active boot chain is now `cmd.exe /c X:\Windows\System32\pe_ci_run.cmd`.
- Removed `winpeshl.ini`, `winpeshl.cmd`, and `startnet.cmd` from the active wimboot injection path. The old ISO builder may still contain `winpeshl` logic, but it is not used by the KuerPE/wimboot path.
- Reworked `scripts/build_winpe_wimboot.sh` to accept a direct WIM input, reuse `WORK_WIM`, inject `peshell.exe`, VC runtime DLLs, Lua runtime files, `win-kit`, `win-utils`, `tasks/runner.lua`, `pe_ci_run.cmd`, and `serial_cmd.exe`.
- Added `scripts/pe_ci_run.cmd` as the WinPE launcher. It finds a tagged FAT result drive, writes `pe_ci_result.log`, supports normal execution, serial interactive mode, and serial bridge mode.
- Added `tools/serial_cmd/serial_cmd.cpp`, a standalone Win32 serial automation bridge. It polls for `COM1`, supports command execution, file upload/download, chunked upload, `--autorun`, `reboot`, and returns structured markers over serial.
- Fixed the WinPE profile root cause: `os.exit(...)` in the LuaJIT host caused `0xC0000409` / `3221226505` in WinPE. `scripts/winpe_test_profile.lua` now prints `WINPE_CI_EXIT: <code>` and returns the exit code instead.
- Kept real WinPE execution conservative: real `init_pe` only; drive-letter assignment and display changes are validated through dry-run plans to avoid disrupting the result drive or QEMU display.
- Fixed local QEMU launch robustness by rewriting `boot.ipxe` with the selected HTTP port on each run and reading `wimboot.index` with a fallback to index 1.

Validated locally:

- Normal automatic path: `Setup\CmdLine -> pe_ci_run.cmd -> peshell.exe run winpe_test_profile.lua` completed with `WINPE_CI_SUMMARY: 12 0 0` and `WINPE_CI_EXIT: 0`.
- Serial bridge path: `serial_cmd.exe --autorun "X:\Windows\System32\peshell.exe run X:\Windows\System32\winpe_test_profile.lua"` returned the full profile log and `<<<AUTORUN_END rc=0>>>`.
- Serial interactive mode supports live command execution and file transfer into the running PE image.
- COM1 availability is delayed in this PE image; `serial_cmd.exe` handles this by polling until the device exists.
- Latest static checks passed: `bash -n` for the shell scripts, LuaJIT bytecode compilation for `winpe_test_profile.lua`, MinGW cross-compilation for `serial_cmd.exe`, `git diff --check`, and a targeted search confirming no `os.exit` remains in `scripts/*.lua`.
- GitNexus change detection reported low risk for indexed tracked changes: 2 changed files, 0 changed symbols, 0 affected processes.

Current status:

- Core refactor goals are complete: `win-kit` is the PE policy/task layer, `win-utils` owns reusable Windows APIs, `lua-ffi-bindings` owns FFI declarations, and `peshell_minimal` dispatches profiles through the task runner instead of embedding PE policy.
- Local WinPE validation is complete for non-destructive automation and diagnostic coverage.
- WinPE E2E validation is intentionally local-only. Cloud CI no longer runs PE/QEMU tests because reliable KVM/nested virtualization requires paid or self-hosted runners; AI-agent development and debugging use the local KuerPE/wimboot harness instead.
- The worktree still contains uncommitted local tooling changes and unrelated dirty/untracked files. The expected local tooling set is `scripts/build_winpe_wimboot.sh`, `scripts/winpe_test_profile.lua`, `scripts/local_qemu_test.sh`, `scripts/pe_ci_run.cmd`, `tools/serial_cmd/serial_cmd.cpp`, and optionally the built `tools/serial_cmd/serial_cmd.exe`.

Still pending or out of scope for this pass:

- Run destructive or hardware-specific scenarios on real hardware.
- Decide whether to commit the built `serial_cmd.exe` binary or build it as part of a local/CI preparation step.
