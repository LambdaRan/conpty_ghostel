# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Ghostel 是嵌入 Emacs 的终端模拟器，基于 libghostty-vt 驱动。本仓库是 [dakra/ghostel](https://github.com/dakra/ghostel) 的 fork，添加了 **Windows ConPTY 支持**。上游远程为 `upstream` (dakra/ghostel)，fork 远程为 `origin` (LambdaRan/conpty_ghostel)。

## 相关目录

| 路径 | 说明 |
|---|---|
| `E:\lambda\selfcode\conpty_ghostel` | ghostel 源码（本仓库） |
| `E:\lambda\selfcode\conpty_proxy` | conpty_proxy.exe 源码（独立项目） |

## 构建命令

### Windows

```bash
build.cmd                  # Release 构建
build.cmd debug            # Debug 构建
build.cmd clean            # 清理所有构建产物
```

在 MSYS2/Bash 环境下调用需禁用路径转换：

```bash
MSYS_NO_PATHCONV=1 cmd.exe /c "E:\lambda\selfcode\conpty_ghostel\build.cmd"
```

依赖：Zig 0.15.2+，Emacs 头文件从 `C:\Program Files\Emacs\` 自动检测（或设置 `EMACS_INCLUDE_DIR`）。

#### Windows 构建注意事项

- **GNU ABI**：必须使用 `-Dtarget=native-native-gnu` 以避免 MSVC libcpmt 链接冲突
- **`ZIG_GLOBAL_CACHE_DIR`**：Zig 0.15 的依赖子进程在全局缓存与项目不在同一驱动器时 panic（`Run.zig:662`），`build.cmd` 自动将其固定到项目目录下
- **`link_libcpp`**：`build.zig` 中 Windows 条件启用，simdutf/highway 需要 C++ 运行时
- **`vendor/ghostty/`**：Windows 构建通过 `build.zig.zon` 的 `.path` 依赖使用此目录（Zig 0.15 无法通过 URL 子进程正确解析依赖）。上游同步时需将 vendor/ghostty checkout 到 build.zig.zon 注释中记录的 commit

### Unix
```
make build                   # 构建 ghostel-module.so/.dylib
make test                    # 纯 Elisp 测试（不需要编译模块）
make test-native             # 需要编译模块的测试
make test-all                # 全部测试
make test-evil               # Evil-mode 集成测试
make lint                    # byte-compile + package-lint + checkdoc
make bench                   # 性能基准测试
make clean                   # 清理构建产物
```

### 运行单个测试
```bash
emacs --batch -Q -L lisp -l ert -l test/ghostel-test.el \
  --eval '(ert-run-tests-batch "ghostel-test-TESTNAME")'
```

## 架构

两层设计：**Zig 原生模块** 负责终端模拟 + **Elisp** 负责进程管理和 Emacs 集成。

### 数据流
```
Shell (bash/zsh/fish/cmd.exe)
  → PTY/ConPTY → Elisp ghostel--filter
  → GhostelTerm.ghostel--write-input (CRLF 规范化、OSC 通过 GhostelHandler 拦截、libghostty 解析)
  → gt.Terminal (网格、样式、滚动缓冲区状态)
  → Renderer (脏行跟踪)
  → ghostel--redraw (增量渲染) → Emacs 缓冲区
```

### 原生模块 (src/)

| 文件 | 说明 |
|---|---|
| `module.zig` | 入口点；注册模块级函数（version、vt-log、pty-password、conpty-resize） |
| `GhostelTerm.zig` | 终端状态管理；注册核心函数（new、write-input、set-size、redraw、encode-key 等）；CRLF 规范化 |
| `Renderer.zig` | 增量脏行渲染到 Emacs 缓冲区；单元格提取、样式/超链接应用 |
| `GhostelHandler.zig` | 自定义流处理器，拦截 OSC 4/7/9/10/11/52/133/777 并路由到 Elisp |
| `comint_filter.zig` | libghostty VT 解析器作为 comint preoutput 过滤器 |
| `style_face.zig` | 样式/face 定义 |
| `utils.zig` | parseHexColor、parseHexByte 等共享工具函数 |
| `emacs.zig` | emacs-module.h C API 的类型安全封装 |
| `input.zig` | 键盘和鼠标事件编码 |
| `kitty_graphics.zig` | Kitty 图形协议支持 |
| `sys.zig` | 系统回调（PNG 解码器等） |
| `pty.zig` | PTY 密码模式检测 |
| `fixed_array_list.zig` | 固定大小数组列表 |
| `png.zig` / `ppm.zig` | 图像格式支持 |
| `version.zig` | 单一版本号来源 |

### Elisp 层 (lisp/)
- `ghostel.el` — 主模块：终端创建、PTY/ConPTY 生成、渲染循环、快捷键、shell 集成、TRAMP
- `ghostel-comint.el` — comint 集成，将 libghostty VT 解析器作为 comint preoutput 过滤器
- `ghostel-compile.el` — 使用真实 TTY 的 `M-x compile` 替代（支持进度条、颜色、TUI 工具）
- `ghostel-eshell.el` — 将 eshell 可视命令 (vim, htop) 路由到 ghostel
- `ghostel-debug.el` — 基于 advice 的调试日志（filter、按键、重绘决策）

### Evil 集成 (extensions/evil-ghostel/)
- `evil-ghostel.el` — Evil-mode 光标同步（Emacs point 与终端光标）

### 依赖
libghostty-vt 由 Zig 包管理器获取（见 `build.zig.zon`），通过 `const gt = @import("ghostty-vt");` 使用 Zig API。`vendor/ghostty/` 是 vendored 的 ghostty 源码目录，供 Windows `build.cmd` 使用。

## Windows ConPTY — Fork 特有代码

所有 Windows 特有代码通过 `(eq system-type 'windows-nt)` (Elisp) 或 `comptime builtin.os.tag == .windows` (Zig) 保护。

| 位置 | 函数 | 说明 |
|---|---|---|
| `lisp/ghostel.el` | `ghostel--conpty-proxy-make-process` | 通过 `conpty_proxy.exe` 生成 shell（替代 Unix PTY） |
| `lisp/ghostel.el` | `ghostel--conpty-proxy-resize` | 通过 Zig `ghostel--conpty-resize` 调整大小（替代 Unix ioctl） |
| `src/module.zig` | `ghostel--conpty-resize` / `fnConptyResize` | 写入命名管道 `\\.\pipe\conpty-proxy-ctrl-{id}` |
| `src/GhostelTerm.zig` | `ghostel--write-input` | CRLF 规范化（流式插入缺失 `\r`），已是上游代码的一部分 |
| `build.cmd` / `build.zig` | — | GNU ABI (`-Dtarget=native-native-gnu`)；`build.zig` 中条件启用 `link_libcpp`；`ZIG_GLOBAL_CACHE_DIR` 必须在同一驱动器（Zig 0.15 bug） |

## 上游同步工作流

> **严格按步骤执行：** 步骤 1→2→3→4→5 必须逐项完成，不得跳过或合并。

### 步骤 1：拉取并合并

```bash
git fetch upstream
git log main..upstream/main --oneline --no-decorate
git merge upstream/main --no-edit
```

预期冲突位置：
- `src/module.zig` — `emacs_functions` 表和 import 区域（上游可能重构注册模式）
- `lisp/ghostel.el` — `ghostel--start-process` 中 Windows 条件分支
- `src/emacs.zig` — Emacs API 封装层
- `src/GhostelTerm.zig` — 函数注册表和实现（核心逻辑集中于此）

解决冲突原则：
1. 采用上游的架构改进（如函数分散到各模块、表驱动注册）
2. 保留 fork 特有的 ConPTY 函数（`ghostel--conpty-resize`、`fnConptyResize`）
3. 新增的上游功能若与 fork 功能重叠，以上游为准

### 步骤 2：审查 ConPTY Patch 影响

| 审查点 | 涉及文件 | 检查方法 |
|---|---|---|
| ConPTY 函数注册 | `src/module.zig` `emacs_functions` 表 | 确认 `ghostel--conpty-resize` 条目存在 |
| `fnConptyResize` 实现 | `src/module.zig` | 确认函数体完整，签名匹配注册声明 |
| CRLF 处理 | `src/GhostelTerm.zig` `ghostel--write-input` | 验证流式 CRLF 规范化 + alt screen 跳过逻辑 |
| Emacs API 调用 | `src/emacs.zig` | 上游可能改变调用签名——确保 fork 代码跟上 |
| Elisp 进程管理 | `lisp/ghostel.el` | ConPTY 路径环境变量、buffer 设置与 `ghostel--spawn-pty` 对等 |
| 构建脚本 | `build.zig` / `build.zig.zon` | 确认 `link_libcpp`、`.dll` 输出名、依赖版本未被覆盖 |

### 步骤 3：逻辑审查清单

- [ ] `ghostel--conpty-proxy-make-process` 与 `ghostel--spawn-pty` 功能对等
- [ ] `ghostel--conpty-proxy-resize` 与 Unix resize 路径功能对等
- [ ] `ghostel--conpty-resize` 在 `src/module.zig` `emacs_functions` 表中注册
- [ ] `fnConptyResize` 实现完整，签名匹配表项
- [ ] CRLF 规范化在 `src/GhostelTerm.zig` 中完整（alt screen 跳过 + 流式 \r 插入）
- [ ] `version` 常量：`src/version.zig`、`build.zig.zon`、`lisp/ghostel.el` 三处一致

### 步骤 4：构建验证

```bash
MSYS_NO_PATHCONV=1 cmd.exe /c "E:\lambda\selfcode\conpty_ghostel\build.cmd"
```

零错误零警告才算通过。

### 步骤 5：总结变更

输出格式：
```
## 上游合并总结：vX.Y.Z (N commits)

### 分类 1
- **变更点** — 一句话描述

### 冲突解决
- 文件 — 具体处理方式
```

## 关键约定

- Elisp 公共 API 使用 `ghostel-` 前缀；内部使用 `ghostel--`（双横线）
- Zig 函数注册使用 `emacs_functions` 表驱动模式（`[_]emacs.FunctionEntry`），每个表项的 `.impl` 字段是包含 `pub fn call(env: emacs.Env, nargs: isize, args: [*c]emacs.Value) !emacs.Value` 方法的类型
- `test/ghostel-test.el` 中的测试分为纯 Elisp 和 native 两类；CI 在 Emacs 28.2、29.4 和 snapshot 上运行
- Shell 集成脚本位于 `etc/shell/bootstrap/` (bash/zsh/fish) 和 `etc/shell/ghostel.{bash,zsh,fish}`（SSH terminfo）
- 打包的 terminfo 在 `etc/terminfo/` 中
- 编辑 `.zig` 文件后运行 `zig fmt <file>` 格式化
