# Ghostel Windows 构建系统修复总结

## 问题背景

Ghostel 项目从上游 (dakra/ghostel) fork 后添加了 Windows ConPTY 支持。`build.cmd` 负责在 Windows 上构建 `ghostel-module.dll`，但在 Zig 升级到 0.15.2 后构建失败。

## 根本原因

Zig 0.15 改变了依赖系统的执行方式——将依赖的 `build.zig` 编译为独立的子进程 (`build.exe`) 运行。这导致两个关键问题：

### 1. URL 依赖无法找到 artifact

`build.zig.zon` 通过远程 URL 获取 ghostty：

```zig
.ghostty = .{
    .url = "https://github.com/ghostty-org/ghostty/archive/01825411ab....tar.gz",
    .hash = "ghostty-1.3.2-dev-...",
},
```

根目录 `zig build` 调用 `ghostty_dep.artifact("ghostty-vt-static")` 直接 panic：

```
thread panic: unable to find artifact 'ghostty-vt-static'
```

原因：ghostty 的 `build.zig` 使用 `b.dep_prefix.len > 0` 判断 `is_dep`。在子进程模式下 `dep_prefix` 为空，导致 `is_dep=false`，artifact 未通过标准 API 暴露。

### 2. 路径依赖不传递自定义选项

将 `build.zig.zon` 改为路径依赖 (`.path = "vendor/ghostty"`) 后，`artifact()` 调用不再 panic，但 `emit-lib-vt=true` 选项**未被传递**到子进程的 `-D` 参数中：

```
# 子进程实际收到的参数（缺少 -Demit-lib-vt=true）：
build.exe ... -Doptimize=ReleaseFast -Dtarget=native-native-gnu
```

结果：`config.emit_lib_vt` 保持默认值 `false`，ghostty 在 Windows 上尝试构建完整的 `ghostty-internal.dll`，触发 DllMain 类型冲突。

### 3. vendor/ghostty 版本不匹配（次要问题）

`vendor/ghostty` 子目录的 commit (`ba398dff`) 与 `build.zig.zon` 中 URL 指向的 commit (`01825411ab`) 不同，导致 API 不兼容（缺少 `GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT` 等符号）。

## 解决方案

### build.zig — 添加 Windows 专用构建路径

Windows 上绕过 Zig 依赖系统，直接链接 `vendor/ghostty/zig-out/` 中的预构建产物；Unix 保持原有的包管理器路径不变。

```zig
if (target_os == .windows) {
    // 直接链接预构建库
    mod.addIncludePath(b.path("vendor/ghostty/zig-out/include"));
    mod.addObjectFile(b.path("vendor/ghostty/zig-out/lib/ghostty-vt-static.lib"));
    mod.addObjectFile(b.path("vendor/ghostty/zig-out/lib/simdutf.lib"));
    mod.addObjectFile(b.path("vendor/ghostty/zig-out/lib/highway.lib"));
    mod.addObjectFile(b.path("vendor/ghostty/zig-out/lib/utfcpp.lib"));
} else {
    // Unix: 使用 Zig 依赖系统
    const ghostty_dep = b.dependency("ghostty", .{ ... });
    ...
}
```

关键改动：
- 删除了 `addModuleIncludes` 辅助函数（不再需要）
- Windows 模块添加 `link_libcpp = true`（simdutf/highway 需要 C++ 运行时）

### build.cmd — 优化重写

| 改进项 | 旧版 | 新版 |
|--------|------|------|
| Debug 构建 | 不支持 | `build.cmd debug` |
| 清理命令 | 不支持 | `build.cmd clean` |
| 依赖库拷贝 | 只拷贝 simdutf + highway | 拷贝 simdutf + highway + **utfcpp** |
| 拷贝逻辑 | 重复代码 | `for %%L in (...)` 循环 |
| 子模块检查 | `git submodule update`（无 .gitmodules 会失败） | 检查 `vendor\ghostty\build.zig` 是否存在 |
| 进度展示 | 无编号 | `[1/3] [2/3] [3/3]` |

### vendor/ghostty — 版本对齐

将 `vendor/ghostty` checkout 到与 `build.zig.zon` URL 匹配的 commit：

```
01825411ab2720e47e6902e9464e805bc6a062a1
```

## 构建流程（修复后）

```
build.cmd                  # Release 构建
build.cmd debug            # Debug 构建
build.cmd clean            # 清理所有构建产物
```

内部步骤：

1. **[1/3]** 在 `vendor/ghostty` 中运行 `zig build -Demit-lib-vt=true` 构建 libghostty-vt
2. **[2/3]** 从 `vendor/ghostty/.zig-cache` 拷贝 C++ 依赖库 (simdutf, highway, utfcpp) 到 `zig-out/lib/`
3. **[3/3]** 在根目录运行 `zig build`，Windows 路径直接链接预构建产物，生成 `ghostel-module.dll`

## 注意事项

- **上游同步时**：合并上游后需检查 `build.zig.zon` 中的 ghostty URL commit，并将 `vendor/ghostty` 同步到对应 commit
- **Zig 版本**：此问题特定于 Zig 0.15.x 的子进程依赖执行模式，未来版本可能修复选项传递问题
- **GNU ABI**：Windows 构建必须使用 `-Dtarget=native-native-gnu` 以避免 MSVC libcpmt 链接冲突
