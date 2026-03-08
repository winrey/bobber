import SwiftUI

struct GeneralSettingsView: View {
    @Binding var config: BobberConfig
    @ObservedObject var claudeCLIManager: ClaudeCLIManager
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General").font(.title2).fontWeight(.semibold)

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
