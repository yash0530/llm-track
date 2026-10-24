# LLM Track (`llm-track`)

A native macOS status bar menu bar utility designed for developers running multi-agent workflows. It monitors real-time quotas, context windows, and process states across **Claude Code**, **Antigravity (AGY)**, **Kiro CLI**, and **Local Qwen (LM Studio)**.

Built in native Swift 6 and SwiftUI with an understated, compact liquid glass aesthetic matching modern macOS design principles.

---

## Features

- **Menu Bar Status Tile**:
  - Ultra-compact status capsule with a subtle chip icon and 4 quiet status dots:
    - 🟢 **Claude Code** (Active / Idle)
    - 🟢 **Antigravity** (Active / Idle)
    - 🟡 **Kiro CLI** (Active Terminal / Idle)
    - ⚪️ **Local Qwen** (Serving / Stopped)
  - Zero arbitrary battery or lightning icons, no cluttering raw numbers.

- **Understated Liquid Glass HUD**:
  - Translucent macOS frosted glass styling (`.ultraThinMaterial` / native vibrancy).
  - Compact horizontal progress bars with remaining percentage and reset countdowns.
  - High information density without flashy neon glow effects.

- **Monitored Services**:
  1. **Claude Code**:
     - 5-Hour rolling session limit remaining + reset countdown timer (from `~/.claude.json`).
     - 7-Day weekly quota remaining.
     - Extra usage credit balance.
     - Live process status and PID.
  2. **Antigravity (AGY)**:
     - Active model (e.g. Gemini 3.8 Flash High).
     - Active project directory & Language Server Hub port.
     - Session context window capacity remaining.
     - Daily tier request quota remaining.
  3. **Kiro CLI**:
     - Real-time session context window remaining (from `~/.kiro/sessions/cli`).
     - Active model (e.g. Opus 5.5).
     - Terminal process status and PID.
  4. **Local Qwen (LM Studio)**:
     - Real-time local server detection on `localhost:1234`.
     - Model parameter size (27B) and architecture (`qwen3_5`).
     - VRAM / disk footprint on Apple Silicon Metal GPU (17.4 GB).
     - 1-Click **Start Server (lms)** / **Stop Server** toggle directly from the menu.

---

## Architecture & Performance

- **100% Native Swift 6 + SwiftUI**:
  - Tiny memory footprint: Under **20 MB RAM**.
  - Extremely fast: Collector telemetry executes in `< 5ms`.
  - Binary size: ~**560 KB** (no Electron, no Python runtime overhead).
- **Transient Popover**: Uses `NSPopover` with AppKit `NSStatusItem`, clicking outside automatically dismisses the HUD.

---

## Build & Installation

### Requirements
- macOS 14.0+ (Sonoma, Sequoia, or later)
- Swift 5.9+ / Xcode command line tools

### Build App Bundle
```bash
git clone https://github.com/yash0530/llm-track.git
cd llm-track

# Build and package LLMTrack.app
make app

# Launch application
open build/LLMTrack.app
```

### CLI Quick Telemetry Dump
You can also run the telemetry engine directly from the command line:
```bash
make dump
```

Output:
```text
=== LLM TRACK TELEMETRY ===
Claude: running=true, pid=4704, 5h=21.0% rem, 7d=50.0% rem, credits=$98.50
AGY: running=true, pid=45911, model=Gemini 3.8 Flash High, context=71.8% rem, daily=65.0% rem
Kiro: running=true, pid=4631, model=Opus 5.5, context=84.5% rem
Qwen: serverRunning=false, model=qwen3.8-27b-splash, disk=17.4 GB
===========================
```

---

## License

MIT License. Crafted for high-efficiency multi-agent coding on macOS.
