<div align="center">

# ⌨️ Kizamu

**A modern terminal-based typing speed test — built with Zig.**

Kizamu (刻む — _to carve, to engrave_) helps you practice and measure your typing
speed right inside the terminal. Powered by
[libvaxis](https://github.com/rockorager/libvaxis) for a smooth, GPU-free TUI
experience with full 24-bit colour support.

![Zig](https://img.shields.io/badge/Zig-0.15-orange?logo=zig&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)

</div>

---

## ✨ Features

| Feature                | Description                                                                          |
| ---------------------- | ------------------------------------------------------------------------------------ |
| **Word & Timed modes** | Choose between 10 / 25 / 50 / 100 / 200 word tests or 15 / 30 / 60 second timed runs |
| **Difficulty levels**  | Easy (top 100 words), Medium (top 300), Hard (all 500)                               |
| **Live stats**         | Real-time WPM, accuracy, and elapsed/remaining time displayed as you type            |
| **Detailed results**   | Net WPM, Raw WPM, accuracy %, keystroke breakdown, and most-missed characters        |
| **Tokyo Night theme**  | A carefully tuned colour palette that's easy on the eyes                             |
| **Zero dependencies**  | No curses, no external runtime — just Zig + libvaxis                                 |

## 📦 Prerequisites

- **Zig ≥ 0.15.0** — install from [ziglang.org/download](https://ziglang.org/download/)
- A terminal with **24-bit colour** support (kitty, alacritty, wezterm, ghostty, iTerm2, Windows Terminal, etc.)
- Minimum terminal size: **46 × 24**

## 🚀 Build & Run

```bash
# Clone the repository
git clone https://github.com/<your-username>/kizamu.git
cd kizamu

# Build (release for best performance)
zig build -Doptimize=ReleaseFast

# Run
zig build run

# Or run the binary directly
./zig-out/bin/kizamu
```

## 🎮 Usage

### Menu

| Key                    | Action                                        |
| ---------------------- | --------------------------------------------- |
| `j` / `k` or `↑` / `↓` | Navigate modes                                |
| `h` / `l` or `←` / `→` | Cycle difficulty (Easy / Medium / Hard)       |
| `Enter`                | Start selected mode                           |
| `1`–`5`                | Quick-start word modes (10, 25, 50, 100, 200) |
| `6`–`8`                | Quick-start timed modes (15s, 30s, 60s)       |
| `Esc`                  | Quit                                          |

### Typing

| Key                 | Action                          |
| ------------------- | ------------------------------- |
| _any printable key_ | Type the displayed text         |
| `Backspace`         | Delete last character           |
| `Space`             | Submit current word and advance |
| `Tab`               | Restart current test            |
| `Esc`               | Return to menu                  |

### Results

| Key            | Action          |
| -------------- | --------------- |
| `Enter` or `r` | Retry same mode |
| `Tab`          | Return to menu  |
| `Esc`          | Quit            |

## 📊 Statistics Explained

| Metric          | Meaning                                                  |
| --------------- | -------------------------------------------------------- |
| **WPM**         | Net words per minute — `(correct_chars / 5) / minutes`   |
| **Raw WPM**     | Gross typing speed — `(total_chars_typed / 5) / minutes` |
| **Accuracy**    | `correct_chars / (correct + incorrect) × 100%`           |
| **Keystrokes**  | Total key presses including backspaces                   |
| **Most missed** | Characters you typed incorrectly most often              |

## 🏗️ Project Structure

```
.
├── build.zig          # Zig build configuration
├── build.zig.zon      # Package manifest (libvaxis dependency)
├── flake.nix          # Nix flake (optional)
├── src/
│   ├── main.zig       # Entry point & event loop
│   ├── game.zig       # Game state, modes, difficulty, stats
│   ├── render.zig     # TUI rendering (Tokyo Night palette)
│   └── words.zig      # 500 most common English words
└── zig-out/
    └── bin/
        └── kizamu     # Compiled binary
```

## 📝 License

MIT — see [LICENSE](LICENSE) for details.
