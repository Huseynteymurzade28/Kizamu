// Kizamu — Game state, modes, difficulty, and statistics.
const std = @import("std");
const words_mod = @import("words.zig");

// ─── Constants ───────────────────────────────────────────────────────────────
pub const MAX_WORDS = 500;
pub const MAX_INPUT = 64;
pub const MAX_CATEGORY = 4;

// ─── Difficulty ──────────────────────────────────────────────────────────────
pub const Difficulty = enum {
    easy,
    medium,
    hard,

    pub fn label(self: Difficulty) []const u8 {
        return switch (self) {
            .easy => "Easy",
            .medium => "Medium",
            .hard => "Hard",
        };
    }

    pub fn poolSize(self: Difficulty) usize {
        return switch (self) {
            .easy => 100,
            .medium => 300,
            .hard => words_mod.common_words.len,
        };
    }
};

pub const ALL_DIFFICULTIES = [_]Difficulty{ .easy, .medium, .hard };

// ─── Game Mode ───────────────────────────────────────────────────────────────
pub const GameMode = enum {
    words_10,
    words_25,
    words_50,
    words_100,
    words_200,
    words_500,
    timed_15,
    timed_30,
    timed_60,
    timed_120,

    pub fn isTimed(self: GameMode) bool {
        return switch (self) {
            .timed_15, .timed_30, .timed_60, .timed_120 => true,
            else => false,
        };
    }

    pub fn timeLimitMs(self: GameMode) i64 {
        return switch (self) {
            .timed_15 => 15_000,
            .timed_30 => 30_000,
            .timed_60 => 60_000,
            .timed_120 => 120_000,
            else => 0,
        };
    }

    pub fn wordGenCount(self: GameMode) usize {
        return switch (self) {
            .words_10 => 10,
            .words_25 => 25,
            .words_50 => 50,
            .words_100 => 100,
            .words_200 => 200,
            .words_500 => 500,
            .timed_15, .timed_30, .timed_60, .timed_120 => MAX_WORDS,
        };
    }

    pub fn label(self: GameMode) []const u8 {
        return switch (self) {
            .words_10 => "10 words",
            .words_25 => "25 words",
            .words_50 => "50 words",
            .words_100 => "100 words",
            .words_200 => "200 words",
            .words_500 => "500 words",
            .timed_15 => "15 seconds",
            .timed_30 => "30 seconds",
            .timed_60 => "60 seconds",
            .timed_120 => "120 seconds",
        };
    }
};

pub const ALL_MODES = [_]GameMode{
    .words_10, .words_25, .words_50, .words_100, .words_200, .words_500,
    .timed_15, .timed_30, .timed_60, .timed_120,
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

// ─── Error tracking ──────────────────────────────────────────────────────────
pub const CharError = struct { char: u8, count: u16 };

// ─── Game State ──────────────────────────────────────────────────────────────
pub const Game = struct {
    words: [MAX_WORDS][]const u8 = .{""} ** MAX_WORDS,
    word_count: usize = 0,
    current_word: usize = 0,
    input_buf: [MAX_INPUT]u8 = undefined,
    input_len: usize = 0,
    correct_chars: usize = 0,
    incorrect_chars: usize = 0,
    total_chars_typed: usize = 0,
    backspace_count: usize = 0,
    char_errors: [128]u16 = .{0} ** 128,
    word_correct: [MAX_WORDS]bool = .{true} ** MAX_WORDS,
    start_time: ?i64 = null,
    end_time: ?i64 = null,
    mode: GameMode = .words_25,
    difficulty: Difficulty = .medium,
    category: words_mod.Category = .common,
    streak: usize = 0,
    best_wpm: f64 = 0.0,
    best_accuracy: f64 = 0.0,

    pub fn reset(self: *Game, m: GameMode, diff: Difficulty) void {
        self.mode = m;
        self.difficulty = diff;
        self.word_count = m.wordGenCount();
        self.current_word = 0;
        self.input_len = 0;
        self.correct_chars = 0;
        self.incorrect_chars = 0;
        self.total_chars_typed = 0;
        self.backspace_count = 0;
        self.char_errors = .{0} ** 128;
        self.word_correct = .{true} ** MAX_WORDS;
        self.start_time = null;
        self.end_time = null;

        var rng = Rng.init();
        const pool = diff.poolSize();
        const word_list = words_mod.getWordList(self.category);
        const pool_len = word_list.len;
        const actual_pool = if (pool > pool_len) pool_len else pool;
        for (0..self.word_count) |i| {
            self.words[i] = word_list[rng.lessThan(actual_pool)];
        }
    }

    pub fn resetWithCategory(self: *Game, m: GameMode, diff: Difficulty, cat: words_mod.Category) void {
        self.category = cat;
        self.reset(m, diff);
    }

    /// Milliseconds elapsed since start (or since end if finished).
    pub fn elapsedMs(self: *const Game) i64 {
        const s = self.start_time orelse return 0;
        const e = self.end_time orelse std.time.milliTimestamp();
        return e - s;
    }

    /// Net WPM based on correctly-typed characters.
    pub fn wpm(self: *const Game) f64 {
        const ms = self.elapsedMs();
        if (ms <= 0) return 0;
        const minutes: f64 = @as(f64, @floatFromInt(ms)) / 60_000.0;
        return (@as(f64, @floatFromInt(self.correct_chars)) / 5.0) / minutes;
    }

    /// Raw WPM based on all typed characters (before correction).
    pub fn rawWpm(self: *const Game) f64 {
        const ms = self.elapsedMs();
        if (ms <= 0) return 0;
        const minutes: f64 = @as(f64, @floatFromInt(ms)) / 60_000.0;
        return (@as(f64, @floatFromInt(self.total_chars_typed)) / 5.0) / minutes;
    }

    /// Accuracy as a percentage (0–100).
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

    /// Get the top N most-errored characters.  Returns entries written.
    pub fn topErrors(self: *const Game, out: []CharError) usize {
        var all: [96]CharError = undefined;
        var count: usize = 0;
        for (32..127) |ci| {
            if (self.char_errors[ci] > 0) {
                all[count] = .{ .char = @intCast(ci), .count = self.char_errors[ci] };
                count += 1;
            }
        }
        const n = @min(count, out.len);
        for (0..n) |i| {
            var max_idx: usize = i;
            for (i + 1..count) |j| {
                if (all[j].count > all[max_idx].count) max_idx = j;
            }
            const tmp = all[i];
            all[i] = all[max_idx];
            all[max_idx] = tmp;
            out[i] = all[i];
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

    /// Check if time has expired (for timed modes).
    pub fn isTimeUp(self: *const Game) bool {
        if (!self.mode.isTimed()) return false;
        const s = self.start_time orelse return false;
        const now = std.time.milliTimestamp();
        return (now - s) >= self.mode.timeLimitMs();
    }

    /// Remaining time in milliseconds (for timed modes).
    pub fn remainingMs(self: *const Game) i64 {
        if (!self.mode.isTimed()) return 0;
        const s = self.start_time orelse return self.mode.timeLimitMs();
        const elapsed = std.time.milliTimestamp() - s;
        const remaining = self.mode.timeLimitMs() - elapsed;
        return if (remaining > 0) remaining else 0;
    }

    /// Total keypresses (chars + backspaces).
    pub fn totalKeystrokes(self: *const Game) usize {
        return self.total_chars_typed + self.backspace_count;
    }
};
