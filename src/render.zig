// Kizamu — TUI rendering with theme support.
const std = @import("std");
const vaxis = @import("vaxis");
const game_mod = @import("game.zig");
const words_mod = @import("words.zig");

const Game = game_mod.Game;
const Segment = vaxis.Segment;
const Style = vaxis.Style;
const Color = vaxis.Color;
const Window = vaxis.Window;

// ─── Theme System ─────────────────────────────────────────────────────────────

pub const Theme = struct {
    name: []const u8,
    accent: Color,
    accent2: Color,
    correct: Color,
    error_c: Color,
    dim: Color,
    dim2: Color,
    fg: Color,
    gold: Color,
    gold2: Color,
    magenta: Color,
    bg: Color,
    mid: Color,
    mid2: Color,
    sep: Color,
};

const tokyo_night = Theme{
    .name    = "Tokyo Night",
    .accent  = .{ .rgb = .{ 125, 207, 255 } },
    .accent2 = .{ .rgb = .{ 122, 162, 247 } },
    .correct = .{ .rgb = .{ 158, 206, 106 } },
    .error_c = .{ .rgb = .{ 247, 118, 142 } },
    .dim     = .{ .rgb = .{  86,  95, 137 } },
    .dim2    = .{ .rgb = .{  52,  56,  80 } },
    .fg      = .{ .rgb = .{ 192, 202, 245 } },
    .gold    = .{ .rgb = .{ 224, 175, 104 } },
    .gold2   = .{ .rgb = .{ 255, 158, 100 } },
    .magenta = .{ .rgb = .{ 187, 154, 247 } },
    .bg      = .{ .rgb = .{  26,  27,  38 } },
    .mid     = .{ .rgb = .{  36,  40,  59 } },
    .mid2    = .{ .rgb = .{  52,  59,  88 } },
    .sep     = .{ .rgb = .{  59,  66,  97 } },
};

const catppuccin = Theme{
    .name    = "Catppuccin",
    .accent  = .{ .rgb = .{ 137, 220, 235 } },
    .accent2 = .{ .rgb = .{ 180, 190, 254 } },
    .correct = .{ .rgb = .{ 166, 227, 161 } },
    .error_c = .{ .rgb = .{ 243, 139, 168 } },
    .dim     = .{ .rgb = .{ 108, 112, 134 } },
    .dim2    = .{ .rgb = .{  69,  71,  90 } },
    .fg      = .{ .rgb = .{ 205, 214, 244 } },
    .gold    = .{ .rgb = .{ 249, 226, 175 } },
    .gold2   = .{ .rgb = .{ 250, 179, 135 } },
    .magenta = .{ .rgb = .{ 245, 194, 231 } },
    .bg      = .{ .rgb = .{  30,  30,  46 } },
    .mid     = .{ .rgb = .{  49,  50,  68 } },
    .mid2    = .{ .rgb = .{  58,  60,  78 } },
    .sep     = .{ .rgb = .{  88,  91, 112 } },
};

const gruvbox = Theme{
    .name    = "Gruvbox",
    .accent  = .{ .rgb = .{ 131, 165, 152 } },
    .accent2 = .{ .rgb = .{  69, 133, 136 } },
    .correct = .{ .rgb = .{ 184, 187,  38 } },
    .error_c = .{ .rgb = .{ 204,  36,  29 } },
    .dim     = .{ .rgb = .{ 102,  92,  84 } },
    .dim2    = .{ .rgb = .{  80,  73,  69 } },
    .fg      = .{ .rgb = .{ 235, 219, 178 } },
    .gold    = .{ .rgb = .{ 250, 189,  47 } },
    .gold2   = .{ .rgb = .{ 214,  93,  14 } },
    .magenta = .{ .rgb = .{ 211, 134, 155 } },
    .bg      = .{ .rgb = .{  40,  40,  40 } },
    .mid     = .{ .rgb = .{  60,  56,  54 } },
    .mid2    = .{ .rgb = .{  80,  73,  69 } },
    .sep     = .{ .rgb = .{ 102,  92,  84 } },
};

const nord = Theme{
    .name    = "Nord",
    .accent  = .{ .rgb = .{ 136, 192, 208 } },
    .accent2 = .{ .rgb = .{ 129, 161, 193 } },
    .correct = .{ .rgb = .{ 163, 190, 140 } },
    .error_c = .{ .rgb = .{ 191,  97, 106 } },
    .dim     = .{ .rgb = .{  76,  86, 106 } },
    .dim2    = .{ .rgb = .{  59,  66,  82 } },
    .fg      = .{ .rgb = .{ 236, 239, 244 } },
    .gold    = .{ .rgb = .{ 235, 203, 139 } },
    .gold2   = .{ .rgb = .{ 208, 135, 112 } },
    .magenta = .{ .rgb = .{ 180, 142, 173 } },
    .bg      = .{ .rgb = .{  46,  52,  64 } },
    .mid     = .{ .rgb = .{  59,  66,  82 } },
    .mid2    = .{ .rgb = .{  67,  76,  94 } },
    .sep     = .{ .rgb = .{  76,  86, 106 } },
};

pub const THEMES = [_]Theme{ tokyo_night, catppuccin, gruvbox, nord };
pub const THEME_COUNT = THEMES.len;

// ─── Style derivation ─────────────────────────────────────────────────────────

const Styles = struct {
    accent: Style,
    accent_bold: Style,
    accent2: Style,
    correct: Style,
    correct_bold: Style,
    err: Style,
    err_ul: Style,
    dim: Style,
    dim2: Style,
    fg: Style,
    gold: Style,
    gold_bold: Style,
    gold2: Style,
    sep: Style,
    cursor: Style,
    key: Style,
    magenta: Style,
    mid_bg: Style,
    mid2_bg: Style,
    warn: Style,
};

fn makeStyles(t: Theme) Styles {
    return .{
        .accent       = .{ .fg = t.accent },
        .accent_bold  = .{ .fg = t.accent,   .bold = true },
        .accent2      = .{ .fg = t.accent2 },
        .correct      = .{ .fg = t.correct },
        .correct_bold = .{ .fg = t.correct,  .bold = true },
        .err          = .{ .fg = t.error_c },
        .err_ul       = .{ .fg = t.error_c,  .ul_style = .curly, .ul = t.error_c },
        .dim          = .{ .fg = t.dim },
        .dim2         = .{ .fg = t.dim2 },
        .fg           = .{ .fg = t.fg },
        .gold         = .{ .fg = t.gold },
        .gold_bold    = .{ .fg = t.gold,     .bold = true },
        .gold2        = .{ .fg = t.gold2 },
        .sep          = .{ .fg = t.sep },
        .cursor       = .{ .fg = t.bg,       .bg = t.accent, .bold = true },
        .key          = .{ .fg = t.gold,     .bold = true },
        .magenta      = .{ .fg = t.magenta },
        .mid_bg       = .{ .bg = t.mid },
        .mid2_bg      = .{ .bg = t.mid2 },
        .warn         = .{ .fg = t.gold2,    .bold = true },
    };
}

// ─── Sparkline ────────────────────────────────────────────────────────────────

const SPARK = [_][]const u8{
    " ",
    "\xe2\x96\x81", // ▁
    "\xe2\x96\x82", // ▂
    "\xe2\x96\x83", // ▃
    "\xe2\x96\x84", // ▄
    "\xe2\x96\x85", // ▅
    "\xe2\x96\x86", // ▆
    "\xe2\x96\x87", // ▇
    "\xe2\x96\x88", // █
};

fn drawSparkline(win: Window, col: u16, row: u16, width: u16, samples: []const f32, s: Styles) void {
    if (samples.len == 0 or width == 0) return;
    var max_v: f32 = 10.0;
    for (samples) |v| if (v > max_v) { max_v = v; };
    const n = @min(samples.len, @as(usize, width));
    const start = if (samples.len > n) samples.len - n else 0;
    for (0..n) |i| {
        const v = samples[start + i];
        const ratio = v / max_v;
        const idx: usize = @intFromFloat(@min(8.0, ratio * 8.0 + 0.5));
        const style: Style = if (idx >= 7) s.accent_bold
                             else if (idx >= 5) s.accent
                             else if (idx >= 3) s.gold
                             else s.dim;
        win.writeCell(col + @as(u16, @intCast(i)), row, .{
            .char = .{ .grapheme = SPARK[idx], .width = 1 },
            .style = style,
        });
    }
}

// ─── Digit / string helpers ───────────────────────────────────────────────────

const DIGITS = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" };

const ASCII = blk: {
    @setEvalBranchQuota(256);
    var arr: [128][1]u8 = undefined;
    for (0..128) |i| arr[i] = .{@intCast(i)};
    break :blk arr;
};

fn asciiG(ch: u8) []const u8 {
    if (ch >= 128) return "?";
    return &ASCII[ch];
}

fn numWidth(val: u64) u16 {
    if (val == 0) return 1;
    var w: u16 = 0;
    var v = val;
    while (v > 0) : (w += 1) v /= 10;
    return w;
}

fn writeU64(win: Window, col: u16, row: u16, val: u64, style: Style) u16 {
    const w = numWidth(val);
    if (val == 0) {
        win.writeCell(col, row, .{ .char = .{ .grapheme = DIGITS[0], .width = 1 }, .style = style });
        return 1;
    }
    var v = val;
    var i: u16 = w;
    while (i > 0) {
        i -= 1;
        win.writeCell(col + i, row, .{
            .char = .{ .grapheme = DIGITS[@intCast(v % 10)], .width = 1 },
            .style = style,
        });
        v /= 10;
    }
    return w;
}

fn writeFixed1(win: Window, col: u16, row: u16, int_part: u64, dec_part: u64, style: Style) u16 {
    var c: u16 = 0;
    c += writeU64(win, col + c, row, int_part, style);
    win.writeCell(col + c, row, .{ .char = .{ .grapheme = ".", .width = 1 }, .style = style });
    c += 1;
    c += writeU64(win, col + c, row, dec_part, style);
    return c;
}

fn fixed1Width(int_part: u64, dec_part: u64) u16 {
    return numWidth(int_part) + 1 + numWidth(dec_part);
}

fn splitFixed1(val: f64, clamp_max: f64) struct { i: u64, d: u64 } {
    const safe: f64 = if (std.math.isFinite(val) and val >= 0.0) @min(val, clamp_max) else 0.0;
    const x10: u64 = @intFromFloat(safe * 10.0 + 0.5);
    return .{ .i = x10 / 10, .d = x10 % 10 };
}

fn writeStr(win: Window, col: u16, row: u16, text: []const u8, style: Style) u16 {
    _ = win.print(&[_]Segment{.{ .text = text, .style = style }}, .{
        .row_offset = row,
        .col_offset = col,
        .wrap = .none,
    });
    return @intCast(text.len);
}

fn print1(win: Window, col: u16, row: u16, text: []const u8, style: Style) void {
    _ = win.print(&[_]Segment{.{ .text = text, .style = style }}, .{
        .row_offset = row,
        .col_offset = col,
        .wrap = .none,
    });
}

fn fillRow(win: Window, row: u16, style: Style) void {
    var c: u16 = 0;
    while (c < win.width) : (c += 1) {
        win.writeCell(c, row, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = style });
    }
}

fn drawSep(win: Window, col: u16, row: u16, width: u16, style: Style) void {
    var i: u16 = 0;
    while (i < width) : (i += 1) {
        win.writeCell(col + i, row, .{
            .char = .{ .grapheme = "\xe2\x94\x80", .width = 1 }, // ─
            .style = style,
        });
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MENU SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

pub fn drawMenu(
    win: Window,
    cursor: usize,
    diff_cursor: usize,
    cat_cursor: usize,
    theme_idx: usize,
    frame: u32,
) void {
    const t = THEMES[theme_idx % THEME_COUNT];
    const s = makeStyles(t);

    const BOX_W: u16 = 56;
    const BOX_H: u16 = 30;
    const actual_w: u16 = @min(BOX_W, win.width -| 2);
    const actual_h: u16 = @min(BOX_H, win.height -| 2);
    if (actual_w < 32 or actual_h < 12) return;

    const bx: u16 = (win.width -| actual_w) / 2;
    const by: u16 = (win.height -| actual_h) / 2;

    const border_style = if (cursor >= 10) s.magenta else s.accent;
    const box = win.child(.{
        .x_off = bx,
        .y_off = by,
        .width = actual_w,
        .height = actual_h,
        .border = .{ .where = .all, .glyphs = .single_rounded, .style = border_style },
    });

    // ── Animated title ──────────────────────────────────────────────────────
    {
        const lcols = [_]u16{ 4, 8, 12, 16, 20, 24 };
        const letters = "KIZAMU";
        const WAVE: u32 = 18;
        const wave_pos = frame % WAVE;
        for (lcols, 0..) |lc, li| {
            const peak: u32 = @as(u32, @intCast(li)) * 3;
            const dist = @min(
                (wave_pos + WAVE - peak) % WAVE,
                (peak + WAVE - wave_pos) % WAVE,
            );
            const col: Color = if (dist == 0) t.gold
                               else if (dist <= 1) t.accent
                               else if (dist <= 3) t.fg
                               else t.dim;
            print1(box, lc, 1, letters[li .. li + 1], .{ .fg = col, .bold = dist <= 2 });
        }
        const sep_cols = [_]u16{ 6, 10, 14, 18, 22 };
        for (sep_cols) |sc| print1(box, sc, 1, ".", s.dim);
        print1(box, 4, 2, "typing practice", s.dim);
    }

    // Theme name (top right)
    {
        const tname = t.name;
        const tc: u16 = box.width -| @as(u16, @intCast(tname.len)) -| 2;
        print1(box, tc, 1, tname, s.dim);
        print1(box, tc -| 3, 2, "[t]", s.key);
    }

    drawSep(box, 0, 3, box.width, s.sep);

    // ── Category (w/s keys) ───────────────────────────────────────────────────
    if (actual_h > 5) {
        print1(box, 4, 4, "Category", s.dim);
        print1(box, 13, 4, "[w/s]", s.key);
        const catlabel = words_mod.categoryLabel(words_mod.ALL_CATEGORIES[cat_cursor]);
        const cdot: u16 = 20;
        print1(box, cdot, 4, "\xe2\x97\x82", s.accent); // ◂
        print1(box, cdot + 2, 4, catlabel, .{ .fg = t.accent2, .bold = true });
        print1(box, cdot + 2 + @as(u16, @intCast(catlabel.len)) + 1, 4, "\xe2\x96\xb8", s.accent); // ▸
        // dot indicators for category position
        if (box.width >= 50) {
            const ncat = words_mod.ALL_CATEGORIES.len;
            const dotc: u16 = box.width -| @as(u16, @intCast(ncat)) -| 3;
            for (0..ncat) |i| {
                const on = (i == cat_cursor);
                print1(box, dotc + @as(u16, @intCast(i)), 4, if (on) "\xe2\x97\x8f" else "\xe2\x97\x8b",
                    if (on) s.accent2 else s.dim2); // ● ○
            }
        }
    }

    // ── Difficulty (h/l keys) ─────────────────────────────────────────────────
    if (actual_h > 6) {
        print1(box, 4, 5, "Difficulty", s.dim);
        print1(box, 15, 5, "[h/l]", s.key);
        const dlabel = game_mod.ALL_DIFFICULTIES[diff_cursor].label();
        const ddot: u16 = 22;
        print1(box, ddot, 5, "\xe2\x97\x82", s.accent);
        print1(box, ddot + 2, 5, dlabel, .{ .fg = t.magenta, .bold = true });
        print1(box, ddot + 2 + @as(u16, @intCast(dlabel.len)) + 1, 5, "\xe2\x96\xb8", s.accent);
        if (box.width >= 50) {
            const ndiff = game_mod.ALL_DIFFICULTIES.len;
            const dotc: u16 = box.width -| @as(u16, @intCast(ndiff)) -| 3;
            for (0..ndiff) |i| {
                const on = (i == diff_cursor);
                print1(box, dotc + @as(u16, @intCast(i)), 5, if (on) "\xe2\x97\x8f" else "\xe2\x97\x8b",
                    if (on) s.magenta else s.dim2);
            }
        }
    }

    drawSep(box, 0, 6, box.width, s.sep);

    // ── WORD COUNT ──────────────────────────────────────────────────────────
    if (actual_h > 8) {
        print1(box, 4, 7, "WORD COUNT", s.accent2);
        const word_labels = [_][]const u8{ "10", "25", "50", "100", "200", "500" };
        for (0..6) |i| {
            const row: u16 = @as(u16, @intCast(i)) + 8;
            if (row >= actual_h -| 3) break;
            const selected = (i == cursor);
            if (selected) {
                fillRow(box, row, s.mid_bg);
                print1(box, 4, row, ">", s.accent_bold);
                print1(box, 6, row, word_labels[i], .{ .fg = t.gold, .bg = t.mid, .bold = true });
                print1(box, 6 + @as(u16, @intCast(word_labels[i].len)), row, " words",
                    .{ .fg = t.fg, .bg = t.mid, .bold = true });
            } else {
                print1(box, 6, row, word_labels[i], s.dim);
                print1(box, 6 + @as(u16, @intCast(word_labels[i].len)), row, " words", s.dim);
            }
        }
    }

    // ── TIMED ───────────────────────────────────────────────────────────────
    if (actual_h > 16) {
        print1(box, 4, 15, "TIMED", s.accent2);
        const time_labels = [_][]const u8{ "15", "30", "60", "120" };
        const time_suffixes = [_][]const u8{ " sec", " sec", " sec", " sec" };
        for (0..4) |i| {
            const row: u16 = @as(u16, @intCast(i)) + 16;
            if (row >= actual_h -| 3) break;
            const selected = (i + 6 == cursor);
            if (selected) {
                fillRow(box, row, s.mid_bg);
                print1(box, 4, row, ">", s.accent_bold);
                print1(box, 6, row, time_labels[i], .{ .fg = t.gold, .bg = t.mid, .bold = true });
                print1(box, 6 + @as(u16, @intCast(time_labels[i].len)), row, time_suffixes[i],
                    .{ .fg = t.fg, .bg = t.mid, .bold = true });
            } else {
                print1(box, 6, row, time_labels[i], s.dim);
                print1(box, 6 + @as(u16, @intCast(time_labels[i].len)), row, time_suffixes[i], s.dim);
            }
        }
    }

    // ── CHALLENGES ──────────────────────────────────────────────────────────
    if (actual_h > 22) {
        print1(box, 4, 21, "CHALLENGES", s.accent2);
        const ch_keys    = [_][]const u8{ "z", "d", "a", "x" };
        const ch_labels  = [_][]const u8{ "Zen", "Sudden Death", "Accuracy Rush", "Reverse" };
        const ch_descs   = [_][]const u8{
            "endless flow",
            "wrong word = over",
            "<85% acc = over",
            "words backwards!",
        };
        const ch_colors  = [_]Color{ t.accent, t.error_c, t.gold2, t.magenta };
        for (0..4) |i| {
            const row: u16 = @as(u16, @intCast(i)) + 22;
            if (row >= actual_h -| 3) break;
            const selected = (i + 10 == cursor);
            const lstart: u16 = 9;
            if (selected) {
                fillRow(box, row, s.mid_bg);
                print1(box, 4, row, ">", s.accent_bold);
                print1(box, 6, row, ch_keys[i], .{ .fg = t.gold, .bg = t.mid, .bold = true });
                print1(box, lstart, row, ch_labels[i], .{ .fg = ch_colors[i], .bg = t.mid, .bold = true });
                print1(box, lstart + @as(u16, @intCast(ch_labels[i].len)) + 2, row, ch_descs[i],
                    .{ .fg = t.dim, .bg = t.mid });
            } else {
                print1(box, 6, row, ch_keys[i], s.dim);
                print1(box, lstart, row, ch_labels[i], .{ .fg = ch_colors[i] });
                print1(box, lstart + @as(u16, @intCast(ch_labels[i].len)) + 2, row, ch_descs[i], s.dim);
            }
        }
    }

    // ── Help text ───────────────────────────────────────────────────────────
    const help_row: u16 = actual_h -| 3;
    if (help_row > 10) {
        drawSep(box, 0, help_row, box.width, s.sep);
        print1(box, 4, help_row + 1, "j/k", s.key);
        print1(box, 7, help_row + 1, " mode ", s.dim);
        print1(box, 13, help_row + 1, "h/l", s.key);
        print1(box, 16, help_row + 1, " diff ", s.dim);
        print1(box, 22, help_row + 1, "w/s", s.key);
        print1(box, 25, help_row + 1, " cat ", s.dim);
        print1(box, 30, help_row + 1, "t", s.key);
        print1(box, 31, help_row + 1, " theme", s.dim);
        print1(box, 4, help_row + 2, "1-9", s.key);
        print1(box, 7, help_row + 2, " modes ", s.dim);
        print1(box, 14, help_row + 2, "z d a x", s.key);
        print1(box, 21, help_row + 2, " chal ", s.dim);
        print1(box, 31, help_row + 2, "Esc", s.key);
        print1(box, 34, help_row + 2, " quit", s.dim);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TYPING SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

pub fn drawTyping(win: Window, game: *const Game, theme_idx: usize, frame: u32) void {
    const t = THEMES[theme_idx % THEME_COUNT];
    const s = makeStyles(t);

    if (win.width < 25 or win.height < 10) return;

    // Dynamic side margin: proportional on wide terminals
    const mx: u16 = @max(2, @min(8, win.width / 16));
    const w: u16 = win.width -| mx * 2;

    // ── Header background ────────────────────────────────────────────────────
    for (0..win.width) |c| {
        win.writeCell(@intCast(c), 0, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = s.mid2_bg });
    }

    // Title + mode info
    print1(win, mx, 0, "KIZAMU", s.accent_bold);
    print1(win, mx + 7, 0, "|", s.dim2);

    var hcol: u16 = mx + 9;

    // Challenge badge
    if (game.mode.isChallenge()) {
        const badge_style: Style = switch (game.mode) {
            .sudden_death => .{ .fg = t.error_c, .bold = true },
            .accuracy_rush => .{ .fg = t.gold2,  .bold = true },
            .zen           => .{ .fg = t.accent,  .bold = true },
            .reverse       => .{ .fg = t.magenta, .bold = true },
            else => s.dim,
        };
        const badge = game.mode.label();
        print1(win, hcol, 0, badge, badge_style);
        hcol += @as(u16, @intCast(badge.len)) + 2;
        print1(win, hcol -| 1, 0, "|", s.dim2);
    } else {
        const ml = game.mode.label();
        print1(win, hcol, 0, ml, s.dim);
        hcol += @as(u16, @intCast(ml.len)) + 2;
        print1(win, hcol -| 1, 0, "|", s.dim2);
    }

    const cl = words_mod.categoryLabel(game.category);
    print1(win, hcol, 0, cl, s.magenta);
    hcol += @as(u16, @intCast(cl.len)) + 2;
    print1(win, hcol -| 1, 0, "|", s.dim2);

    const dl = game.difficulty.label();
    print1(win, hcol, 0, dl, s.fg);

    // ── Live stats ───────────────────────────────────────────────────────────
    drawLiveStats(win, game, mx, s, t);

    // ── Live speed gauge + streak (left of row 1) ─────────────────────────────
    drawSpeedGauge(win, game, mx, 1, s, t, frame);

    // ── Separators and word area ─────────────────────────────────────────────
    drawSep(win, mx, 2, w, s.sep);

    const words_top: u16 = 4;
    const words_bottom: u16 = win.height -| 5;
    const words_h: u16 = if (words_bottom > words_top) words_bottom - words_top else 3;

    const words_win = win.child(.{
        .x_off = mx,
        .y_off = words_top,
        .width = w,
        .height = words_h,
    });
    drawWords(words_win, game, s, t, frame);

    drawSep(win, mx, win.height -| 4, w, s.sep);
    drawProgress(win, game, mx, win.height -| 2, w, s, t);
}

fn drawSpeedGauge(win: Window, game: *const Game, mx: u16, row: u16, s: Styles, t: Theme, frame: u32) void {
    if (win.width < 60 or game.start_time == null) return;

    const iw = game.instantWpm();
    const GW: u16 = 10;
    const maxw: f64 = 150.0;
    const ratio = @min(1.0, iw / maxw);
    const filled: u16 = @intFromFloat(ratio * @as(f64, @floatFromInt(GW)) + 0.0001);

    var c: u16 = mx;
    c += writeStr(win, c, row, "SPD ", s.dim);
    var i: u16 = 0;
    while (i < GW) : (i += 1) {
        const on = i < filled;
        const frac = (@as(f64, @floatFromInt(i)) + 0.5) / @as(f64, @floatFromInt(GW));
        const col: Color = if (!on) t.dim2
            else if (frac < 0.4) t.correct
            else if (frac < 0.7) t.gold
            else t.gold2;
        print1(win, c + i, row, if (on) "\xe2\x96\xb0" else "\xe2\x96\xb1", .{ .fg = col, .bold = on }); // ▰ ▱
    }
    c += GW + 1;

    // Tier label — pulses while blazing fast.
    const Tier = struct { label: []const u8, col: Color, blaze: bool };
    const tier: Tier = if (iw < 15) .{ .label = "...",     .col = t.dim,     .blaze = false }
        else if (iw < 45)  .{ .label = "warm",    .col = t.dim,     .blaze = false }
        else if (iw < 75)  .{ .label = "good",    .col = t.correct, .blaze = false }
        else if (iw < 105) .{ .label = "fast",    .col = t.gold,    .blaze = false }
        else if (iw < 135) .{ .label = "FAST",    .col = t.gold2,   .blaze = false }
        else               .{ .label = "BLAZING", .col = t.error_c, .blaze = true };
    const pulse_on = (frame / 3) % 2 == 0;
    const lstyle: Style = if (tier.blaze)
        .{ .fg = if (pulse_on) t.error_c else t.gold2, .bold = true }
    else
        .{ .fg = tier.col, .bold = iw >= 75 };
    c += writeStr(win, c, row, tier.label, lstyle);

    // Streak counter (only on wider terminals).
    if (game.streak >= 5 and win.width >= 78) {
        c += 2;
        const hot = game.streak >= 20;
        const sstyle: Style = if (hot) .{ .fg = t.gold, .bold = true } else .{ .fg = t.accent2 };
        c += writeStr(win, c, row, "\xc3\x97", sstyle); // ×
        _ = writeU64(win, c, row, @intCast(game.streak), sstyle);
    }
}

fn drawLiveStats(win: Window, game: *const Game, mx: u16, s: Styles, t: Theme) void {
    _ = t;
    if (game.start_time == null) {
        const label = "WPM -- | Acc --%";
        print1(win, win.width -| @as(u16, @intCast(label.len)) -| mx, 1, label, s.dim);
        return;
    }

    const wpm_v = splitFixed1(game.wpm(), 9999.0);
    const acc_v = splitFixed1(game.accuracy(), 100.0);
    const show_cpm = win.width > 80;

    // Accuracy style: warn when low in accuracy_rush mode
    const acc_style: Style = if (game.mode == .accuracy_rush and game.accuracy() < 90.0)
        s.warn
    else
        s.gold;

    // Build right-aligned stats
    var total_w: u16 = 0;
    total_w += 4; // "WPM "
    total_w += fixed1Width(wpm_v.i, wpm_v.d);
    if (show_cpm) {
        const cpm_v = splitFixed1(game.cpm(), 9999.0);
        total_w += 7; // " | CPM "
        total_w += fixed1Width(cpm_v.i, cpm_v.d);
    }
    total_w += 7; // " | Acc "
    total_w += fixed1Width(acc_v.i, acc_v.d);
    total_w += 4; // "% | "

    if (game.mode.isTimed()) {
        const rem_s: u64 = @intCast(@max(0, @divTrunc(game.remainingMs(), 1000)));
        total_w += numWidth(rem_s) + 6; // "s left"
        const sc = win.width -| total_w -| mx;
        var c: u16 = sc;
        c += writeStr(win, c, 1, "WPM ", s.gold);
        c += writeFixed1(win, c, 1, wpm_v.i, wpm_v.d, s.gold);
        if (show_cpm) {
            const cpm_v = splitFixed1(game.cpm(), 9999.0);
            c += writeStr(win, c, 1, " | CPM ", s.gold);
            c += writeFixed1(win, c, 1, cpm_v.i, cpm_v.d, s.gold);
        }
        c += writeStr(win, c, 1, " | Acc ", acc_style);
        c += writeFixed1(win, c, 1, acc_v.i, acc_v.d, acc_style);
        const time_style: Style = if (rem_s <= 5) s.err else if (rem_s <= 10) s.gold2 else s.gold;
        c += writeStr(win, c, 1, "% | ", acc_style);
        c += writeU64(win, c, 1, rem_s, time_style);
        _ = writeStr(win, c, 1, "s left", time_style);
    } else {
        const elapsed_ms = game.elapsedMs();
        const t_s: u64 = @intCast(@divTrunc(elapsed_ms, 1000));
        const t_d: u64 = @intCast(@divTrunc(@rem(elapsed_ms, 1000), 100));
        total_w += numWidth(t_s) + 1 + numWidth(t_d) + 1; // "X.Xs"
        const sc = win.width -| total_w -| mx;
        var c: u16 = sc;
        c += writeStr(win, c, 1, "WPM ", s.gold);
        c += writeFixed1(win, c, 1, wpm_v.i, wpm_v.d, s.gold);
        if (show_cpm) {
            const cpm_v = splitFixed1(game.cpm(), 9999.0);
            c += writeStr(win, c, 1, " | CPM ", s.gold);
            c += writeFixed1(win, c, 1, cpm_v.i, cpm_v.d, s.gold);
        }
        c += writeStr(win, c, 1, " | Acc ", acc_style);
        c += writeFixed1(win, c, 1, acc_v.i, acc_v.d, acc_style);
        c += writeStr(win, c, 1, "% | ", acc_style);
        c += writeU64(win, c, 1, t_s, s.gold);
        c += writeStr(win, c, 1, ".", s.gold);
        c += writeU64(win, c, 1, t_d, s.gold);
        _ = writeStr(win, c, 1, "s", s.gold);
    }
}

fn drawProgress(win: Window, game: *const Game, mx: u16, row: u16, avail_w: u16, s: Styles, t: Theme) void {
    const BAR_W: u16 = @min(28, avail_w / 2);

    if (game.mode == .zen) {
        // Zen: simple word counter, no pressure
        var c: u16 = mx;
        c += writeStr(win, c, row, "word ", s.dim2);
        c += writeU64(win, c, row, @intCast(game.current_word), s.dim);
        c += writeStr(win, c, row, "/500", s.dim2);
        return;
    }

    if (game.mode.isTimed()) {
        const limit = game.mode.timeLimitMs();
        const elapsed = game.elapsedMs();
        const filled: u16 = if (limit > 0)
            @intCast(@min(BAR_W, @as(u64, @intCast(@max(0, elapsed))) * BAR_W / @as(u64, @intCast(limit))))
        else 0;
        const rem_s: u64 = @intCast(@max(0, @divTrunc(game.remainingMs(), 1000)));

        // For accuracy rush: bar color reflects accuracy level
        const bar_color: Color = if (game.mode == .accuracy_rush) blk: {
            const acc = game.accuracy();
            break :blk if (acc < 87.0) t.error_c
                        else if (acc < 92.0) t.gold2
                        else t.accent;
        } else blk: {
            break :blk if (rem_s <= 5) t.error_c
                        else if (rem_s <= 10) t.gold2
                        else t.accent;
        };

        var bi: u16 = 0;
        while (bi < BAR_W) : (bi += 1) {
            const glyph = if (bi < filled) "\xe2\x96\x88" else "\xe2\x96\x91"; // █ ░
            const gstyle: Style = if (bi < filled) .{ .fg = bar_color } else s.dim2;
            print1(win, mx + bi, row, glyph, gstyle);
        }
        var c: u16 = mx + BAR_W + 2;
        c += writeU64(win, c, row, rem_s, s.fg);
        _ = writeStr(win, c, row, "s left", s.dim);
    } else {
        const filled: u16 = if (game.word_count > 0)
            @intCast(@min(BAR_W, @as(u64, game.current_word) * BAR_W / game.word_count))
        else 0;

        var bi: u16 = 0;
        while (bi < BAR_W) : (bi += 1) {
            const glyph = if (bi < filled) "\xe2\x96\x88" else "\xe2\x96\x91";
            const gstyle: Style = if (bi < filled) s.accent else s.dim2;
            print1(win, mx + bi, row, glyph, gstyle);
        }
        var c: u16 = mx + BAR_W + 2;
        c += writeU64(win, c, row, @intCast(game.current_word), s.dim);
        c += writeStr(win, c, row, "/", s.dim2);
        _ = writeU64(win, c, row, @intCast(game.word_count), s.dim);
    }

    // Hints (right side)
    const HINT_W: u16 = 26;
    if (win.width > mx + HINT_W + 2) {
        const hcol = win.width -| mx -| HINT_W;
        print1(win, hcol, row, "[Tab]", s.key);
        print1(win, hcol + 5, row, " restart ", s.dim);
        print1(win, hcol + 13, row, "|", s.dim2);
        print1(win, hcol + 15, row, "[Esc]", s.key);
        print1(win, hcol + 20, row, " menu", s.dim);
    }
}

fn drawWords(words_win: Window, game: *const Game, s: Styles, t: Theme, frame: u32) void {
    if (words_win.width == 0 or words_win.height == 0) return;
    const ww: u16 = words_win.width;

    // Pulsing cursor for a livelier feel.
    const cursor_st: Style = if ((frame / 5) % 2 == 0)
        s.cursor
    else
        .{ .fg = t.bg, .bg = t.accent2, .bold = true };

    var layout_row: [game_mod.MAX_WORDS]u16 = .{0} ** game_mod.MAX_WORDS;
    var layout_col: [game_mod.MAX_WORDS]u16 = .{0} ** game_mod.MAX_WORDS;
    {
        var cur_col: u16 = 0;
        var cur_row: u16 = 0;
        for (0..game.word_count) |wi| {
            const wlen: u16 = @intCast(game.words[wi].len);
            if (cur_col > 0 and cur_col + wlen > ww) {
                cur_row += 1;
                cur_col = 0;
            }
            layout_row[wi] = cur_row;
            layout_col[wi] = cur_col;
            cur_col += wlen + 1;
        }
    }

    const cur_layout_row = layout_row[game.current_word];
    const scroll: u16 = if (cur_layout_row >= 1) cur_layout_row - 1 else 0;

    for (0..game.word_count) |wi| {
        const lr = layout_row[wi];
        if (lr < scroll) continue;
        const vis_row = lr - scroll;
        if (vis_row >= words_win.height) continue;

        const lc = layout_col[wi];
        const word = game.words[wi];

        if (wi < game.current_word) {
            const st = if (game.word_correct[wi]) s.correct else s.err;
            print1(words_win, lc, vis_row, word, st);
        } else if (wi == game.current_word) {
            for (0..word.len) |ci| {
                const colu: u16 = lc + @as(u16, @intCast(ci));
                if (ci < game.input_len) {
                    const st = if (game.input_buf[ci] == word[ci]) s.correct else s.err_ul;
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], st);
                } else if (ci == game.input_len) {
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], cursor_st);
                } else {
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], s.fg);
                }
            }
            var ei: usize = word.len;
            while (ei < game.input_len and ei < game_mod.MAX_INPUT) : (ei += 1) {
                const colu: u16 = lc + @as(u16, @intCast(ei));
                if (colu < words_win.width)
                    print1(words_win, colu, vis_row, game.input_buf[ei .. ei + 1], s.err_ul);
            }
            if (game.input_len == word.len) {
                const colu: u16 = lc + @as(u16, @intCast(word.len));
                if (colu < words_win.width)
                    print1(words_win, colu, vis_row, " ", cursor_st);
            }
        } else {
            print1(words_win, lc, vis_row, word, s.dim);
        }
    }

    if (game.start_time == null) {
        const hint_row = if (words_win.height > 1) words_win.height - 1 else 0;
        print1(words_win, 0, hint_row, "Start typing to begin...", s.dim2);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESULTS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

pub fn drawResults(win: Window, game: *const Game, theme_idx: usize, frame: u32) void {
    const t = THEMES[theme_idx % THEME_COUNT];
    const s = makeStyles(t);

    const BOX_W: u16 = 56;
    const BOX_H: u16 = 28;
    const actual_w: u16 = @min(BOX_W, win.width -| 2);
    const actual_h: u16 = @min(BOX_H, win.height -| 2);
    if (actual_w < 32 or actual_h < 12) return;

    const bx: u16 = (win.width -| actual_w) / 2;
    const by: u16 = (win.height -| actual_h) / 2;

    const border_style = switch (game.over_reason) {
        .normal => s.gold,
        .sudden_death => s.err,
        .accuracy_fail => s.warn,
    };

    const box = win.child(.{
        .x_off = bx,
        .y_off = by,
        .width = actual_w,
        .height = actual_h,
        .border = .{ .where = .all, .glyphs = .single_rounded, .style = border_style },
    });

    // ── Title ────────────────────────────────────────────────────────────────
    const title: []const u8 = switch (game.over_reason) {
        .normal       => "RESULTS",
        .sudden_death => "FAILED — SUDDEN DEATH",
        .accuracy_fail => "FAILED — LOW ACCURACY",
    };
    const title_style: Style = switch (game.over_reason) {
        .normal => s.gold_bold,
        .sudden_death => Style{ .fg = t.error_c, .bold = true },
        .accuracy_fail => Style{ .fg = t.gold2,  .bold = true },
    };
    print1(box, 3, 1, title, title_style);

    // Mode + category top-right
    const ml = game.mode.label();
    print1(box, box.width -| @as(u16, @intCast(ml.len)) -| 2, 1, ml, s.dim);
    const cl = words_mod.categoryLabel(game.category);
    print1(box, 3, 2, cl, s.accent2);
    const dl = game.difficulty.label();
    print1(box, 3 + @as(u16, @intCast(cl.len)) + 2, 2, dl, s.dim);

    // Flashing NEW BEST banner (top-right of row 2).
    if (game.new_best and game.over_reason == .normal) {
        const banner = "\xe2\x98\x85 NEW BEST \xe2\x98\x85"; // ★ NEW BEST ★
        const bw: u16 = 12;
        const bcol: u16 = box.width -| bw -| 2;
        const on = (frame / 4) % 2 == 0;
        const bstyle: Style = .{ .fg = if (on) t.gold else t.gold2, .bold = true };
        if (bcol > @as(u16, @intCast(cl.len)) + 6)
            print1(box, bcol, 2, banner, bstyle);
    }

    if (actual_h <= 6) {
        // Tiny terminal: just show WPM
        const wpm_v = splitFixed1(game.wpm(), 9999.0);
        print1(box, 3, 3, "WPM", s.dim);
        _ = writeFixed1(box, 7, 3, wpm_v.i, wpm_v.d, s.gold_bold);
        return;
    }

    drawSep(box, 0, 3, box.width, s.sep);

    // ── Main stats ───────────────────────────────────────────────────────────
    const wpm_val  = game.wpm();
    const raw_val  = game.rawWpm();
    const acc_val  = game.accuracy();
    const cpm_val  = game.cpm();
    const cons_val = game.consistency();

    // WPM with mini bar
    print1(box, 3, 4, "WPM", s.dim);
    {
        const v = splitFixed1(wpm_val, 9999.0);
        const bar_w: u16 = @min(20, actual_w -| 20);
        const filled: u16 = @intCast(@min(bar_w, @as(u64, v.i) * bar_w / 200));
        var bi: u16 = 0;
        while (bi < bar_w) : (bi += 1) {
            const glyph = if (bi < filled) "\xe2\x96\x88" else "\xe2\x96\x91";
            const gs: Style = if (bi < filled) .{ .fg = t.gold } else s.dim2;
            print1(box, 8 + bi, 4, glyph, gs);
        }
        _ = writeFixed1(box, 8 + bar_w + 1, 4, v.i, v.d, s.gold_bold);
    }

    // Raw WPM
    print1(box, 3, 5, "Raw", s.dim);
    {
        const v = splitFixed1(raw_val, 9999.0);
        _ = writeFixed1(box, 8, 5, v.i, v.d, s.gold2);
    }

    // CPM
    if (actual_h > 8) {
        print1(box, 3, 6, "CPM", s.dim);
        {
            const v = splitFixed1(cpm_val, 9999.0);
            _ = writeFixed1(box, 8, 6, v.i, v.d, s.accent);
        }
    }

    // Accuracy with bar
    if (actual_h > 9) {
        print1(box, 3, 7, "Acc", s.dim);
        {
            const v = splitFixed1(acc_val, 100.0);
            const bar_w: u16 = @min(20, actual_w -| 20);
            const filled: u16 = @intCast(@min(bar_w, @as(u64, v.i) * bar_w / 100));
            const acc_color: Color = if (acc_val >= 95.0) t.correct
                                     else if (acc_val >= 80.0) t.gold
                                     else t.error_c;
            var bi: u16 = 0;
            while (bi < bar_w) : (bi += 1) {
                const glyph = if (bi < filled) "\xe2\x96\x88" else "\xe2\x96\x91";
                const gs: Style = if (bi < filled) .{ .fg = acc_color } else s.dim2;
                print1(box, 8 + bi, 7, glyph, gs);
            }
            const c = writeFixed1(box, 8 + bar_w + 1, 7, v.i, v.d,
                .{ .fg = acc_color, .bold = true });
            print1(box, 8 + bar_w + 1 + c, 7, "%", .{ .fg = acc_color, .bold = true });
        }
    }

    // Consistency
    if (actual_h > 10) {
        print1(box, 3, 8, "Cons", s.dim);
        const v = splitFixed1(cons_val, 100.0);
        const cons_color: Color = if (cons_val >= 80.0) t.correct
                                   else if (cons_val >= 60.0) t.gold
                                   else t.gold2;
        const c = writeFixed1(box, 8, 8, v.i, v.d, .{ .fg = cons_color });
        print1(box, 8 + c, 8, "%", .{ .fg = cons_color });
    }

    // Time
    if (actual_h > 11) {
        const elapsed_ms = game.elapsedMs();
        const time_s: u64 = @intCast(@divTrunc(elapsed_ms, 1000));
        const time_d: u64 = @intCast(@divTrunc(@rem(elapsed_ms, 1000), 100));
        print1(box, 3, 9, "Time", s.dim);
        const c = writeU64(box, 8, 9, time_s, s.fg);
        print1(box, 8 + c, 9, ".", s.fg);
        const c2 = writeU64(box, 8 + c + 1, 9, time_d, s.fg);
        print1(box, 8 + c + 1 + c2, 9, "s", s.fg);
    }

    if (actual_h <= 14) return;
    drawSep(box, 0, 11, box.width, s.sep);

    // ── Keystrokes ───────────────────────────────────────────────────────────
    print1(box, 3, 12, "KEYSTROKES", s.accent2);

    print1(box, 3, 13, "Correct:", s.dim);
    _ = writeU64(box, 12, 13, @intCast(game.correct_chars), s.correct);

    print1(box, 24, 13, "Errors:", s.dim);
    _ = writeU64(box, 32, 13, @intCast(game.incorrect_chars), s.err);

    print1(box, 3, 14, "Backspace:", s.dim);
    _ = writeU64(box, 14, 14, @intCast(game.backspace_count), s.dim);

    print1(box, 24, 14, "Total:", s.dim);
    _ = writeU64(box, 31, 14, @intCast(game.totalKeystrokes()), s.fg);

    print1(box, 3, 15, "Words:", s.dim);
    const cw = game.correctWords();
    const tw = game.current_word;
    const cw_w = writeU64(box, 10, 15, @intCast(cw), s.fg);
    print1(box, 10 + cw_w, 15, "/", s.dim);
    _ = writeU64(box, 10 + cw_w + 1, 15, @intCast(tw), s.dim);

    if (actual_h <= 18) {
        drawSep(box, 0, 17, box.width, s.sep);
        print1(box, 3, 18, "[Enter]", s.key);
        print1(box, 11, 18, "again", s.dim);
        print1(box, 19, 18, "[Tab]", s.key);
        print1(box, 25, 18, "menu", s.dim);
        return;
    }

    drawSep(box, 0, 17, box.width, s.sep);

    // ── Error chars ──────────────────────────────────────────────────────────
    {
        var errors: [6]game_mod.CharError = undefined;
        const n = game.topErrors(&errors);
        if (n == 0) {
            print1(box, 3, 18, "No errors — perfect!", s.correct_bold);
        } else {
            print1(box, 3, 18, "Missed:", s.dim);
            var c: u16 = 12;
            for (0..n) |i| {
                if (i > 0) { c += writeStr(box, c, 18, " ", s.dim); }
                print1(box, c, 18, &[_]u8{errors[i].char}, .{ .fg = t.error_c, .bold = true });
                c += 1;
                c += writeStr(box, c, 18, "(", s.dim);
                c += writeU64(box, c, 18, errors[i].count, s.fg);
                c += writeStr(box, c, 18, ")", s.dim);
            }
        }
    }

    // ── WPM Sparkline ────────────────────────────────────────────────────────
    if (actual_h > 21 and game.wpm_sample_count >= 3) {
        var spark_buf: [game_mod.WPM_HISTORY]f32 = undefined;
        const spark_n = game.wpmSamples(&spark_buf);
        const spark_w: u16 = @min(@as(u16, @intCast(spark_n)), actual_w -| 14);
        print1(box, 3, 19, "Trend:", s.dim);
        drawSparkline(box, 10, 19, spark_w, spark_buf[0..spark_n], s);
        // Consistency % after sparkline
        if (actual_w > 30) {
            const cons_v = splitFixed1(cons_val, 100.0);
            const sc: u16 = 10 + spark_w + 2;
            if (sc + 8 < actual_w) {
                const c = writeFixed1(box, sc, 19, cons_v.i, cons_v.d, s.dim);
                print1(box, sc + c, 19, "% cons", s.dim);
            }
        }
    }

    // ── Session stats ────────────────────────────────────────────────────────
    if (actual_h > 22 and game.session_games > 0) {
        drawSep(box, 0, 21, box.width, s.sep);
        print1(box, 3, 22, "Session:", s.dim);
        const gw = writeU64(box, 12, 22, game.session_games, s.fg);
        print1(box, 12 + gw, 22, " games", s.dim);
        if (game.session_best_wpm > 0) {
            print1(box, 24, 22, "Best:", s.dim);
            const bv = splitFixed1(game.session_best_wpm, 9999.0);
            const bw = writeFixed1(box, 30, 22, bv.i, bv.d, s.gold_bold);
            print1(box, 30 + bw, 22, " WPM", s.dim);
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    const act_row: u16 = actual_h -| 3;
    if (act_row > 14) {
        drawSep(box, 0, act_row, box.width, s.sep);
        print1(box, 3, act_row + 1, "[Enter]", s.key);
        print1(box, 11, act_row + 1, "again", s.dim);
        print1(box, 18, act_row + 1, "[Tab]", s.key);
        print1(box, 24, act_row + 1, "menu", s.dim);
        print1(box, 30, act_row + 1, "[Esc]", s.key);
        print1(box, 36, act_row + 1, "quit", s.dim);
    }
}
