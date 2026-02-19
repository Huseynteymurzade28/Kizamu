const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

// ═══════════════════════════════════════════════════════════════════════════
// Word List — 200 common English words
// ═══════════════════════════════════════════════════════════════════════════

const word_list = [_][]const u8{
    "the",    "be",     "to",    "of",     "and",     "a",      "in",    "that",
    "have",   "it",     "for",   "not",    "on",      "with",   "he",    "as",
    "you",    "do",     "at",    "this",   "but",     "his",    "by",    "from",
    "they",   "we",     "say",   "her",    "she",     "or",     "an",    "will",
    "my",     "one",    "all",   "would",  "there",   "their",  "what",  "so",
    "up",     "out",    "if",    "about",  "who",     "get",    "which", "go",
    "me",     "when",   "make",  "can",    "like",    "time",   "no",    "just",
    "him",    "know",   "take",  "people", "into",    "year",   "your",  "good",
    "some",   "could",  "them",  "see",    "other",   "than",   "then",  "now",
    "look",   "only",   "come",  "its",    "over",    "think",  "also",  "back",
    "after",  "use",    "two",   "how",    "our",     "work",   "first", "well",
    "way",    "even",   "new",   "want",   "because", "any",    "these", "give",
    "day",    "most",   "us",    "great",  "between", "need",   "large", "under",
    "never",  "each",   "right", "begin",  "help",    "always", "home",  "while",
    "above",  "last",   "both",  "life",   "long",    "still",  "small", "end",
    "hand",   "high",   "keep",  "place",  "where",   "much",   "might", "very",
    "start",  "own",    "part",  "move",   "fact",    "world",  "head",  "thing",
    "point",  "turn",   "old",   "play",   "run",     "set",    "few",   "house",
    "number", "same",   "side",  "water",  "been",    "call",   "find",  "more",
    "word",   "before", "must",  "down",   "should",  "kind",   "many",  "line",
    "name",   "again",  "off",   "came",   "too",     "does",   "tell",  "said",
    "found",  "next",   "every", "early",  "soon",    "hard",   "food",  "learn",
    "near",   "city",   "tree",  "read",   "paper",   "group",  "open",  "state",
    "close",  "night",  "real",  "often",  "light",   "change", "young", "stop",
    "land",   "story",  "face",  "watch",  "color",   "care",
};

// ═══════════════════════════════════════════════════════════════════════════
// Simple RNG (LCG — good enough for word shuffling)
// ═══════════════════════════════════════════════════════════════════════════

const Rng = struct {
    state: u64,

    fn init() Rng {
        const ns: u128 = @bitCast(std.time.nanoTimestamp());
        return .{ .state = @truncate(ns) };
    }

    fn next(self: *Rng) u64 {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        return self.state;
    }

    fn lessThan(self: *Rng, max: usize) usize {
        return @intCast(self.next() % max);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// Terminal — raw mode management
// ═══════════════════════════════════════════════════════════════════════════

const Terminal = struct {
    original: posix.termios,

    fn enableRawMode() !Terminal {
        const original = try posix.tcgetattr(posix.STDIN_FILENO);
        var raw = original;

        // Disable canonical mode, echo, signals, extended processing
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        // Disable input processing
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        // Disable output processing
        raw.oflag.OPOST = false;

        // Read returns after 1 byte, no timeout
        raw.cc[@intFromEnum(linux.V.MIN)] = 1;
        raw.cc[@intFromEnum(linux.V.TIME)] = 0;

        try posix.tcsetattr(posix.STDIN_FILENO, .NOW, raw);
        return .{ .original = original };
    }

    fn disableRawMode(self: *const Terminal) void {
        posix.tcsetattr(posix.STDIN_FILENO, .NOW, self.original) catch {};
    }

    fn readByte(_: *const Terminal) !u8 {
        var buf: [1]u8 = undefined;
        const n = try posix.read(posix.STDIN_FILENO, &buf);
        if (n == 0) return error.EndOfStream;
        return buf[0];
    }

    fn hasPendingInput(_: *const Terminal, timeout_ms: i32) !bool {
        var fds = [_]posix.pollfd{.{
            .fd = posix.STDIN_FILENO,
            .events = 1, // POLLIN
            .revents = 0,
        }};
        const n = try posix.poll(&fds, timeout_ms);
        return n > 0;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// Input — keyboard event parsing
// ═══════════════════════════════════════════════════════════════════════════

const Input = union(enum) {
    char: u8,
    backspace,
    enter,
    tab,
    escape,
    ctrl_c,
    unknown,
};

fn readInput(term: *const Terminal) !Input {
    const byte = try term.readByte();

    return switch (byte) {
        0x03 => .ctrl_c,
        0x09 => .tab,
        0x0D => .enter,
        0x1B => blk: {
            // Bare Escape or start of escape sequence (arrow keys etc.)
            if (try term.hasPendingInput(50)) {
                const next = term.readByte() catch break :blk .escape;
                if (next == '[') {
                    // CSI sequence — consume the final byte and ignore
                    if (try term.hasPendingInput(50)) {
                        _ = term.readByte() catch {};
                    }
                    break :blk .unknown;
                }
                break :blk .unknown;
            }
            break :blk .escape;
        },
        0x7F => .backspace,
        0x20...0x7E => .{ .char = byte },
        else => .unknown,
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// Game state
// ═══════════════════════════════════════════════════════════════════════════

const MAX_WORDS = 100;
const MAX_INPUT = 64;

const GameMode = enum {
    words_10,
    words_25,
    words_50,
    words_100,

    fn count(self: GameMode) usize {
        return switch (self) {
            .words_10 => 10,
            .words_25 => 25,
            .words_50 => 50,
            .words_100 => 100,
        };
    }

    fn fromCount(n: usize) GameMode {
        return switch (n) {
            10 => .words_10,
            25 => .words_25,
            50 => .words_50,
            else => .words_100,
        };
    }
};

const AppState = enum { menu, typing, results };

const Game = struct {
    words: [MAX_WORDS][]const u8 = .{""} ** MAX_WORDS,
    word_count: usize = 0,
    current_word: usize = 0,
    input_buf: [MAX_INPUT]u8 = undefined,
    input_len: usize = 0,
    correct_chars: usize = 0,
    incorrect_chars: usize = 0,
    word_correct: [MAX_WORDS]bool = .{true} ** MAX_WORDS,
    start_time: ?i64 = null,
    end_time: ?i64 = null,

    fn reset(self: *Game, mode: GameMode) void {
        self.word_count = mode.count();
        self.current_word = 0;
        self.input_len = 0;
        self.correct_chars = 0;
        self.incorrect_chars = 0;
        self.word_correct = .{true} ** MAX_WORDS;
        self.start_time = null;
        self.end_time = null;

        var rng = Rng.init();
        for (0..self.word_count) |i| {
            self.words[i] = word_list[rng.lessThan(word_list.len)];
        }
    }

    fn elapsedMs(self: *const Game) i64 {
        const s = self.start_time orelse return 0;
        const e = self.end_time orelse std.time.milliTimestamp();
        return e - s;
    }

    fn wpm(self: *const Game) f64 {
        const ms = self.elapsedMs();
        if (ms <= 0) return 0;
        const minutes = @as(f64, @floatFromInt(ms)) / 60000.0;
        return (@as(f64, @floatFromInt(self.correct_chars)) / 5.0) / minutes;
    }

    fn accuracy(self: *const Game) f64 {
        const total = self.correct_chars + self.incorrect_chars;
        if (total == 0) return 100.0;
        return (@as(f64, @floatFromInt(self.correct_chars)) /
            @as(f64, @floatFromInt(total))) * 100.0;
    }

    fn finishWord(self: *Game) void {
        const word = self.words[self.current_word];
        if (self.input_len != word.len) {
            self.word_correct[self.current_word] = false;
        } else {
            var ok = true;
            for (0..word.len) |i| {
                if (self.input_buf[i] != word[i]) {
                    ok = false;
                    break;
                }
            }
            self.word_correct[self.current_word] = ok;
        }
        // Count space as correct char (standard WPM includes spaces)
        // but not after the last word
        if (self.current_word + 1 < self.word_count) {
            self.correct_chars += 1;
        }
        self.current_word += 1;
        self.input_len = 0;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// Rendering helpers
// ═══════════════════════════════════════════════════════════════════════════

const BufWriter = std.io.FixedBufferStream([]u8).Writer;

fn writeRaw(data: []const u8) void {
    var off: usize = 0;
    while (off < data.len) {
        off += posix.write(posix.STDOUT_FILENO, data[off..]) catch return;
    }
}

fn moveTo(w: BufWriter, row: u16, col: u16) !void {
    try w.print("\x1b[{d};{d}H", .{ row, col });
}

// ═══════════════════════════════════════════════════════════════════════════
// Menu screen
// ═══════════════════════════════════════════════════════════════════════════

fn drawMenu(w: BufWriter, term_w: u16) !void {
    try w.writeAll("\x1b[2J\x1b[H\x1b[?25l");

    const cx: u16 = term_w / 2;
    const bx: u16 = if (cx >= 14) cx - 14 else 1;

    try moveTo(w, 3, bx);
    try w.writeAll("\x1b[36m╔════════════════════════════╗\x1b[0m");
    try moveTo(w, 4, bx);
    try w.writeAll("\x1b[36m║\x1b[0m  \x1b[1m\x1b[97mKIZAMU\x1b[0m                   \x1b[36m║\x1b[0m");
    try moveTo(w, 5, bx);
    try w.writeAll("\x1b[36m║\x1b[0m  \x1b[90mtyping practice\x1b[0m          \x1b[36m║\x1b[0m");
    try moveTo(w, 6, bx);
    try w.writeAll("\x1b[36m╠════════════════════════════╣\x1b[0m");
    try moveTo(w, 7, bx);
    try w.writeAll("\x1b[36m║\x1b[0m                            \x1b[36m║\x1b[0m");
    try moveTo(w, 8, bx);
    try w.writeAll("\x1b[36m║\x1b[0m   \x1b[33m[1]\x1b[0m   10 words          \x1b[36m║\x1b[0m");
    try moveTo(w, 9, bx);
    try w.writeAll("\x1b[36m║\x1b[0m   \x1b[33m[2]\x1b[0m   25 words          \x1b[36m║\x1b[0m");
    try moveTo(w, 10, bx);
    try w.writeAll("\x1b[36m║\x1b[0m   \x1b[33m[3]\x1b[0m   50 words          \x1b[36m║\x1b[0m");
    try moveTo(w, 11, bx);
    try w.writeAll("\x1b[36m║\x1b[0m   \x1b[33m[4]\x1b[0m  100 words          \x1b[36m║\x1b[0m");
    try moveTo(w, 12, bx);
    try w.writeAll("\x1b[36m║\x1b[0m                            \x1b[36m║\x1b[0m");
    try moveTo(w, 13, bx);
    try w.writeAll("\x1b[36m╚════════════════════════════╝\x1b[0m");

    try moveTo(w, 15, bx);
    try w.writeAll("  \x1b[90mPress 1-4 to start, Esc to quit\x1b[0m");
}

// ═══════════════════════════════════════════════════════════════════════════
// Typing screen
// ═══════════════════════════════════════════════════════════════════════════

fn drawTyping(w: BufWriter, game: *const Game, term_w: u16) !void {
    try w.writeAll("\x1b[2J\x1b[H\x1b[?25l");

    const margin: u16 = 4;
    const max_width: u16 = if (term_w > margin * 2 + 10) term_w - margin * 2 else 40;

    // Header
    try moveTo(w, 1, margin);
    try w.writeAll("\x1b[36m\x1b[1mKIZAMU\x1b[0m");

    // Live stats on the right
    if (game.start_time != null) {
        const stats_col: u16 = if (term_w > 30) term_w - 30 else margin + 10;
        try moveTo(w, 1, stats_col);
        try w.print("\x1b[90mWPM: \x1b[33m{d:.1}\x1b[90m | Acc: \x1b[33m{d:.1}%\x1b[0m", .{
            game.wpm(),
            game.accuracy(),
        });
    }

    // Separator
    try moveTo(w, 2, margin);
    try w.writeAll("\x1b[90m");
    {
        var i: u16 = 0;
        while (i < max_width) : (i += 1) {
            try w.writeAll("\xe2\x94\x80"); // ─ in UTF-8
        }
    }
    try w.writeAll("\x1b[0m");

    // Words display
    var row: u16 = 4;
    var col: u16 = margin;

    for (0..game.word_count) |word_idx| {
        const word = game.words[word_idx];
        const wlen: u16 = @intCast(word.len);

        // Word wrap
        if (col != margin and col + wlen > margin + max_width) {
            row += 1;
            col = margin;
        }

        try moveTo(w, row, col);

        if (word_idx < game.current_word) {
            // Completed word
            if (game.word_correct[word_idx]) {
                try w.writeAll("\x1b[32m"); // green
            } else {
                try w.writeAll("\x1b[31m"); // red
            }
            try w.writeAll(word);
            try w.writeAll("\x1b[0m");
        } else if (word_idx == game.current_word) {
            // Current word — character by character coloring
            for (0..word.len) |ci| {
                if (ci < game.input_len) {
                    if (game.input_buf[ci] == word[ci]) {
                        try w.writeAll("\x1b[32m"); // green
                    } else {
                        try w.writeAll("\x1b[31m\x1b[4m"); // red + underline
                    }
                    try w.writeByte(word[ci]);
                    try w.writeAll("\x1b[0m");
                } else if (ci == game.input_len) {
                    // Cursor position
                    try w.writeAll("\x1b[97m\x1b[4m"); // bright white + underline
                    try w.writeByte(word[ci]);
                    try w.writeAll("\x1b[0m");
                } else {
                    try w.writeAll("\x1b[90m"); // gray
                    try w.writeByte(word[ci]);
                    try w.writeAll("\x1b[0m");
                }
            }
            // Extra typed chars beyond word length
            if (game.input_len > word.len) {
                try w.writeAll("\x1b[31m\x1b[4m"); // red + underline
                for (word.len..game.input_len) |ei| {
                    try w.writeByte(game.input_buf[ei]);
                }
                try w.writeAll("\x1b[0m");
            }
        } else {
            // Future word
            try w.writeAll("\x1b[90m"); // gray
            try w.writeAll(word);
            try w.writeAll("\x1b[0m");
        }

        col += wlen + 1;
    }

    // Progress + help
    const info_row = row + 3;
    try moveTo(w, info_row, margin);
    try w.print("\x1b[90m{d}/{d} words\x1b[0m", .{ game.current_word, game.word_count });

    const help_col: u16 = if (term_w > 30) term_w - 28 else margin;
    try moveTo(w, info_row, help_col);
    try w.writeAll("\x1b[90m[Tab] restart  [Esc] menu\x1b[0m");
}

// ═══════════════════════════════════════════════════════════════════════════
// Results screen
// ═══════════════════════════════════════════════════════════════════════════

fn drawResults(w: BufWriter, game: *const Game, term_w: u16) !void {
    try w.writeAll("\x1b[2J\x1b[H\x1b[?25l");

    const cx: u16 = term_w / 2;
    const bx: u16 = if (cx >= 16) cx - 16 else 1;
    const seconds = @as(f64, @floatFromInt(game.elapsedMs())) / 1000.0;

    try moveTo(w, 3, bx);
    try w.writeAll("\x1b[36m╔════════════════════════════════╗\x1b[0m");
    try moveTo(w, 4, bx);
    try w.writeAll("\x1b[36m║\x1b[0m          \x1b[1m\x1b[97mRESULTS\x1b[0m             \x1b[36m║\x1b[0m");
    try moveTo(w, 5, bx);
    try w.writeAll("\x1b[36m╠════════════════════════════════╣\x1b[0m");
    try moveTo(w, 6, bx);
    try w.writeAll("\x1b[36m║\x1b[0m                                \x1b[36m║\x1b[0m");

    try moveTo(w, 7, bx);
    try w.print("\x1b[36m║\x1b[0m  WPM:       \x1b[33m\x1b[1m{d:>8.1}\x1b[0m         \x1b[36m║\x1b[0m", .{game.wpm()});

    try moveTo(w, 8, bx);
    try w.print("\x1b[36m║\x1b[0m  Accuracy:  \x1b[33m\x1b[1m{d:>7.1}%\x1b[0m         \x1b[36m║\x1b[0m", .{game.accuracy()});

    try moveTo(w, 9, bx);
    try w.print("\x1b[36m║\x1b[0m  Time:      \x1b[97m{d:>7.1}s\x1b[0m         \x1b[36m║\x1b[0m", .{seconds});

    try moveTo(w, 10, bx);
    try w.print("\x1b[36m║\x1b[0m  Words:     \x1b[97m{d:>8}\x1b[0m         \x1b[36m║\x1b[0m", .{game.word_count});

    try moveTo(w, 11, bx);
    try w.print("\x1b[36m║\x1b[0m  Correct:   \x1b[32m{d:>8}\x1b[0m         \x1b[36m║\x1b[0m", .{game.correct_chars});

    try moveTo(w, 12, bx);
    try w.print("\x1b[36m║\x1b[0m  Errors:    \x1b[31m{d:>8}\x1b[0m         \x1b[36m║\x1b[0m", .{game.incorrect_chars});

    try moveTo(w, 13, bx);
    try w.writeAll("\x1b[36m║\x1b[0m                                \x1b[36m║\x1b[0m");
    try moveTo(w, 14, bx);
    try w.writeAll("\x1b[36m╚════════════════════════════════╝\x1b[0m");

    try moveTo(w, 16, bx);
    try w.writeAll("  \x1b[90m[Enter] play again  [Tab] menu  [Esc] quit\x1b[0m");
}

// ═══════════════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════════════

pub fn main() !void {
    var term = try Terminal.enableRawMode();
    defer {
        writeRaw("\x1b[?1049l"); // leave alt screen
        writeRaw("\x1b[?25h"); // show cursor
        writeRaw("\x1b[0m"); // reset colors
        term.disableRawMode();
    }

    // Enter alternate screen buffer
    writeRaw("\x1b[?1049h");

    var screen_buf: [32768]u8 = undefined;
    var game = Game{};
    var state: AppState = .menu;
    const term_w: u16 = 80; // sensible default

    while (true) {
        var fbs = std.io.fixedBufferStream(&screen_buf);
        const w = fbs.writer();

        switch (state) {
            .menu => {
                try drawMenu(w, term_w);
                writeRaw(fbs.getWritten());

                const input = try readInput(&term);
                switch (input) {
                    .char => |c| switch (c) {
                        '1' => {
                            game.reset(.words_10);
                            state = .typing;
                        },
                        '2' => {
                            game.reset(.words_25);
                            state = .typing;
                        },
                        '3' => {
                            game.reset(.words_50);
                            state = .typing;
                        },
                        '4' => {
                            game.reset(.words_100);
                            state = .typing;
                        },
                        else => {},
                    },
                    .escape, .ctrl_c => return,
                    else => {},
                }
            },

            .typing => {
                try drawTyping(w, &game, term_w);
                writeRaw(fbs.getWritten());

                const input = try readInput(&term);
                switch (input) {
                    .char => |c| {
                        if (game.start_time == null) {
                            game.start_time = std.time.milliTimestamp();
                        }

                        if (c == ' ') {
                            game.finishWord();
                            if (game.current_word >= game.word_count) {
                                game.end_time = std.time.milliTimestamp();
                                state = .results;
                            }
                        } else {
                            if (game.input_len < MAX_INPUT) {
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
                        }
                    },
                    .backspace => {
                        if (game.input_len > 0) {
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
                    },
                    .tab => {
                        game.reset(GameMode.fromCount(game.word_count));
                    },
                    .escape, .ctrl_c => {
                        state = .menu;
                    },
                    else => {},
                }
            },

            .results => {
                try drawResults(w, &game, term_w);
                writeRaw(fbs.getWritten());

                const input = try readInput(&term);
                switch (input) {
                    .enter => {
                        game.reset(GameMode.fromCount(game.word_count));
                        state = .typing;
                    },
                    .tab => {
                        state = .menu;
                    },
                    .escape, .ctrl_c => return,
                    else => {},
                }
            },
        }
    }
}
