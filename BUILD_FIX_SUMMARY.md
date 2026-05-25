# Ghostel Windows 构建系统修复总结

## 问题背景

Ghostel 项目从上游 (dakra/ghostel) fork 后添加了 Windows ConPTY 支持。`build.cmd` 负责在 Windows 上构建 `ghostel-module.dll`。

## 历史问题与解决

### Zig 0.15 跨驱动器路径 bug

Zig 0.15 的依赖子进程执行会在 `Run.zig:662` 断言失败（`assert(!std.fs.path.isAbsolute(child_cwd_rel))`），当全局缓存目录与项目不在同一驱动器时触发。

**解决方案**：`build.cmd` 将 `ZIG_GLOBAL_CACHE_DIR` 固定到项目目录下（`%~dp0.zig-global-cache`），确保所有路径在同一驱动器。

### 上游 API 迁移：C API → Zig API

上游在 v0.28.0 中从 `artifact("ghostty-vt-static")` + C 头文件切换为 `module("ghostty-vt")` + Zig import。这一变更使 `b.dependency()` 的 `.module()` 调用能在 Windows 上正常工作（不再需要 `.artifact()` 查找），因此旧的三步构建流程（pre-build vendor/ghostty → copy libs → root build）不再需要。

## 当前构建流程

```
build.cmd                  # Release 构建
build.cmd debug            # Debug 构建
build.cmd clean            # 清理所有构建产物
```

内部仅执行一步：

```
zig build -Doptimize=<mode> -Dtarget=native-native-gnu
```

Zig 构建系统自动从 `build.zig.zon` 的 URL 下载 ghostty 依赖并编译。

## 注意事项

- **GNU ABI**：Windows 构建必须使用 `-Dtarget=native-native-gnu` 以避免 MSVC libcpmt 链接冲突
- **`ZIG_GLOBAL_CACHE_DIR`**：必须在与项目同一驱动器上，否则 Zig 0.15 panic
- **`link_libcpp`**：`build.zig` 中 Windows 条件启用，simdutf/highway 需要 C++ 运行时
- **Emacs 头文件**：从 `C:\Program Files\Emacs\` 自动检测，或手动设置 `EMACS_INCLUDE_DIR`
- **`vendor/ghostty/`**：历史遗留目录，当前构建不再使用（Zig 依赖系统直接从 URL 获取）
