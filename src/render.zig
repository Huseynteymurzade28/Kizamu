const std = @import("std");
const vaxis = @import("vaxis");
const game_mod = @import("game.zig");

const Game = game_mod.Game;
const Segment = vaxis.Segment;
const Style = vaxis.Style;
const Color = vaxis.Color;
const Window = vaxis.Window;

// ─── Color palette ───────────────────────────────────────────────────────────
const c_accent: Color = .{ .rgb = .{ 86, 182, 194 } }; // cyan
const c_correct: Color = .{ .rgb = .{ 100, 220, 100 } }; // green
const c_error: Color = .{ .rgb = .{ 235, 75, 75 } }; // red
const c_dim: Color = .{ .rgb = .{ 90, 95, 110 } }; // grey-blue
const c_white: Color = .{ .rgb = .{ 215, 215, 215 } }; // off-white
const c_gold: Color = .{ .rgb = .{ 255, 200, 70 } }; // yellow
const c_dark: Color = .{ .rgb = .{ 18, 18, 28 } }; // near-black
const c_mid: Color = .{ .rgb = .{ 50, 50, 70 } }; // selection bg
const c_sep: Color = .{ .rgb = .{ 55, 60, 80 } }; // separator

// ─── Style constants ─────────────────────────────────────────────────────────
const s_accent: Style = .{ .fg = c_accent };
const s_accent_bold: Style = .{ .fg = c_accent, .bold = true };
const s_correct: Style = .{ .fg = c_correct };
const s_error: Style = .{ .fg = c_error };
const s_error_ul: Style = .{ .fg = c_error, .ul_style = .curly, .ul = c_error };
const s_dim: Style = .{ .fg = c_dim };
const s_white: Style = .{ .fg = c_white };
const s_white_bold: Style = .{ .fg = c_white, .bold = true };
const s_gold: Style = .{ .fg = c_gold };
const s_gold_bold: Style = .{ .fg = c_gold, .bold = true };
const s_sep: Style = .{ .fg = c_sep };
// cursor: inverted (dark text on accent background)
const s_cursor: Style = .{ .fg = c_dark, .bg = c_accent };
// selected menu item
const s_sel: Style = .{ .fg = c_white, .bold = true };
const s_sel_bg: Style = .{ .fg = c_white, .bg = c_mid, .bold = true };
const s_key: Style = .{ .fg = c_gold };

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Print a single segment at (col, row) in the given window.
fn print1(win: Window, col: u16, row: u16, text: []const u8, style: Style) void {
    _ = win.print(&[_]Segment{.{ .text = text, .style = style }}, .{
        .row_offset = row,
        .col_offset = col,
        .wrap = .none,
    });
}

/// Fill an entire row from col to col+width with a space using the given style.
fn fillRow(win: Window, row: u16, style: Style) void {
    var c: u16 = 0;
    while (c < win.width) : (c += 1) {
        win.writeCell(c, row, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = style });
    }
}

/// Safe integer div returning 0 when divisor is 0.
fn safeDiv(a: u16, b: u16) u16 {
    if (b == 0) return 0;
    return a / b;
}

// ─── Menu Screen ─────────────────────────────────────────────────────────────
//
//   ╭──────────────────────────────────────╮
//   │                                      │
//   │   K · I · Z · A · M · U             │
//   │   typing practice                    │
//   │                                      │
//   ├──────────────────────────────────────┤
//   │                                      │
//   │   ❯  10 words                        │
//   │      25 words                        │
//   │      50 words                        │
//   │     100 words                        │
//   │     200 words                        │
//   │                                      │
//   ╰──────────────────────────────────────╯
//     ↑↓ navigate · Enter select · Esc quit
//
pub fn drawMenu(win: Window, cursor: usize) void {
    const BOX_W: u16 = 40;
    const BOX_H: u16 = 16;

    if (win.width < BOX_W + 2 or win.height < BOX_H + 2) return;

    const bx: u16 = (win.width -| BOX_W) / 2;
    const by: u16 = (win.height -| BOX_H) / 2;

    // Outer bordered box
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

    // Title section
    print1(box, 2, 1, "K · I · Z · A · M · U", s_gold_bold);
    print1(box, 2, 2, "typing practice", s_dim);

    // Separator
    var si: u16 = 0;
    while (si < box.width) : (si += 1) {
        box.writeCell(si, 3, .{ .char = .{ .grapheme = "─", .width = 1 }, .style = s_sep });
    }

    // Mode options
    const modes = game_mod.ALL_MODES;
    const labels = [_][]const u8{ "10 words", "25 words", "50 words", "100 words", "200 words" };

    for (0..modes.len) |i| {
        const row: u16 = @as(u16, @intCast(i)) + 5;
        const selected = (i == cursor);

        if (selected) {
            // Highlight whole row
            fillRow(box, row, .{ .bg = c_mid });
            print1(box, 2, row, "❯", s_accent_bold);
            // Make number prominent
            var num_buf: [8]u8 = undefined;
            const n_str = std.fmt.bufPrint(&num_buf, "{d}", .{modes[i].count()}) catch "?";
            // right-align number within 3 chars
            const pad: u16 = if (n_str.len < 3) 3 - @as(u16, @intCast(n_str.len)) else 0;
            print1(box, 4 + pad, row, n_str, .{ .fg = c_gold, .bg = c_mid, .bold = true });
            print1(box, 8, row, "words", .{ .fg = c_white, .bg = c_mid, .bold = true });
        } else {
            const n_str = labels[i];
            // dim, right-align number
            const prefix: []const u8 = switch (i) {
                0 => " 10",
                1 => " 25",
                2 => " 50",
                3 => "100",
                else => "200",
            };
            print1(box, 4, row, prefix, s_dim);
            print1(box, 8, row, " words", s_dim);
            _ = n_str;
        }
    }

    // Bottom separator
    var bi: u16 = 0;
    while (bi < box.width) : (bi += 1) {
        box.writeCell(bi, 11, .{ .char = .{ .grapheme = "─", .width = 1 }, .style = s_sep });
    }

    // Help text inside box
    print1(box, 2, 12, "↑↓", s_accent);
    print1(box, 5, 12, "navigate", s_dim);
    print1(box, 14, 12, "·", s_dim);
    print1(box, 16, 12, "1-5", s_accent);
    print1(box, 20, 12, "quick select", s_dim);
    print1(box, 2, 13, "Enter", s_accent);
    print1(box, 8, 13, "confirm", s_dim);
    print1(box, 16, 13, "·", s_dim);
    print1(box, 18, 13, "Esc", s_accent);
    print1(box, 22, 13, "quit", s_dim);
}

// ─── Typing Screen ───────────────────────────────────────────────────────────
pub fn drawTyping(win: Window, game: *const Game) void {
    if (win.width < 20 or win.height < 8) return;

    const mx: u16 = 3; // horizontal margin
    const w: u16 = win.width -| mx * 2;

    // ── Header (row 1) ──────────────────────────────────────────────────────
    print1(win, mx, 1, "KIZAMU", s_accent_bold);
    print1(win, mx + 8, 1, "·", s_dim);

    const mode_label = game.mode.label();
    print1(win, mx + 10, 1, mode_label, s_dim);

    // Live stats on the right
    if (game.start_time != null) {
        const elapsed_s = @as(f64, @floatFromInt(game.elapsedMs())) / 1000.0;
        var buf: [80]u8 = undefined;
        const stats = std.fmt.bufPrint(
            &buf,
            "WPM {d:>5.1}  ·  Acc {d:>4.1}%  ·  {d:>4.1}s",
            .{ game.wpm(), game.accuracy(), elapsed_s },
        ) catch "—";
        const stats_col = win.width -| @as(u16, @intCast(stats.len)) -| mx;
        print1(win, stats_col, 1, stats, s_gold);
    }

    // ── Top separator (row 2) ───────────────────────────────────────────────
    drawSeparator(win, mx, 2, w);

    // ── Word display ────────────────────────────────────────────────────────
    const words_top: u16 = 4;
    const words_bottom: u16 = win.height -| 4; // leave room for footer
    const words_h: u16 = if (words_bottom > words_top) words_bottom - words_top else 3;

    const words_win = win.child(.{
        .x_off = mx,
        .y_off = words_top,
        .width = w,
        .height = words_h,
    });

    drawWords(words_win, game);

    // ── Bottom separator ─────────────────────────────────────────────────────
    drawSeparator(win, mx, win.height -| 3, w);

    // ── Footer (last two rows) ───────────────────────────────────────────────
    drawProgress(win, game, mx, win.height -| 2, w);
}

fn drawSeparator(win: Window, col: u16, row: u16, width: u16) void {
    var i: u16 = 0;
    while (i < width) : (i += 1) {
        win.writeCell(col + i, row, .{
            .char = .{ .grapheme = "─", .width = 1 },
            .style = s_sep,
        });
    }
}

fn drawProgress(win: Window, game: *const Game, mx: u16, row: u16, avail_w: u16) void {
    // Progress bar
    const BAR_W: u16 = @min(30, avail_w / 2);
    const filled: u16 = if (game.word_count > 0)
        @intCast(@min(BAR_W, @as(u64, game.current_word) * BAR_W / game.word_count))
    else
        0;

    var bi: u16 = 0;
    while (bi < BAR_W) : (bi += 1) {
        const ch = if (bi < filled) "█" else "░";
        const st = if (bi < filled) Style{ .fg = c_accent } else s_dim;
        print1(win, mx + bi, row, ch, st);
    }

    // Word count
    var wc_buf: [24]u8 = undefined;
    const wc = std.fmt.bufPrint(&wc_buf, "  {d}/{d}", .{
        game.current_word, game.word_count,
    }) catch "?";
    print1(win, mx + BAR_W, row, wc, s_dim);

    // Hints (right side)
    const hint = "[Tab] restart  ·  [Esc] menu";
    if (win.width > mx + @as(u16, @intCast(hint.len)) + 2) {
        const hcol = win.width -| mx -| @as(u16, @intCast(hint.len));
        print1(win, hcol, row, "[Tab]", s_key);
        print1(win, hcol + 5, row, " restart  ·  ", s_dim);
        print1(win, hcol + 18, row, "[Esc]", s_key);
        print1(win, hcol + 23, row, " menu", s_dim);
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
            cur_col += wlen + 1; // +1 for space
        }
    }

    // Scrolling: keep current word on the 2nd visible row (index 1)
    const cur_layout_row = layout_row[game.current_word];
    const scroll: u16 = if (cur_layout_row >= 1) cur_layout_row - 1 else 0;

    // Draw each word
    for (0..game.word_count) |wi| {
        const lr = layout_row[wi];
        if (lr < scroll) continue;
        const vis_row = lr - scroll;
        if (vis_row >= words_win.height) continue;

        const lc = layout_col[wi];
        const word = game.words[wi];

        if (wi < game.current_word) {
            // Completed word
            const st = if (game.word_correct[wi]) s_correct else s_error;
            print1(words_win, lc, vis_row, word, st);
        } else if (wi == game.current_word) {
            // Active word — per-character coloring
            for (0..word.len) |ci| {
                const colu: u16 = lc + @as(u16, @intCast(ci));
                if (ci < game.input_len) {
                    const st = if (game.input_buf[ci] == word[ci]) s_correct else s_error_ul;
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], st);
                } else if (ci == game.input_len) {
                    // Cursor position
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], s_cursor);
                } else {
                    print1(words_win, colu, vis_row, word[ci .. ci + 1], s_dim);
                }
            }
            // Extra chars typed beyond word length
            var ei: usize = word.len;
            while (ei < game.input_len and ei < game_mod.MAX_INPUT) : (ei += 1) {
                const colu: u16 = lc + @as(u16, @intCast(ei));
                if (colu < words_win.width) {
                    print1(words_win, colu, vis_row, game.input_buf[ei .. ei + 1], s_error_ul);
                }
            }
            // Show cursor after word if input matches word exactly
            if (game.input_len == word.len) {
                const colu: u16 = lc + @as(u16, @intCast(word.len));
                if (colu < words_win.width) {
                    print1(words_win, colu, vis_row, " ", s_cursor);
                }
            }
        } else {
            // Upcoming word
            print1(words_win, lc, vis_row, word, s_dim);
        }
    }
}

// ─── Results Screen ───────────────────────────────────────────────────────────
pub fn drawResults(win: Window, game: *const Game) void {
    const BOX_W: u16 = 42;
    const BOX_H: u16 = 18;

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

    // Title
    print1(box, 2, 1, "R · E · S · U · L · T · S", s_gold_bold);

    // Separator
    var si: u16 = 0;
    while (si < box.width) : (si += 1) {
        box.writeCell(si, 2, .{ .char = .{ .grapheme = "─", .width = 1 }, .style = s_sep });
    }

    // Big WPM display
    var wpm_buf: [16]u8 = undefined;
    const wpm_str = std.fmt.bufPrint(&wpm_buf, "{d:.1}", .{game.wpm()}) catch "??";
    print1(box, 2, 4, "WPM", s_dim);
    print1(box, 8, 4, wpm_str, .{ .fg = c_gold, .bold = true });

    // Accuracy
    var acc_buf: [16]u8 = undefined;
    const acc_str = std.fmt.bufPrint(&acc_buf, "{d:.1}%", .{game.accuracy()}) catch "??";
    print1(box, 2, 5, "Accuracy", s_dim);
    print1(box, 12, 5, acc_str, .{ .fg = c_correct, .bold = true });

    // Time
    const elapsed_s = @as(f64, @floatFromInt(game.elapsedMs())) / 1000.0;
    var t_buf: [16]u8 = undefined;
    const t_str = std.fmt.bufPrint(&t_buf, "{d:.1}s", .{elapsed_s}) catch "??";
    print1(box, 2, 6, "Time", s_dim);
    print1(box, 8, 6, t_str, s_white);

    // Separator
    var s2i: u16 = 0;
    while (s2i < box.width) : (s2i += 1) {
        box.writeCell(s2i, 8, .{ .char = .{ .grapheme = "─", .width = 1 }, .style = s_sep });
    }

    // Word stats
    const correct_words = game.correctWords();
    const total_words = game.current_word;

    var w1: [16]u8 = undefined;
    const words_str = std.fmt.bufPrint(&w1, "{d}/{d}", .{ correct_words, total_words }) catch "?";
    print1(box, 2, 9, "Words correct", s_dim);
    print1(box, 17, 9, words_str, s_white);

    var w2: [16]u8 = undefined;
    const cc_str = std.fmt.bufPrint(&w2, "{d}", .{game.correct_chars}) catch "?";
    print1(box, 2, 10, "Correct chars", s_dim);
    print1(box, 17, 10, cc_str, s_correct);

    var w3: [16]u8 = undefined;
    const ic_str = std.fmt.bufPrint(&w3, "{d}", .{game.incorrect_chars}) catch "?";
    print1(box, 2, 11, "Errors", s_dim);
    print1(box, 17, 11, ic_str, s_error);

    // Second separator
    var s3i: u16 = 0;
    while (s3i < box.width) : (s3i += 1) {
        box.writeCell(s3i, 13, .{ .char = .{ .grapheme = "─", .width = 1 }, .style = s_sep });
    }

    // Actions
    print1(box, 2, 14, "[Enter]", s_key);
    print1(box, 10, 14, "play again", s_dim);
    print1(box, 22, 14, "·", s_sep);
    print1(box, 24, 14, "[Tab]", s_key);
    print1(box, 30, 14, "menu", s_dim);
    print1(box, 2, 15, "[Esc]", s_key);
    print1(box, 8, 15, "quit", s_dim);
}
