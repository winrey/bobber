# Bobber — macOS Multi-Agent Session Monitor

> A floating desktop companion that watches your AI coding agents, alerts you when they need attention, and lets you act without leaving your current window.

## Problem

When running multiple Claude Code sessions across VS Code, JetBrains, and terminal windows, you have no way to know which sessions are blocked waiting for permission, which finished and need your next instruction, and which are still working. You end up constantly switching windows to check.

## Solution

A native macOS app that:

1. **Menubar icon** — ambient awareness at a glance (badge count, color state)
2. **Floating panel** — pinnable, draggable detail view of all sessions
3. **Action cards** — see pending decisions and act on them inline, without switching windows
4. **Sound alerts** — hear when something needs you

## Core Concepts

### Three Event Types

Every notification Bobber surfaces falls into one of three categories:

| Type | Trigger | Card Action |
|------|---------|-------------|
| **Permission** | Claude requests tool approval (`permission_prompt`) | Full permission dialog: Approve / Approve for project / Deny / Edit command / Custom response |
| **Decision** | Claude asks a question (`elicitation_dialog`) | Show the question and all options, let user pick |
| **Completion** | Claude finishes and is idle (`idle_prompt`) | Mark as read (auto-dismissed if new interaction occurs) |

### Session States

```
active      — agent is working (green pulse)
blocked     — waiting for permission or decision (red/orange highlight)
idle        — finished, waiting for next prompt (yellow)
completed   — session ended (gray, fades out)
stale       — no events for 30+ minutes (dim)
```

## UI Design

### Menubar Icon

A small bobber (fishing float) icon in the macOS menu bar.

- **Normal**: default monochrome icon
- **Attention needed**: icon turns red/orange + numeric badge (e.g. `3`)
- **All clear**: icon turns green momentarily after clearing all actions

Click to toggle the floating panel.

### Floating Panel

A compact, always-on-top panel (like Claude Monitor's glass panel). Can be:

- **Dragged** to any screen position
- **Pinned** to stay visible, or set to auto-hide
- **Resized** between compact and expanded modes

#### Two Tabs

**Sessions Tab** — Overview of all active sessions

```
┌─────────────────────────────────────┐
│  Sessions          Actions (3)      │
├─────────────────────────────────────┤
│ 🔴 taskcast                    2m  │
│    ⏳ Permission: Bash              │
│                                     │
│ 🟡 my-website                  5m  │
│    💤 Idle                          │
│                                     │
│ 🟢 api-server                 now  │
│    Working: Edit src/auth.ts        │
│                                     │
│ 🟢 mobile-app                 30s  │
│    Working: WebSearch               │
└─────────────────────────────────────┘
```

Each session row shows:
- **Status dot** (color + optional pulse animation)
- **Project name** (derived from working directory basename)
- **Session title** (from Claude Code session name, or auto-generated)
- **Elapsed time** since last event
- **Current activity** (which tool is running, or status description)

Interactions:
- **Single click** → expand to show details (recent activity, git branch, tool details)
- **Double click** → jump to the terminal/IDE window

**Actions Tab** — Pending items requiring your attention

This is the primary action surface. Shows a card stack of pending items, navigable with left/right arrows or swipe.

```
┌─────────────────────────────────────┐
│  Sessions          Actions (3)      │
├─────────────────────────────────────┤
│                                     │
│  taskcast                    ← 1/3 →│
│  "Fix auth middleware"              │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Allow this bash command?    │   │
│  │                             │   │
│  │ cd /Users/winrey/Projects/  │   │
│  │ taskcast && pnpm test       │   │
│  │                             │   │
│  │ Run all tests               │   │
│  │ ─────────────────────────── │   │
│  │ [Edit command...]           │   │
│  │                             │   │
│  │ ✅ Yes                      │   │
│  │ 📁 Yes, for this project    │   │
│  │ ❌ No                       │   │
│  │ 💬 Tell Claude instead...   │   │
│  └─────────────────────────────┘   │
│                                     │
│            [↗ Jump]                 │
└─────────────────────────────────────┘
```

Card contents vary by type:

**Permission card:**
- Command/tool details with full context
- Editable command field (click "Edit command..." to modify before approving)
- All permission options matching Claude Code's native UI:
  - Yes (approve once)
  - Yes, for this project (auto-approve this tool pattern for the project)
  - No (deny)
  - Tell Claude what to do instead (free text input)

**Decision card (AskUserQuestion / elicitation):**
- The question text
- All available options rendered as buttons
- "Other" option with text input
- Multi-select support when applicable

**Completion card:**
- Summary of what was done (last tool used, files changed)
- "Mark as read" button (or just click to dismiss)
- Auto-dismissed if a new interaction occurs in that session

Navigation between cards: `←` / `→` arrows, or swipe gesture, or keyboard shortcuts.

### Quick Action: Keyboard Gesture

Inspired by ClawdHub's Cmd+Tab-like gesture:

- **Option+B** (mnemonic: Bobber) → show floating panel with Actions tab focused
- While panel is open, **1-9** number keys to jump to a specific session
- **Esc** to dismiss

## Data Architecture

### Hook-Based Event Capture

Bobber uses **Claude Code's plugin system** (public beta, v1.0.33+) as the primary integration method. VibeBar already proves this approach works for session monitoring.

#### Plugin Structure

```
plugins/claude-bobber-plugin/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   └── hooks.json
└── scripts/
    ├── bobber-event.sh       # Status events (async)
    └── bobber-permission.sh  # Permission handling (sync, blocking)
```

**plugin.json:**
```json
{
  "name": "bobber-claude",
  "version": "1.0.0",
  "description": "Session monitoring hooks for Bobber",
  "author": { "name": "Bobber" },
  "license": "MIT",
  "keywords": ["bobber", "monitoring", "hooks", "session"]
}
```

**hooks/hooks.json:**
```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" SessionStart" }] }
    ],
    "PreToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" PreToolUse" }] }
    ],
    "PermissionRequest": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-permission.sh\"" }] }
    ],
    "Notification": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" Notification" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" Stop" }] }
    ],
    "TaskCompleted": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" TaskCompleted" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" UserPromptSubmit" }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/bobber-event.sh\" SessionEnd" }] }
    ]
  }
}
```

#### Why Plugin System over settings.json

| Dimension | Plugin | Direct settings.json |
|-----------|--------|---------------------|
| Install/Uninstall | `claude plugin install/uninstall` — one command | Manual JSON surgery |
| Conflict risk | Hooks namespaced, auto-merged | Risk of overwriting user hooks |
| Updates | `claude plugin update`, auto-update | Must re-run installer |
| Path resolution | `${CLAUDE_PLUGIN_ROOT}` auto-resolves | Hardcoded `~/.bobber/` paths |
| Discovery | `/plugin` Discover tab, marketplace | Must know Bobber exists |
| Enable/Disable | `claude plugin enable/disable` | Must edit JSON |

#### Installation Methods

```bash
# Method 1: Via marketplace (recommended)
# User adds Bobber's marketplace, then installs
/plugin marketplace add bobber-team/bobber
/plugin install bobber-claude@bobber

# Method 2: Direct local install
claude plugin install /path/to/bobber/plugins/claude-bobber-plugin
claude plugin enable bobber-claude

# Method 3: Fallback — direct settings.json (for Claude Code < 1.0.33)
bobber init --settings
```

#### Hook Scripts

**`bobber-event.sh`** (async — status monitoring, does not block Claude Code):
1. Reads JSON event data from stdin (provided by Claude Code)
2. Detects terminal environment by walking the process tree (PPID → terminal app)
3. Writes structured JSON to `~/.bobber/events/{timestamp}-{pid}.json`
4. Sends a signal to the Bobber daemon via Unix socket (`/tmp/bobber.sock`)

**`bobber-permission.sh`** (sync — blocks until user decides, like Claude Monitor):
1. Reads permission request JSON from stdin
2. Connects to Bobber daemon via Unix socket
3. Sends permission details, blocks on `recv()` until user clicks Approve/Deny in Bobber UI
4. Outputs Claude Code's expected response format to stdout
5. If Bobber is not running, exits with code 0 (graceful fallback to Claude's native dialog)

### Event JSON Schema

```json
{
  "version": 1,
  "timestamp": "2026-03-02T10:30:00Z",
  "pid": 54321,
  "sessionId": "derived-from-pid-and-project",
  "projectPath": "/Users/winrey/Projects/taskcast",
  "projectName": "taskcast",
  "sessionTitle": "Fix auth middleware",
  "eventType": "permission_prompt",
  "details": {
    "tool": "Bash",
    "command": "cd /Users/winrey/Projects/taskcast && pnpm test",
    "description": "Run all tests",
    "options": [
      { "key": "yes", "label": "Yes" },
      { "key": "project", "label": "Yes, for this project (just you)" },
      { "key": "no", "label": "No" },
      { "key": "custom", "label": "Tell Claude what to do instead" }
    ]
  },
  "terminal": {
    "app": "iTerm2",
    "bundleId": "com.googlecode.iterm2",
    "windowId": "window-123",
    "tabId": "session-abc",
    "pid": 12340
  }
}
```

### State Management

Bobber daemon maintains an in-memory session map, persisted to `~/.bobber/state.json`:

```json
{
  "sessions": {
    "session-id-1": {
      "projectName": "taskcast",
      "sessionTitle": "Fix auth middleware",
      "state": "blocked",
      "lastEvent": "2026-03-02T10:30:00Z",
      "pendingAction": { ... },
      "terminal": { ... }
    }
  }
}
```

Session lifecycle:
- **Created** when first event arrives for an unknown PID
- **Updated** on each subsequent event
- **Stale** after 30 minutes with no events
- **Removed** when PID is dead AND marked stale (or 5 seconds after stop event)

### Terminal Detection

Walk the process tree from Claude Code's PID upward:

```
Claude Code (node) → shell (zsh/bash) → terminal emulator OR IDE
```

Identify the terminal by matching process names:

| Process | App | Jump Method |
|---------|-----|-------------|
| `iTerm2` | iTerm2 | AppleScript: `tell session id to select` |
| `Terminal` | Terminal.app | AppleScript: `tell tab to select` |
| `ghostty` | Ghostty | `ghostty +focus-window` CLI |
| `kitty` | Kitty | `kitty @ focus-window` |
| `Electron` (with VS Code) | VS Code | AppleScript: activate + window match |
| `idea` / `webstorm` etc. | JetBrains | AppleScript: activate + window match |
| `tmux` (in tree) | tmux session | `tmux select-window -t` + `select-pane -t` |

### Sending Responses Back

When the user approves/denies from Bobber, send the response to the terminal:

| Terminal | Method |
|----------|--------|
| iTerm2 | `tell application "iTerm2" to tell session id "X" to write text "y"` |
| Terminal.app | `tell application "Terminal" to do script "y" in selected tab of window 1` |
| Ghostty | Not directly supported — fallback to jump |
| Kitty | `kitty @ send-text --match id:X "y\n"` |
| tmux | `tmux send-keys -t session:window.pane "y" Enter` |
| VS Code | Activate window + send keystroke via Accessibility API |
| JetBrains | Activate window + send keystroke via Accessibility API |

For "Tell Claude what to do instead" — type the full custom message into the terminal.

For "Edit command" — deny the current command, then type the modified command suggestion as a custom response.

## Sound System

Different sounds for different events, using NSSound or AVAudioPlayer:

| Event | Sound | Description |
|-------|-------|-------------|
| Permission needed | Short attention tone | Two-note alert, distinct but not jarring |
| Decision needed | Softer chime | Single gentle chime |
| Task completed | Pleasant ding | Satisfying completion sound |
| Error / failure | Low tone | Deeper alert sound |

Configuration:
- Global on/off toggle
- Per-event-type on/off
- Volume control (0-100%)
- Custom sound file support (drag & drop .aiff/.mp3)
- Cooldown: max one sound per 3 seconds to prevent spam
- Do Not Disturb: respect macOS Focus modes

Optional: voice announcements via macOS TTS (e.g. "taskcast needs permission"), toggleable.

## Configuration

Stored at `~/.bobber/config.json`:

```json
{
  "ui": {
    "showMenubarIcon": true,
    "floatingPanel": {
      "enabled": true,
      "position": { "x": 100, "y": 100 },
      "pinned": false,
      "opacity": 0.95
    },
    "theme": "auto"
  },
  "sounds": {
    "enabled": true,
    "volume": 0.7,
    "permission": "default",
    "decision": "default",
    "completion": "default",
    "error": "default",
    "voiceAnnouncements": false,
    "cooldownSeconds": 3
  },
  "keyboard": {
    "togglePanel": "Option+B",
    "nextAction": "Right",
    "prevAction": "Left"
  },
  "sessions": {
    "staleTimeoutMinutes": 30,
    "keepCompletedCount": 10
  }
}
```

## Setup Flow

```bash
# 1. Install Bobber app via Homebrew
brew install --cask bobber

# 2. Install Claude Code plugin (from within Claude Code)
/plugin marketplace add bobber-team/bobber
/plugin install bobber-claude@bobber

# 3. Launch Bobber — it will:
#    → Create ~/.bobber/ directory
#    → Verify the plugin is active
#    → Send a test notification
#    → Request Accessibility permission (for window management)
```

For users on older Claude Code (< 1.0.33) without plugin support:
```bash
bobber init --settings  # Fallback: directly edit ~/.claude/settings.json
```

Both methods are idempotent — safe to run multiple times.

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI + AppKit (for menubar, floating window, accessibility)
- **IPC**: Unix domain socket (`/tmp/bobber.sock`) for hook → daemon communication
- **File watching**: FSEvents for `~/.bobber/events/` directory
- **Process inspection**: `sysctl` / `proc_pidpath` for process tree walking
- **Window management**: AppleScript + Accessibility API (AXUIElement)
- **Sound**: AVAudioPlayer
- **Persistence**: JSON files (no database needed at this scale)
- **Distribution**: Homebrew Cask + DMG download

## Requirements Pool

Features collected from competitive research. Not planned for v1 — to be prioritized later.

### Multi-Agent Support

| Feature | Source | Description |
|---------|--------|-------------|
| Codex CLI support | Pulser, Agent Deck, CCManager | Different hook mechanism, same event schema |
| Gemini CLI support | Agent Deck, CCManager, VibeBar | Process monitoring based detection |
| Aider / OpenCode support | VibeBar, Agent Deck | PTY wrapper or process scanning |
| `AgentProvider` protocol | — | Abstract interface so each agent type plugs in independently |
| Per-tool state detection strategies | CCManager | Each CLI tool has its own optimized detection mechanism |
| 3-channel state detection | VibeBar | PTY wrapper + socket events + process scanning with priority fallback |

### Mobile & Remote

| Feature | Source | Description |
|---------|--------|-------------|
| Mobile web UI | claude-code-monitor | Embedded local HTTP server, QR code to connect from phone |
| Push notifications to phone | ntfy + Tailscale setup | Self-hosted ntfy server on Tailscale private network |
| Telegram bridge | Agent Deck | Send/receive notifications via Telegram bot |
| Slack bridge | Agent Deck | Channel-based control with slash commands |
| Remote Control integration | Claude Code official | Leverage Claude Code's built-in remote control feature |

### Smart Features

| Feature | Source | Description |
|---------|--------|-------------|
| Auto-labeling sessions | Context Manager | Use small LLM (e.g. Haiku) to generate session descriptions from activity |
| Rules engine (YOLO mode) | Clorch | Per-tool approve/deny rules with regex pattern matching, "first match wins" |
| AI-powered auto-approve | CCManager | Use Haiku to classify prompts as safe/unsafe, auto-approve safe ones |
| Context health percentage | Context Manager | Show token usage / context window remaining per session |
| Branch drift detection | Context Manager | Warn when git branch doesn't match the session's expected branch |
| Session history & analytics | — | Browse past sessions, duration, tools used, files changed |
| Conductor / orchestrator | Agent Deck | A persistent Claude session that auto-responds to child sessions when confident |

### UI Enhancements

| Feature | Source | Description |
|---------|--------|-------------|
| Token usage progress rings | Claude Sessions | Compact circular visualization of context window usage |
| Git branch + dirty file count | Clorch | Show `branch (+10 -5)` in session card |
| Staleness timer (yellow/red) | Clorch | Idle > 30s yellow, idle > 120s red |
| Active tool + file display | ClawdHub | Show which tool is running and which file is being modified |
| Session forking | Agent Deck | Fork a session to explore multiple solution branches |
| Worktree-aware sessions | CCManager | Auto-create worktrees, copy session data between branches |
| Custom menubar icon styles | VibeBar | Ring, Particles, Energy Bar, Ice Grid icon animations |
| Batch approve all | Clorch | One-click approve all pending permissions |
| Kill session button | Claude Monitor | Hover to reveal kill button per session |
| Cmd+Tab-like cycling | ClawdHub | Hold modifier to show panel, tap to cycle, release to jump |
| ElevenLabs voice | Claude Monitor | Premium AI-generated voice announcements via API |
| PR status badges | Context Manager | Show PR status directly in session card |
| Session grouping | Agent Deck | Organize sessions into named groups |
| Status-based filtering | Agent Deck | Filter by running/waiting/idle/error with hotkeys |
| tmux status bar widget | Clorch | Show waiting sessions in tmux status bar for ambient awareness |

## Competitive Positioning

| | Bobber | Claude Monitor | Clorch | Pulser | ClawdHub |
|---|---|---|---|---|---|
| macOS native | Yes | Yes | No (TUI) | Yes | Yes |
| Floating panel | Yes | Yes | No | No | Yes (gesture) |
| Inline approve/deny | Full dialog | Allow/Deny/Jump | y/n/Y/YOLO | No | No |
| Command editing | Yes | No | No | No | No |
| Decision (A2UI) support | Yes | No | No | No | No |
| Sound alerts | Yes + voice | Voice (TTS) | System sounds | No | No |
| Action card navigation | Yes | No | Hotkeys | No | No |
| Keyboard gesture | Option+B | No | j/k vim-style | No | Option+Cmd |
| Multi-agent (future) | Planned | No | No | Yes | No |
| Mobile (future) | Planned | No | No | No | No |

Bobber's unique value: **the only native macOS tool that lets you see the full decision context and act on it inline** — including editing commands, answering questions, and managing permissions — all from a floating panel without switching windows.
