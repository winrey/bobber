# Settings Panel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Settings window to Bobber with plugin lifecycle management, sound/appearance/session/shortcut/general configuration.

**Architecture:** macOS native Settings window (NSWindow + SwiftUI NavigationSplitView) opened via gear icon in floating panel. Plugin management via `claude` CLI subprocess calls. Config changes hot-reload to services via callback closures.

**Tech Stack:** Swift, SwiftUI, AppKit (NSWindow, NSOpenPanel, Process), LaunchAgents plist

---

### Task 1: Extend BobberConfig with new config sections

**Files:**
- Modify: `Sources/Bobber/Models/BobberConfig.swift`
- Test: `Tests/BobberTests/ModelTests.swift`

**Step 1: Write the failing test**

Add to `Tests/BobberTests/ModelTests.swift`:

```swift
func testBobberConfigDecodesWithNewSections() throws {
    let json = """
    {
        "sounds": { "enabled": true, "volume": 0.7, "cooldownSeconds": 3 },
        "sessions": { "staleTimeoutMinutes": 30, "keepCompletedCount": 10 },
        "appearance": { "idleOpacity": 0.5, "hoverOpacity": 0.9 },
        "shortcuts": { "togglePanelKey": "b", "togglePanelModifiers": ["option"] },
        "general": { "launchAtLogin": false }
    }
    """.data(using: .utf8)!
    let config = try JSONDecoder().decode(BobberConfig.self, from: json)
    XCTAssertEqual(config.appearance.idleOpacity, 0.5)
    XCTAssertEqual(config.appearance.hoverOpacity, 0.9)
    XCTAssertEqual(config.shortcuts.togglePanelKey, "b")
    XCTAssertEqual(config.shortcuts.togglePanelModifiers, ["option"])
    XCTAssertEqual(config.general.launchAtLogin, false)
    XCTAssertNil(config.general.claudeCLIPath)
}

func testBobberConfigDecodesWithoutNewSections() throws {
    let json = """
    {
        "sounds": { "enabled": true, "volume": 0.7, "cooldownSeconds": 3 },
        "sessions": { "staleTimeoutMinutes": 30, "keepCompletedCount": 10 }
    }
    """.data(using: .utf8)!
    let config = try JSONDecoder().decode(BobberConfig.self, from: json)
    XCTAssertEqual(config.appearance.idleOpacity, 0.65)
    XCTAssertEqual(config.appearance.hoverOpacity, 1.0)
    XCTAssertEqual(config.shortcuts.togglePanelKey, "b")
    XCTAssertEqual(config.general.launchAtLogin, false)
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift test --filter ModelTests 2>&1 | tail -20`
Expected: FAIL — `AppearanceConfig`, `ShortcutsConfig`, `GeneralConfig` not defined

**Step 3: Write minimal implementation**

Replace `Sources/Bobber/Models/BobberConfig.swift` entirely:

```swift
import Foundation

struct BobberConfig: Codable {
    var sounds: SoundConfig = SoundConfig()
    var sessions: SessionConfig = SessionConfig()
    var appearance: AppearanceConfig = AppearanceConfig()
    var shortcuts: ShortcutsConfig = ShortcutsConfig()
    var general: GeneralConfig = GeneralConfig()

    struct SoundConfig: Codable {
        var enabled: Bool = true
        var volume: Float = 0.7
        var cooldownSeconds: Double = 3
    }

    struct SessionConfig: Codable {
        var staleTimeoutMinutes: Int = 30
        var keepCompletedCount: Int = 10
    }

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

    static let configURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bobber/config.json")
    }()

    static func load() -> BobberConfig {
        guard let data = try? Data(contentsOf: configURL) else { return BobberConfig() }
        return (try? JSONDecoder().decode(BobberConfig.self, from: data)) ?? BobberConfig()
    }

    func save() {
        let dir = Self.configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.configURL)
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift test --filter ModelTests 2>&1 | tail -20`
Expected: All ModelTests PASS

**Step 5: Commit**

```bash
git add Sources/Bobber/Models/BobberConfig.swift Tests/BobberTests/ModelTests.swift
git commit -m "feat: extend BobberConfig with appearance, shortcuts, general sections"
```

---

### Task 2: Create ClaudeCLIManager service

**Files:**
- Create: `Sources/Bobber/Services/ClaudeCLIManager.swift`
- Test: `Tests/BobberTests/ClaudeCLIManagerTests.swift`

**Step 1: Write the failing test**

Create `Tests/BobberTests/ClaudeCLIManagerTests.swift`:

```swift
import XCTest
@testable import Bobber

final class ClaudeCLIManagerTests: XCTestCase {
    func testAutoDetectFindsClaudeInPath() {
        let manager = ClaudeCLIManager()
        // Should at least attempt detection without crashing
        manager.autoDetect()
        // Path is either found or nil — no crash
    }

    func testSetCustomPath() {
        let manager = ClaudeCLIManager()
        manager.setCustomPath("/usr/local/bin/claude")
        XCTAssertEqual(manager.cliPath, "/usr/local/bin/claude")
    }

    func testPluginStatusDefaultsToUnknown() {
        let manager = ClaudeCLIManager()
        XCTAssertEqual(manager.pluginStatus, .unknown)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift test --filter ClaudeCLIManagerTests 2>&1 | tail -20`
Expected: FAIL — `ClaudeCLIManager` not defined

**Step 3: Write minimal implementation**

Create `Sources/Bobber/Services/ClaudeCLIManager.swift`:

```swift
import Foundation

enum PluginStatus: Equatable {
    case unknown
    case notInstalled
    case installed
    case installedDisabled
    case updateAvailable(local: String, remote: String)
    case cliNotFound
}

class ClaudeCLIManager: ObservableObject {
    @Published var cliPath: String?
    @Published var pluginStatus: PluginStatus = .unknown
    @Published var isRunningOperation: Bool = false
    @Published var operationLog: String = ""

    private static let searchPaths = [
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
    ]

    private static let githubRepo = "anthropics/bobber"  // TODO: replace with actual repo

    func autoDetect() {
        // Try `which claude` first
        if let path = runShell("/usr/bin/which", args: ["claude"]), !path.isEmpty {
            cliPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        // Try known paths
        for path in Self.searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cliPath = path
                return
            }
        }
        // Try ~/.npm/bin/claude
        let npmPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".npm/bin/claude").path
        if FileManager.default.isExecutableFile(atPath: npmPath) {
            cliPath = npmPath
            return
        }
        // Try ~/.claude/local/claude
        let localPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/local/claude").path
        if FileManager.default.isExecutableFile(atPath: localPath) {
            cliPath = localPath
            return
        }
        cliPath = nil
    }

    func setCustomPath(_ path: String) {
        cliPath = path
    }

    func checkPluginStatus() {
        guard let cli = cliPath else {
            pluginStatus = .cliNotFound
            return
        }

        // Check installed_plugins.json
        let installedURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/plugins/installed_plugins.json")
        guard let data = try? Data(contentsOf: installedURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: Any] else {
            pluginStatus = .notInstalled
            return
        }

        // Look for bobber-claude in any marketplace
        let bobberKey = plugins.keys.first { $0.hasPrefix("bobber-claude@") }
        guard bobberKey != nil else {
            pluginStatus = .notInstalled
            return
        }

        // Check enabledPlugins in settings.json
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        if let settingsData = try? Data(contentsOf: settingsURL),
           let settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
           let enabled = settings["enabledPlugins"] as? [String: Bool] {
            let enabledKey = enabled.keys.first { $0.hasPrefix("bobber-claude@") }
            if let key = enabledKey, enabled[key] == false {
                pluginStatus = .installedDisabled
                return
            }
        }

        pluginStatus = .installed
    }

    func installPlugin(completion: @escaping (Bool) -> Void) {
        guard let cli = cliPath else {
            completion(false)
            return
        }
        isRunningOperation = true
        operationLog = ""

        Task.detached { [weak self] in
            // Step 1: Add marketplace
            let addResult = self?.runCLI(cli, args: ["plugin", "marketplace", "add", Self.githubRepo])
            await MainActor.run {
                self?.operationLog += "Adding marketplace...\n\(addResult ?? "")\n"
            }

            // Step 2: Install plugin
            let installResult = self?.runCLI(cli, args: ["plugin", "install", "bobber-claude@bobber"])
            await MainActor.run {
                self?.operationLog += "Installing plugin...\n\(installResult ?? "")\n"
                self?.isRunningOperation = false
                self?.checkPluginStatus()
                completion(self?.pluginStatus == .installed)
            }
        }
    }

    func uninstallPlugin(completion: @escaping (Bool) -> Void) {
        guard let cli = cliPath else {
            completion(false)
            return
        }
        isRunningOperation = true
        operationLog = ""

        Task.detached { [weak self] in
            let uninstallResult = self?.runCLI(cli, args: ["plugin", "uninstall", "bobber-claude@bobber"])
            await MainActor.run {
                self?.operationLog += "Uninstalling plugin...\n\(uninstallResult ?? "")\n"
            }

            let removeResult = self?.runCLI(cli, args: ["plugin", "marketplace", "remove", "bobber"])
            await MainActor.run {
                self?.operationLog += "Removing marketplace...\n\(removeResult ?? "")\n"
                self?.isRunningOperation = false
                self?.checkPluginStatus()
                completion(self?.pluginStatus == .notInstalled)
            }
        }
    }

    func reinstallPlugin(completion: @escaping (Bool) -> Void) {
        uninstallPlugin { [weak self] _ in
            self?.installPlugin(completion: completion)
        }
    }

    func updatePlugin(completion: @escaping (Bool) -> Void) {
        guard let cli = cliPath else {
            completion(false)
            return
        }
        isRunningOperation = true
        operationLog = ""

        Task.detached { [weak self] in
            let result = self?.runCLI(cli, args: ["plugin", "update", "bobber-claude@bobber"])
            await MainActor.run {
                self?.operationLog += "Updating plugin...\n\(result ?? "")\n"
                self?.isRunningOperation = false
                self?.checkPluginStatus()
                completion(self?.pluginStatus == .installed)
            }
        }
    }

    // MARK: - Private

    private func runShell(_ path: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func runCLI(_ cli: String, args: [String]) -> String? {
        return runShell(cli, args: args)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift test --filter ClaudeCLIManagerTests 2>&1 | tail -20`
Expected: All PASS

**Step 5: Commit**

```bash
git add Sources/Bobber/Services/ClaudeCLIManager.swift Tests/BobberTests/ClaudeCLIManagerTests.swift
git commit -m "feat: add ClaudeCLIManager for plugin lifecycle management"
```

---

### Task 3: Create SettingsWindow and root SettingsView

**Files:**
- Create: `Sources/Bobber/UI/SettingsWindow.swift`
- Create: `Sources/Bobber/UI/Settings/SettingsView.swift`

**Step 1: Create SettingsWindow**

Create `Sources/Bobber/UI/SettingsWindow.swift`:

```swift
import AppKit
import SwiftUI

class SettingsWindowController {
    private var window: NSWindow?
    private let config: Binding<BobberConfig>
    private let claudeCLIManager: ClaudeCLIManager
    private let onConfigChanged: () -> Void

    init(config: Binding<BobberConfig>, claudeCLIManager: ClaudeCLIManager, onConfigChanged: @escaping () -> Void) {
        self.config = config
        self.claudeCLIManager = claudeCLIManager
        self.onConfigChanged = onConfigChanged
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            config: config,
            claudeCLIManager: claudeCLIManager,
            onConfigChanged: onConfigChanged
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bobber Settings"
        window.contentMinSize = NSSize(width: 500, height: 350)
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
```

**Step 2: Create root SettingsView**

Create `Sources/Bobber/UI/Settings/SettingsView.swift`:

```swift
import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case plugin = "Plugin"
    case sounds = "Sounds"
    case appearance = "Appearance"
    case sessions = "Sessions"
    case shortcuts = "Shortcuts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .plugin: return "puzzlepiece.extension"
        case .sounds: return "speaker.wave.2"
        case .appearance: return "paintbrush"
        case .sessions: return "list.bullet.rectangle"
        case .shortcuts: return "keyboard"
        }
    }
}

struct SettingsView: View {
    @Binding var config: BobberConfig
    @ObservedObject var claudeCLIManager: ClaudeCLIManager
    let onConfigChanged: () -> Void
    @State private var selectedCategory: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.rawValue, systemImage: category.icon)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            Group {
                switch selectedCategory {
                case .general:
                    GeneralSettingsView(config: $config, claudeCLIManager: claudeCLIManager, onConfigChanged: onConfigChanged)
                case .plugin:
                    PluginSettingsView(claudeCLIManager: claudeCLIManager)
                case .sounds:
                    SoundsSettingsView(config: $config, onConfigChanged: onConfigChanged)
                case .appearance:
                    AppearanceSettingsView(config: $config, onConfigChanged: onConfigChanged)
                case .sessions:
                    SessionsSettingsView(config: $config, onConfigChanged: onConfigChanged)
                case .shortcuts:
                    ShortcutsSettingsView(config: $config, onConfigChanged: onConfigChanged)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
    }
}
```

**Step 3: Build to verify compilation**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift build 2>&1 | tail -10`
Expected: Compilation errors for missing setting views (GeneralSettingsView, etc.) — expected, will be created in subsequent tasks.

**Step 4: Commit**

```bash
git add Sources/Bobber/UI/SettingsWindow.swift Sources/Bobber/UI/Settings/SettingsView.swift
git commit -m "feat: add SettingsWindow and root SettingsView with NavigationSplitView"
```

---

### Task 4: Create GeneralSettingsView

**Files:**
- Create: `Sources/Bobber/UI/Settings/GeneralSettingsView.swift`

**Step 1: Create the view**

```swift
import SwiftUI

struct GeneralSettingsView: View {
    @Binding var config: BobberConfig
    @ObservedObject var claudeCLIManager: ClaudeCLIManager
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General").font(.title2).fontWeight(.semibold)

            // Launch at Login
            GroupBox("Startup") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch Bobber at login", isOn: $config.general.launchAtLogin)
                        .onChange(of: config.general.launchAtLogin) { _ in
                            updateLaunchAgent()
                            onConfigChanged()
                        }
                    Text("Automatically start Bobber when you log in.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            // Claude CLI Path
            GroupBox("Claude CLI") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Path:")
                        Text(claudeCLIManager.cliPath ?? "Not found")
                            .foregroundColor(claudeCLIManager.cliPath != nil ? .primary : .red)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        Button("Auto-detect") {
                            claudeCLIManager.autoDetect()
                            config.general.claudeCLIPath = claudeCLIManager.cliPath
                            onConfigChanged()
                        }
                        Button("Browse...") {
                            browseForCLI()
                        }
                    }
                    if claudeCLIManager.cliPath == nil {
                        Text("Claude CLI is required for plugin management. Install Claude Code first, then click Auto-detect.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(8)
            }

            Spacer()
        }
    }

    private func browseForCLI() {
        let panel = NSOpenPanel()
        panel.title = "Select Claude CLI binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            claudeCLIManager.setCustomPath(url.path)
            config.general.claudeCLIPath = url.path
            onConfigChanged()
        }
    }

    private static let launchAgentLabel = "com.bobber.app"
    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    private func updateLaunchAgent() {
        if config.general.launchAtLogin {
            // Find current binary path
            let binaryPath = ProcessInfo.processInfo.arguments[0]
            let plist: [String: Any] = [
                "Label": Self.launchAgentLabel,
                "ProgramArguments": [binaryPath],
                "RunAtLoad": true,
                "KeepAlive": false,
            ]
            let dir = Self.launchAgentURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: Self.launchAgentURL)
            NSLog("[Bobber] Created LaunchAgent at \(Self.launchAgentURL.path)")
        } else {
            try? FileManager.default.removeItem(at: Self.launchAgentURL)
            NSLog("[Bobber] Removed LaunchAgent")
        }
    }
}
```

**Step 2: Build**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift build 2>&1 | tail -10`
Expected: Still fails due to missing other settings views — expected.

**Step 3: Commit**

```bash
git add Sources/Bobber/UI/Settings/GeneralSettingsView.swift
git commit -m "feat: add GeneralSettingsView with launch-at-login and CLI path"
```

---

### Task 5: Create PluginSettingsView

**Files:**
- Create: `Sources/Bobber/UI/Settings/PluginSettingsView.swift`

**Step 1: Create the view**

```swift
import SwiftUI

struct PluginSettingsView: View {
    @ObservedObject var claudeCLIManager: ClaudeCLIManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Plugin").font(.title2).fontWeight(.semibold)

            // Status card
            GroupBox {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle).fontWeight(.medium)
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
            }

            // Action buttons
            GroupBox("Actions") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        switch claudeCLIManager.pluginStatus {
                        case .notInstalled, .cliNotFound, .unknown:
                            Button("Install Plugin") {
                                claudeCLIManager.installPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.pluginStatus == .cliNotFound || claudeCLIManager.isRunningOperation)
                        case .installed:
                            Button("Reinstall") {
                                claudeCLIManager.reinstallPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                            Button("Uninstall") {
                                claudeCLIManager.uninstallPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                        case .installedDisabled:
                            Button("Uninstall") {
                                claudeCLIManager.uninstallPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                        case .updateAvailable(_, _):
                            Button("Update") {
                                claudeCLIManager.updatePlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                            Button("Uninstall") {
                                claudeCLIManager.uninstallPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                        }

                        if claudeCLIManager.isRunningOperation {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Button("Refresh Status") {
                        claudeCLIManager.checkPluginStatus()
                    }
                    .disabled(claudeCLIManager.isRunningOperation)
                }
                .padding(8)
            }

            // Operation log
            if !claudeCLIManager.operationLog.isEmpty {
                GroupBox("Log") {
                    ScrollView {
                        Text(claudeCLIManager.operationLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                }
            }

            Spacer()
        }
        .onAppear {
            claudeCLIManager.checkPluginStatus()
        }
    }

    private var statusColor: Color {
        switch claudeCLIManager.pluginStatus {
        case .installed: return .green
        case .updateAvailable: return .orange
        case .installedDisabled: return .yellow
        case .notInstalled, .unknown: return .red
        case .cliNotFound: return .gray
        }
    }

    private var statusTitle: String {
        switch claudeCLIManager.pluginStatus {
        case .installed: return "Installed & Active"
        case .installedDisabled: return "Installed (Disabled)"
        case .updateAvailable(let local, let remote): return "Update Available (\(local) → \(remote))"
        case .notInstalled: return "Not Installed"
        case .cliNotFound: return "Claude CLI Not Found"
        case .unknown: return "Checking..."
        }
    }

    private var statusDescription: String {
        switch claudeCLIManager.pluginStatus {
        case .installed: return "Bobber plugin is active in Claude Code."
        case .installedDisabled: return "Plugin is installed but disabled. Enable it in Claude Code with /plugin."
        case .updateAvailable: return "A newer version is available."
        case .notInstalled: return "Plugin not installed. Click Install to set up."
        case .cliNotFound: return "Set Claude CLI path in General settings first."
        case .unknown: return "Detecting plugin status..."
        }
    }
}
```

**Step 2: Commit**

```bash
git add Sources/Bobber/UI/Settings/PluginSettingsView.swift
git commit -m "feat: add PluginSettingsView with status detection and lifecycle actions"
```

---

### Task 6: Create SoundsSettingsView and AppearanceSettingsView

**Files:**
- Create: `Sources/Bobber/UI/Settings/SoundsSettingsView.swift`
- Create: `Sources/Bobber/UI/Settings/AppearanceSettingsView.swift`

**Step 1: Create SoundsSettingsView**

```swift
import SwiftUI

struct SoundsSettingsView: View {
    @Binding var config: BobberConfig
    let onConfigChanged: () -> Void

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

            Spacer()
        }
    }
}
```

**Step 2: Create AppearanceSettingsView**

```swift
import SwiftUI

struct AppearanceSettingsView: View {
    @Binding var config: BobberConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance").font(.title2).fontWeight(.semibold)

            GroupBox("Panel Opacity") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Idle:")
                        Slider(value: $config.appearance.idleOpacity, in: 0.1...1.0, step: 0.05)
                            .onChange(of: config.appearance.idleOpacity) { _ in onConfigChanged() }
                        Text("\(Int(config.appearance.idleOpacity * 100))%")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Hover:")
                        Slider(value: $config.appearance.hoverOpacity, in: 0.5...1.0, step: 0.05)
                            .onChange(of: config.appearance.hoverOpacity) { _ in onConfigChanged() }
                        Text("\(Int(config.appearance.hoverOpacity * 100))%")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }

                    Text("The panel fades to idle opacity when not hovered.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            Spacer()
        }
    }
}
```

**Step 3: Commit**

```bash
git add Sources/Bobber/UI/Settings/SoundsSettingsView.swift Sources/Bobber/UI/Settings/AppearanceSettingsView.swift
git commit -m "feat: add SoundsSettingsView and AppearanceSettingsView"
```

---

### Task 7: Create SessionsSettingsView and ShortcutsSettingsView

**Files:**
- Create: `Sources/Bobber/UI/Settings/SessionsSettingsView.swift`
- Create: `Sources/Bobber/UI/Settings/ShortcutsSettingsView.swift`

**Step 1: Create SessionsSettingsView**

```swift
import SwiftUI

struct SessionsSettingsView: View {
    @Binding var config: BobberConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sessions").font(.title2).fontWeight(.semibold)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Stale timeout:")
                        TextField("", value: $config.sessions.staleTimeoutMinutes, format: .number)
                            .frame(width: 60)
                            .onChange(of: config.sessions.staleTimeoutMinutes) { _ in onConfigChanged() }
                        Text("minutes")
                            .foregroundColor(.secondary)
                    }
                    Text("Sessions with no events for this long are marked stale.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack {
                        Text("Keep completed:")
                        TextField("", value: $config.sessions.keepCompletedCount, format: .number)
                            .frame(width: 60)
                            .onChange(of: config.sessions.keepCompletedCount) { _ in onConfigChanged() }
                        Text("sessions")
                            .foregroundColor(.secondary)
                    }
                    Text("Maximum number of completed sessions to keep in history.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            Spacer()
        }
    }
}
```

**Step 2: Create ShortcutsSettingsView**

```swift
import SwiftUI

struct ShortcutsSettingsView: View {
    @Binding var config: BobberConfig
    let onConfigChanged: () -> Void
    @State private var isRecording = false
    @State private var conflictWarning: String?

    private static let systemShortcuts: Set<String> = [
        "command+c", "command+v", "command+x", "command+z",
        "command+a", "command+s", "command+q", "command+w",
        "command+tab", "command+space",
        "control+space",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shortcuts").font(.title2).fontWeight(.semibold)

            GroupBox("Toggle Panel") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hotkey:")
                        if isRecording {
                            Text("Press a key combination...")
                                .foregroundColor(.orange)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Text(shortcutDisplay)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15)))
                        }
                        Spacer()
                        Button(isRecording ? "Cancel" : "Record") {
                            isRecording.toggle()
                            if !isRecording { conflictWarning = nil }
                        }
                    }

                    if let warning = conflictWarning {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(warning)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Text("Press Record, then press your desired key combination.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
            .background(
                ShortcutRecorder(isRecording: $isRecording) { key, modifiers in
                    let combo = modifiers.sorted().joined(separator: "+") + "+" + key
                    if Self.systemShortcuts.contains(combo.lowercased()) {
                        conflictWarning = "'\(combo)' conflicts with a system shortcut. It may not work as expected."
                    } else {
                        conflictWarning = nil
                    }
                    config.shortcuts.togglePanelKey = key
                    config.shortcuts.togglePanelModifiers = modifiers
                    isRecording = false
                    onConfigChanged()
                }
            )

            Spacer()
        }
    }

    private var shortcutDisplay: String {
        let mods = config.shortcuts.togglePanelModifiers.map { mod -> String in
            switch mod.lowercased() {
            case "option": return "\u{2325}"
            case "command": return "\u{2318}"
            case "control": return "\u{2303}"
            case "shift": return "\u{21E7}"
            default: return mod
            }
        }.joined()
        return mods + config.shortcuts.togglePanelKey.uppercased()
    }
}

/// NSViewRepresentable that captures keyboard events when isRecording is true
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (String, [String]) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        ShortcutRecorderView(onRecord: onRecord)
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.isRecordingEnabled = isRecording
    }

    class ShortcutRecorderView: NSView {
        let onRecord: (String, [String]) -> Void
        var isRecordingEnabled = false
        private var monitor: Any?

        init(onRecord: @escaping (String, [String]) -> Void) {
            self.onRecord = onRecord
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecordingEnabled else { return event }
                var modifiers: [String] = []
                if event.modifierFlags.contains(.command) { modifiers.append("command") }
                if event.modifierFlags.contains(.option) { modifiers.append("option") }
                if event.modifierFlags.contains(.control) { modifiers.append("control") }
                if event.modifierFlags.contains(.shift) { modifiers.append("shift") }
                guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return event }
                // Ignore bare modifier key presses
                guard !modifiers.isEmpty else { return event }
                self.onRecord(key, modifiers)
                return nil  // consume event
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
```

**Step 3: Build to verify all settings views compile**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift build 2>&1 | tail -10`
Expected: Build succeeds (all settings views exist now)

**Step 4: Commit**

```bash
git add Sources/Bobber/UI/Settings/SessionsSettingsView.swift Sources/Bobber/UI/Settings/ShortcutsSettingsView.swift
git commit -m "feat: add SessionsSettingsView and ShortcutsSettingsView with conflict detection"
```

---

### Task 8: Add gear icon to PanelContentView

**Files:**
- Modify: `Sources/Bobber/UI/PanelContentView.swift`

**Step 1: Add gear button and onSettings callback**

In `PanelContentView`, add `var onSettings: (() -> Void)?` property and a gear icon button in the title bar, on the right side (symmetric with `CloseButton` on left).

Modify the `ZStack` in the body:

```swift
// Add property:
var onSettings: (() -> Void)?

// Replace the ZStack content in body:
ZStack {
    Picker("", selection: $selectedTab) {
        Text("Sessions").tag(PanelTab.sessions)
        HStack(spacing: 4) {
            Text("Actions")
            if sessionManager.pendingActions.count > 0 {
                Text("\(sessionManager.pendingActions.count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
            }
        }.tag(PanelTab.actions)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize()

    HStack {
        CloseButton(action: { onHide?() })
        Spacer()
        Button(action: { onSettings?() }) {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
}
```

**Step 2: Build**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/Bobber/UI/PanelContentView.swift
git commit -m "feat: add gear icon button to panel title bar for settings"
```

---

### Task 9: Wire up FloatingPanel to read opacity from config

**Files:**
- Modify: `Sources/Bobber/UI/FloatingPanel.swift`

**Step 1: Make opacity configurable**

Change the hardcoded opacity values to be configurable via an `updateOpacity` method. Replace the static constants with instance properties:

```swift
// Replace:
//   private static let idleAlpha: CGFloat = 0.65
//   private static let hoverAlpha: CGFloat = 1.0
// With:
private(set) var idleAlpha: CGFloat = 0.65
private(set) var hoverAlpha: CGFloat = 1.0

func updateOpacity(idle: CGFloat, hover: CGFloat) {
    idleAlpha = idle
    hoverAlpha = hover
    // If not currently hovered, update immediately
    if alphaValue != hoverAlpha {
        alphaValue = idleAlpha
    }
}
```

Also update `HoverTrackingHostingView` to reference the panel's instance properties instead of static ones. The `onHover` closure already captures `self` (the panel), so change:

```swift
let hostingView = HoverTrackingHostingView(rootView: contentView) { [weak self] hovering in
    guard let self else { return }
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        self.animator().alphaValue = hovering ? self.hoverAlpha : self.idleAlpha
    }
}
```

**Step 2: Build and test**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/Bobber/UI/FloatingPanel.swift
git commit -m "feat: make FloatingPanel opacity configurable instead of hardcoded"
```

---

### Task 10: Wire up HotkeyManager to read shortcut from config

**Files:**
- Modify: `Sources/Bobber/Services/HotkeyManager.swift`

**Step 1: Make hotkey configurable**

Add properties and a `reconfigure` method:

```swift
class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onTogglePanel: (() -> Void)?
    var onJumpToSession: ((Int) -> Void)?
    var isPanelVisible: (() -> Bool)?

    var toggleKey: String = "b"
    var toggleModifiers: Set<String> = ["option"]

    func reconfigure(key: String, modifiers: [String]) {
        toggleKey = key
        toggleModifiers = Set(modifiers)
        // Restart monitors to pick up new config
        stop()
        start()
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Configurable toggle hotkey
        if matchesToggleShortcut(event) {
            onTogglePanel?()
            return
        }

        guard isPanelVisible?() == true else { return }

        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let char = event.charactersIgnoringModifiers,
           let digit = Int(char),
           digit >= 1 && digit <= 9 {
            onJumpToSession?(digit - 1)
        }

        if event.keyCode == 53 {
            onTogglePanel?()
        }
    }

    private func matchesToggleShortcut(_ event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers,
              chars.lowercased() == toggleKey.lowercased() else { return false }
        let flags = event.modifierFlags
        let expected = toggleModifiers
        if expected.contains("option") != flags.contains(.option) { return false }
        if expected.contains("command") != flags.contains(.command) { return false }
        if expected.contains("control") != flags.contains(.control) { return false }
        if expected.contains("shift") != flags.contains(.shift) { return false }
        return true
    }
}
```

**Step 2: Build and test**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/Bobber/Services/HotkeyManager.swift
git commit -m "feat: make HotkeyManager shortcut configurable with reconfigure method"
```

---

### Task 11: Wire everything together in AppDelegate and PanelController

**Files:**
- Modify: `Sources/Bobber/AppDelegate.swift`
- Modify: `Sources/Bobber/UI/PanelController.swift`

**Step 1: Add settings infrastructure to AppDelegate**

Add `SettingsWindowController`, `ClaudeCLIManager`, and `BobberConfig` to AppDelegate. Wire config changes to all services.

In `AppDelegate`:

```swift
// Add new properties:
private var settingsController: SettingsWindowController?
private var claudeCLIManager: ClaudeCLIManager!
private var config: BobberConfig = BobberConfig.load()

// In applicationDidFinishLaunching, after existing init:
claudeCLIManager = ClaudeCLIManager()
if let savedPath = config.general.claudeCLIPath {
    claudeCLIManager.setCustomPath(savedPath)
} else {
    claudeCLIManager.autoDetect()
}

// Apply config to services:
applyConfig()

// In setupPanel, pass onSettings:
// Add onSettings callback to PanelController init

// Add method:
private func applyConfig() {
    soundManager.enabled = config.sounds.enabled
    soundManager.volume = config.sounds.volume
    soundManager.cooldownSeconds = config.sounds.cooldownSeconds

    if let panel = panelController?.panel {
        panel.updateOpacity(idle: CGFloat(config.appearance.idleOpacity),
                           hover: CGFloat(config.appearance.hoverOpacity))
    }

    hotkeyManager?.reconfigure(key: config.shortcuts.togglePanelKey,
                                modifiers: config.shortcuts.togglePanelModifiers)
}

private func showSettings() {
    if settingsController == nil {
        settingsController = SettingsWindowController(
            config: Binding(get: { self.config }, set: { self.config = $0 }),
            claudeCLIManager: claudeCLIManager,
            onConfigChanged: { [weak self] in
                guard let self else { return }
                self.config.save()
                self.applyConfig()
            }
        )
    }
    settingsController?.show()
}
```

**Step 2: Update PanelController to expose panel and accept onSettings**

In `PanelController`:

```swift
// Add property:
private let onSettings: (() -> Void)?

// Update init signature:
init(sessionManager: SessionManager,
     onPermissionDecision: ((String, PermissionDecision) -> Void)? = nil,
     onJumpToSession: ((Session) -> Void)? = nil,
     onSettings: (() -> Void)? = nil) {
    self.sessionManager = sessionManager
    self.onPermissionDecision = onPermissionDecision
    self.onJumpToSession = onJumpToSession
    self.onSettings = onSettings
}

// Expose panel for opacity updates:
var panel: FloatingPanel? { _panel }
// Rename private var to _panel or make it accessible

// In show(), pass onSettings to PanelContentView:
let contentView = PanelContentView(
    sessionManager: sessionManager,
    onPermissionDecision: onPermissionDecision,
    onJumpToSession: onJumpToSession,
    onHide: { [weak self] in self?.hide() },
    onSettings: onSettings
)
```

**Step 3: Update setupPanel in AppDelegate**

```swift
private func setupPanel() {
    panelController = PanelController(
        sessionManager: sessionManager,
        onPermissionDecision: { [weak self] sessionId, decision in
            self?.permissionServer?.respond(sessionId: sessionId, decision: decision)
        },
        onJumpToSession: { [weak self] session in
            self?.windowJumper.jumpToSession(session)
        },
        onSettings: { [weak self] in
            self?.showSettings()
        }
    )
}
```

**Step 4: Build and run**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift build 2>&1 | tail -10`
Expected: Build succeeds

**Step 5: Run all tests**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift test 2>&1 | tail -20`
Expected: All tests pass

**Step 6: Commit**

```bash
git add Sources/Bobber/AppDelegate.swift Sources/Bobber/UI/PanelController.swift
git commit -m "feat: wire settings window, config, and CLI manager into app lifecycle"
```

---

### Task 12: Add marketplace.json to repo root

**Files:**
- Create: `.claude-plugin/marketplace.json`

**Step 1: Create marketplace manifest**

Create `.claude-plugin/marketplace.json`:

```json
{
  "name": "bobber",
  "owner": {
    "name": "Bobber"
  },
  "metadata": {
    "description": "Bobber - floating desktop companion for Claude Code sessions"
  },
  "plugins": [
    {
      "name": "bobber-claude",
      "source": "./plugins/claude-bobber-plugin",
      "description": "Session monitoring hooks for Bobber",
      "version": "1.0.0",
      "keywords": ["bobber", "monitoring", "hooks", "session"]
    }
  ]
}
```

**Step 2: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "feat: add marketplace.json for Claude Code plugin distribution"
```

---

### Task 13: Manual integration test

**Step 1: Build and run**

Run: `cd /Users/winrey/Projects/weightwave/bobber && ./Scripts/restart.sh`

**Step 2: Test checklist**

- [ ] Gear icon visible in panel title bar (right side)
- [ ] Click gear opens Settings window (separate from panel)
- [ ] Sidebar shows all 6 categories with icons
- [ ] General: Launch at login toggle works (check ~/Library/LaunchAgents/)
- [ ] General: CLI auto-detect finds claude (or shows "Not found")
- [ ] General: Browse button opens file picker
- [ ] Plugin: Status card shows correct state
- [ ] Plugin: Install/Uninstall buttons work (if CLI found)
- [ ] Sounds: Toggle, volume slider, cooldown input all save to config
- [ ] Appearance: Opacity sliders change panel opacity in real-time
- [ ] Sessions: Timeout and count inputs save correctly
- [ ] Shortcuts: Record button captures new key combo
- [ ] Shortcuts: Conflict warning appears for Cmd+C etc.
- [ ] Shortcuts: New shortcut actually works after recording
- [ ] Settings window persists while panel hides/shows
- [ ] Config persists after app restart (check ~/.bobber/config.json)

**Step 3: Fix any issues found**

**Step 4: Final commit**

```bash
git add -A
git commit -m "fix: integration test fixes for settings panel"
```

---

### Task 14: Run full test suite

**Step 1: Run all tests**

Run: `cd /Users/winrey/Projects/weightwave/bobber && swift test 2>&1`
Expected: All tests pass

**Step 2: Commit if any test fixes needed**

```bash
git add -A
git commit -m "fix: test fixes for settings panel"
```
