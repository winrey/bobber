# Bobber — Implementation Reference from Competitor Source Code

Concrete patterns extracted from reading the actual source code of Claude Monitor, ClawdHub, Claude Sessions, VibeBar, and Clorch. Each section includes the exact approach and code patterns to borrow.

## 1. Floating Panel (NSPanel)

All three Swift competitors (Claude Monitor, ClawdHub, Claude Sessions) converge on the same `NSPanel` configuration. This is the proven recipe:

```swift
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = true
    }
}
```

**Why `.nonactivatingPanel`**: Clicking buttons in the panel does NOT steal focus from the terminal. This is critical — without it, clicking "Approve" would deactivate the terminal window.

**Why `acceptsFirstMouse`** (from Claude Monitor): Without this override, the first click on the panel just activates it without triggering the button action:

```swift
class ClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

**Frosted glass look** (from Claude Monitor): `NSVisualEffectView` with `.hudWindow` material.

**Auto-resize** (from Claude Monitor): KVO on hosting view's `fittingSize`, keeping top edge anchored, bottom edge grows/shrinks.

**No dock icon**: `NSApp.setActivationPolicy(.accessory)`.

**Position persistence**: `UserDefaults` for x/y, save on `NSWindow.didMoveNotification`.

Source: Claude Monitor (`FloatingPanel`), ClawdHub (`PanelController`), Claude Sessions (`FloatingPanelController`)

## 2. Keyboard Gesture

ClawdHub implements this without `CGEventTap` (which requires Accessibility permissions and is fragile):

```swift
// Use NSEvent global + local monitors
globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
    self.handleEvent(event)
}
localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
    self.handleEvent(event)
    return event
}
```

**State machine for gesture**:
- Track `previousFlags` for `.flagsChanged` events
- Option+Cmd both down → start peek, record `peekStartTime`
- While peeking, Cmd tapped → cycle to next session
- Option released with `commandTapCount > 0` → jump to selected
- Option held > 1.0s without cycling → persistent mode (panel stays)
- Number keys 1-9 in persistent mode → jump directly
- Escape → dismiss

**Safety**: 3-second timer validates physical key state via `CGEventSource.flagsState(.combinedSessionState)` to recover from missed events.

**No debounce on `.flagsChanged`** (need full fidelity for fast taps), but 16ms debounce on `.keyDown`.

Source: ClawdHub (`HotkeyManager.swift`)

## 3. Permission IPC (Blocking Socket)

Claude Monitor's approach is the most elegant — **keep the socket fd open** until the user decides:

**Hook side** (Python):
```python
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(300)  # 5 min max
sock.connect("/tmp/bobber.sock")
sock.sendall(json.dumps(request).encode())
response = sock.recv(4096)  # BLOCKS until user decides
# Parse response, output to Claude Code's stdout
```

**App side** (Swift):
```swift
class PermissionServer {
    private var pendingClients: [String: Int32] = [:]  // sessionId -> fd

    func acceptClient(fd: Int32, data: Data) {
        let request = try JSONDecoder().decode(PermissionRequest.self, from: data)
        pendingClients[request.sessionId] = fd  // Hold the fd open!
    }

    func respond(sessionId: String, decision: String) {
        guard let fd = pendingClients.removeValue(forKey: sessionId) else { return }
        let response = "{\"decision\":\"\(decision)\"}".data(using: .utf8)!
        response.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
        Darwin.close(fd)
    }
}
```

**Why not file-based**: Claude Code's PermissionRequest hook has a timing constraint. File polling is too slow. Unix socket gives instant blocking IPC.

**Graceful degradation**: If Bobber isn't running, the hook script exits with code 0 and no output. Claude Code falls back to its standard terminal dialog.

**Three response options** in Claude Monitor:
- Allow → `{"behavior":"allow"}`
- Deny → `{"behavior":"deny","message":"Denied from Bobber"}`
- Terminal → exit with no output (fallback to Claude's dialog) + jump to window

Source: Claude Monitor (`PermissionSocketServer`, `monitor_permission.py`)

## 4. Hook Installation

### Primary: Claude Code Plugin System (recommended)

Claude Code has an official plugin system (public beta, v1.0.33+). VibeBar already uses this for session monitoring. The plugin approach is cleaner than editing settings.json.

**Plugin directory structure:**
```
plugins/claude-bobber-plugin/
├── .claude-plugin/
│   └── plugin.json            # Only name is required
├── hooks/
│   └── hooks.json             # Identical format to settings.json hooks
└── scripts/
    ├── bobber-event.sh        # Async status hooks
    └── bobber-permission.sh   # Sync permission hook (blocking)
```

**Key advantages:**
- `${CLAUDE_PLUGIN_ROOT}` resolves script paths automatically — no hardcoded `~/.bobber/` paths
- Install/uninstall is one command: `claude plugin install/uninstall`
- Hooks are namespaced, auto-merged with user hooks — zero conflict risk
- Version tracking and auto-update via marketplace
- Discoverability via `/plugin` Discover tab
- Enable/disable without removing: `claude plugin enable/disable`

**Distribution via marketplace** — create `.claude-plugin/marketplace.json` at the repo root:
```json
{
  "name": "bobber",
  "owner": { "name": "Bobber" },
  "plugins": [{
    "name": "bobber-claude",
    "source": "./plugins/claude-bobber-plugin",
    "description": "Session monitoring hooks for Bobber",
    "version": "1.0.0"
  }]
}
```

Users install via:
```bash
/plugin marketplace add bobber-team/bobber
/plugin install bobber-claude@bobber
```

Can also submit to [Anthropic's official marketplace](https://claude.ai/settings/plugins/submit) for maximum reach.

Source: [Claude Code Plugin Docs](https://code.claude.com/docs/en/plugins), VibeBar (`plugins/claude-vibebar-plugin/`)

### Fallback: Direct settings.json Editing

For users on Claude Code < 1.0.33 without plugin support. Use Clorch's merge strategy:

```python
def install_hooks(settings_path="~/.claude/settings.json"):
    settings = json.loads(Path(settings_path).read_text())
    marker = "bobber/hooks/"  # Identify our hooks vs user's

    for event_name in HOOK_EVENTS:
        existing_rules = settings.get("hooks", {}).get(event_name, [])
        cleaned = [r for r in existing_rules if marker not in str(r)]
        cleaned.append({
            "matcher": "",
            "hooks": [{
                "type": "command",
                "command": f"~/.bobber/hooks/{script_for_event(event_name)}",
                "async": True
            }]
        })
        settings.setdefault("hooks", {})[event_name] = cleaned

    Path(settings_path).write_text(json.dumps(settings, indent=2))
```

**Key patterns**:
- Use marker substring (`"bobber/hooks/"`) to identify and replace only our hooks
- Preserve all other hooks (user's or other tools')
- Backup before modifying: `settings.json.bak.{timestamp}`
- Idempotent — safe to run multiple times

Source: Clorch (`installer.py`), ClawdHub (`HookRegistrar.swift`)

## 5. Hook Scripts: Data Capture

### Terminal detection (from Claude Monitor)

iTerm2 fast path — check env var first:
```bash
if [ -n "$ITERM_SESSION_ID" ]; then
    echo "iterm2|$ITERM_SESSION_ID"  # Format: w0t0p0:GUID
    return
fi
```

Terminal.app fallback — walk process tree to find TTY:
```bash
local pid=$$
for _ in 1 2 3 4 5; do
    pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
    [ -z "$pid" ] || [ "$pid" = "1" ] && break
    tty_name=$(ps -o tty= -p "$pid" | tr -d ' ')
    if [ -n "$tty_name" ] && [ "$tty_name" != "??" ]; then
        echo "terminal|/dev/$tty_name"
        return
    fi
done
```

### tmux detection (from Clorch)

Find which tmux pane the Claude process is in:
```bash
PPID_TTY=$(ps -p "$PPID" -o tty= | tr -d ' ')
TMUX_INFO=$(tmux list-panes -a -F '#{pane_tty} #{window_name} #{pane_index}' \
    | grep "$PPID_TTY" | head -1)
TMUX_WINDOW=$(echo "$TMUX_INFO" | awk '{print $2}')
TMUX_PANE=$(echo "$TMUX_INFO" | awk '{print $3}')
```

### Tool activity summary (from ClawdHub + Clorch)

Per-tool human-readable formatting:
```bash
case "$TOOL_NAME" in
    Bash)    SUMMARY="$ $(echo "$TOOL_INPUT" | jq -r '.command // ""' | head -c 300)" ;;
    Edit)    SUMMARY="$(echo "$TOOL_INPUT" | jq -r '.file_path // ""')" ;;
    Write)   SUMMARY="$(echo "$TOOL_INPUT" | jq -r '.file_path // ""') ($(echo "$TOOL_INPUT" | jq -r '.content // ""' | wc -l) lines)" ;;
    Read)    SUMMARY="$(echo "$TOOL_INPUT" | jq -r '.file_path // ""')" ;;
    Grep)    SUMMARY="$(echo "$TOOL_INPUT" | jq -r '.pattern // ""' | head -c 40)" ;;
    Glob)    SUMMARY="$(echo "$TOOL_INPUT" | jq -r '.pattern // ""' | head -c 40)" ;;
    *)       SUMMARY="$TOOL_NAME" ;;
esac
```

### Atomic file writes (universal pattern)

Every competitor uses this — never write directly to the state file:
```bash
TEMP="$(mktemp "${STATE_DIR}/.tmp.XXXXXX")"
trap 'rm -f "$TEMP"' EXIT
echo "$JSON" > "$TEMP"
mv "$TEMP" "$STATE_FILE"
```

Source: Claude Monitor (`monitor.sh`), ClawdHub (`on-activity.sh`), Clorch (`event_handler.sh`)

## 6. Window Jumping via AppleScript

### iTerm2 (by unique session ID)

```swift
let script = """
tell application "iTerm2"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if unique id of s is "\(uniqueId)" then
                    select t
                    return
                end if
            end repeat
        end repeat
    end repeat
end tell
"""
```

### Terminal.app (by TTY path)

```swift
let script = """
tell application "Terminal"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            if tty of t is "\(ttyPath)" then
                set selected tab of w to t
                set index of w to 1
                return
            end if
        end repeat
    end repeat
end tell
"""
```

### VS Code / Cursor (CLI + delayed activation)

```swift
// Launch CLI with reuse-window flag
Process.launchedProcess(launchPath: "/usr/local/bin/code", arguments: ["-r", projectPath])
// Delay activation by 0.2s to let CLI process first
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
}
```

### tmux (send-keys for approve/deny)

```bash
tmux send-keys -t "session:window.pane" -l "y"   # -l = literal
tmux send-keys -t "session:window.pane" Enter
```

### Fallback terminal activation (by bundle ID)

```swift
let bundleIds = [
    "com.googlecode.iterm2", "com.apple.Terminal",
    "com.mitchellh.ghostty", "com.github.wez.wezterm",
    "net.kovidgoyal.kitty", "io.alacritty", "dev.warp.Warp-Stable"
]
for bundleId in bundleIds {
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
        app.activate(options: [.activateAllWindows])
        break
    }
}
```

Source: Claude Monitor, ClawdHub (`TerminalFocusManager.swift`), Claude Sessions

## 7. State Polling & Change Detection

### Snapshot fingerprinting (from Clorch)

Only trigger UI updates when state actually changes:
```python
def _build_snapshot(agents):
    return {
        a.session_id: f"{a.status}|{a.last_event_time}|{a.tool_count}"
        for a in agents
    }
# Compare snapshots: if old_snapshot != new_snapshot → trigger update
```

### Dual watching (from ClawdHub)

File system event watcher as primary, polling as fallback:
```swift
// Primary: DispatchSourceFileSystemObject watches sessions.json
let source = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: fd,
    eventMask: [.write, .rename],
    queue: .main
)
source.setEventHandler { [weak self] in self?.reload() }

// Fallback: 2-second polling timer
Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
    self.reload()
}
```

### Poll intervals used

| Tool | Interval | Purpose |
|------|----------|---------|
| Claude Monitor | 500ms | State file polling |
| Claude Monitor | 5s | Liveness check (PID alive?) |
| ClawdHub | FS events + 2s fallback | State file |
| Claude Sessions | 2s | HTTP poll to state server |
| VibeBar | 1s | Full refresh cycle |
| Clorch | 500ms | State directory scan |

Source: All competitors

## 8. Session Cleanup

Converged pattern across all competitors:

```swift
func cleanupSessions() {
    for session in sessions {
        // 1. PID liveness check
        if kill(session.pid, 0) != 0 {  // ESRCH = process doesn't exist
            removeSession(session)
            continue
        }
        // 2. Stale timeout (no events for N minutes)
        if session.lastEvent.timeIntervalSinceNow < -staleTimeout {
            markStale(session)
        }
        // 3. TTY existence (macOS specific)
        if !FileManager.default.fileExists(atPath: session.ttyPath) {
            removeSession(session)
        }
    }
}
```

**Timing**:
- Claude Monitor: 10 min stale, 5s after stop event
- ClawdHub: 24h max age, 10 min for unknown TTY
- Clorch: PID check + 1h max age fallback
- VibeBar: 10s for wrapper, 30 min for idle plugin sessions

Source: All competitors

## 9. Sound

### System sounds via afplay (from Clorch)

```swift
func playSound(for event: EventType) {
    let soundPath: String
    switch event {
    case .permission:  soundPath = "/System/Library/Sounds/Sosumi.aiff"
    case .decision:    soundPath = "/System/Library/Sounds/Ping.aiff"
    case .completion:  soundPath = "/System/Library/Sounds/Glass.aiff"
    case .error:       soundPath = "/System/Library/Sounds/Basso.aiff"
    }
    Process.launchedProcess(launchPath: "/usr/bin/afplay", arguments: [soundPath])
}
```

### Voice TTS (from Claude Monitor)

Use `osascript` (not `say` CLI) for volume control:
```bash
osascript -e "say \"$msg\" using \"$voice\" speaking rate $rate volume $volume" &
disown
```

### Cooldown (from Clorch)

Only play once per poll cycle for the highest-priority status change. Prevents sound spam.

Source: Clorch (`sound.py`), Claude Monitor (`monitor.sh`)

## 10. Context & Token Data (from Claude Sessions)

Claude Code exposes context data via the statusline hook:

```bash
# In statusline hook script:
CONTEXT_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty')
INPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.input_tokens // empty')
```

Color thresholds for context health:
```swift
switch percentage {
case 0..<0.6:  return .white.opacity(0.4)  // Healthy
case 0.6..<0.8: return .yellow              // Warning
default:        return .red                  // Critical
}
```

Memory per session via `ps`:
```bash
ps -eo tty,rss,comm | grep claude  # RSS in KB → convert to MB
```

Source: Claude Sessions (`statusline.sh`, `StateManager.swift`)

## Summary: Recommended Stack for Bobber

| Component | Recommended Approach | Source |
|-----------|---------------------|--------|
| Floating window | `NSPanel` + `.nonactivatingPanel` + `.borderless` + `.floating` | Claude Monitor, ClawdHub, Claude Sessions |
| SwiftUI hosting | Custom `NSHostingView` with `acceptsFirstMouse` override | Claude Monitor |
| Glass appearance | `NSVisualEffectView(.hudWindow, .behindWindow)` | Claude Monitor |
| Keyboard gesture | `NSEvent.addGlobalMonitorForEvents(.flagsChanged, .keyDown)` | ClawdHub |
| Permission IPC | Unix domain socket, hold fd open until user decides | Claude Monitor |
| Hook installation | Claude Code plugin system (primary) + settings.json merge (fallback) | VibeBar, Clorch |
| Terminal detection | `$ITERM_SESSION_ID` fast path + process tree walk for TTY | Claude Monitor |
| tmux detection | Match PPID TTY against `tmux list-panes` output | Clorch |
| Window jumping | AppleScript per terminal type, bundle ID fallback | Claude Monitor, ClawdHub |
| Approve/deny | Unix socket response for hooks; `tmux send-keys` for TUI sessions | Claude Monitor (socket), Clorch (tmux) |
| State polling | FSEvents primary + 2s timer fallback + snapshot fingerprinting | ClawdHub + Clorch |
| Sound | `afplay` for system sounds, `osascript say` for TTS | Clorch + Claude Monitor |
| Session cleanup | PID liveness + stale timeout + TTY existence | All |
| Atomic writes | temp file + `mv` (universal pattern) | All |
| Context data | statusline hook for `context_window.used_percentage` | Claude Sessions |
