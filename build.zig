const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/module.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Emacs module header
    mod.addSystemIncludePath(.{
        .cwd_relative = "/Applications/Emacs.app/Contents/Resources/include",
    });

    // libghostty-vt headers and static library (pre-built)
    // Build with: cd vendor/ghostty && zig build -Demit-lib-vt=true
    mod.addIncludePath(b.path("vendor/ghostty/zig-out/include"));
    mod.addObjectFile(b.path("vendor/ghostty/zig-out/lib/libghostty-vt.a"));

    // libghostty-vt bundled dependencies (built by ghostty's zig build)
    mod.addObjectFile(.{ .cwd_relative = "vendor/ghostty/.zig-cache/o/a24e184e2a99205eae8505b6856500ae/libsimdutf.a" });
    mod.addObjectFile(.{ .cwd_relative = "vendor/ghostty/.zig-cache/o/7d65643d9998f245b2e274b7ff8d3516/libhighway.a" });

    // libghostty-vt depends on libc++
    mod.linkSystemLibrary("c++", .{});

    const lib = b.addLibrary(.{
        .name = "ghostel-module",
        .linkage = .dynamic,
        .root_module = mod,
    });

    b.installArtifact(lib);

    // Copy the shared library to project root for easy Emacs loading
    const copy_step = b.addInstallFile(
        lib.getEmittedBin(),
        "../ghostel-module.dylib",
    );
    b.getInstallStep().dependOn(&copy_step.step);
}
