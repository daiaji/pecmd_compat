# 005 附录与元机制

文档范围：`PECMD帮助文档.txt` 第 3332-3673 行。

本块覆盖 Windows 按键键值表、分区类型表、磁盘媒体类型表、脚本转命令行、注释规则、初始化/内置脚本、图标编号、插件系统、定制/拖放、PE 制作资料、许可与声明中对重构有影响的信息。

## Vkeylist / Windows 按键键值表

功能点：
- 文档提供虚拟键 Virtual Key 对照表，供 `HOTK`、`HKEY`、`SEND`、`WAIT` 等命令使用。
- 覆盖鼠标键、控制键、字母数字、功能键、小键盘、左右 Shift/Ctrl/Alt、Win/App 键、IME 相关键、OEM 标点键。
- `VK_MENU` 等同 Alt 键。
- 标点键提供键面、VK 名称、十六进制/十进制值、替代串。
- 支持 `VK_` 名称、十六进制、十进制、替代串作为按键输入。

Lua 重构提示：
- 应整理成机器可读 `vkeys` 表，供热键注册、按键模拟、按键等待共用。

## fenqutype / 分区类型操作数

功能点：
- 文档提供 MBR 分区类型 0x00-0xFF 的名称对照。
- `0x00` 表示空/彻底隐藏。
- 包含 FAT、NTFS、隐藏 FAT/NTFS、扩展分区、Linux、BSD、Solaris、EFI、Dell、SpeedStor 等常见与历史类型。
- 文档补充分区类型：`0x15` 隐藏扩展分区、`0x1f` 隐藏 Win95 扩展分区 LBA、`0x95` 隐藏 Linux 扩展分区。
- 文档说明对 PECMD `SHOW` 等加载而言，只要不是 0 和扩展分区，数值主要作为给人和自动化软件的提示。

Lua 重构提示：
- 应整理为 `partition.mbr_type_names`，供 `PART`、`SHOW`、报告输出使用。

## GPT 分区类型 GUID

功能点：
- 文档提供 GPT 分区类型 GUID 对照。
- 包含 Microsoft Basic Data、MBR partition scheme、EFI system、BIOS boot、Microsoft reserved、LDM metadata/data、Microsoft recovery。
- 包含 Linux data/RAID/swap/LVM/reserved。
- 包含 FreeBSD boot/data/swap/UFS/vinum/ZFS。
- 包含 Mac OS X HFS+、Apple UFS、ZFS、RAID、boot、label、Apple TV recovery、Core Storage、APFS。
- 包含 Solaris boot/root/swap/backup/usr/var/home/EFI alternate sector/reserved。
- 包含 NetBSD swap/FFS/LFS/RAID/concatenated/encrypted。

Lua 重构提示：
- 应整理为 `partition.gpt_type_names`，供 `PART` 和磁盘报告使用。

## disktype / 磁盘媒体类型

功能点：
- 文档提供 Windows 磁盘媒体类型枚举到十六进制/十进制值的对照。
- 包含 Unknown、各类软盘、RemovableMedia、FixedMedia 等。
- 文档说明若要获取隐藏分区原本文件系统和剩余空间，可先用 `SUBJ` 临时加载，再用 `FIND` 查询总空间、`IFEX` 查询剩余空间。

Lua 重构提示：
- 应整理为 `disk.media_type_names`，供 `FORM`、`PART list disk`、报告输出使用。

## 脚本转化为一个命令行

功能点：
- 支持把多行脚本转换为单条命令行。
- 转换步骤：先去掉所有注释。
- 把所有“空格;;空格”替换为“空格;;;空格”，更多分号均加一个。
- 把所有换行替换为“空格;;空格”。
- 在前面增加 `/L` 开关，表示多行命令行。
- `/L` 不传入程序当参数。
- `/L` 时第一行作程序参数，命令从第二行开始。
- `/l` 时第一行兼作命令。
- 在线命令行中 Ctrl+Enter 可在内存中执行脚本。
- 点击执行区下方数字可改变命令行高度。

Lua 重构提示：
- 属于兼容 CLI 预处理能力，应作为脚本解析器输入模式之一。

## 注释规则

功能点：
- 注释符为 `;`、`` ` ``、`//`。
- 注释符必须在行首或前面有一个空字符。
- 注释符前面的空字符也算注释。
- 命令行中默认关闭注释。
- 脚本中默认开启注释。
- 行尾空字符可用 `TEAM` 保留，也可用变量如 `%SPACE%` 传入。

Lua 重构提示：
- 必须纳入兼容脚本 lexer/preprocessor。

## 初始化脚本与内置脚本

功能点：
- 初始化脚本可直接加入程序资源 `SCRIPTINIT\100\2052`。
- 程序启动时先自动执行初始化脚本，然后进入正常流程。
- 内置脚本可直接加入资源 `SCRIPT\101\2052`。
- 启动时可自动执行内置脚本并退出。
- 命令行参数作为内置脚本参数。
- 可以增加更多内置脚本。
- `LOAD #102 A B`、`LOAD #103` 可加载指定内置脚本。

Lua 重构提示：
- 如需单文件发布，可用资源打包/嵌入 Lua chunk 替代。

## ICOLIST / 图标编号

功能点：
- `#2` 表示自然编号，内部图标组号从 0 开始依次重新编号。
- `##2` 表示内部图标组号。
- `###2` 表示内部帧号。
- 省略文件名时 `#1` 和 `##1` 的含义相反。

Lua 重构提示：
- 供 `IMAG`、`ITEM`、`TIPS`、托盘/菜单图标解析复用。

## 插件系统

功能点：
- 支持脚本插件，格式包括资源 `#编号`、`WCI`、`WCS`、`WCE`、`WCZ` 及自定义格式。
- 支持可执行文件插件，格式包括 `EXE`、`COM`、`NTR`、`NTE`、`CMD`、`BAT`。
- 支持动态库插件，格式包括 `DLL`、`DLX`。
- 通过 `ENVI &&&LoadPlugin=[基本文件名]` 初始化插件系统。
- 基本文件名默认当前 PECMD 程序名。
- 基本文件名会自动扩展为全路径，并生成参考路径。
- 多次初始化只执行一次。
- 可放入启动脚本自动初始化。
- 内部脚本插件来自资源 `SCRIPT` 下编号，可以是 `CMPS` 压缩脚本。
- 内部插件列表来自资源 `INDATA\4`，格式为 `LOAD: 命令名 #编号[+偏移[+长度限制]]`。
- 内部插件列表也可以 `CMPS` 压缩。
- 内部脚本插件命令执行时把余下命令行作为脚本参数。
- 外部脚本插件文件名格式为 `参考路径.命令[+偏移[+长度限制]].后缀`。
- 外部脚本后缀包括 `WCI`、`WCS`、`WCE`、`WCZ`。
- 可执行文件插件文件名格式为 `参考路径.执行标志命令.后缀`。
- 可执行文件插件执行标志为 `=`、`!`、`@` 三种的组合。
- 可执行文件插件自动以隐藏等待方式执行。
- `NTR`、`NTE` 是 EXE 或 COM 改名。
- 动态库插件文件名格式为 `参考路径.$命令.后缀`。
- `DLX` 是 DLL 改名。
- 支持 PECMD 专门插件库 `参考路径.pecmdplugin.*.PEI`。
- PEI 文件内部含命令名表。
- 插件执行优先级为：PECMD 专门插件库、资源编号、WCI/WCS/WCE/WCZ、EXE/COM/NTR/NTE/BAT/CMD、DLL。
- 找到插件后不再继续查找。
- 插件优先于没有 `EXEC` 的外部命令和没有 `LOAD` 的 WCS 脚本文件。

Lua 重构提示：
- Lua 原生模块系统可替代大部分插件机制。
- 若要兼容旧插件发现行为，必须实现命令解析 fallback 及优先级表。
- 旧 DLL/PEI 插件 ABI 建议明确废弃，除非有真实存量需求。

## DIYSIZE / 定制与拖放

功能点：
- 可从资源中删除帮助文件以缩小占用硬盘空间，不影响执行。
- 未删除帮助文件也不占用内存。
- 脚本拖到命令行为编辑。
- 脚本拖到 HELP 区为显示并执行，支持压缩脚本。

Lua 重构提示：
- 属于旧 GUI/资源定制体验，可在现代化界面中重新设计。

## DIYPE / PE 制作关键资料

功能点：
- Win7/Win8 PE 制作时建议先加入权限管理并取得管理员所有权限。
- 示例命令使用 `takeown` 和 `icacls` 对加载到主机目录的 PE 授予 administrators 完全控制。
- 需要确保系统存在 `takeown` 和 `icacls`，没有则可从正常系统复制。
- DLL 或驱动无法安装注册成功的权限问题，很多与 FAT32 文件系统有关。
- 制作 PE 时需注意文件系统是 NTFS 还是 FAT32。

Lua 重构提示：
- 可作为 PE 构建工具的前置检查：权限、文件系统、系统工具存在性。

## 致谢

功能点：
- 文档记录 PECMD2012 参考 PECMD2.4、XCMD V2.2 及无忧论坛建议等来源。
- 对 Lua 重构没有直接功能要求，但对 clean-room/许可追踪有来源记录价值。

Lua 重构提示：
- 保留为来源说明，不进入功能兼容矩阵的实现项。

## 许可 / 许可与声明

功能点：
- PECMD2012 NonCopyRight 许可允许个人和组织免费使用、逆向工程、二进制修改。
- 修改或使用源码时强烈建议公开项目源码；商业组织可不公开源码，但必须公开开发接口及文档。
- PECMD2.4 许可更严格，使用或修改源码要求公开项目源码和文档。
- 文档明确免费版 PECMD2012 没有功能限制和标记。

Lua 重构提示：
- 若借鉴旧源码实现细节，需要单独做许可证兼容性审查。
- 若只根据官方帮助文档做 clean-room 能力对齐，风险相对低，但仍应保留来源记录。
