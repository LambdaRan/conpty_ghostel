# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Ghostel 是嵌入 Emacs 的终端模拟器，基于 libghostty-vt 驱动。本仓库是 [dakra/ghostel](https://github.com/dakra/ghostel) 的 fork，添加了 **Windows ConPTY 支持**。上游远程为 `upstream` (dakra/ghostel)，fork 远程为 `origin` (LambdaRan/conpty_ghostel)。

## 相关目录

| 路径 | 说明 |
|---|---|
| `E:\lambda\selfcode\conpty_ghostel` | ghostel 源码（本仓库） |
| `E:\lambda\selfcode\conpty_proxy` | conpty_proxy.exe 源码（独立项目） |
| `C:\emacs-lambda` | Emacs 配置目录 |
| `C:\emacs-lambda\site-lisp\extensions\ghostel` | ghostel 安装目录（需手动同步构建产物） |

构建后需将以下文件同步到安装目录：
- `lisp/ghostel.el`、`lisp/ghostel-compile.el`、`lisp/ghostel-eshell.el`、`lisp/ghostel-debug.el`
- `extensions/evil-ghostel/evil-ghostel.el`
- `ghostel-module.dll`（构建产物在仓库根目录）
- `etc/terminfo/`、`etc/shell/`

## 构建命令

### Windows（本 fork 的主要开发平台）
```
build.cmd                    # 完整构建：libghostty-vt + ghostel-module.dll
```
依赖：Zig 0.15.2+，Emacs 头文件从 `C:\Program Files\Emacs\` 自动检测（或设置 `EMACS_INCLUDE_DIR`）。

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
  → Zig fnWriteInput (CRLF 规范化、OSC 提取、通过 libghostty 解析 VT 序列)
  → GhosttyTerminal (网格、样式、滚动缓冲区状态)
  → RenderState (脏行跟踪)
  → Zig fnRedraw (单元格提取、样式应用) → Emacs 缓冲区
```

### 原生模块 (src/)
- `module.zig` — 入口；注册 22+ 个 Elisp 可调用函数，OSC 分发 (4/7/9/10/11/51/52/133/777)，CRLF 处理
- `terminal.zig` — 封装 GhosttyTerminal + RenderState；尺寸、滚动缓冲区、键盘/鼠标编码器
- `render.zig` — 增量脏行渲染到 Emacs 缓冲区；单元格提取、样式/超链接应用
- `emacs.zig` — emacs-module.h C API 的类型安全封装
- `ghostty.zig` — libghostty-vt C API 的 Zig 绑定
- `input.zig` — 通过 libghostty 编码器进行键盘和鼠标事件编码

### Elisp 层 (lisp/)
- `ghostel.el` — 主模块：终端创建、PTY 生成、渲染循环、快捷键、shell 集成、TRAMP
- `ghostel-compile.el` — 使用真实 TTY 的 `M-x compile` 替代（支持进度条、颜色、TUI 工具）
- `ghostel-eshell.el` — 将 eshell 可视命令 (vim, htop) 路由到 ghostel
- `ghostel-debug.el` — 基于 advice 的调试日志（filter、按键、重绘决策）

### Evil 集成 (extensions/evil-ghostel/)
- `evil-ghostel.el` — Evil-mode 光标同步（Emacs point 与终端光标）

### 依赖
libghostty-vt 由 Zig 包管理器获取（见 `build.zig.zon`）。`vendor/ghostty/` 是 git 子模块，供 Windows `build.cmd` 使用。

## Windows ConPTY — Fork 特有代码

所有 Windows 特有代码通过 `(eq system-type 'windows-nt)` (Elisp) 或 `comptime builtin.os.tag == .windows` (Zig) 保护。关键位置：

- `ghostel--conpty-proxy-make-process` — 通过外部 `conpty_proxy.exe` 生成 shell（替代 Unix PTY）
- `ghostel--conpty-proxy-resize` — 通过 `conpty_proxy.exe resize` 调整大小（替代 Unix ioctl）
- `module.zig` CRLF 分支 — Windows 路径跳过 CRLF 规范化（ConPTY 处理行规则）
- `build.cmd` — 使用 GNU ABI (`-Dtarget=native-native-gnu`) 避免 MSVC libcpmt 冲突；手动从 zig-cache 复制 simdutf.lib + highway.lib

### 上游同步注意事项

合并上游时，冲突通常发生在 `ghostel--start-process` (Elisp) 和 `fnWriteInput` (Zig) 中 Windows 条件分支所在的位置。确保 ConPTY 路径与 `ghostel--spawn-pty` 保持功能对等（环境变量、性能设置如 `process-adaptive-read-buffering`、`read-process-output-max`）。

## 关键约定

- Elisp 公共 API 使用 `ghostel-` 前缀；内部使用 `ghostel--`（双横线）
- Zig 中注册的原生函数使用 `fn` 前缀命名 (fnRedraw, fnWriteInput 等)，映射到 `ghostel--` Elisp 符号
- `test/ghostel-test.el` 中的测试分为纯 Elisp 和 native 两类；CI 在 Emacs 28.2、29.4 和 snapshot 上运行
- Shell 集成脚本位于 `etc/shell/bootstrap/` (bash/zsh/fish) 和 `etc/shell/ghostel.{bash,zsh,fish}`（SSH terminfo）
- 打包的 terminfo 在 `etc/terminfo/` 中，覆盖 Linux (x/, g/) 和 macOS (78/, 67/) 两种哈希目录布局
