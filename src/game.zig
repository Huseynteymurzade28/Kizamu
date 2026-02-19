const std = @import("std");
const words_mod = @import("words.zig");

// ─── Constants ───────────────────────────────────────────────────────────────
pub const MAX_WORDS = 200;
pub const MAX_INPUT = 64;

// ─── Game Mode ───────────────────────────────────────────────────────────────
pub const GameMode = enum {
    words_10,
    words_25,
    words_50,
    words_100,
    words_200,

    pub fn count(self: GameMode) usize {
        return switch (self) {
            .words_10 => 10,
            .words_25 => 25,
            .words_50 => 50,
            .words_100 => 100,
            .words_200 => 200,
        };
    }

    pub fn fromCount(n: usize) GameMode {
        return switch (n) {
            10 => .words_10,
            25 => .words_25,
            50 => .words_50,
            100 => .words_100,
            else => .words_200,
        };
    }

    pub fn label(self: GameMode) []const u8 {
        return switch (self) {
            .words_10 => "10 words",
            .words_25 => "25 words",
            .words_50 => "50 words",
            .words_100 => "100 words",
            .words_200 => "200 words",
        };
    }
};

pub const ALL_MODES = [_]GameMode{
    .words_10, .words_25, .words_50, .words_100, .words_200,
};

// ─── Simple LCG RNG ──────────────────────────────────────────────────────────
pub const Rng = struct {
    state: u64,

    pub fn init() Rng {
        const ns: u128 = @bitCast(std.time.nanoTimestamp());
        return .{ .state = @truncate(ns) };
    }

    pub fn next(self: *Rng) u64 {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        return self.state;
    }

    pub fn lessThan(self: *Rng, max: usize) usize {
        return @intCast(self.next() % max);
    }
};

// ─── Game State ──────────────────────────────────────────────────────────────
pub const Game = struct {
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
    mode: GameMode = .words_25,

    pub fn reset(self: *Game, m: GameMode) void {
        self.mode = m;
        self.word_count = m.count();
        self.current_word = 0;
        self.input_len = 0;
        self.correct_chars = 0;
        self.incorrect_chars = 0;
        self.word_correct = .{true} ** MAX_WORDS;
        self.start_time = null;
        self.end_time = null;

        var rng = Rng.init();
        for (0..self.word_count) |i| {
            self.words[i] = words_mod.word_list[rng.lessThan(words_mod.word_list.len)];
        }
    }

    /// Milliseconds elapsed since start (or since end if finished).
    pub fn elapsedMs(self: *const Game) i64 {
        const s = self.start_time orelse return 0;
        const e = self.end_time orelse std.time.milliTimestamp();
        return e - s;
    }

    /// Words per minute based on correctly-typed characters.
    pub fn wpm(self: *const Game) f64 {
        const ms = self.elapsedMs();
        if (ms <= 0) return 0;
        const minutes: f64 = @as(f64, @floatFromInt(ms)) / 60_000.0;
        return (@as(f64, @floatFromInt(self.correct_chars)) / 5.0) / minutes;
    }

    /// Accuracy as a percentage (0-100).
    pub fn accuracy(self: *const Game) f64 {
        const total = self.correct_chars + self.incorrect_chars;
        if (total == 0) return 100.0;
        return (@as(f64, @floatFromInt(self.correct_chars)) /
            @as(f64, @floatFromInt(total))) * 100.0;
    }

    /// Number of correctly-typed full words.
    pub fn correctWords(self: *const Game) usize {
        var n: usize = 0;
        for (0..self.current_word) |i| {
            if (self.word_correct[i]) n += 1;
        }
        return n;
    }

    /// Finish the current word (called on space-press).
    pub fn finishWord(self: *Game) void {
        const word = self.words[self.current_word];
        const ok = blk: {
            if (self.input_len != word.len) break :blk false;
            for (0..word.len) |i| {
                if (self.input_buf[i] != word[i]) break :blk false;
            }
            break :blk true;
        };
        self.word_correct[self.current_word] = ok;

        // Count the space as a correct character (standard WPM convention),
        // but not after the last word.
        if (self.current_word + 1 < self.word_count) {
            self.correct_chars += 1;
        }
        self.current_word += 1;
        self.input_len = 0;
    }
};
