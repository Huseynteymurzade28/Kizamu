const std = @import("std");
const posix = std.posix;

// =============================================================================
// Linux input_event struct (from <linux/input.h>)
// =============================================================================
//
// The kernel delivers input events as a stream of fixed-size structs.
// We define the struct manually (no @cImport) using `extern struct` so that
// Zig guarantees C-ABI-compatible layout: fields are laid out in declaration
// order with natural alignment, matching what the kernel writes.
//
// C definition (64-bit):
//
//   struct input_event {
//       struct timeval time;    // { long tv_sec; long tv_usec; }  → 16 bytes
//       __u16 type;             // event type                      →  2 bytes
//       __u16 code;             // event code (key scancode, etc.) →  2 bytes
//       __s32 value;            // value (0/1/2 for keys)          →  4 bytes
//   };                          //                          total  = 24 bytes
//
// On 64-bit Linux, `long` is 8 bytes, so timeval is 16 bytes.
// There is no padding between the fields because u16+u16+i32 = 8 bytes,
// which is already naturally aligned after the 16-byte timeval block.
// =============================================================================
const InputEvent = extern struct {
    /// Seconds since Unix epoch (struct timeval.tv_sec — kernel `long`)
    tv_sec: i64,
    /// Microseconds component  (struct timeval.tv_usec — kernel `long`)
    tv_usec: i64,

    /// Event type: EV_SYN(0x00), EV_KEY(0x01), EV_REL(0x02), EV_ABS(0x03)…
    type: u16,
    /// Event code: scancode for EV_KEY, axis id for EV_REL/EV_ABS, etc.
    code: u16,
    /// Event value: for EV_KEY → 0 = released, 1 = pressed, 2 = repeat
    value: i32,
};

// Compile-time sanity check: the struct must be exactly 24 bytes on 64-bit.
comptime {
    if (@sizeOf(InputEvent) != 24) {
        @compileError("InputEvent size mismatch — expected 24 bytes (64-bit Linux)");
    }
}

// Event type constant from <linux/input-event-codes.h>
const EV_KEY: u16 = 0x01;

// Key state values
const KEY_RELEASED: i32 = 0;
const KEY_PRESSED: i32 = 1;
const KEY_REPEAT: i32 = 2;

/// Read exactly `buf.len` bytes from a POSIX fd using the raw read() syscall.
/// Device files like /dev/input/eventX are *streaming* — they do not support
/// positional reads (pread). We must use plain read() and loop to handle
/// potential short reads (though evdev typically delivers complete events).
fn readExact(fd: posix.fd_t, buf: []u8) !usize {
    var index: usize = 0;
    while (index < buf.len) {
        const n = posix.read(fd, buf[index..]) catch |err| {
            return err;
        };
        if (n == 0) return index; // EOF — device disconnected
        index += n;
    }
    return index;
}

/// Scan /proc/bus/input/devices to find the first keyboard event device.
/// Returns the path (e.g. "/dev/input/event0") or null if not found.
fn findKeyboardDevice(out_buf: []u8) ?[]const u8 {
    const data = std.fs.cwd().readFile("/proc/bus/input/devices", out_buf) catch return null;

    // Parse the devices file block by block.
    // Each device block starts with "I:" and contains N:, P:, S:, U:, H:, B: lines.
    // We look for EV= bitmask that includes bit 1 (EV_KEY) and a Handlers line
    // with "kbd" + "eventN" — this identifies a real keyboard.
    var it = std.mem.splitSequence(u8, data, "\n\n");
    while (it.next()) |block| {
        // Must have "kbd" handler (kernel keyboard driver attached)
        const has_kbd = std.mem.indexOf(u8, block, "kbd") != null;
        if (!has_kbd) continue;

        // Must have "sysrq" — the main system keyboard has sysrq support
        const has_sysrq = std.mem.indexOf(u8, block, "sysrq") != null;
        if (!has_sysrq) continue;

        // Extract "eventN" from Handlers line
        if (std.mem.indexOf(u8, block, "event")) |ev_pos| {
            // Find the start of "event" followed by digits
            const after_event = block[ev_pos..];
            const event_prefix = "event";
            var end: usize = event_prefix.len;
            while (end < after_event.len and after_event[end] >= '0' and after_event[end] <= '9') {
                end += 1;
            }
            if (end > event_prefix.len) {
                const event_name = after_event[0..end]; // e.g. "event0"
                const prefix = "/dev/input/";
                var path_buf: [64]u8 = undefined;
                const path = std.fmt.bufPrint(&path_buf, "{s}{s}", .{ prefix, event_name }) catch return null;
                // Copy to caller's buffer so we can return a stable slice
                if (path.len <= out_buf.len) {
                    // We'll reuse the very end of out_buf for the path
                    const dest_start = out_buf.len - path.len;
                    @memcpy(out_buf[dest_start..], path);
                    return out_buf[dest_start..];
                }
            }
        }
    }
    return null;
}

pub fn main() !void {
    // ── Argument parsing ────────────────────────────────────────────────
    var args = std.process.args();
    _ = args.next(); // skip argv[0] (program name)

    // Auto-detect keyboard if no argument given
    var detect_buf: [8192]u8 = undefined;
    const device_path: []const u8 = args.next() orelse blk: {
        if (findKeyboardDevice(&detect_buf)) |path| {
            std.debug.print("Klavye otomatik tespit edildi: {s}\n", .{path});
            break :blk path;
        }
        std.debug.print("Kullanim: kizamu <cihaz_yolu>\n", .{});
        std.debug.print("Ornek:    sudo ./zig-out/bin/kizamu /dev/input/event0\n\n", .{});
        std.debug.print("Mevcut cihazlari gormek icin:\n", .{});
        std.debug.print("  cat /proc/bus/input/devices\n", .{});
        std.debug.print("  ls -la /dev/input/event*\n", .{});
        std.process.exit(1);
    };

    // ── Open the input device ───────────────────────────────────────────
    // We use std.fs.openFileAbsolute because device paths are always absolute
    // (e.g. /dev/input/event0). Read-only is sufficient — we only consume events.
    const file = std.fs.openFileAbsolute(device_path, .{ .mode = .read_only }) catch |err| {
        switch (err) {
            error.AccessDenied => {
                std.debug.print("Hata: Erisim reddedildi — '{s}'\n", .{device_path});
                std.debug.print("  sudo ile calistirmayi deneyin:\n", .{});
                std.debug.print("  sudo ./zig-out/bin/kizamu {s}\n", .{device_path});
            },
            error.FileNotFound => {
                std.debug.print("Hata: Cihaz bulunamadi — '{s}'\n", .{device_path});
                std.debug.print("  Mevcut cihazlari listeleyin:\n", .{});
                std.debug.print("  ls -la /dev/input/event*\n", .{});
            },
            else => {
                std.debug.print("Hata: Cihaz acilamadi — {}\n", .{err});
            },
        }
        std.process.exit(1);
    };
    defer file.close();

    // Get the raw file descriptor for direct POSIX read().
    // Device files are streaming — they don't support pread/positional I/O.
    // Using the raw fd with read() is the most reliable approach for evdev.
    const fd = file.handle;

    std.debug.print("╔══════════════════════════════════════════╗\n", .{});
    std.debug.print("║  Kizamu — Raw Input Reader               ║\n", .{});
    std.debug.print("╠══════════════════════════════════════════╣\n", .{});
    std.debug.print("║  Cihaz : {s:<31} ║\n", .{device_path});
    std.debug.print("╚══════════════════════════════════════════╝\n", .{});
    std.debug.print("Cikmak icin Ctrl+C basin.\n\n", .{});

    // ── Event loop ──────────────────────────────────────────────────────
    // We read exactly @sizeOf(InputEvent) bytes per iteration using raw
    // POSIX read(). The kernel guarantees that each read() on an evdev fd
    // delivers one or more complete input_event structs atomically.
    const event_size = @sizeOf(InputEvent);
    var buf: [event_size]u8 align(@alignOf(InputEvent)) = undefined;

    while (true) {
        // Read one complete input_event from the device fd.
        // readExact uses POSIX read() which works correctly on streaming
        // device files (unlike pread-based readers).
        const bytes_read = readExact(fd, &buf) catch |err| {
            std.debug.print("Okuma hatasi: {}\n", .{err});
            std.process.exit(1);
        };

        if (bytes_read != event_size) {
            // Incomplete read means the device was likely disconnected
            std.debug.print("Eksik okuma: {d}/{d} bayt — cihaz koparilmis olabilir.\n", .{ bytes_read, event_size });
            break;
        }

        // Reinterpret the aligned byte buffer as an InputEvent pointer.
        // Safe because: (1) buf is aligned to @alignOf(InputEvent),
        //               (2) InputEvent is extern struct with defined layout,
        //               (3) we verified we read exactly @sizeOf(InputEvent) bytes.
        const event: *const InputEvent = @ptrCast(&buf);

        // Filter: only process EV_KEY events (type == 1).
        // This skips EV_SYN (synchronization markers), EV_REL (mouse deltas),
        // EV_MSC (miscellaneous), and all other event types.
        if (event.type != EV_KEY) continue;

        // Decode key state to a human-readable string
        const state: []const u8 = switch (event.value) {
            KEY_PRESSED => "Pressed",
            KEY_RELEASED => "Released",
            KEY_REPEAT => "Repeat",
            else => "Unknown",
        };

        // Output in the requested format:
        // [Timestamp] KeyCode: {d} | State: {s}
        // Using std.debug.print (writes to stderr, unbuffered) for immediate
        // visibility — no buffering delay when monitoring live keystrokes.
        // Cast tv_usec to u64 to avoid the '+' sign prefix on positive i64 values.
        std.debug.print("[{d}.{d:0>6}] KeyCode: {d} | State: {s}\n", .{
            event.tv_sec,
            @as(u64, @intCast(event.tv_usec)),
            event.code,
            state,
        });
    }
}
