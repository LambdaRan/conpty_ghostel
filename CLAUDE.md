# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ghostel is a GPU-accelerated terminal emulator embedded in Emacs, powered by libghostty-vt. This is a fork of [dakra/ghostel](https://github.com/dakra/ghostel) with **Windows ConPTY support** added. The upstream remote is `upstream` (dakra/ghostel), the fork is `origin` (LambdaRan/conpty_ghostel).

## Build Commands

### Windows (primary development platform for this fork)
```
build.cmd                    # Full build: libghostty-vt + ghostel-module.dll
```
Requires: Zig 0.15.2+, Emacs headers auto-detected from `C:\Program Files\Emacs\` (or set `EMACS_INCLUDE_DIR`).

### Unix
```
make build                   # Build ghostel-module.so/.dylib
make test                    # Pure Elisp tests (no compiled module needed)
make test-native             # Tests requiring compiled module
make test-all                # Both
make test-evil               # Evil-mode integration tests
make lint                    # byte-compile + package-lint + checkdoc
make bench                   # Performance benchmarks
make clean                   # Remove build artifacts
```

### Running a single test
```bash
emacs --batch -Q -L . -l ert -l test/ghostel-test.el \
  --eval '(ert-run-tests-batch "ghostel-test-TESTNAME")'
```

## Architecture

Two-layer design: **Zig native module** for terminal emulation + **Elisp** for process management and Emacs integration.

### Data Flow
```
Shell (bash/zsh/fish/cmd.exe)
  → PTY/ConPTY → Elisp ghostel--filter
  → Zig fnWriteInput (CRLF normalization, OSC extraction, VT parsing via libghostty)
  → GhosttyTerminal (grid, styles, scrollback state)
  → RenderState (dirty row tracking)
  → Zig fnRedraw (cell extraction, style application) → Emacs buffer
```

### Native Module (src/)
- `module.zig` — Entry point; registers 22+ Elisp-callable functions, OSC dispatch (4/7/9/10/11/51/52/133/777), CRLF handling
- `terminal.zig` — Wraps GhosttyTerminal + RenderState; dimensions, scrollback, key/mouse encoders
- `render.zig` — Incremental dirty-row rendering to Emacs buffers; cell extraction, style/hyperlink application
- `emacs.zig` — Type-safe wrapper around emacs-module.h C API
- `ghostty.zig` — Zig bindings for libghostty-vt C API
- `input.zig` — Key and mouse event encoding via libghostty encoders

### Elisp Layer
- `ghostel.el` — Main: terminal creation, PTY spawning, rendering loop, keybindings, shell integration, TRAMP
- `ghostel-compile.el` — `M-x compile` replacement using real TTY (supports progress bars, colors, TUI tools)
- `ghostel-eshell.el` — Routes eshell visual commands (vim, htop) to ghostel
- `evil-ghostel.el` — Evil-mode cursor sync between Emacs point and terminal cursor
- `ghostel-debug.el` — Advice-based debug logging for filter, keys, redraw decisions

### Dependency
libghostty-vt is fetched by Zig package manager (see `build.zig.zon`). `vendor/ghostty/` is a git submodule used by `build.cmd` on Windows.

## Windows ConPTY — Fork-Specific Code

All Windows-specific additions are guarded by `(eq system-type 'windows-nt)` (Elisp) or `comptime builtin.os.tag == .windows` (Zig). Key locations:

- `ghostel--conpty-proxy-make-process` — Spawns shell via external `conpty_proxy.exe` instead of Unix PTY
- `ghostel--conpty-proxy-resize` — Resize via `conpty_proxy.exe resize` (vs Unix ioctl)
- `module.zig` CRLF branch — Windows path skips CRLF normalization (ConPTY handles line discipline)
- `build.cmd` — Builds with GNU ABI (`-Dtarget=native-native-gnu`) to avoid MSVC libcpmt conflicts; manually copies simdutf.lib + highway.lib from zig-cache

When syncing with upstream, conflicts typically occur in `ghostel--start-process` (Elisp) and `fnWriteInput` (Zig) where the Windows conditional branches live. Ensure the ConPTY path stays feature-parity with `ghostel--spawn-pty` (env vars, performance settings like `process-adaptive-read-buffering`, `read-process-output-max`).

## Key Conventions

- The Elisp public API uses `ghostel-` prefix; internals use `ghostel--` (double dash)
- Native functions registered in Zig follow `fn` prefix naming (fnRedraw, fnWriteInput, etc.) and map to `ghostel--` Elisp symbols
- Tests in `test/ghostel-test.el` are split into pure-Elisp and native categories; CI runs on Emacs 28.2, 29.4, and snapshot
- Shell integration scripts live in `etc/shell-integration/` (bash/zsh/fish) plus `etc/ghostel.{bash,zsh,fish}` for SSH terminfo
- Bundled terminfo in `terminfo/` covers both Linux (x/, g/) and macOS (78/, 67/) hashed-dir layouts
