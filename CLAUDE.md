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

### 构建命令 (Windows)

在 MSYS2/Bash 环境下调用 `build.cmd` 需禁用路径转换：

```bash
MSYS_NO_PATHCONV=1 cmd.exe /c "E:\lambda\selfcode\conpty_ghostel\build.cmd"
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
- `module.zig` CRLF 分支 — 流式 CRLF 规范化是幂等的，所有平台安全运行；无需 Windows comptime 守卫
- `build.cmd` — 使用 GNU ABI (`-Dtarget=native-native-gnu`) 避免 MSVC libcpmt 冲突；手动从 zig-cache 复制 simdutf.lib + highway.lib

## 上游同步工作流

> **严格按步骤执行：** 步骤 1→2→3→4→5 必须逐项完成，不得跳过或合并。每一步完成后才能进入下一步。步骤 3 的每个检查项必须全部打勾确认。

每次上游发布新版本时执行以下步骤：

### 步骤 1：拉取并合并

```bash
git fetch upstream
git log main..upstream/main --oneline --no-decorate   # 查看新增 commit
git merge upstream/main --no-edit
```

如果冲突发生，通常出现在以下位置：
- `src/module.zig` — `bindFunction` 注册区域（上游重构 vs fork 特有函数）
- `lisp/ghostel.el` — `ghostel--start-process` 中 Windows 条件分支
- `src/emacs.zig` — Emacs API 封装层

解决冲突原则：
1. 采用上游的代码风格改进（如：`f` 函数替代 `callN`，多行文档字符串格式）
2. 保留 fork 特有的 Windows/ConPTY 函数（`ghostel--conpty-resize`、`fnConptyResize` 等）
3. 新增的上游函数如果与 fork 功能重叠，以前者为准（上游已合入 `ghostel--pty-password-input-p`）

### 步骤 2：审查 ConPTY Patch 影响

对每个上游变更，检查是否影响 fork 特有代码：

| 审查点 | 涉及文件 | 检查方法 |
|---|---|---|
| `module.zig` 注册区域 | `src/module.zig:34-178` | `diff upstream/main...HEAD -- src/module.zig` 确认 ConPTY 函数未被覆盖 |
| CRLF 处理路径 | `src/module.zig` 中 `fnWriteInput` | 流式 CRLF 规范化（插入缺失的 `\r`）是幂等的，所有平台安全运行；无需 Windows `comptime` 守卫 |
| Emacs API 调用方式 | `src/emacs.zig` | 上游重构可能改变调用签名（如 `callN` → `f`）——确保 fork 代码跟上 |
| Elisp 进程管理 | `lisp/ghostel.el` `ghostel--start-process` | 对比 `ghostel--spawn-pty` 确保 ConPTY 路径环境变量、buffer 设置同步 |
| 构建脚本 | `build.zig` / `build.zig.zon` | 确认 GNU ABI 目标、依赖版本、libghostty-vt 依赖声明未被覆盖 |

### 步骤 3：逻辑审查清单

合并后逐个检查：

- [ ] `ghostel--conpty-proxy-make-process` 与 `ghostel--spawn-pty` 功能对等（环境变量、`process-adaptive-read-buffering`、`read-process-output-max`）
- [ ] `ghostel--conpty-proxy-resize` 与 Unix `ioctl` resize 路径功能对等
- [ ] `ghostel--conpty-resize` (Zig) 注册仍存在
- [ ] `fnConptyResize` 实现完整（函数签名与注册声明一致）
- [ ] CRLF 规范化流式方法是幂等的，所有平台安全；无需 `comptime` 守卫
- [ ] 上游新增的 OSC handler 在 ConPTY 路径下是否也需要处理
- [ ] `version` 常量与上游版本号一致

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

### 分类 2
...

### 冲突解决
- 文件 — 具体处理方式
```

## 关键约定

- Elisp 公共 API 使用 `ghostel-` 前缀；内部使用 `ghostel--`（双横线）
- Zig 中注册的原生函数使用 `fn` 前缀命名 (fnRedraw, fnWriteInput 等)，映射到 `ghostel--` Elisp 符号
- `test/ghostel-test.el` 中的测试分为纯 Elisp 和 native 两类；CI 在 Emacs 28.2、29.4 和 snapshot 上运行
- Shell 集成脚本位于 `etc/shell/bootstrap/` (bash/zsh/fish) 和 `etc/shell/ghostel.{bash,zsh,fish}`（SSH terminfo）
- 打包的 terminfo 在 `etc/terminfo/` 中，覆盖 Linux (x/, g/) 和 macOS (78/, 67/) 两种哈希目录布局
