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

fn tickThread(loop: *vaxis.Loop(Event), running: *std.atomic.Value(bool)) void {
    const req = std.os.linux.timespec{ .sec = 0, .nsec = 80 * std.time.ns_per_ms };
    while (running.load(.acquire)) {
        _ = std.os.linux.clock_nanosleep(.MONOTONIC, .{ .ABSTIME = false }, &req, null);
        loop.postEvent(.{ .tick = {} }) catch {};
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var tty_buf: [4096 * 4]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buf);
    defer tty.deinit();

    var vx = try vaxis.init(io, allocator, init.environ_map, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    defer vx.exitAltScreen(tty.writer()) catch {};
    try vx.queryTerminalSend(tty.writer());

    var game = game_m.Game{};
    var state = AppState.menu;
    var menu_cursor: usize = 1;   // default: 25 words
    var diff_cursor: usize = 1;   // default: Medium
    var cat_cursor: usize = 0;    // default: Common
    var theme_idx: usize = 0;     // default: Tokyo Night
    var anim_frame: u32 = 0;

    var running = std.atomic.Value(bool).init(true);
    const tick_thread = try std.Thread.spawn(.{}, tickThread, .{ &loop, &running });
    defer {
        running.store(false, .release);
        tick_thread.detach();
    }

    outer: while (true) {
        const event = try loop.nextEvent();

        switch (event) {
            .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            .tick => {
                anim_frame +%= 1;
                if (state == .typing and game.mode.isTimed() and game.start_time != null) {
                    if (game.isTimeUp()) {
                        game.end_time = game_m.milliTimestamp();
                        game.recordSession();
                        state = .results;
                    }
                }
            },
            .key_press => |key| {
                // Theme cycling works in all states
                if (key.matches('t', .{})) {
                    theme_idx = (theme_idx + 1) % render.THEME_COUNT;
                }

                switch (state) {
                    // ── Menu ───────────────────────────────────────────────
                    .menu => {
                        if (key.matches('c', .{ .ctrl = true })) break :outer;
                        if (key.matches(vaxis.Key.escape, .{})) break :outer;

                        // Navigate modes
                        if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) {
                            if (menu_cursor > 0) menu_cursor -= 1;
                        }
                        if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) {
                            if (menu_cursor < game_m.ALL_MODES.len - 1) menu_cursor += 1;
                        }

                        // Navigate difficulty
                        if (key.matches(vaxis.Key.left, .{}) or key.matches('h', .{})) {
                            if (diff_cursor > 0) diff_cursor -= 1;
                        }
                        if (key.matches(vaxis.Key.right, .{}) or key.matches('l', .{})) {
                            if (diff_cursor < game_m.ALL_DIFFICULTIES.len - 1) diff_cursor += 1;
                        }

                        // Navigate category
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

                        // Quick-start: word count modes (1-6)
                        if (key.matches('1', .{})) startGame(&game, &state, .words_10,  diff_cursor, cat_cursor);
                        if (key.matches('2', .{})) startGame(&game, &state, .words_25,  diff_cursor, cat_cursor);
                        if (key.matches('3', .{})) startGame(&game, &state, .words_50,  diff_cursor, cat_cursor);
                        if (key.matches('4', .{})) startGame(&game, &state, .words_100, diff_cursor, cat_cursor);
                        if (key.matches('5', .{})) startGame(&game, &state, .words_200, diff_cursor, cat_cursor);
                        if (key.matches('6', .{})) startGame(&game, &state, .words_500, diff_cursor, cat_cursor);
                        // Quick-start: timed modes (7-0)
                        if (key.matches('7', .{})) startGame(&game, &state, .timed_15,  diff_cursor, cat_cursor);
                        if (key.matches('8', .{})) startGame(&game, &state, .timed_30,  diff_cursor, cat_cursor);
                        if (key.matches('9', .{})) startGame(&game, &state, .timed_60,  diff_cursor, cat_cursor);
                        if (key.matches('0', .{})) startGame(&game, &state, .timed_120, diff_cursor, cat_cursor);
                        // Quick-start: challenge modes
                        if (key.matches('z', .{})) startGame(&game, &state, .zen,           diff_cursor, cat_cursor);
                        if (key.matches('d', .{})) startGame(&game, &state, .sudden_death,  diff_cursor, cat_cursor);
                        if (key.matches('a', .{})) startGame(&game, &state, .accuracy_rush, diff_cursor, cat_cursor);
                    },

                    // ── Typing ─────────────────────────────────────────────
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

                    // ── Results ────────────────────────────────────────────
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
            .menu    => render.drawMenu(win, menu_cursor, diff_cursor, cat_cursor, theme_idx, anim_frame),
            .typing  => render.drawTyping(win, &game, theme_idx),
            .results => render.drawResults(win, &game, theme_idx),
        }

        try vx.render(tty.writer());
    }
}

fn startGame(game: *game_m.Game, state: *AppState, mode: game_m.GameMode, diff_cursor: usize, cat_cursor: usize) void {
    const diff = game_m.ALL_DIFFICULTIES[diff_cursor];
    const cat = words_mod.ALL_CATEGORIES[cat_cursor];
    game.resetWithCategory(mode, diff, cat);
    state.* = .typing;
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
        game.start_time = game_m.milliTimestamp();
    }
    if (c == ' ') {
        game.total_chars_typed += 1;
        const word_ok = game.finishWord();

        // Sudden death: wrong word ends the game
        if (game.mode == .sudden_death and !word_ok) {
            game.end_time = game_m.milliTimestamp();
            game.over_reason = .sudden_death;
            game.recordSession();
            state.* = .results;
            return;
        }

        // Accuracy rush: low accuracy ends the game
        if (game.isAccuracyFailed()) {
            game.end_time = game_m.milliTimestamp();
            game.over_reason = .accuracy_fail;
            game.recordSession();
            state.* = .results;
            return;
        }

        // Zen: never ends on word count (completes at 500 words like others)
        if (game.current_word >= game.word_count) {
            game.end_time = game_m.milliTimestamp();
            game.recordSession();
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
