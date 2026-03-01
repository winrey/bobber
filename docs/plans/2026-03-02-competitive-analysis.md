# Bobber — Competitive Analysis

Detailed analysis of 9 existing tools for managing multiple Claude Code / AI agent sessions. Research conducted March 2026.

## Landscape Overview

```
                    Native macOS GUI
                         │
          ┌──────────────┼──────────────┐
          │              │              │
      Menubar only   Floating panel  Menu + panel
          │              │              │
       Pulser      Claude Monitor    ClawdHub
       VibeBar     Claude Sessions   Bobber (planned)
   Context Manager
          │
          │         Terminal TUI
          │              │
          │    ┌─────────┼─────────┐
          │    │         │         │
          │  tmux-based  Standalone  Web UI
          │    │         │         │
          │  Clorch    Agent Deck  claude-code-monitor
          │  tmuxcc    CCManager   Codeman
          │  claude-tmux           Claude Code UI
          │  claude-dashboard
```

## Tier 1: Most Relevant (Native macOS, Active)

### Claude Monitor

| | |
|---|---|
| **URL** | [github.com/brb-dreaming/claude-monitor](https://github.com/brb-dreaming/claude-monitor) |
| **Stars** | 10 |
| **Tech** | Swift (single 1551-line file, compiled with `swiftc`, no Xcode project) |
| **Form** | Always-on-top floating panel, no dock icon |

**Architecture:**
- Hook scripts → JSON files in `~/.claude/monitor/sessions/` → Swift app polls every 500ms
- Separate Python hook (`monitor_permission.py`) for permission handling via Unix socket IPC
- TTS via shell script, not Swift app (works even if UI is not running)

**Session Card:**
- Status dot: pulsing cyan (working), orange (needs attention), green (completed)
- Project name (from `basename` of cwd)
- Elapsed time
- Last prompt preview (truncated 200 chars)
- Kill button on hover

**Permission Handling (most advanced among competitors):**
- Unix socket at `/tmp/claude-monitor.sock` (SOCK_STREAM)
- Python hook connects and blocks on `recv()` until user decides
- Swift app holds the fd open, writes response when user clicks
- Three options: Allow / Deny / Terminal (fallback to native dialog)

**Sound:**
- Voice TTS via `osascript -e "say ... volume ..."` (not `say` CLI, for volume control)
- Optional ElevenLabs integration for AI-generated voices
- Background execution (`&` + `disown`)

**Key Implementation Details:**
- `NSPanel` + `.nonactivatingPanel` + `.borderless` + `.floating` level
- `NSVisualEffectView(.hudWindow, .behindWindow)` for frosted glass
- `acceptsFirstMouse` override on NSHostingView for click-through
- Auto-resize via KVO on `fittingSize`, top edge anchored
- `$ITERM_SESSION_ID` env var for iTerm2 fast path
- Process tree walk for Terminal.app TTY detection
- Atomic JSON writes via tmp + mv
- 5-second liveness check: `ps -t "$tty"` to detect closed tabs

**Strengths:** Permission handling via socket IPC, voice TTS, clean floating panel
**Weaknesses:** Only 10 stars, Terminal.app + iTerm2 only, no keyboard shortcuts, no action queue

---

### ClawdHub

| | |
|---|---|
| **URL** | [github.com/ManmeetSethi/clawdhub](https://github.com/ManmeetSethi/clawdhub) |
| **Stars** | 1 |
| **Tech** | Swift |
| **Form** | Menubar icon + floating panel triggered by keyboard gesture |

**Architecture:**
- Hook scripts → `~/.clawdhub/sessions.json` (single array file) → DispatchSourceFileSystemObject + 2s polling fallback
- `HookRegistrar.swift` auto-registers hooks into `~/.claude/settings.json`

**Session Card:**
- Agent name, status (Running / Waiting / Idle / Error)
- Active tool being used
- File currently being modified
- Command execution details (Bash: first 60 chars, Edit: basename, Grep: first 40 chars of pattern)

**Keyboard Gesture (most innovative):**
- `NSEvent.addGlobalMonitorForEvents(.flagsChanged, .keyDown)` — NOT `CGEventTap`
- Hold Option+Cmd → show panel, tap Cmd to cycle, release Option → jump
- Hold > 1s → persistent mode, 1-9 number keys to jump, Esc to dismiss
- 3-second safety timer with `CGEventSource.flagsState` fallback
- No debounce on `.flagsChanged` for fast tap fidelity

**Terminal Support (broadest):**
9 terminals with bundle IDs:
- Terminal.app, iTerm2 → AppleScript TTY matching
- VS Code, Cursor → CLI with `-r` flag + 0.2s delayed activation
- Ghostty, WezTerm, Alacritty, Kitty, Warp → NSWorkspace activation by bundle ID

**Key Implementation Details:**
- `NSPanel` + `.nonactivatingPanel` + `.transient` collection behavior
- Panel centered at 65% screen height, 4-column grid of agent cards
- `DispatchSourceFileSystemObject` for file watching with 0.1s debounce
- Session cleanup: >24h old, TTY no longer exists, unknown >10min
- `SafeDecodable<T>` wrapper prevents one bad entry from breaking array decode

**Strengths:** Keyboard gesture is brilliant UX, broadest terminal support, shows active tool+file
**Weaknesses:** 1 star, very new, no approve/deny, no sound

---

### Pulser

| | |
|---|---|
| **URL** | [getpulser.app](https://getpulser.app/) |
| **Tech** | Closed source, macOS native |
| **Form** | Menubar app |

**Session Card:** Minimal — notification-focused, no persistent session list.

**State Detection:**
- Claude Code: via hooks (deepest integration)
- Other agents (ChatGPT CLI, Copilot CLI, Aider, Cline, Codex CLI): process/output monitoring

**Notification:** Native macOS notifications identifying which agent and which terminal.

**Strengths:** Simplest to use, multi-agent out of the box, battle-tested
**Weaknesses:** No dashboard, no approve/deny, notification-only (easy to miss when busy), closed source

---

### VibeBar

| | |
|---|---|
| **URL** | [github.com/yelog/vibebar](https://github.com/yelog/vibebar) / [vibebar.yelog.org](https://vibebar.yelog.org/) |
| **Stars** | 9 |
| **Tech** | Swift |
| **Form** | Menubar app with customizable icon styles |

**Architecture (most robust detection):**
Three-channel state detection with priority ordering:

| Priority | Channel | Method |
|----------|---------|--------|
| 5 | OpenCode HTTP API | Polls HTTP endpoint |
| 4 | Claude log files | Parses Claude Code logs |
| 3 | Copilot JSON-RPC server | Server communication |
| 2 | Hook state files | Claude/Copilot/Gemini hooks |
| 1 | Process scanning | `ps -axo pid,ppid,pcpu,comm,args` fallback |

Detectors run in parallel, results deduplicated by `(tool, pid)`, highest priority wins.

**PTY Wrapper (unique):**
- `vibebar` CLI wraps target tool in a pseudo-terminal via `forkpty()`
- Raw mode terminal, `poll()` loop with 200ms timeout
- Regex-based state detection from output stream
- `PromptDetector` with per-tool patterns (await hints, resume hints)
- State: outputLag < 0.8s → running, awaitingInputLatched → awaitingInput, else idle

**Plugin System Integration:**
- Uses Claude Code's official plugin system (`claude plugin install`)
- Plugin has `hooks/hooks.json` + `scripts/emit.js`
- `emit.js` reads hook JSON from stdin, maps to VibeBar status, sends to Unix socket

**Menubar Icon Styles:**
- Ring: segmented arc per session state
- Particles: colored dots in orbital pattern
- Energy Bar: stacked colored blocks
- Ice Grid: 2-row cells with glow

**Strengths:** Most robust detection (3-channel), multi-agent support (6 tools), plugin-based, beautiful icons
**Weaknesses:** View-only (no approve/deny, no jump-to-session), no sound

---

### Context Manager

| | |
|---|---|
| **URL** | [contextmanager.cc](https://contextmanager.cc/) |
| **Tech** | Closed source, macOS native |
| **Form** | Menubar app (freemium) |

**Session Card:**
- Project name + branch
- Auto-generated label (uses Haiku to name sessions like "OAuth login flow")
- Token count + context health percentage
- Status badges: Running / Waiting / Idle
- Action buttons: Rename, Hide, Switch & Resume

**Unique Features:**
- Context health warnings at 20-40% remaining
- Branch drift detection: warns when git branch doesn't match session
- PR status badges in session cards
- Auto-stash + branch switch + resume workflow
- Claude Code plugin integration (`/ctx:find`, `/ctx:status`)

**State Detection:** `ps aux` + `lsof` — process-based, no hooks.

**Strengths:** Auto-labeling is brilliant UX, context health + branch drift are unique data, clean UI
**Weaknesses:** No approve/deny, no sound, closed source, freemium model

---

### Claude Sessions

| | |
|---|---|
| **URL** | [github.com/caiopizzol/claude-sessions](https://github.com/caiopizzol/claude-sessions) |
| **Stars** | 4 |
| **Tech** | Swift/SwiftUI |
| **Form** | Floating panel (always visible, not menubar dropdown) |

**Architecture:**
- Two-layer IPC: Unix socket for hooks → StateServer, HTTP (port 19847) for SwiftUI polling
- `StateServer` is a Swift `actor` using raw Darwin socket APIs
- Hook scripts send JSON via `nc -U` (netcat for Unix sockets) with Python3 fallback

**Session Card:**
- Two modes: collapsed (180x40pt bar with status dots) and expanded (300x400pt with full cards)
- Colored status dot, session name, state description
- Context percentage (from `statusline.sh` hook) with color thresholds: <60% white, 60-80% yellow, >80% red
- Memory usage in MB (via `ps -eo tty,rss,comm | grep claude`)

**Unique: statusline hook for context data:**
```bash
CONTEXT_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty')
```

**Key Implementation Details:**
- `KeyablePanel` (NSPanel subclass with `canBecomeKey = true`)
- Keyboard navigation: arrows/J/K, Return to focus, Escape to collapse
- Stale detection: 3 consecutive poll cycles without TTY in Terminal.app → remove
- Tab names fetched via AppleScript, cached 5s

**Strengths:** Clean SwiftUI, context percentage data, compact collapsed mode
**Weaknesses:** Terminal.app only, no approve/deny, no sound, small user base

---

## Tier 2: TUI / CLI Tools (Relevant Patterns)

### Clorch

| | |
|---|---|
| **URL** | [github.com/androsovm/clorch](https://github.com/androsovm/clorch) |
| **Stars** | 114 |
| **Tech** | Python (pip installable) |
| **Form** | Terminal TUI |

**Architecture:**
- Hooks → JSON files in `/tmp/clorch/state/{session_id}.json` → 500ms polling + snapshot fingerprinting
- All hooks `"async": true`, event type passed via env var (`CLORCH_EVENT=PreToolUse`)
- Separate `notify_handler.sh` for Notification events (status from message keyword matching)

**Session Card:**
- Agent name, status (color-coded)
- Git branch + dirty file count
- Idle timer: yellow > 30s, red > 120s
- `tool_request_summary` with per-tool formatting

**Approve/Deny (most sophisticated):**
- `tmux send-keys -t session:window.pane -l "y"` + `Enter`
- Safety: re-verify status before sending, check tmux reachability
- Hotkeys: `a-z` to focus items, `y` approve, `n` deny, `Y` approve all
- YOLO mode: auto-approve everything, deny rules force manual review

**Rules Engine:**
```yaml
yolo: true
rules:
  - tools: ["Bash"]
    action: deny
    pattern: "rm -rf|sudo"  # Force manual review
  - tools: ["Write", "Edit"]
    action: approve           # Auto-approve all file edits
```
First match wins. `deny` in YOLO mode = escalate to human (never auto-deny).

**Sound:**
- `afplay /System/Library/Sounds/Sosumi.aiff` (permission)
- `afplay /System/Library/Sounds/Ping.aiff` (question)
- `afplay /System/Library/Sounds/Basso.aiff` (error)
- Non-blocking (`subprocess.Popen`), one sound per poll cycle max

**Hook Installation:**
- Merge into `~/.claude/settings.json`, marker substring `"clorch/hooks/"` for identification
- Backup: `settings.json.bak.{timestamp}`
- Auto-sync on TUI startup: silently updates hook scripts if bundled version is newer

**tmux Detection:**
- Get PPID's TTY via `ps -p "$PPID" -o tty=`
- Match against `tmux list-panes -a -F '#{pane_tty} #{window_name} #{pane_index}'`

**State File Fields:**
```
session_id, status, cwd, project_name, model, last_event, last_event_time,
last_tool, tool_count, error_count, subagent_count, compact_count,
activity_history[10], pid, tmux_window, tmux_pane, term_program,
git_branch, git_dirty_count, notification_message, tool_request_summary
```

**Strengths:** YOLO + rules engine, batch approve, rich state data, tmux-native, sound
**Weaknesses:** TUI only (not GUI), tmux required for approve/deny, no floating window

---

### Agent Deck

| | |
|---|---|
| **URL** | [github.com/asheshgoplani/agent-deck](https://github.com/asheshgoplani/agent-deck) |
| **Stars** | 1,175 |
| **Tech** | Go (single binary) |
| **Form** | Terminal TUI |

**Session Card:**
- `*` green = Running, half-circle yellow = Waiting, `○` gray = Idle, `x` red = Error
- Organized into named groups

**Unique Features:**
- **Conductor**: Persistent Claude session that auto-responds to child sessions when confident
- **Session forking**: Fork with context inheritance to explore multiple branches
- **MCP Manager**: Toggle MCP servers per-session, socket pooling reduces memory 85-90%
- **Skills Manager**: Attach/detach Claude skills per-project
- **Container sessions**: Sandboxed execution
- **Remote monitoring**: Telegram + Slack bridges, periodic heartbeat
- **tmux status bar integration**: Waiting sessions appear in tmux status bar

**State Detection:** Smart polling with 4 status conditions.

**Navigation:** `/` local search, `G` global search, `!@#$` status filters (running/waiting/idle/error).

**Strengths:** Most feature-rich, largest community (1175 stars), multi-agent (8 tools), conductor concept
**Weaknesses:** TUI only, complex setup, tmux-centric

---

### CCManager

| | |
|---|---|
| **URL** | [github.com/kbwo/ccmanager](https://github.com/kbwo/ccmanager) |
| **Stars** | 811 |
| **Tech** | Rust (binary) |
| **Form** | CLI/TUI |

**Session Card:**
- `[active/busy/waiting]` count format per project
- Git status: `+10 -5` file changes, `up3 down1` commit tracking

**Unique Features:**
- **AI-powered auto-approve**: Uses Haiku to classify prompts as safe/unsafe
- **8 agent support**: Claude, Gemini, Cursor, Copilot, Cline, OpenCode, Kimi, Aider
- **Worktree management**: Auto-create, merge, delete worktrees from the app
- **Session data copying**: Copy conversation context between worktrees
- **Configurable per-tool state detection**: Each CLI tool has its own optimized mechanism
- **Devcontainer support**

**Strengths:** Widest agent support, Rust performance, worktree-aware, AI auto-approve
**Weaknesses:** TUI only, complex configuration

---

### claude-code-monitor

| | |
|---|---|
| **URL** | [github.com/onikan27/claude-code-monitor](https://github.com/onikan27/claude-code-monitor) |
| **Stars** | 193 |
| **Tech** | TypeScript (npm package) |
| **Form** | CLI + Mobile Web UI |

**Unique:** QR code for mobile access, token auth, Tailscale support, iTerm2/Terminal.app/Ghostty focus switching. macOS only.

**Strengths:** Mobile web UI is unique for phone checking, npm installable
**Weaknesses:** macOS only, no approve/deny from mobile

---

## Tier 3: Other Notable Tools

| Tool | Stars | Tech | Form | Unique Value |
|------|-------|------|------|-------------|
| [claude-code-hooks-multi-agent-observability](https://github.com/disler/claude-code-hooks-multi-agent-observability) | 1,216 | Python | tmux | Multi-agent swarm orchestration |
| [claude_code_agent_farm](https://github.com/Dicklesworthstone/claude_code_agent_farm) | 672 | Shell | tmux | 20-50 agent orchestration |
| [CCNotify](https://github.com/dazuiba/CCNotify) | 158 | Python | Desktop notifications | Pure notification, simple setup |
| [Codeman](https://github.com/Ark0N/Codeman) | 136 | TypeScript | Web UI + tmux | Modern web dashboard |
| [claude-tmux](https://github.com/nielsgroen/claude-tmux) | 34 | Rust | tmux popup | Git worktree + PR workflow |
| [tmuxcc](https://github.com/nyanko3141592/tmuxcc) | 51 | Rust | TUI + tmux | Multi-agent dashboard |
| [Claude Code UI](https://github.com/KyleAMathews/claude-code-ui) | 371 | TypeScript | Web | Durable Streams real-time UI |
| [claude-code-otel](https://github.com/ColeMurray/claude-code-otel) | 284 | Docker | Grafana | Enterprise observability (Prometheus + Loki) |
| [claude-dashboard](https://github.com/seunggabi/claude-dashboard) | 18 | Go | TUI | k9s-style keybindings |
| [Claude Monitor (brb-dreaming)](https://github.com/brb-dreaming/claude-monitor) | 10 | Swift | Floating | Voice TTS, permission IPC |

---

## Enterprise / Observability

| Tool | Description |
|------|-------------|
| [Datadog AI Agents Console](https://www.datadoghq.com/blog/claude-code-monitoring/) | Org-wide AI agent monitoring in Datadog |
| [SigNoz Dashboard Template](https://signoz.io/docs/dashboards/dashboard-templates/claude-code-dashboard/) | Self-hosted observability dashboard |
| [claude-code-otel](https://github.com/ColeMurray/claude-code-otel) | OpenTelemetry + Prometheus + Loki + Grafana stack |

---

## Comparative Matrix

| Feature | Pulser | Claude Monitor | Clorch | ClawdHub | VibeBar | Context Mgr | Claude Sessions | Agent Deck | CCManager |
|---------|--------|---------------|--------|----------|---------|------------|----------------|------------|-----------|
| **Form** | Menu | Float | TUI | Menu+Float | Menu | Menu | Float | TUI | CLI |
| **Tech** | Closed | Swift | Python | Swift | Swift | Closed | Swift | Go | Rust |
| **Stars** | — | 10 | 114 | 1 | 9 | — | 4 | 1,175 | 811 |
| **Approve/Deny** | — | Socket IPC | tmux keys | — | — | — | — | Via conductor | AI classify |
| **Sound** | — | Voice TTS | afplay | — | — | — | — | Via daemon | — |
| **Jump to window** | Notification | AppleScript | tmux | AppleScript | — | — | AppleScript | tmux | — |
| **Keyboard gesture** | — | — | vim keys | Opt+Cmd | — | Cmd+K | arrows/JK | / search | / search |
| **Multi-agent** | 6 tools | Claude only | Claude | Claude | 6 tools | Claude | Claude | 8 tools | 8 tools |
| **Plugin-based** | No | No | No | No | **Yes** | Yes | No | No | No |
| **Context health** | — | — | — | — | — | **Yes** | **Yes** | — | — |
| **Git info** | — | — | **branch+dirty** | — | — | **branch+drift** | — | — | **status** |
| **Rules engine** | — | — | **YOLO+regex** | — | — | — | — | — | **AI-based** |
| **Mobile** | — | — | — | — | — | — | — | Telegram/Slack | — |
| **Active tool display** | — | — | last tool | **tool+file** | — | — | — | — | — |
| **Session title** | — | prompt preview | project name | tool activity | — | **AI-generated** | tab name | group name | project |

---

## Key Patterns Across All Competitors

### What everyone does the same way
1. **Hook-based event capture** for Claude Code (the hooks API is the universal integration point)
2. **JSON state files** as the communication medium between hooks and UI
3. **Atomic writes** (temp file + mv) for state files
4. **PID-based session identity** and liveness checks
5. **AppleScript** for Terminal.app and iTerm2 window focusing

### What no one does well yet
1. **Full permission dialog inline** — Claude Monitor has Allow/Deny/Terminal but no command editing or custom response
2. **Decision/elicitation handling** — no tool surfaces AskUserQuestion prompts
3. **Native macOS floating panel + approve/deny + sound + keyboard gesture** combined — each tool does 1-2 of these
4. **Plugin-based hook installation + native GUI** — VibeBar uses plugins but has no approve/deny; Claude Monitor has approve/deny but edits settings.json

### Bobber's unique opportunity
The intersection of:
- Plugin-based clean installation (like VibeBar)
- Socket-based permission IPC (like Claude Monitor)
- Full permission dialog with command editing and custom response (new)
- Decision/elicitation card support (new)
- Keyboard gesture (like ClawdHub)
- Sound + voice (like Claude Monitor + Clorch)
- Native macOS floating panel (like Claude Monitor)

No existing tool combines all of these.
