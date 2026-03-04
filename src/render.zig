// Kizamu — TUI rendering (Tokyo Night palette).
const std = @import("std");
const vaxis = @import("vaxis");
const game_mod = @import("game.zig");
const words_mod = @import("words.zig");

const Game = game_mod.Game;
const Segment = vaxis.Segment;
const Style = vaxis.Style;
const Color = vaxis.Color;
const Window = vaxis.Window;

// ─── Tokyo Night colour palette ──────────────────────────────────────────────
const c_accent: Color = .{ .rgb = .{ 125, 207, 255 } }; // cyan
const c_accent2: Color = .{ .rgb = .{ 122, 162, 247 } }; // blue
const c_correct: Color = .{ .rgb = .{ 158, 206, 106 } }; // green
const c_error: Color = .{ .rgb = .{ 247, 118, 142 } }; // red/pink
const c_dim: Color = .{ .rgb = .{ 86, 95, 137 } }; // comment
const c_dim2: Color = .{ .rgb = .{ 52, 56, 80 } }; // very dim
const c_white: Color = .{ .rgb = .{ 192, 202, 245 } }; // fg
const c_gold: Color = .{ .rgb = .{ 224, 175, 104 } }; // yellow
const c_gold2: Color = .{ .rgb = .{ 255, 158, 100 } }; // orange
const c_magenta: Color = .{ .rgb = .{ 187, 154, 247 } }; // magenta
const c_dark: Color = .{ .rgb = .{ 26, 27, 38 } }; // bg
const c_mid: Color = .{ .rgb = .{ 36, 40, 59 } }; // selection bg
const c_mid2: Color = .{ .rgb = .{ 52, 59, 88 } }; // lighter mid
const c_sep: Color = .{ .rgb = .{ 59, 66, 97 } }; // separator

// ─── Style constants ─────────────────────────────────────────────────────────
const s_accent: Style = .{ .fg = c_accent };
const s_accent_bold: Style = .{ .fg = c_accent, .bold = true };
const s_accent2: Style = .{ .fg = c_accent2 };
const s_correct: Style = .{ .fg = c_correct };
const s_correct_b: Style = .{ .fg = c_correct, .bold = true };
const s_correct_bold: Style = .{ .fg = c_correct, .bold = true };
const s_error: Style = .{ .fg = c_error };
const s_error_ul: Style = .{ .fg = c_error, .ul_style = .curly, .ul = c_error };
const s_dim: Style = .{ .fg = c_dim };
const s_dim2: Style = .{ .fg = c_dim2 };
const s_white: Style = .{ .fg = c_white };
const s_gold: Style = .{ .fg = c_gold };
const s_gold_bold: Style = .{ .fg = c_gold, .bold = true };
const s_gold2: Style = .{ .fg = c_gold2 };
const s_sep: Style = .{ .fg = c_sep };
const s_cursor: Style = .{ .fg = c_dark, .bg = c_accent, .bold = true };
const s_key: Style = .{ .fg = c_gold, .bold = true };
const s_magenta: Style = .{ .fg = c_magenta };

// ─── Static digit graphemes (safe to store in vaxis cells) ───────────────────
const DIGITS = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" };

/// Comptime lookup: single-character static strings for ASCII 0-127.
const ASCII = blk: {
    @setEvalBranchQuota(256);
    var arr: [128][1]u8 = undefined;
    for (0..128) |i| {
        arr[i] = .{@intCast(i)};
    }
    break :blk arr;
};

/// Return a static []const u8 slice for an ASCII character.
fn asciiG(ch: u8) []const u8 {
    if (ch >= 128) return "?";
    return &ASCII[ch];
}

// ─── Numeric rendering helpers ───────────────────────────────────────────────

/// Decimal digit count of a u64 value.
fn numWidth(val: u64) u16 {
    if (val == 0) return 1;
    var w: u16 = 0;
    var v = val;
    while (v > 0) : (w += 1) v /= 10;
    return w;
}

/// Write a u64 as decimal digits with writeCell. Returns columns written.
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

/// Write "int.dec" (one-decimal fixed point). Returns columns written.
fn writeFixed1(win: Window, col: u16, row: u16, int_part: u64, dec_part: u64, style: Style) u16 {
    var c: u16 = 0;
    c += writeU64(win, col + c, row, int_part, style);
    win.writeCell(col + c, row, .{ .char = .{ .grapheme = ".", .width = 1 }, .style = style });
    c += 1;
    c += writeU64(win, col + c, row, dec_part, style);
    return c;
}

/// Width of "int.dec" representation.
fn fixed1Width(int_part: u64, dec_part: u64) u16 {
    return numWidth(int_part) + 1 + numWidth(dec_part);
}

/// Convert f64 to (integer, 1-decimal) safely clamped/rounded.
fn splitFixed1(val: f64, clamp_max: f64) struct { i: u64, d: u64 } {
    const safe: f64 = if (std.math.isFinite(val) and val >= 0.0) @min(val, clamp_max) else 0.0;
    const x10: u64 = @intFromFloat(safe * 10.0 + 0.5);
    return .{ .i = x10 / 10, .d = x10 % 10 };
}

// ─── General helpers ─────────────────────────────────────────────────────────

/// Print a static text segment at (col, row). Returns columns written.
fn writeStr(win: Window, col: u16, row: u16, text: []const u8, style: Style) u16 {
    _ = win.print(&[_]Segment{.{ .text = text, .style = style }}, .{
        .row_offset = row,
        .col_offset = col,
        .wrap = .none,
    });
    return @intCast(text.len);
}

/// Shorthand: write a segment (no return). Same as old print1.
fn print1(win: Window, col: u16, row: u16, text: []const u8, style: Style) void {
    _ = win.print(&[_]Segment{.{ .text = text, .style = style }}, .{
        .row_offset = row,
        .col_offset = col,
        .wrap = .none,
    });
}

/// Fill an entire row with a space using the given style.
fn fillRow(win: Window, row: u16, style: Style) void {
    var c: u16 = 0;
    while (c < win.width) : (c += 1) {
        win.writeCell(c, row, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = style });
    }
}

/// Draw a horizontal line.
fn drawSep(win: Window, col: u16, row: u16, width: u16) void {
    var i: u16 = 0;
    while (i < width) : (i += 1) {
        win.writeCell(col + i, row, .{
            .char = .{ .grapheme = "\xe2\x94\x80", .width = 1 }, // ─
            .style = s_sep,
        });
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MENU SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

pub fn drawMenu(win: Window, cursor: usize, diff_cursor: usize, cat_cursor: usize, frame: u32) void {
    const BOX_W: u16 = 52;
    const BOX_H: u16 = 30;

    if (win.width < BOX_W + 2 or win.height < BOX_H + 2) return;

    const bx: u16 = (win.width -| BOX_W) / 2;
    const by: u16 = (win.height -| BOX_H) / 2;

    const box = win.child(.{
        .x_off = bx,
        .y_off = by,
        .width = BOX_W,
        .height = BOX_H,
        .border = .{
            .where = .all,
            .glyphs = .single_rounded,
            .style = s_accent,
        },
    });

    // ── Animated title ──────────────────────────────────────────────────────
    {
        const lcols = [_]u16{ 6, 10, 14, 18, 22, 26 };
        const letters = "KIZAMU";
        const WAVE: u32 = 18;
        const wave_pos = frame % WAVE;
        for (lcols, 0..) |lc, li| {
            const peak: u32 = @as(u32, @intCast(li)) * 3;
            const dist = @min(
                (wave_pos + WAVE - peak) % WAVE,
                (peak + WAVE - wave_pos) % WAVE,
            );
            const col: Color = if (dist == 0)
                c_gold
            else if (dist <= 1)
                c_accent
            else if (dist <= 3)
                c_white
            else
                c_dim;
            const bold = dist <= 2;
            print1(box, lc, 1, letters[li .. li + 1], .{ .fg = col, .bold = bold });
        }
        const sep_cols = [_]u16{ 8, 12, 16, 20, 24 };
        for (sep_cols) |sc| {
            print1(box, sc, 1, ".", s_dim);
        }
    }
    print1(box, 6, 2, "typing practice", s_dim);

    // ── Separator ───────────────────────────────────────────────────────────
    drawSep(box, 0, 3, box.width);

    // ── Category selector (centered, larger) ─────────────────────────────────
    {
        print1(box, 4, 4, "Category:", s_dim);
        const cat = words_mod.ALL_CATEGORIES[cat_cursor];
        print1(box, 15, 4, "[<]", s_accent);
        const catlabel = words_mod.categoryLabel(cat);
        print1(box, 20, 4, catlabel, .{ .fg = c_accent2, .bold = true });
        print1(box, 20 + @as(u16, @intCast(catlabel.len)), 4, " >]", s_accent);
    }

    // ── Difficulty selector ─────────────────────────────────────────────────
    {
        print1(box, 4, 5, "Difficulty:", s_dim);
        const diff = game_mod.ALL_DIFFICULTIES[diff_cursor];
        print1(box, 17, 5, "[<]", s_accent);
        const dlabel = diff.label();
        print1(box, 22, 5, dlabel, .{ .fg = c_magenta, .bold = true });
        print1(box, 22 + @as(u16, @intCast(dlabel.len)), 5, " >]", s_accent);
    }

    // ── Separator ───────────────────────────────────────────────────────────
    drawSep(box, 0, 6, box.width);

    // ── WORD COUNT section ──────────────────────────────────────────────────
    print1(box, 4, 7, "WORD COUNT", s_accent2);

    const word_labels = [_][]const u8{ "10", "25", "50", "100", "200", "500" };
    for (0..6) |i| {
        const row: u16 = @as(u16, @intCast(i)) + 8;
        const selected = (i == cursor);
        if (selected) {
            fillRow(box, row, .{ .bg = c_mid });
            print1(box, 4, row, ">", s_accent_bold);
            print1(box, 6, row, word_labels[i], .{ .fg = c_gold, .bg = c_mid, .bold = true });
            print1(box, 6 + @as(u16, @intCast(word_labels[i].len)), row, " words", .{ .fg = c_white, .bg = c_mid, .bold = true });
        } else {
            print1(box, 6, row, word_labels[i], s_dim);
            print1(box, 6 + @as(u16, @intCast(word_labels[i].len)), row, " words", s_dim);
        }
    }

    // ── TIMED section ───────────────────────────────────────────────────────
    print1(box, 4, 15, "TIMED", s_accent2);

    const time_labels = [_][]const u8{ "15", "30", "60", "120" };
    for (0..4) |i| {
        const row: u16 = @as(u16, @intCast(i)) + 16;
        const selected = (i + 6 == cursor);
        if (selected) {
            fillRow(box, row, .{ .bg = c_mid });
            print1(box, 4, row, ">", s_accent_bold);
            print1(box, 6, row, time_labels[i], .{ .fg = c_gold, .bg = c_mid, .bold = true });
            print1(box, 6 + @as(u16, @intCast(time_labels[i].len)), row, " seconds", .{ .fg = c_white, .bg = c_mid, .bold = true });
        } else {
            print1(box, 6, row, time_labels[i], s_dim);
            print1(box, 6 + @as(u16, @intCast(time_labels[i].len)), row, " seconds", s_dim);
        }
    }

    // ── Bottom separator ────────────────────────────────────────────────────
    drawSep(box, 0, 21, box.width);

    // ── Help text ───────────────────────────────────────────────────────────
    print1(box, 4, 22, "j/k", s_accent);
    print1(box, 7, 22, "mode", s_dim);
    print1(box, 14, 22, "|", s_dim2);
    print1(box, 16, 22, "w/s", s_accent);
    print1(box, 20, 22, "category", s_dim);
    print1(box, 4, 23, "h/l", s_accent);
    print1(box, 7, 23, "difficulty", s_dim);
    print1(box, 19, 23, "|", s_dim2);
    print1(box, 21, 23, "Enter", s_accent);
    print1(box, 27, 23, "start", s_dim);
    print1(box, 4, 24, "Esc", s_accent);
    print1(box, 8, 24, "quit", s_dim);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TYPING SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

pub fn drawTyping(win: Window, game: *const Game) void {
    if (win.width < 25 or win.height < 10) return;

    const mx: u16 = 4;
    const w: u16 = win.width -| mx * 2;

    // ── Header ───────────────────────────────────────────────────────────────
    // Background for header
    for (0..win.width) |c| {
        win.writeCell(@intCast(c), 0, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = .{ .bg = c_mid2 } });
    }

    print1(win, mx, 0, "◈ KIZAMU", s_accent_bold);
    print1(win, mx + 10, 0, "│", s_dim2);

    const mode_label = game.mode.label();
    print1(win, mx + 12, 0, mode_label, s_dim);
    print1(win, mx + 12 + @as(u16, @intCast(mode_label.len)) + 1, 0, "|", s_dim2);

    const cat_label = words_mod.categoryLabel(game.category);
    print1(win, mx + 12 + @as(u16, @intCast(mode_label.len)) + 3, 0, cat_label, s_magenta);
    print1(win, mx + 12 + @as(u16, @intCast(mode_label.len)) + 3 + @as(u16, @intCast(cat_label.len)) + 1, 0, "|", s_dim2);

    const diff_label = game.difficulty.label();
    print1(win, mx + 12 + @as(u16, @intCast(mode_label.len)) + 3 + @as(u16, @intCast(cat_label.len)) + 3, 0, diff_label, s_white);

    // ── Live stats (right-aligned on header) ─────────────────────────────────
    drawLiveStats(win, game, mx);

    // ── Top separator (row 2) ───────────────────────────────────────────────
    drawSep(win, mx, 2, w);

    // ── Word display area ───────────────────────────────────────────────────
    const words_top: u16 = 4;
    const words_bottom: u16 = win.height -| 5;
    const words_h: u16 = if (words_bottom > words_top) words_bottom - words_top else 3;

    const words_win = win.child(.{
        .x_off = mx,
        .y_off = words_top,
        .width = w,
        .height = words_h,
    });

    drawWords(words_win, game);

    // ── Bottom separator ────────────────────────────────────────────────────
    drawSep(win, mx, win.height -| 4, w);

    // ── Footer ──────────────────────────────────────────────────────────────
    drawProgress(win, game, mx, win.height -| 2, w);
}

fn drawLiveStats(win: Window, game: *const Game, mx: u16) void {
    if (game.start_time == null) {
        const label = "WPM -- | Acc --%";
        print1(win, win.width -| @as(u16, @intCast(label.len)) -| mx, 1, label, s_dim);
        return;
    }

    const wpm_v = splitFixed1(game.wpm(), 9999.0);
    const acc_v = splitFixed1(game.accuracy(), 100.0);

    // Calculate total width first for right-alignment
    // "WPM XX.X | Acc XX.X% | XX.Xs" or "WPM XX.X | Acc XX.X% | XXs left"
    var total_w: u16 = 0;
    total_w += 4; // "WPM "
    total_w += fixed1Width(wpm_v.i, wpm_v.d);
    total_w += 7; // " | Acc "
    total_w += fixed1Width(acc_v.i, acc_v.d);
    total_w += 4; // "% | "

    if (game.mode.isTimed()) {
        const rem_s: u64 = @intCast(@max(0, @divTrunc(game.remainingMs(), 1000)));
        total_w += numWidth(rem_s);
        total_w += 6; // "s left"
        const sc = win.width -| total_w -| mx;
        var c: u16 = sc;
        c += writeStr(win, c, 1, "WPM ", s_gold);
        c += writeFixed1(win, c, 1, wpm_v.i, wpm_v.d, s_gold);
        c += writeStr(win, c, 1, " | Acc ", s_gold);
        c += writeFixed1(win, c, 1, acc_v.i, acc_v.d, s_gold);
        const time_style: Style = if (rem_s <= 5) .{ .fg = c_error, .bold = true } else if (rem_s <= 10) s_gold2 else s_gold;
        c += writeStr(win, c, 1, "% | ", s_gold);
        c += writeU64(win, c, 1, rem_s, time_style);
        _ = writeStr(win, c, 1, "s left", time_style);
    } else {
        const elapsed_ms = game.elapsedMs();
        const t_s: u64 = @intCast(@divTrunc(elapsed_ms, 1000));
        const t_d: u64 = @intCast(@divTrunc(@rem(elapsed_ms, 1000), 100));
        total_w += numWidth(t_s) + 1 + numWidth(t_d);
        total_w += 1; // "s"
        const sc = win.width -| total_w -| mx;
        var c: u16 = sc;
        c += writeStr(win, c, 1, "WPM ", s_gold);
        c += writeFixed1(win, c, 1, wpm_v.i, wpm_v.d, s_gold);
        c += writeStr(win, c, 1, " | Acc ", s_gold);
        c += writeFixed1(win, c, 1, acc_v.i, acc_v.d, s_gold);
        c += writeStr(win, c, 1, "% | ", s_gold);
        c += writeU64(win, c, 1, t_s, s_gold);
        c += writeStr(win, c, 1, ".", s_gold);
        c += writeU64(win, c, 1, t_d, s_gold);
        _ = writeStr(win, c, 1, "s", s_gold);
    }
}

fn drawProgress(win: Window, game: *const Game, mx: u16, row: u16, avail_w: u16) void {
    const BAR_W: u16 = @min(30, avail_w / 2);

    if (game.mode.isTimed()) {
        // Time-based progress bar
        const limit = game.mode.timeLimitMs();
        const elapsed = game.elapsedMs();
        const filled: u16 = if (limit > 0)
            @intCast(@min(BAR_W, @as(u64, @intCast(@max(0, elapsed))) * BAR_W / @as(u64, @intCast(limit))))
        else
            0;

        const rem_s: u64 = @intCast(@max(0, @divTrunc(game.remainingMs(), 1000)));
        const bar_col: Color = if (rem_s <= 5) c_error else if (rem_s <= 10) c_gold2 else c_accent;

        var bi: u16 = 0;
        while (bi < BAR_W) : (bi += 1) {
            if (bi < filled) {
                print1(win, mx + bi, row, "\xe2\x96\x88", .{ .fg = bar_col }); // █
            } else {
                print1(win, mx + bi, row, "\xe2\x96\x91", s_dim); // ░
            }
        }

        // Remaining time label
        var c: u16 = mx + BAR_W + 2;
        c += writeU64(win, c, row, rem_s, s_white);
        _ = writeStr(win, c, row, "s left", s_dim);
    } else {
        // Word-count progress bar
        const filled: u16 = if (game.word_count > 0)
            @intCast(@min(BAR_W, @as(u64, game.current_word) * BAR_W / game.word_count))
        else
            0;

        var bi: u16 = 0;
        while (bi < BAR_W) : (bi += 1) {
            if (bi < filled) {
                print1(win, mx + bi, row, "\xe2\x96\x88", .{ .fg = c_accent }); // █
            } else {
                print1(win, mx + bi, row, "\xe2\x96\x91", s_dim); // ░
            }
        }

        // Word count
        var c: u16 = mx + BAR_W + 2;
        c += writeU64(win, c, row, @intCast(game.current_word), s_dim);
        c += writeStr(win, c, row, "/", s_dim);
        _ = writeU64(win, c, row, @intCast(game.word_count), s_dim);
    }

    // Hints (right side)
    const HINT_W: u16 = 26;
    if (win.width > mx + HINT_W + 2) {
        const hcol = win.width -| mx -| HINT_W;
        print1(win, hcol, row, "[Tab]", s_key);
        print1(win, hcol + 5, row, " restart ", s_dim);
        print1(win, hcol + 13, row, "|", s_dim2);
        print1(win, hcol + 15, row, "[Esc]", s_key);
        print1(win, hcol + 20, row, " menu", s_dim);
    }
}

fn drawWords(words_win: Window, game: *const Game) void {
    if (words_win.width == 0 or words_win.height == 0) return;

    const ww: u16 = words_win.width;

    // Pre-compute layout: (row, col) for each word
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

    // Scrolling: keep current word on the 2nd visible row
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
            const st = if (game.word_correct[wi]) s_correct else s_error;
            print1(words_win, lc, vis_row, word, st);
        } else if (wi == game.current_word) {
            for (0..word.len) |ci| {
                const colu: u16 = lc + @as(u16, @intCast(ci));
                if (ci < game.input_len) {
                    const st = if (game.input_buf[ci] == word[ci]) s_correct else s_error_ul;
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], st);
                } else if (ci == game.input_len) {
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], s_cursor);
                } else {
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], s_white);
                }
            }
            var ei: usize = word.len;
            while (ei < game.input_len and ei < game_mod.MAX_INPUT) : (ei += 1) {
                const colu: u16 = lc + @as(u16, @intCast(ei));
                if (colu < words_win.width) {
                    print1(words_win, colu, vis_row, game.input_buf[ei .. ei + 1], s_error_ul);
                }
            }
            if (game.input_len == word.len) {
                const colu: u16 = lc + @as(u16, @intCast(word.len));
                if (colu < words_win.width) {
                    print1(words_win, colu, vis_row, " ", s_cursor);
                }
            }
        } else {
            print1(words_win, lc, vis_row, word, s_dim);
        }
    }

    // Add a hint about current progress
    if (game.start_time == null) {
        const hint_row = if (words_win.height > 1) words_win.height - 1 else 0;
        print1(words_win, 0, hint_row, "Start typing to begin...", s_dim2);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESULTS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

pub fn drawResults(win: Window, game: *const Game) void {
    const BOX_W: u16 = 50;
    const BOX_H: u16 = 22;

    if (win.width < BOX_W + 2 or win.height < BOX_H + 2) return;

    const bx: u16 = (win.width -| BOX_W) / 2;
    const by: u16 = (win.height -| BOX_H) / 2;

    const box = win.child(.{
        .x_off = bx,
        .y_off = by,
        .width = BOX_W,
        .height = BOX_H,
        .border = .{
            .where = .all,
            .glyphs = .single_rounded,
            .style = s_gold,
        },
    });

    // Title row
    print1(box, 2, 1, "=== RESULTS ===", s_gold_bold);
    const ml = game.mode.label();
    print1(box, box.width -| @as(u16, @intCast(ml.len)) -| 2, 1, ml, s_dim);

    const cat_label = words_mod.categoryLabel(game.category);
    print1(box, 2, 2, cat_label, s_accent2);

    drawSep(box, 0, 3, box.width);

    // Main stats - using existing helpers
    const wpm_val = game.wpm();
    const raw_val = game.rawWpm();
    const acc_val = game.accuracy();

    // WPM
    print1(box, 4, 5, "WPM:", s_dim);
    {
        const v = splitFixed1(wpm_val, 9999.0);
        _ = writeFixed1(box, 10, 5, v.i, v.d, .{ .fg = c_gold, .bold = true });
    }

    // Raw WPM
    print1(box, 4, 6, "Raw:", s_dim);
    {
        const v = splitFixed1(raw_val, 9999.0);
        _ = writeFixed1(box, 10, 6, v.i, v.d, s_gold2);
    }

    // Accuracy
    print1(box, 4, 7, "Accuracy:", s_dim);
    {
        const v = splitFixed1(acc_val, 100.0);
        const c = writeFixed1(box, 14, 7, v.i, v.d, s_correct_b);
        print1(box, 14 + c, 7, "%", s_correct_b);
    }

    // Time
    const elapsed_ms = game.elapsedMs();
    const time_s: u64 = @intCast(@divTrunc(elapsed_ms, 1000));
    print1(box, 4, 8, "Time:", s_dim);
    _ = writeU64(box, 10, 8, time_s, s_white);
    print1(box, 10 + numWidth(time_s), 8, "s", s_white);

    drawSep(box, 0, 10, box.width);

    // Keystrokes section
    print1(box, 4, 11, "KEYSTROKES", s_accent2);

    // Correct
    print1(box, 4, 12, "Correct:", s_dim);
    _ = writeU64(box, 13, 12, @intCast(game.correct_chars), s_correct);

    // Errors
    print1(box, 25, 12, "Errors:", s_dim);
    _ = writeU64(box, 33, 12, @intCast(game.incorrect_chars), s_error);

    // Backspace
    print1(box, 4, 13, "Backspace:", s_dim);
    _ = writeU64(box, 14, 13, @intCast(game.backspace_count), s_dim);

    // Total
    print1(box, 25, 13, "Total:", s_dim);
    _ = writeU64(box, 32, 13, @intCast(game.totalKeystrokes()), s_white);

    // Words
    print1(box, 4, 14, "Words:", s_dim);
    const cw = game.correctWords();
    const tw = game.current_word;
    _ = writeU64(box, 11, 14, @intCast(cw), s_white);
    print1(box, 11 + numWidth(@intCast(cw)), 14, "/", s_dim);
    _ = writeU64(box, 11 + numWidth(@intCast(cw)) + 1, 14, @intCast(tw), s_dim);

    drawSep(box, 0, 16, box.width);

    // Error characters
    {
        var errors: [5]game_mod.CharError = undefined;
        const n = game.topErrors(&errors);
        if (n == 0) {
            print1(box, 4, 17, "No errors - perfect!", s_correct_bold);
        } else {
            print1(box, 4, 17, "Missed:", s_dim);
            var c: u16 = 12;
            for (0..n) |i| {
                if (i > 0) {
                    print1(box, c, 17, " ", s_dim);
                    c += 1;
                }
                print1(box, c, 17, &[_]u8{errors[i].char}, .{ .fg = c_error, .bold = true });
                c += 1;
                print1(box, c, 17, "(", s_dim);
                c += 1;
                c += writeU64(box, c, 17, errors[i].count, s_white);
                print1(box, c, 17, ")", s_dim);
                c += 1;
            }
        }
    }

    drawSep(box, 0, 19, box.width);

    // Actions
    print1(box, 4, 20, "[Enter]", s_key);
    print1(box, 12, 20, "again", s_dim);
    print1(box, 20, 20, "|", s_dim2);
    print1(box, 22, 20, "[Tab]", s_key);
    print1(box, 28, 20, "menu", s_dim);
    print1(box, 34, 20, "|", s_dim2);
    print1(box, 36, 20, "[Esc]", s_key);
    print1(box, 42, 20, "quit", s_dim);
}

// Helper to print float as string
fn printFloat(val: f64) []const u8 {
    var buf: [16]u8 = undefined;
    if (val < 0 or !std.math.isFinite(val)) {
        return "0";
    }
    const int_part: u64 = @intFromFloat(@floor(val));
    const frac_part: u64 = @intCast(@floor((val - @as(f64, @floatFromInt(int_part))) * 10));

    var i: usize = 0;
    var v = int_part;
    if (int_part == 0) {
        buf[0] = '0';
        i = 1;
    } else {
        var temp: [16]u8 = undefined;
        var len: usize = 0;
        while (v > 0) {
            temp[len] = v % 10 + '0';
            len += 1;
            v /= 10;
        }
        var j: usize = 0;
        while (j < len) {
            buf[i] = temp[len - 1 - j];
            i += 1;
            j += 1;
        }
    }
    buf[i] = '.';
    i += 1;
    buf[i] = @intCast(frac_part + '0');
    i += 1;
    return buf[0..i];
}

// Helper to print percent
fn printPercent(val: f64) []const u8 {
    var buf: [16]u8 = undefined;
    const int_val: u64 = @intFromFloat(@round(val));
    var i: usize = 0;
    var v = int_val;
    if (int_val == 0) {
        buf[0] = '0';
        i = 1;
    } else {
        var temp: [16]u8 = undefined;
        var len: usize = 0;
        while (v > 0) {
            temp[len] = v % 10 + '0';
            len += 1;
            v /= 10;
        }
        var j: usize = 0;
        while (j < len) {
            buf[i] = temp[len - 1 - j];
            i += 1;
            j += 1;
        }
    }
    buf[i] = '%';
    i += 1;
    return buf[0..i];
}

// Helper to print integer
fn printInt(val: u64) []const u8 {
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    var v = val;
    if (val == 0) {
        buf[0] = '0';
        return buf[0..1];
    }
    var temp: [16]u8 = undefined;
    var len: usize = 0;
    while (v > 0) {
        temp[len] = @intCast(v % 10 + '0');
        len += 1;
        v /= 10;
    }
    var j: usize = 0;
    while (j < len) {
        buf[i] = temp[len - 1 - j];
        i += 1;
        j += 1;
    }
    return buf[0..i];
}

// Get width of integer
fn intWidth(val: u64) u16 {
    if (val == 0) return 1;
    var w: u16 = 0;
    var v = val;
    while (v > 0) : (w += 1) v /= 10;
    return w;
}
