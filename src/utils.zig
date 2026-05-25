const gt = @import("ghostty-vt");

pub fn parseHexByte(hi: u8, lo: u8) ?u8 {
    const h = hexDigit(hi) orelse return null;
    const l = hexDigit(lo) orelse return null;
    return (h << 4) | l;
}

pub fn hexDigit(ch: u8) ?u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    return null;
}

/// Parse a "#RRGGBB" hex color string into a ColorRgb.
pub fn parseHexColor(s: []const u8) ?gt.color.RGB {
    if (s.len < 7 or s[0] != '#') return null;
    const r = parseHexByte(s[1], s[2]) orelse return null;
    const g = parseHexByte(s[3], s[4]) orelse return null;
    const b = parseHexByte(s[5], s[6]) orelse return null;
    return .{ .r = r, .g = g, .b = b };
}
