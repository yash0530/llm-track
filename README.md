# LLM Track (`llm-track`)

A native, ultra-clean macOS menu bar utility for developers managing local and cloud AI coding agents. It provides glanceable, real-time quota tracking, usage runways, and process state monitoring across **Claude Code**, **Antigravity (AGY)**, **Kiro CLI**, and **Local Qwen (LM Studio / `llm-serve`)**.

Built 100% in native Swift 6 and SwiftUI with an understated, compact **Liquid Glass** aesthetic that integrates seamlessly with modern macOS design.

---

## Visual Design & User Experience

```
+-----------------------------------------------------------+
|  LLM TRACK  ·  4 Active                                ⟳  |
+-----------------------------------------------------------+
| ╭───────────────────────────────────────────────────────╮ |
| │ 🟢 Claude Code                                        │ |
| │ Session             0% left · Resets in 3h 41m        │ |
| │ [---------------------------------------------------] │ |
| │ Weekly             33% left · Resets in 21h 51m       │ |
| │ [=================----------------------------------] │ |
| │ $98.50 credits remaining                              │ |
| ╰───────────────────────────────────────────────────────╯ |
| ╭───────────────────────────────────────────────────────╮ |
| │ 🟢 Antigravity                                        │ |
| │ 5-Hour             81% left · Resets in 3h 41m         │ |
| │ [========================================-----------] │ |
| │ Weekly             86% left · Resets in 6d 10h        │ |
| │ [===========================================--------] │ |
| ╰───────────────────────────────────────────────────────╯ |
| ╭───────────────────────────────────────────────────────╮ |
| │ 🟢 Kiro CLI                                           │ |
| │ Monthly             0% left · Resets Nov 1            │ |
| │ [---------------------------------------------------] │ |
| ╰───────────────────────────────────────────────────────╯ |
| ╭───────────────────────────────────────────────────────╮ |
| │ 🟢 Qwen 27B                                     [Off] │ |
| ╰───────────────────────────────────────────────────────╯ |
| Live · 10:08 AM                                    Quit   |
+-----------------------------------------------------------+
```

### Highlights
- **Single Native Semiconductor Icon**: Clean, crisp Apple SF Symbol (`cpu`, template mode) in the macOS menu bar that automatically adapts to light and dark wallpapers. Zero extraneous badges or colored dot clusters.
- **Micro Status Dots**: Subtle `5.5pt` status dots (🟢 **Green** when active, ⚪ **Gray** when stopped). No PIDs, uppercase labels, or noisy badges.
- **Consistent Bar Hierarchy**: Unified vertical flow across all providers: **Session / 5-Hour** limit on top, **Weekly / Monthly** limit directly below.
- **Human-Readable Countdown Timers**: Precision relative countdowns (`Resets in 3h 41m`, `Resets in 6d 10h`) calculated dynamically against target timestamps.
- **100% Focus on Usage Runway**: Completely stripped of marketing tags (`Google AI Pro`, `KIRO STUDENT`), context-window token counts, and harsh `(EXHAUSTED)` text. When a quota hits zero, it cleanly displays `0% left` in a soft coral red.
- **Interactive Qwen Control**: 1-Click `On` / `Off` toggle directly controls the local `llm-serve` stack without opening Terminal.
- **Smooth Refresh Button**: 24×24pt hit target with an animated 360° spin that forces an immediate live telemetry query.

---

## Monitored Services & Telemetry

### 1. Claude Code
- **Session (5-Hour) Limit**: Live runway remaining percentage and exact relative countdown (`Resets in Xh Ym`).
- **Weekly (7-Day) Limit**: Multi-model weekly remaining percentage and countdown (`Resets in Xd Yh`).
- **Extra Usage Credits**: Live balance tracking for extra pay-as-you-go credit allowances.
- **Telemetry Protection**: Live OAuth requests to Anthropic's usage API are intelligently throttled with automated fallback to `~/.claude/statusline_state.json` and `~/.claude.json`.

### 2. Antigravity (AGY)
- **Live Connect-RPC Telemetry**: Dynamically extracts quota via Antigravity's local Go `language_server` Connect-RPC endpoint (`/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`) with live CSRF token authentication.
- **5-Hour Limit**: Precision gauge matching the IDE View Usage flyout (e.g. `81% left · Resets in 3h 41m`).
- **Weekly Limit**: Weekly request capacity gauge (e.g. `86% left · Resets in 6d 10h`).
- **Process Telemetry**: Live detection of the active Antigravity IDE and Language Server Hub.

### 3. Kiro CLI
- **Monthly Plan Credits**: Live credit allowance tracking (`0% left · Resets Nov 1`).
- **Process Telemetry**: Monitors background `kiro-cli` and `kiro-cli-term` terminal sessions.

### 4. Local Qwen 27B (`llm-serve` / LM Studio)
- **Multi-Probe Detection**: Real-time probe of ports `8089` (Splash engine), `8790` (Anthropic proxy), `1234` (LM Studio), pidfiles (`~/.local/state/local-llm/*.pid`), and `splash serve-native` processes.
- **1-Click Daemon Toggle**: Dedicated `On` / `Off` button invokes `/Users/yash/.local/bin/llm-serve` to manage the local model stack.

---

## Architecture & Performance

- **100% Native Swift 6 + SwiftUI**:
  - Memory Footprint: **< 20 MB RAM**.
  - Collector Execution Time: **< 5ms** per cycle.
  - Zero Electron, Node, or Python runtime overhead.
- **Transient Popover**: Uses native AppKit `NSPopover` with `NSStatusItem.variableLength`. Clicking outside instantly dismisses the HUD.
- **Background Periodic Sync**: Runs an automatic background polling loop every 8 seconds, with immediate manual refresh available via the UI.

---

## Build & Installation

### Requirements
- macOS 14.0+ (Sonoma, Sequoia, or later)
- Swift 5.9+ / Xcode Command Line Tools

### 1. Build and Run Application
```bash
git clone https://github.com/yash0530/llm-track.git
cd llm-track

# Build and package build/LLMTrack.app
make app

# Launch LLM Track in macOS menu bar
open build/LLMTrack.app
```

### 2. Quick Telemetry CLI Dump
You can query the telemetry engine directly from the command line:
```bash
make dump
```

Example Output:
```text
=== LLM TRACK TELEMETRY ===
Claude: running=true, pid=4704, model=Opus 5.5, 5h=0.0% rem (EXHAUSTED), resets=Resets in 3h 41m, 7d=33.0% rem (Resets in 21h 51m), credits=$98.50
AGY: running=true, model=Gemini 3.8 Flash High, plan=Google AI Pro, geminiWeekly=88.0% rem (Resets in 6d 10h), gemini5h=88.0% rem, claudeGptWeekly=100.0% rem
Kiro: running=true, pid=4631, model=Opus 5.5, plan=KIRO STUDENT, credits=1000.0/1000.0 (0.0% rem, EXHAUSTED), resets=Resets Nov 1
Qwen: serverRunning=true, model=Qwen 27B, disk=17.4 GB
===========================
```

### 3. Clean Build Artifacts
```bash
make clean
```

---

## Project Structure

```
llm-track/
├── Makefile                          # Build targets: build, run, app, dump, clean
├── Package.swift                     # Swift Package Manager manifest
├── README.md                         # Documentation & Architecture
├── Resources/
│   └── Info.plist                    # App bundle metadata (LSUIElement = true)
├── Scripts/
│   └── build_app.sh                  # Application packaging & codesigning script
└── Sources/
    └── LLMTrack/
        ├── LLMTrackApp.swift         # App entry point & --dump CLI runner
        ├── App/
        │   ├── AppDelegate.swift     # NSStatusItem & NSPopover lifecycle
        │   └── LLMTrackStore.swift   # Central ObservableObject & refresh logic
        ├── Collectors/
        │   ├── AGYCollector.swift    # Antigravity IDE & language_server telemetry
        │   ├── ClaudeCollector.swift # Claude Code OAuth & statusline telemetry
        │   ├── KiroCollector.swift   # Kiro CLI sessions & credit telemetry
        │   ├── ProcessHelper.swift   # Darwin process inspection utilities
        │   └── QwenCollector.swift   # llm-serve multi-probe socket & process monitor
        ├── Models/
        │   └── LLMStatus.swift       # Strongly-typed telemetry models & formatters
        └── Views/
            ├── LiquidGlassCard.swift # Frosted glass card with subtle gradient border
            ├── PopoverHUDView.swift  # Ultra-clean HUD popover root view
            ├── PrecisionProgressBar.swift # Thin quota progress bar with countdown
            └── StatusDot.swift       # 5.5pt glowing status indicator
```

---

## License

MIT License. Designed and maintained for high-performance multi-agent development workflows on macOS.
