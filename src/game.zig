// Kizamu — Game state, modes, difficulty, and statistics.
const std = @import("std");
const linux = std.os.linux;
const words_mod = @import("words.zig");

pub fn milliTimestamp() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.REALTIME, &ts);
    return ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
}

pub const MAX_WORDS = 500;
pub const MAX_INPUT = 64;
pub const WPM_HISTORY = 48;
pub const ACCURACY_RUSH_THRESHOLD: f64 = 85.0;

// ─── Difficulty ───────────────────────────────────────────────────────────────
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

// ─── Game Over Reason ─────────────────────────────────────────────────────────
pub const GameOverReason = enum { normal, sudden_death, accuracy_fail };

// ─── Game Mode ────────────────────────────────────────────────────────────────
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
    zen,
    sudden_death,
    accuracy_rush,

    pub fn isTimed(self: GameMode) bool {
        return switch (self) {
            .timed_15, .timed_30, .timed_60, .timed_120,
            .sudden_death, .accuracy_rush => true,
            else => false,
        };
    }

    pub fn isChallenge(self: GameMode) bool {
        return switch (self) {
            .zen, .sudden_death, .accuracy_rush => true,
            else => false,
        };
    }

    pub fn timeLimitMs(self: GameMode) i64 {
        return switch (self) {
            .timed_15 => 15_000,
            .timed_30 => 30_000,
            .timed_60 => 60_000,
            .timed_120 => 120_000,
            .sudden_death => 30_000,
            .accuracy_rush => 60_000,
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
            else => MAX_WORDS,
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
            .zen => "Zen",
            .sudden_death => "Sudden Death",
            .accuracy_rush => "Accuracy Rush",
        };
    }

    pub fn challengeDesc(self: GameMode) []const u8 {
        return switch (self) {
            .zen => "endless flow, no pressure",
            .sudden_death => "wrong word = game over  [30s]",
            .accuracy_rush => "<85% accuracy = over  [60s]",
            else => "",
        };
    }
};

pub const ALL_MODES = [_]GameMode{
    .words_10,    .words_25, .words_50,      .words_100, .words_200,   .words_500,
    .timed_15,    .timed_30, .timed_60,      .timed_120,
    .zen,         .sudden_death,             .accuracy_rush,
};

// ─── Simple LCG RNG ───────────────────────────────────────────────────────────
pub const Rng = struct {
    state: u64,

    pub fn init() Rng {
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(.MONOTONIC, &ts);
        const ns: u64 = @bitCast(ts.sec *% 1_000_000_000 +% ts.nsec);
        return .{ .state = ns ^ 0xdeadbeefcafe1234 };
    }

    pub fn next(self: *Rng) u64 {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        return self.state;
    }

    pub fn lessThan(self: *Rng, max: usize) usize {
        return @intCast(self.next() % max);
    }
};

pub const CharError = struct { char: u8, count: u16 };

// ─── Game State ───────────────────────────────────────────────────────────────
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
    // WPM history for sparkline and consistency
    wpm_samples: [WPM_HISTORY]f32 = .{0} ** WPM_HISTORY,
    wpm_sample_count: usize = 0,
    // Game outcome
    over_reason: GameOverReason = .normal,
    // Session stats (persist across resets)
    session_best_wpm: f64 = 0.0,
    session_games: u32 = 0,

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
        self.wpm_samples = .{0} ** WPM_HISTORY;
        self.wpm_sample_count = 0;
        self.over_reason = .normal;

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

    fn sampleWpm(self: *Game) void {
        const w = self.wpm();
        if (w <= 0) return;
        const sample: f32 = @floatCast(@min(w, 300.0));
        if (self.wpm_sample_count < WPM_HISTORY) {
            self.wpm_samples[self.wpm_sample_count] = sample;
            self.wpm_sample_count += 1;
        } else {
            var i: usize = 0;
            while (i < WPM_HISTORY - 1) : (i += 1) {
                self.wpm_samples[i] = self.wpm_samples[i + 1];
            }
            self.wpm_samples[WPM_HISTORY - 1] = sample;
        }
    }

    /// Fill `out` with WPM samples in chronological order. Returns count written.
    pub fn wpmSamples(self: *const Game, out: []f32) usize {
        const n = @min(self.wpm_sample_count, out.len);
        for (0..n) |i| out[i] = self.wpm_samples[i];
        return n;
    }

    pub fn elapsedMs(self: *const Game) i64 {
        const s = self.start_time orelse return 0;
        const e = self.end_time orelse milliTimestamp();
        return e - s;
    }

    pub fn wpm(self: *const Game) f64 {
        const ms = self.elapsedMs();
        if (ms <= 0) return 0;
        const minutes: f64 = @as(f64, @floatFromInt(ms)) / 60_000.0;
        return (@as(f64, @floatFromInt(self.correct_chars)) / 5.0) / minutes;
    }

    pub fn rawWpm(self: *const Game) f64 {
        const ms = self.elapsedMs();
        if (ms <= 0) return 0;
        const minutes: f64 = @as(f64, @floatFromInt(ms)) / 60_000.0;
        return (@as(f64, @floatFromInt(self.total_chars_typed)) / 5.0) / minutes;
    }

    pub fn cpm(self: *const Game) f64 {
        const ms = self.elapsedMs();
        if (ms <= 0) return 0;
        const minutes: f64 = @as(f64, @floatFromInt(ms)) / 60_000.0;
        return @as(f64, @floatFromInt(self.correct_chars)) / minutes;
    }

    pub fn consistency(self: *const Game) f64 {
        const n = self.wpm_sample_count;
        if (n < 2) return 100.0;
        var sum: f64 = 0;
        for (0..n) |i| sum += self.wpm_samples[i];
        const mean = sum / @as(f64, @floatFromInt(n));
        if (mean <= 0) return 100.0;
        var variance: f64 = 0;
        for (0..n) |i| {
            const diff = @as(f64, self.wpm_samples[i]) - mean;
            variance += diff * diff;
        }
        variance /= @as(f64, @floatFromInt(n));
        const std_dev = @sqrt(variance);
        const cv = (std_dev / mean) * 100.0;
        return @max(0.0, @min(100.0, 100.0 - cv));
    }

    pub fn accuracy(self: *const Game) f64 {
        const total = self.correct_chars + self.incorrect_chars;
        if (total == 0) return 100.0;
        return (@as(f64, @floatFromInt(self.correct_chars)) /
            @as(f64, @floatFromInt(total))) * 100.0;
    }

    pub fn correctWords(self: *const Game) usize {
        var n: usize = 0;
        for (0..self.current_word) |i| {
            if (self.word_correct[i]) n += 1;
        }
        return n;
    }

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

    /// Finish the current word on space-press. Returns true if word was correct.
    pub fn finishWord(self: *Game) bool {
        const word = self.words[self.current_word];
        const ok = blk: {
            if (self.input_len != word.len) break :blk false;
            for (0..word.len) |i| {
                if (self.input_buf[i] != word[i]) break :blk false;
            }
            break :blk true;
        };
        self.word_correct[self.current_word] = ok;
        if (self.current_word + 1 < self.word_count) {
            self.correct_chars += 1;
        }
        self.current_word += 1;
        self.input_len = 0;
        self.sampleWpm();
        return ok;
    }

    pub fn isTimeUp(self: *const Game) bool {
        if (!self.mode.isTimed()) return false;
        const s = self.start_time orelse return false;
        return (milliTimestamp() - s) >= self.mode.timeLimitMs();
    }

    pub fn remainingMs(self: *const Game) i64 {
        if (!self.mode.isTimed()) return 0;
        const s = self.start_time orelse return self.mode.timeLimitMs();
        const elapsed = milliTimestamp() - s;
        const remaining = self.mode.timeLimitMs() - elapsed;
        return if (remaining > 0) remaining else 0;
    }

    pub fn totalKeystrokes(self: *const Game) usize {
        return self.total_chars_typed + self.backspace_count;
    }

    /// True when accuracy drops below threshold after a grace period.
    pub fn isAccuracyFailed(self: *const Game) bool {
        if (self.mode != .accuracy_rush) return false;
        if (self.current_word < 5) return false;
        return self.accuracy() < ACCURACY_RUSH_THRESHOLD;
    }

    pub fn recordSession(self: *Game) void {
        const w = self.wpm();
        if (w > self.session_best_wpm) self.session_best_wpm = w;
        self.session_games += 1;
    }
};
