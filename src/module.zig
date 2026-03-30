/// Ghostel — Emacs dynamic module entry point.
///
/// This is the top-level file compiled into ghostel-module.so/.dylib.
/// It exports emacs_module_init (the C entry point Emacs calls on load)
/// and registers all Elisp-callable functions.
const std = @import("std");
const emacs = @import("emacs.zig");
const Terminal = @import("terminal.zig");
const gt = @import("ghostty.zig");
const render = @import("render.zig");
const input = @import("input.zig");

const c = emacs.c;

// ---------------------------------------------------------------------------
// Module entry point
// ---------------------------------------------------------------------------

/// Emacs calls this when loading the dynamic module.
export fn emacs_module_init(runtime: *c.struct_emacs_runtime) callconv(.c) c_int {
    if (runtime.size < @sizeOf(c.struct_emacs_runtime)) {
        return 1; // ABI mismatch
    }

    const raw_env = runtime.get_environment.?(runtime);
    const env = emacs.Env.init(raw_env);

    // Register functions
    env.bindFunction("ghostel--new", 2, 3, &fnNew, "Create a new ghostel terminal.\n\n(ghostel--new ROWS COLS &optional MAX-SCROLLBACK)");
    env.bindFunction("ghostel--write-input", 2, 2, &fnWriteInput, "Write raw bytes to the terminal.\n\n(ghostel--write-input TERM DATA)");
    env.bindFunction("ghostel--set-size", 3, 3, &fnSetSize, "Resize the terminal.\n\n(ghostel--set-size TERM ROWS COLS)");
    env.bindFunction("ghostel--get-title", 1, 1, &fnGetTitle, "Get the terminal title.\n\n(ghostel--get-title TERM)");
    env.bindFunction("ghostel--redraw", 1, 1, &fnRedraw, "Redraw dirty regions of the terminal into the current buffer.\n\n(ghostel--redraw TERM)");
    env.bindFunction("ghostel--scroll", 2, 2, &fnScroll, "Scroll the terminal viewport by DELTA lines.\n\n(ghostel--scroll TERM DELTA)");
    env.bindFunction("ghostel--encode-key", 3, 4, &fnEncodeKey, "Encode a key event using the terminal's key encoder.\n\n(ghostel--encode-key TERM KEY MODS &optional UTF8)");

    env.provide("ghostel-module");
    return 0;
}

// ---------------------------------------------------------------------------
// Plugin version — required by Emacs >= 27
// ---------------------------------------------------------------------------

export const plugin_is_GPL_compatible: c_int = 0;

// ---------------------------------------------------------------------------
// Exported Elisp functions
// ---------------------------------------------------------------------------

/// (ghostel--new ROWS COLS &optional MAX-SCROLLBACK)
fn fnNew(raw_env: ?*c.emacs_env, nargs: isize, args: [*c]c.emacs_value, _: ?*anyopaque) callconv(.c) c.emacs_value {
    const env = emacs.Env.init(raw_env.?);
    const rows: u16 = @intCast(env.extractInteger(args[0]));
    const cols: u16 = @intCast(env.extractInteger(args[1]));
    const max_scrollback: usize = if (nargs > 2 and env.isNotNil(args[2]))
        @intCast(env.extractInteger(args[2]))
    else
        10000;

    const term = std.heap.c_allocator.create(Terminal) catch {
        env.signalError("ghostel: out of memory");
        return env.nil();
    };

    term.* = Terminal.init(cols, rows, max_scrollback) catch {
        std.heap.c_allocator.destroy(term);
        env.signalError("ghostel: failed to create terminal");
        return env.nil();
    };

    // Register callbacks
    term.setUserdata(term);
    term.setWritePty(&writePtyCallback);
    term.setBell(&bellCallback);
    term.setTitleChanged(&titleChangedCallback);

    // Set default colors (light gray on black)
    const default_fg = gt.ColorRgb{ .r = 204, .g = 204, .b = 204 };
    const default_bg = gt.ColorRgb{ .r = 0, .g = 0, .b = 0 };
    term.setColorForeground(&default_fg);
    term.setColorBackground(&default_bg);

    return env.makeUserPtr(&Terminal.emacsFinalize, term);
}

/// (ghostel--write-input TERM DATA)
fn fnWriteInput(raw_env: ?*c.emacs_env, _: isize, args: [*c]c.emacs_value, _: ?*anyopaque) callconv(.c) c.emacs_value {
    const env = emacs.Env.init(raw_env.?);
    const term = env.getUserPtr(Terminal, args[0]) orelse {
        env.signalError("ghostel: invalid terminal handle");
        return env.nil();
    };

    // Extract string data — try stack buffer first, fall back to alloc
    var stack_buf: [65536]u8 = undefined;
    var heap_buf: ?[]const u8 = null;
    defer if (heap_buf) |hb| std.heap.c_allocator.free(hb);

    const data = env.extractString(args[1], &stack_buf) orelse blk: {
        heap_buf = env.extractStringAlloc(args[1], std.heap.c_allocator);
        break :blk heap_buf;
    };

    if (data == null) {
        return env.nil();
    }

    // Stash env for callbacks
    term.env = env;
    defer term.env = null;

    term.vtWrite(data.?);
    return env.nil();
}

/// (ghostel--set-size TERM ROWS COLS)
fn fnSetSize(raw_env: ?*c.emacs_env, _: isize, args: [*c]c.emacs_value, _: ?*anyopaque) callconv(.c) c.emacs_value {
    const env = emacs.Env.init(raw_env.?);
    const term = env.getUserPtr(Terminal, args[0]) orelse {
        env.signalError("ghostel: invalid terminal handle");
        return env.nil();
    };

    const rows: u16 = @intCast(env.extractInteger(args[1]));
    const cols: u16 = @intCast(env.extractInteger(args[2]));

    term.resize(cols, rows) catch {
        env.signalError("ghostel: resize failed");
        return env.nil();
    };

    return env.nil();
}

/// (ghostel--get-title TERM)
fn fnGetTitle(raw_env: ?*c.emacs_env, _: isize, args: [*c]c.emacs_value, _: ?*anyopaque) callconv(.c) c.emacs_value {
    const env = emacs.Env.init(raw_env.?);
    const term = env.getUserPtr(Terminal, args[0]) orelse return env.nil();

    if (term.getTitle()) |title| {
        return env.makeString(title);
    }
    return env.nil();
}

/// (ghostel--redraw TERM)
/// Reads the render state and updates the current Emacs buffer with styled text.
fn fnRedraw(raw_env: ?*c.emacs_env, _: isize, args: [*c]c.emacs_value, _: ?*anyopaque) callconv(.c) c.emacs_value {
    const env = emacs.Env.init(raw_env.?);
    const term = env.getUserPtr(Terminal, args[0]) orelse return env.nil();
    render.redraw(env, term);
    return env.nil();
}

/// (ghostel--scroll TERM DELTA)
fn fnScroll(raw_env: ?*c.emacs_env, _: isize, args: [*c]c.emacs_value, _: ?*anyopaque) callconv(.c) c.emacs_value {
    const env = emacs.Env.init(raw_env.?);
    const term = env.getUserPtr(Terminal, args[0]) orelse return env.nil();

    const delta = env.extractInteger(args[1]);
    term.scrollViewport(gt.SCROLL_DELTA, @intCast(delta));

    return env.nil();
}

/// (ghostel--encode-key TERM KEY MODS &optional UTF8)
/// Encode a key event and send it to the PTY.
/// KEY is a key name string (e.g. "a", "return", "up", "f1").
/// MODS is a modifier string (e.g. "ctrl", "shift,ctrl", "").
/// UTF8 is optional text generated by the key (e.g. "a" for the 'a' key).
fn fnEncodeKey(raw_env: ?*c.emacs_env, nargs: isize, args: [*c]c.emacs_value, _: ?*anyopaque) callconv(.c) c.emacs_value {
    const env = emacs.Env.init(raw_env.?);
    const term = env.getUserPtr(Terminal, args[0]) orelse return env.nil();

    // Extract key name
    var key_buf: [64]u8 = undefined;
    const key_name = env.extractString(args[1], &key_buf) orelse return env.nil();

    // Extract modifiers
    var mod_buf: [64]u8 = undefined;
    const mod_str = env.extractString(args[2], &mod_buf) orelse "";

    // Extract optional UTF-8 text
    var utf8_buf: [32]u8 = undefined;
    const utf8: ?[]const u8 = if (nargs > 3 and env.isNotNil(args[3]))
        env.extractString(args[3], &utf8_buf)
    else
        null;

    const key = input.mapKey(key_name);
    const mods = input.parseMods(mod_str);

    if (input.encodeAndSend(env, term, key, mods, utf8)) {
        return env.t();
    }
    return env.nil();
}

// ---------------------------------------------------------------------------
// Ghostty callbacks — invoked synchronously during vtWrite
// ---------------------------------------------------------------------------

/// Called when the terminal needs to write response data back to the PTY.
fn writePtyCallback(_: gt.Terminal, userdata: ?*anyopaque, data: [*c]const u8, len: usize) callconv(.c) void {
    const term: *Terminal = @ptrCast(@alignCast(userdata));
    const env = term.env orelse return;

    if (len == 0) return;
    const str = env.makeString(data[0..len]);
    _ = env.call1(env.intern("ghostel--flush-output"), str);
}

/// Called when the terminal receives BEL.
fn bellCallback(_: gt.Terminal, userdata: ?*anyopaque) callconv(.c) void {
    const term: *Terminal = @ptrCast(@alignCast(userdata));
    const env = term.env orelse return;

    _ = env.call0(env.intern("ding"));
}

/// Called when the terminal title changes.
fn titleChangedCallback(_: gt.Terminal, userdata: ?*anyopaque) callconv(.c) void {
    const term: *Terminal = @ptrCast(@alignCast(userdata));
    const env = term.env orelse return;

    if (term.getTitle()) |title| {
        _ = env.call1(env.intern("ghostel--set-title"), env.makeString(title));
    }
}
