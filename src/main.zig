// Kizamu - Typing Practice
// Entry-point and event loop.
const std = @import("std");
const vaxis = @import("vaxis");
const game_m = @import("game.zig");
const render = @import("render.zig");

const AppState = enum { menu, typing, results };

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    focus_out,
};

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
    var menu_cursor: usize = 1;

    outer: while (true) {
        const event = loop.nextEvent();

        switch (event) {
            .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            .key_press => |key| {
                switch (state) {
                    .menu => {
                        if (key.matches('c', .{ .ctrl = true })) break :outer;
                        if (key.matches(vaxis.Key.escape, .{})) break :outer;
                        if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) {
                            if (menu_cursor > 0) menu_cursor -= 1;
                        }
                        if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) {
                            if (menu_cursor < game_m.ALL_MODES.len - 1) menu_cursor += 1;
                        }
                        if (key.matches(vaxis.Key.enter, .{})) {
                            game.reset(game_m.ALL_MODES[menu_cursor]);
                            state = .typing;
                        }
                        if (key.matches('1', .{})) {
                            game.reset(.words_10);
                            state = .typing;
                        }
                        if (key.matches('2', .{})) {
                            game.reset(.words_25);
                            state = .typing;
                        }
                        if (key.matches('3', .{})) {
                            game.reset(.words_50);
                            state = .typing;
                        }
                        if (key.matches('4', .{})) {
                            game.reset(.words_100);
                            state = .typing;
                        }
                        if (key.matches('5', .{})) {
                            game.reset(.words_200);
                            state = .typing;
                        }
                    },
                    .typing => {
                        if (key.matches('c', .{ .ctrl = true })) break :outer;
                        if (key.matches(vaxis.Key.escape, .{})) {
                            state = .menu;
                        } else if (key.matches(vaxis.Key.tab, .{})) {
                            game.reset(game_m.GameMode.fromCount(game.word_count));
                        } else if (key.matches(vaxis.Key.backspace, .{})) {
                            handleBackspace(&game);
                        } else {
                            const cp = key.codepoint;
                            if (cp >= 0x20 and cp <= 0x7E) {
                                handleChar(&game, @intCast(cp), &state);
                            }
                        }
                    },
                    .results => {
                        if (key.matches('c', .{ .ctrl = true })) break :outer;
                        if (key.matches(vaxis.Key.escape, .{})) break :outer;
                        if (key.matches(vaxis.Key.enter, .{}) or key.matches('r', .{})) {
                            game.reset(game_m.GameMode.fromCount(game.word_count));
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
            .menu => render.drawMenu(win, menu_cursor),
            .typing => render.drawTyping(win, &game),
            .results => render.drawResults(win, &game),
        }

        try vx.render(tty.writer());
    }
}

fn handleBackspace(game: *game_m.Game) void {
    if (game.input_len == 0) return;
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
        game.finishWord();
        if (game.current_word >= game.word_count) {
            game.end_time = std.time.milliTimestamp();
            state.* = .results;
        }
        return;
    }
    if (game.input_len >= game_m.MAX_INPUT) return;
    const word = game.words[game.current_word];
    if (game.input_len < word.len) {
        if (c == word[game.input_len]) {
            game.correct_chars += 1;
        } else {
            game.incorrect_chars += 1;
        }
    } else {
        game.incorrect_chars += 1;
    }
    game.input_buf[game.input_len] = c;
    game.input_len += 1;
}
