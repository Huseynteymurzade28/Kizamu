// Kizamu — TUI rendering (Tokyo Night palette).
//
// BUG FIX: All numeric values are rendered digit-by-digit using writeCell with
// static grapheme references (DIGITS table in .rodata).  This avoids the
// dangling-pointer bug where bufPrint'd stack slices were stored in vaxis cells
// but freed before vx.render() — producing garbled "���" output for WPM, etc.
const std = @import("std");
const vaxis = @import("vaxis");
const game_mod = @import("game.zig");

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

pub fn drawMenu(win: Window, cursor: usize, diff_cursor: usize, frame: u32) void {
    const BOX_W: u16 = 42;
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
            .style = s_accent,
        },
    });

    // ── Animated title ──────────────────────────────────────────────────────
    {
        const lcols = [_]u16{ 3, 7, 11, 15, 19, 23 };
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
        const sep_cols = [_]u16{ 5, 9, 13, 17, 21 };
        for (sep_cols) |sc| {
            print1(box, sc, 1, ".", s_dim);
        }
    }
    print1(box, 3, 2, "typing practice", s_dim);

    // ── Separator ───────────────────────────────────────────────────────────
    drawSep(box, 0, 3, box.width);

    // ── Difficulty selector ─────────────────────────────────────────────────
    {
        print1(box, 3, 4, "Difficulty", s_dim);
        const diff = game_mod.ALL_DIFFICULTIES[diff_cursor];
        print1(box, 15, 4, "<", s_accent);
        const dlabel = diff.label();
        print1(box, 17, 4, dlabel, .{ .fg = c_magenta, .bold = true });
        print1(box, 17 + @as(u16, @intCast(dlabel.len)) + 1, 4, ">", s_accent);
    }

    // ── Separator ───────────────────────────────────────────────────────────
    drawSep(box, 0, 5, box.width);

    // ── WORD COUNT section ──────────────────────────────────────────────────
    print1(box, 3, 6, "WORD COUNT", s_accent2);

    const word_labels = [_][]const u8{ " 10", " 25", " 50", "100", "200" };
    for (0..5) |i| {
        const row: u16 = @as(u16, @intCast(i)) + 7;
        const selected = (i == cursor);
        if (selected) {
            fillRow(box, row, .{ .bg = c_mid });
            print1(box, 3, row, ">", s_accent_bold);
            print1(box, 5, row, word_labels[i], .{ .fg = c_gold, .bg = c_mid, .bold = true });
            print1(box, 8, row, " words", .{ .fg = c_white, .bg = c_mid, .bold = true });
        } else {
            print1(box, 5, row, word_labels[i], s_dim);
            print1(box, 8, row, " words", s_dim);
        }
    }

    // ── TIMED section ───────────────────────────────────────────────────────
    print1(box, 3, 13, "TIMED", s_accent2);

    const time_labels = [_][]const u8{ "15", "30", "60" };
    for (0..3) |i| {
        const row: u16 = @as(u16, @intCast(i)) + 14;
        const mode_idx = i + 5;
        const selected = (mode_idx == cursor);
        if (selected) {
            fillRow(box, row, .{ .bg = c_mid });
            print1(box, 3, row, ">", s_accent_bold);
            print1(box, 5, row, time_labels[i], .{ .fg = c_gold, .bg = c_mid, .bold = true });
            print1(box, 5 + @as(u16, @intCast(time_labels[i].len)), row, " seconds", .{ .fg = c_white, .bg = c_mid, .bold = true });
        } else {
            print1(box, 5, row, time_labels[i], s_dim);
            print1(box, 5 + @as(u16, @intCast(time_labels[i].len)), row, " seconds", s_dim);
        }
    }

    // ── Bottom separator ────────────────────────────────────────────────────
    drawSep(box, 0, 17, box.width);

    // ── Help text ───────────────────────────────────────────────────────────
    print1(box, 3, 18, "j/k", s_accent);
    print1(box, 6, 18, " navigate", s_dim);
    print1(box, 17, 18, "|", s_dim2);
    print1(box, 19, 18, "h/l", s_accent);
    print1(box, 22, 18, " difficulty", s_dim);
    print1(box, 3, 19, "Enter", s_accent);
    print1(box, 8, 19, " start", s_dim);
    print1(box, 17, 19, "|", s_dim2);
    print1(box, 19, 19, "Esc", s_accent);
    print1(box, 22, 19, " quit", s_dim);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TYPING SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

pub fn drawTyping(win: Window, game: *const Game) void {
    if (win.width < 20 or win.height < 8) return;

    const mx: u16 = 3;
    const w: u16 = win.width -| mx * 2;

    // ── Header (row 1) ──────────────────────────────────────────────────────
    print1(win, mx, 1, "KIZAMU", s_accent_bold);
    print1(win, mx + 8, 1, "|", s_dim2);

    const mode_label = game.mode.label();
    print1(win, mx + 10, 1, mode_label, s_dim);
    const diff_label = game.difficulty.label();
    print1(win, mx + 10 + @as(u16, @intCast(mode_label.len)) + 1, 1, diff_label, s_magenta);

    // ── Live stats (right-aligned on row 1) ─────────────────────────────────
    drawLiveStats(win, game, mx);

    // ── Top separator (row 2) ───────────────────────────────────────────────
    drawSep(win, mx, 2, w);

    // ── Word display ────────────────────────────────────────────────────────
    const words_top: u16 = 4;
    const words_bottom: u16 = win.height -| 4;
    const words_h: u16 = if (words_bottom > words_top) words_bottom - words_top else 3;

    const words_win = win.child(.{
        .x_off = mx,
        .y_off = words_top,
        .width = w,
        .height = words_h,
    });

    drawWords(words_win, game);

    // ── Bottom separator ────────────────────────────────────────────────────
    drawSep(win, mx, win.height -| 3, w);

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
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], s_dim);
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESULTS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

pub fn drawResults(win: Window, game: *const Game) void {
    const BOX_W: u16 = 44;
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

    // ── Title ───────────────────────────────────────────────────────────────
    print1(box, 2, 1, "[ RESULTS ]", s_gold_bold);
    const ml = game.mode.label();
    print1(box, box.width -| @as(u16, @intCast(ml.len)) -| 2, 1, ml, s_dim);

    drawSep(box, 0, 2, box.width);

    // ── Main stats ──────────────────────────────────────────────────────────
    const val_col: u16 = 16;

    // WPM
    {
        const v = splitFixed1(game.wpm(), 9999.0);
        print1(box, 2, 4, "WPM", s_dim);
        _ = writeFixed1(box, val_col, 4, v.i, v.d, .{ .fg = c_gold, .bold = true });
    }

    // Raw WPM
    {
        const v = splitFixed1(game.rawWpm(), 9999.0);
        print1(box, 2, 5, "Raw WPM", s_dim);
        _ = writeFixed1(box, val_col, 5, v.i, v.d, s_gold2);
    }

    // Accuracy
    {
        const v = splitFixed1(game.accuracy(), 100.0);
        print1(box, 2, 6, "Accuracy", s_dim);
        const c: u16 = writeFixed1(box, val_col, 6, v.i, v.d, s_correct_b);
        _ = writeStr(box, val_col + c, 6, "%", s_correct_b);
    }

    // Time
    {
        const elapsed_ms = game.elapsedMs();
        const t_s: u64 = @intCast(@divTrunc(elapsed_ms, 1000));
        const t_d: u64 = @intCast(@divTrunc(@rem(elapsed_ms, 1000), 100));
        print1(box, 2, 7, "Time", s_dim);
        const c: u16 = writeFixed1(box, val_col, 7, t_s, t_d, s_white);
        _ = writeStr(box, val_col + c, 7, "s", s_white);
    }

    drawSep(box, 0, 9, box.width);

    // ── Keystroke details ───────────────────────────────────────────────────
    print1(box, 2, 10, "Keystrokes", s_accent2);

    // Correct / Errors row
    {
        print1(box, 2, 11, "Correct", s_dim);
        _ = writeU64(box, 12, 11, @intCast(game.correct_chars), s_correct);
        print1(box, 22, 11, "Errors", s_dim);
        _ = writeU64(box, 31, 11, @intCast(game.incorrect_chars), s_error);
    }

    // Backspace / Total row
    {
        print1(box, 2, 12, "Backspace", s_dim);
        _ = writeU64(box, 12, 12, @intCast(game.backspace_count), s_dim);
        print1(box, 22, 12, "Total", s_dim);
        _ = writeU64(box, 31, 12, @intCast(game.totalKeystrokes()), s_white);
    }

    // Words correct
    {
        const cw = game.correctWords();
        const tw = game.current_word;
        print1(box, 2, 13, "Words", s_dim);
        var c: u16 = writeU64(box, 12, 13, @intCast(cw), s_white);
        c += writeStr(box, 12 + c, 13, "/", s_dim);
        _ = writeU64(box, 12 + c, 13, @intCast(tw), s_dim);
    }

    drawSep(box, 0, 15, box.width);

    // ── Most missed characters ──────────────────────────────────────────────
    {
        var errors: [5]game_mod.CharError = undefined;
        const n = game.topErrors(&errors);
        if (n == 0) {
            print1(box, 2, 16, "No errors - perfect!", s_correct);
        } else {
            var c: u16 = writeStr(box, 2, 16, "Most missed: ", s_dim);
            c += 2;
            for (0..n) |i| {
                if (i > 0) {
                    c += writeStr(box, c, 16, " ", s_dim);
                }
                // Write char using static ASCII grapheme
                box.writeCell(c, 16, .{
                    .char = .{ .grapheme = asciiG(errors[i].char), .width = 1 },
                    .style = .{ .fg = c_error, .bold = true },
                });
                c += 1;
                c += writeStr(box, c, 16, "(", s_dim);
                c += writeU64(box, c, 16, errors[i].count, s_white);
                c += writeStr(box, c, 16, ")", s_dim);
            }
        }
    }

    drawSep(box, 0, 18, box.width);

    // ── Actions ─────────────────────────────────────────────────────────────
    print1(box, 2, 19, "[Enter]", s_key);
    print1(box, 10, 19, "again", s_dim);
    print1(box, 17, 19, "|", s_dim2);
    print1(box, 19, 19, "[Tab]", s_key);
    print1(box, 25, 19, "menu", s_dim);
    print1(box, 31, 19, "|", s_dim2);
    print1(box, 33, 19, "[Esc]", s_key);
    print1(box, 39, 19, "quit", s_dim);
}
