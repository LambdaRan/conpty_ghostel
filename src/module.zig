/// Ghostel — Emacs dynamic module entry point.
///
/// This is the top-level file compiled into ghostel-module.so/.dylib.
/// It exports emacs_module_init (the C entry point Emacs calls on load)
/// and registers all Elisp-callable functions.
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const gt = @import("ghostty-vt");

const emacs = @import("emacs.zig");
const ComintFilter = @import("comint_filter.zig");
const GhostelTerm = @import("GhostelTerm.zig");
const png = @import("png.zig");

const c = emacs.c;

/// In debug builds, all allocations go through DebugAllocator for corruption
/// detection (double-free, use-after-free, overflow canaries).  A debug-only
/// kill-emacs-hook explicitly deinits all live terminals before process exit so
/// atexit can call deinit() on a clean slate.
var debug_alloc: std.heap.DebugAllocator(.{}) = .init;
var alloc: Allocator = std.heap.c_allocator;

/// Module version — see src/version.zig.  Keep in sync with ghostel.el
/// and build.zig.zon.
const version = @import("version.zig").version;

extern fn atexit(func: *const fn () callconv(.c) void) c_int;

// ---------------------------------------------------------------------------
// Module entry point
// ---------------------------------------------------------------------------

/// Emacs calls this when loading the dynamic module.
export fn emacs_module_init(runtime: *c.struct_emacs_runtime) callconv(.c) c_int {
    if (runtime.size < @sizeOf(c.struct_emacs_runtime)) {
        return 1; // ABI mismatch
    }

    if (builtin.mode == .Debug) {
        alloc = debug_alloc.allocator();
        _ = atexit(&debugAtExit);
    }

    const raw_env = runtime.get_environment.?(runtime);
    emacs.initModule(alloc, raw_env);

    const env = emacs.Env.init(raw_env);

    env.registerFunctions(&emacs_functions);

    ComintFilter.initModule(alloc, env);
    GhostelTerm.initModule(alloc, env);

    gt.sys.decode_png = &png.decode;

    _ = env.f("provide", .{emacs.sym.@"ghostel-module"});
    return 0;
}

fn debugAtExit() callconv(.c) void {
    if (debug_alloc.deinit() == .leak) {
        std.debug.print("ghostel: memory leak detected at exit\n", .{});
    }
}

// ---------------------------------------------------------------------------
// Plugin version — required by Emacs >= 27
// ---------------------------------------------------------------------------

export const plugin_is_GPL_compatible: c_int = 0;

// ---------------------------------------------------------------------------
// Exported Elisp functions
// ---------------------------------------------------------------------------

const emacs_functions = [_]emacs.FunctionEntry{
    .{
        .name = "ghostel--module-version",
        .arity = .{ 0, 0 },
        .doc =
        \\Return the native module version string.
        \\
        \\(ghostel--module-version)
        ,
        .impl = struct {
            pub fn call(env: emacs.Env, _: isize, _: [*c]emacs.Value) !emacs.Value {
                return env.makeString(version);
            }
        },
    },
    .{
        .name = "ghostel--enable-vt-log",
        .arity = .{ 0, 0 },
        .doc =
        \\Enable libghostty internal log routing to *ghostel-debug*.
        \\
        \\(ghostel--enable-vt-log)
        ,
        .impl = struct {
            pub fn call(env: emacs.Env, _: isize, _: [*c]emacs.Value) !emacs.Value {
                vt_log_active = true;
                return env.t();
            }
        },
    },
    .{
        .name = "ghostel--disable-vt-log",
        .arity = .{ 0, 0 },
        .doc =
        \\Disable libghostty internal log routing.
        \\
        \\(ghostel--disable-vt-log)
        ,
        .impl = struct {
            pub fn call(env: emacs.Env, _: isize, _: [*c]emacs.Value) !emacs.Value {
                vt_log_active = false;
                return env.t();
            }
        },
    },
    .{
        .name = "ghostel--conpty-resize",
        .arity = .{ 3, 3 },
        .doc =
        \\Resize the ConPTY pseudo-console by writing to the control named pipe.
        \\
        \\(ghostel--conpty-resize ID WIDTH HEIGHT)
        ,
        .impl = struct {
            pub fn call(env: emacs.Env, _: isize, args: [*c]emacs.Value) !emacs.Value {
                return fnConptyResize(env, args);
            }
        },
    },
};

/// (ghostel--conpty-resize ID WIDTH HEIGHT)
/// Resize the ConPTY pseudo-console by writing directly to the control
/// named pipe, avoiding a process spawn on every resize.
/// Returns t on success, nil on failure.
fn fnConptyResize(env: emacs.Env, args: [*c]emacs.Value) emacs.Value {
    if (comptime builtin.os.tag != .windows) {
        return env.nil();
    }

    const HANDLE = *anyopaque;
    const DWORD = u32;
    const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
    const GENERIC_WRITE = 0x40000000;
    const OPEN_EXISTING: DWORD = 3;

    const kernel32 = struct {
        extern "kernel32" fn CreateFileA(
            lpFileName: [*:0]const u8,
            dwDesiredAccess: DWORD,
            dwShareMode: DWORD,
            lpSecurityAttributes: ?*anyopaque,
            dwCreationDisposition: DWORD,
            dwFlagsAndAttributes: DWORD,
            hTemplateFile: ?HANDLE,
        ) callconv(.winapi) HANDLE;
        extern "kernel32" fn WriteFile(
            hFile: HANDLE,
            lpBuffer: [*]const u8,
            nNumberOfBytesToWrite: DWORD,
            lpNumberOfBytesWritten: *DWORD,
            lpOverlapped: ?*anyopaque,
        ) callconv(.winapi) i32;
        extern "kernel32" fn CloseHandle(
            hObject: HANDLE,
        ) callconv(.winapi) i32;
    };

    var id_buf: [64]u8 = undefined;
    const id = env.extractString(args[0], &id_buf) catch return env.nil();
    const width: u16 = @intCast(env.extractInteger(args[1]));
    const height: u16 = @intCast(env.extractInteger(args[2]));

    var pipename_buf: [128]u8 = undefined;
    const pipename = std.fmt.bufPrintZ(&pipename_buf, "\\\\.\\pipe\\conpty-proxy-ctrl-{s}", .{id}) catch return env.nil();

    const pipe = kernel32.CreateFileA(
        pipename,
        GENERIC_WRITE,
        0,
        null,
        OPEN_EXISTING,
        0,
        null,
    );
    if (pipe == INVALID_HANDLE_VALUE) {
        return env.nil();
    }
    defer _ = kernel32.CloseHandle(pipe);

    var msg_buf: [32]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "{d} {d}", .{ width, height }) catch return env.nil();

    var written: DWORD = 0;
    const ok = kernel32.WriteFile(pipe, msg.ptr, @intCast(msg.len), &written, null);
    if (ok == 0 or written != @as(DWORD, @intCast(msg.len))) {
        return env.nil();
    }
    return env.t();
}

// ---------------------------------------------------------------------------
// zig log callback
// ---------------------------------------------------------------------------

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = if (builtin.mode == .Debug) .debug else .warn,
};

/// Whether VT logging is active.
pub var vt_log_active: bool = false;

/// Log callback matching GhosttySysLogFn.  Formats the message and
/// forwards it to `ghostel--debug-log-vt' in Elisp.
fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // Debug only: in `emacs -nw' the module's stderr is the user's tty.
    if (builtin.mode == .Debug) {
        std.log.defaultLog(message_level, scope, format, args);
    }

    if (!vt_log_active) return;
    const env = emacs.current_env orelse return;
    const level_str: []const u8 = switch (message_level) {
        .err => "error",
        .warn => "warning",
        .info => "info",
        .debug => "debug",
    };
    const scope_slice = @tagName(scope);
    var buf: [4096]u8 = undefined;
    const msg_slice = std.fmt.bufPrint(&buf, format, args) catch return;

    _ = env.f("ghostel--debug-log-vt", .{ level_str, scope_slice, msg_slice });

    // If the Elisp call signaled an error (e.g. ghostel--debug-log-vt is
    // void-function because ghostel-debug.el isn't loaded), clear it so it
    // doesn't leak into the calling context and disable logging to prevent
    // repeated errors.
    if (env.nonLocalExitCheck() != .normal) {
        env.nonLocalExitClear();
        vt_log_active = false;
    }
}
