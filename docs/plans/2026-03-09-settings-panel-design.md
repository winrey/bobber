# Settings Panel Design

## Overview

Add a Settings window to Bobber, accessed via a gear icon in the floating panel's title bar. The window provides plugin lifecycle management (install/uninstall/update via Claude Code's official plugin system), plus UI for all existing and new configuration options.

## Entry Point

Gear icon button in PanelContentView title bar, right side (symmetric with close button on left). Opens an independent `NSWindow` (not NSPanel), standard macOS window behavior.

## Window Structure

macOS native Settings style using `NavigationSplitView` (macOS 13+):
- Left sidebar: category list with SF Symbol icons
- Right content: category-specific settings

### Categories

1. **General** — Launch at login, Claude CLI path
2. **Plugin** — Install status, install/uninstall/reinstall/update, version checking
3. **Sounds** — Enable/disable, volume, cooldown
4. **Appearance** — Panel idle/hover opacity
5. **Sessions** — Stale timeout, keep completed count
6. **Shortcuts** — Toggle panel hotkey (with conflict detection)

## Plugin Management

### Claude CLI Discovery (`ClaudeCLIManager`)

Auto-detect order:
1. `which claude` (user PATH)
2. `/usr/local/bin/claude`
3. `~/.npm/bin/claude`
4. `~/.claude/local/claude`

Found path cached to BobberConfig. User can override via file picker in General settings. "Auto-detect" button to re-scan.

### Marketplace Setup

Add `.claude-plugin/marketplace.json` to repo root so the repo itself serves as a marketplace:

```json
{
  "name": "bobber",
  "owner": { "name": "Bobber" },
  "plugins": [
    {
      "name": "bobber-claude",
      "source": "./plugins/claude-bobber-plugin",
      "description": "Session monitoring hooks for Bobber"
    }
  ]
}
```

### Plugin States

| State | Condition | Available Actions |
|-------|-----------|-------------------|
| Not installed | Marketplace not added or plugin not installed | Install |
| Installed & enabled | In installed_plugins.json + enabledPlugins=true | Disable, Uninstall, Reinstall |
| Installed & disabled | In installed_plugins.json + enabledPlugins=false | Enable, Uninstall |
| Update available | Local version < remote version | Update, Uninstall |
| CLI not found | `claude` binary not detected | Show prompt + manual path selector |

### Plugin Operations (shell commands via ClaudeCLIManager)

- **Install**: `claude plugin marketplace add <github-repo>` → `claude plugin install bobber-claude@bobber`
- **Uninstall**: `claude plugin uninstall bobber-claude@bobber` → `claude plugin marketplace remove bobber`
- **Reinstall**: Uninstall → Install
- **Update**: `claude plugin update bobber-claude@bobber`
- **Enable/Disable**: Toggle `enabledPlugins` in `~/.claude/settings.json`

### Version Checking

- Check on Settings open + periodically (every hour)
- Compare local `installed_plugins.json` version vs GitHub repo `plugin.json` version
- Show "Update available: 1.0.0 → 1.1.0" + Update button in Plugin page
- Menubar icon badge hint when update available

### Plugin UI

- Status card at top: green/yellow/red indicator + status text
- Action buttons below (context-dependent)
- Spinner + real-time log output during operations
- CLI-not-found state shows explanation + "Browse..." button

## General Settings

### Launch at Login

- Toggle switch
- Implementation: write/remove `~/Library/LaunchAgents/com.bobber.app.plist` pointing to app binary
- Check plist existence on startup to reflect current state

### Claude CLI Path

- Display detected path (or "Not found")
- "Browse..." button → NSOpenPanel
- "Auto-detect" button → re-scan
- Saved to BobberConfig

## Sounds Settings

Direct mapping to existing `BobberConfig.SoundConfig`:
- Toggle: enabled/disabled
- Volume slider: 0.0 ~ 1.0
- Cooldown input: seconds

## Appearance Settings

New `BobberConfig.AppearanceConfig`:
- Idle opacity slider: 0.1 ~ 1.0 (current hardcoded 0.65)
- Hover opacity slider: 0.5 ~ 1.0 (current hardcoded 1.0)
- Changes apply in real-time to FloatingPanel

## Sessions Settings

Direct mapping to existing `BobberConfig.SessionConfig`:
- Stale timeout: minutes input (default 30)
- Keep completed count: input (default 10)

## Shortcuts Settings

New `BobberConfig.ShortcutsConfig`:
- Toggle panel hotkey: key recorder (capture modifier + key on press)
- Default: Option+B
- HotkeyManager re-registers on config change

### Conflict Detection

- On recording, check against:
  - System reserved shortcuts (Cmd+C/V/X/Q/W/Z/A/S/Tab, etc.)
  - Other Bobber shortcuts
- Show warning on conflict, but allow user to force-use

## BobberConfig Extensions

```swift
struct BobberConfig: Codable {
    var sounds: SoundConfig = SoundConfig()
    var sessions: SessionConfig = SessionConfig()
    var appearance: AppearanceConfig = AppearanceConfig()   // NEW
    var shortcuts: ShortcutsConfig = ShortcutsConfig()     // NEW
    var general: GeneralConfig = GeneralConfig()           // NEW

    struct AppearanceConfig: Codable {
        var idleOpacity: Double = 0.65
        var hoverOpacity: Double = 1.0
    }

    struct ShortcutsConfig: Codable {
        var togglePanelKey: String = "b"
        var togglePanelModifiers: [String] = ["option"]
    }

    struct GeneralConfig: Codable {
        var claudeCLIPath: String? = nil
        var launchAtLogin: Bool = false
    }
}
```

## New Files

| File | Purpose |
|------|---------|
| `.claude-plugin/marketplace.json` | Marketplace manifest at repo root |
| `Sources/Bobber/UI/SettingsWindow.swift` | NSWindow wrapper + controller |
| `Sources/Bobber/UI/Settings/SettingsView.swift` | Root NavigationSplitView |
| `Sources/Bobber/UI/Settings/GeneralSettingsView.swift` | Launch at login, CLI path |
| `Sources/Bobber/UI/Settings/PluginSettingsView.swift` | Plugin lifecycle management |
| `Sources/Bobber/UI/Settings/SoundsSettingsView.swift` | Sound config UI |
| `Sources/Bobber/UI/Settings/AppearanceSettingsView.swift` | Opacity sliders |
| `Sources/Bobber/UI/Settings/SessionsSettingsView.swift` | Timeout/retention config |
| `Sources/Bobber/UI/Settings/ShortcutsSettingsView.swift` | Hotkey recorder + conflict detection |
| `Sources/Bobber/Services/ClaudeCLIManager.swift` | CLI discovery + plugin operations |

## Modified Files

| File | Changes |
|------|---------|
| `Sources/Bobber/Models/BobberConfig.swift` | Add AppearanceConfig, ShortcutsConfig, GeneralConfig |
| `Sources/Bobber/UI/PanelContentView.swift` | Add gear icon button in title bar |
| `Sources/Bobber/UI/FloatingPanel.swift` | Read opacity from config instead of hardcoded |
| `Sources/Bobber/Services/HotkeyManager.swift` | Read keybinding from config, support re-registration |
| `Sources/Bobber/AppDelegate.swift` | Wire up SettingsWindow, pass config to services |

## Data Flow

```
Gear button (PanelContentView)
  → Open SettingsWindow (NSWindow)
    → SettingsView (NavigationSplitView)
      → Section views read/write BobberConfig
        → BobberConfig.save() → ~/.bobber/config.json
        → Notify services for hot-reload:
           - FloatingPanel: re-read opacity
           - HotkeyManager: re-register shortcuts
           - SoundManager: re-read volume/enabled
           - SessionManager: re-read timeout settings

Plugin operations:
  → ClaudeCLIManager executes shell commands
    → Real-time output to PluginSettingsView
    → Refresh status on completion
```

## Out of Scope

- GitHub repo address not configurable (hardcoded)
- No config import/export
