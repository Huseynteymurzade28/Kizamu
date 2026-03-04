// Kizamu — Typing Practice
// Entry-point and event loop.
const std = @import("std");
const vaxis = @import("vaxis");
const game_m = @import("game.zig");
const words_mod = @import("words.zig");
const render = @import("render.zig");

const AppState = enum { menu, typing, results };

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    tick: void,
    focus_in,
    focus_out,
};

/// Background thread: fires a tick event every ~80ms for animation and timers.
fn tickThread(loop: *vaxis.Loop(Event), running: *std.atomic.Value(bool)) void {
    while (running.load(.acquire)) {
        std.Thread.sleep(80 * std.time.ns_per_ms);
        loop.postEvent(.{ .tick = {} });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tty_buf: [4096 * 4]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buf);
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    defer vx.exitAltScreen(tty.writer()) catch {};
    try vx.queryTerminalSend(tty.writer());

    var game = game_m.Game{};
    var state = AppState.menu;
    var menu_cursor: usize = 1; // default: 25 words
    var diff_cursor: usize = 1; // default: Medium
    var cat_cursor: usize = 0; // default: Common
    var anim_frame: u32 = 0;

    // Spawn background ticker for animation and timers (80ms interval).
    var running = std.atomic.Value(bool).init(true);
    const tick_thread = try std.Thread.spawn(.{}, tickThread, .{ &loop, &running });
    defer {
        running.store(false, .release);
        tick_thread.detach();
    }

    outer: while (true) {
        const event = loop.nextEvent();

        switch (event) {
            .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            .tick => {
                anim_frame +%= 1;
                // Check timed-mode expiry
                if (state == .typing and game.mode.isTimed() and game.start_time != null) {
                    if (game.isTimeUp()) {
                        game.end_time = game.start_time.? + game.mode.timeLimitMs();
                        state = .results;
                    }
                }
            },
            .key_press => |key| {
                switch (state) {
                    // ── Menu ─────────────────────────────────────────────
                    .menu => {
                        if (key.matches('c', .{ .ctrl = true })) break :outer;
                        if (key.matches(vaxis.Key.escape, .{})) break :outer;

                        // Navigate modes (j/k / up/down)
                        if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) {
                            if (menu_cursor > 0) menu_cursor -= 1;
                        }
                        if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) {
                            if (menu_cursor < game_m.ALL_MODES.len - 1) menu_cursor += 1;
                        }

                        // Navigate difficulty (h/l / left/right)
                        if (key.matches(vaxis.Key.left, .{}) or key.matches('h', .{})) {
                            if (diff_cursor > 0) diff_cursor -= 1;
                        }
                        if (key.matches(vaxis.Key.right, .{}) or key.matches('l', .{})) {
                            if (diff_cursor < game_m.ALL_DIFFICULTIES.len - 1) diff_cursor += 1;
                        }

                        // Navigate category (w/s / shift+left/right)
                        if (key.matches('w', .{}) or key.matches(vaxis.Key.page_up, .{})) {
                            if (cat_cursor > 0) cat_cursor -= 1;
                        }
                        if (key.matches('s', .{}) or key.matches(vaxis.Key.page_down, .{})) {
                            if (cat_cursor < words_mod.ALL_CATEGORIES.len - 1) cat_cursor += 1;
                        }

                        // Start game
                        if (key.matches(vaxis.Key.enter, .{})) {
                            const mode = game_m.ALL_MODES[menu_cursor];
                            const diff = game_m.ALL_DIFFICULTIES[diff_cursor];
                            const cat = words_mod.ALL_CATEGORIES[cat_cursor];
                            game.resetWithCategory(mode, diff, cat);
                            state = .typing;
                        }

                        // Quick-start shortcuts
                        if (key.matches('1', .{})) {
                            game.resetWithCategory(.words_10, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                        if (key.matches('2', .{})) {
                            game.resetWithCategory(.words_25, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                        if (key.matches('3', .{})) {
                            game.resetWithCategory(.words_50, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                        if (key.matches('4', .{})) {
                            game.resetWithCategory(.words_100, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                        if (key.matches('5', .{})) {
                            game.resetWithCategory(.words_200, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                        if (key.matches('6', .{})) {
                            game.resetWithCategory(.words_500, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                        if (key.matches('7', .{})) {
                            game.resetWithCategory(.timed_15, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                        if (key.matches('8', .{})) {
                            game.resetWithCategory(.timed_30, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                        if (key.matches('9', .{})) {
                            game.resetWithCategory(.timed_60, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                        if (key.matches('0', .{})) {
                            game.resetWithCategory(.timed_120, game_m.ALL_DIFFICULTIES[diff_cursor], words_mod.ALL_CATEGORIES[cat_cursor]);
                            state = .typing;
                        }
                    },

                    // ── Typing ───────────────────────────────────────────
                    .typing => {
                        if (key.matches('c', .{ .ctrl = true })) break :outer;
                        if (key.matches(vaxis.Key.escape, .{})) {
                            state = .menu;
                        } else if (key.matches(vaxis.Key.tab, .{})) {
                            game.reset(game.mode, game.difficulty);
                        } else if (key.matches(vaxis.Key.backspace, .{})) {
                            handleBackspace(&game);
                        } else {
                            const cp = key.codepoint;
                            if (cp >= 0x20 and cp <= 0x7E) {
                                handleChar(&game, @intCast(cp), &state);
                            }
                        }
                    },

                    // ── Results ──────────────────────────────────────────
                    .results => {
                        if (key.matches('c', .{ .ctrl = true })) break :outer;
                        if (key.matches(vaxis.Key.escape, .{})) break :outer;
                        if (key.matches(vaxis.Key.enter, .{}) or key.matches('r', .{})) {
                            game.reset(game.mode, game.difficulty);
                            state = .typing;
                        }
                        if (key.matches(vaxis.Key.tab, .{})) {
                            state = .menu;
                        }
                    },
                }
            },
            else => {},
        }

        const win = vx.window();
        win.clear();
        win.hideCursor();

        switch (state) {
            .menu => render.drawMenu(win, menu_cursor, diff_cursor, cat_cursor, anim_frame),
            .typing => render.drawTyping(win, &game),
            .results => render.drawResults(win, &game),
        }

        try vx.render(tty.writer());
    }
}

fn handleBackspace(game: *game_m.Game) void {
    if (game.input_len == 0) return;
    game.backspace_count += 1;
    game.input_len -= 1;
    const word = game.words[game.current_word];
    if (game.input_len < word.len) {
        if (game.input_buf[game.input_len] == word[game.input_len]) {
            if (game.correct_chars > 0) game.correct_chars -= 1;
        } else {
            if (game.incorrect_chars > 0) game.incorrect_chars -= 1;
        }
    } else {
        if (game.incorrect_chars > 0) game.incorrect_chars -= 1;
    }
}

fn handleChar(game: *game_m.Game, c: u8, state: *AppState) void {
    if (game.start_time == null) {
        game.start_time = std.time.milliTimestamp();
    }
    if (c == ' ') {
        game.total_chars_typed += 1;
        game.finishWord();
        if (game.current_word >= game.word_count) {
            game.end_time = std.time.milliTimestamp();
            state.* = .results;
        }
        return;
    }
    if (game.input_len >= game_m.MAX_INPUT) return;
    game.total_chars_typed += 1;
    const word = game.words[game.current_word];
    if (game.input_len < word.len) {
        if (c == word[game.input_len]) {
            game.correct_chars += 1;
        } else {
            game.incorrect_chars += 1;
            game.char_errors[word[game.input_len]] += 1;
        }
    } else {
        game.incorrect_chars += 1;
    }
    game.input_buf[game.input_len] = c;
    game.input_len += 1;
}
