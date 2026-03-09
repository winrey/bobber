# Sound System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make sounds actually work for all event types with configurable per-event system sound selection.

**Architecture:** Extend SoundConfig with per-event sound names, update SoundManager to use configurable sound names instead of hardcoded paths, wire up EventFileWatcher events to trigger sounds, and add per-event sound pickers to settings UI.

**Tech Stack:** Swift, SwiftUI, AppKit, macOS system sounds (`/System/Library/Sounds/`)

---

### Task 1: Extend SoundConfig with per-event sound names

**Files:**
- Modify: `Sources/Bobber/Models/BobberConfig.swift:10-14`

**Step 1: Add sound name fields to SoundConfig**

In `BobberConfig.swift`, replace the existing `SoundConfig` struct:

```swift
struct SoundConfig: Codable {
    var enabled: Bool = true
    var volume: Float = 0.7
    var cooldownSeconds: Double = 3
    var permissionSound: String = "Sosumi"
    var completionSound: String = "Glass"
    var decisionSound: String = "Ping"
}
```

**Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds (new fields have defaults, so existing config.json files decode fine via `decodeIfPresent`).

**Step 3: Commit**

```
git add Sources/Bobber/Models/BobberConfig.swift
git commit -m "feat(sound): add per-event sound name fields to SoundConfig"
```

---

### Task 2: Update SoundManager with configurable sound names

**Files:**
- Modify: `Sources/Bobber/Services/SoundManager.swift`

**Step 1: Rewrite SoundManager**

Replace the entire file content with:

```swift
import Foundation

class SoundManager {
    var enabled: Bool = true
    var volume: Float = 0.7
    var cooldownSeconds: TimeInterval = 3
    var soundNames: [ActionType: String] = [
        .permission: "Sosumi",
        .decision: "Ping",
        .completion: "Glass",
    ]
    private var lastPlayTime: Date?

    static let availableSounds: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    func play(for type: ActionType) {
        guard enabled, shouldPlay() else { return }
        guard let name = soundNames[type] else { return }
        let path = "/System/Library/Sounds/\(name).aiff"

        recordPlay()
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = ["-v", String(self.volume), path]
            try? process.run()
        }
    }

    /// Play a sound by name (for preview in settings), ignoring cooldown
    func preview(soundName: String) {
        let path = "/System/Library/Sounds/\(soundName).aiff"
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = ["-v", String(self.volume), path]
            try? process.run()
        }
    }

    private func shouldPlay() -> Bool {
        guard let last = lastPlayTime else { return true }
        return Date().timeIntervalSince(last) >= cooldownSeconds
    }

    private func recordPlay() {
        lastPlayTime = Date()
    }
}
```

Key changes:
- `soundPaths` → `soundNames` (names, not full paths; resolved at play time)
- `shouldPlay()` and `recordPlay()` made private
- Added `static let availableSounds` for settings UI
- Added `preview(soundName:)` that bypasses cooldown

**Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Commit**

```
git add Sources/Bobber/Services/SoundManager.swift
git commit -m "feat(sound): configurable sound names and preview support in SoundManager"
```

---

### Task 3: Wire up sound triggers and config sync in AppDelegate

**Files:**
- Modify: `Sources/Bobber/AppDelegate.swift:79-84` (setupEventWatcher)
- Modify: `Sources/Bobber/AppDelegate.swift:132-135` (applyConfig)

**Step 1: Add sound triggers in setupEventWatcher**

Replace the `setupEventWatcher()` method:

```swift
private func setupEventWatcher() {
    eventWatcher = EventFileWatcher { [weak self] event in
        self?.sessionManager.handleEvent(event)
        switch event.eventType {
        case .taskCompleted, .idlePrompt, .stop:
            self?.soundManager.play(for: .completion)
        case .elicitationDialog:
            self?.soundManager.play(for: .decision)
        default:
            break
        }
    }
    try? eventWatcher?.start()
}
```

**Step 2: Sync new config fields in applyConfig**

Replace the sound section of `applyConfig()` (the first 3 lines inside the method):

```swift
soundManager.enabled = config.sounds.enabled
soundManager.volume = config.sounds.volume
soundManager.cooldownSeconds = config.sounds.cooldownSeconds
soundManager.soundNames = [
    .permission: config.sounds.permissionSound,
    .completion: config.sounds.completionSound,
    .decision: config.sounds.decisionSound,
]
```

**Step 3: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 4: Commit**

```
git add Sources/Bobber/AppDelegate.swift
git commit -m "feat(sound): trigger sounds for all event types and sync per-event config"
```

---

### Task 4: Add per-event sound pickers to Settings UI

**Files:**
- Modify: `Sources/Bobber/UI/Settings/SoundsSettingsView.swift`

**Step 1: Rewrite SoundsSettingsView**

Replace entire file content with:

```swift
import SwiftUI

struct SoundsSettingsView: View {
    @Binding var config: BobberConfig
    let onConfigChanged: () -> Void
    let soundManager: SoundManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sounds").font(.title2).fontWeight(.semibold)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable sounds", isOn: $config.sounds.enabled)
                        .onChange(of: config.sounds.enabled) { _ in onConfigChanged() }

                    HStack {
                        Text("Volume:")
                        Slider(value: Binding(
                            get: { Double(config.sounds.volume) },
                            set: { config.sounds.volume = Float($0); onConfigChanged() }
                        ), in: 0...1, step: 0.05)
                        Text("\(Int(config.sounds.volume * 100))%")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .disabled(!config.sounds.enabled)

                    HStack {
                        Text("Cooldown:")
                        TextField("", value: $config.sounds.cooldownSeconds, format: .number)
                            .frame(width: 60)
                            .onChange(of: config.sounds.cooldownSeconds) { _ in onConfigChanged() }
                        Text("seconds")
                            .foregroundColor(.secondary)
                    }
                    .disabled(!config.sounds.enabled)

                    Text("Minimum time between sounds to prevent spam.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            GroupBox(label: Text("Sound Effects")) {
                VStack(alignment: .leading, spacing: 10) {
                    soundPickerRow(label: "Permission:", selection: $config.sounds.permissionSound)
                    soundPickerRow(label: "Completion:", selection: $config.sounds.completionSound)
                    soundPickerRow(label: "Decision:", selection: $config.sounds.decisionSound)
                }
                .padding(8)
            }
            .disabled(!config.sounds.enabled)

            Spacer()
        }
    }

    private func soundPickerRow(label: String, selection: Binding<String>) -> some View {
        HStack {
            Text(label)
                .frame(width: 90, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(SoundManager.availableSounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .frame(width: 130)
            .onChange(of: selection.wrappedValue) { _ in onConfigChanged() }
            Button {
                soundManager.preview(soundName: selection.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}
```

**Step 2: Fix call sites that create SoundsSettingsView**

The view now requires a `soundManager` parameter. Find where `SoundsSettingsView` is constructed and pass `soundManager` through.

Search for: `SoundsSettingsView(` in the codebase. This is likely in `SettingsWindow.swift` or a parent settings view. The `soundManager` needs to be passed down from `AppDelegate` → `SettingsWindowController` → `SoundsSettingsView`.

The exact wiring depends on how SettingsWindowController is structured — read the file, add `soundManager` as a stored property, and pass it to `SoundsSettingsView`.

**Step 3: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 4: Commit**

```
git add Sources/Bobber/UI/Settings/SoundsSettingsView.swift
git add <any other files modified for soundManager plumbing>
git commit -m "feat(sound): add per-event sound pickers with preview to settings UI"
```

---

### Task 5: Manual smoke test

**Step 1: Run the app**

Run: `swift build && swift run`

**Step 2: Verify settings UI**

- Open Settings → Sounds
- Confirm three sound pickers appear (Permission, Completion, Decision)
- Click preview buttons — each should play the selected sound
- Change a sound selection — should persist after closing and reopening settings

**Step 3: Verify sound triggers**

- Start a Claude Code session with the bobber plugin installed
- Confirm permission events play the configured permission sound
- Confirm task completion plays the configured completion sound

**Step 4: Commit any fixes if needed**