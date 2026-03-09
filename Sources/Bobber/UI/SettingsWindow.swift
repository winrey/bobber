import AppKit
import SwiftUI

class ConfigStore: ObservableObject {
    @Published var value: BobberConfig

    init(_ config: BobberConfig) {
        self.value = config
    }
}

class SettingsWindowController {
    private var window: NSWindow?
    private let configStore: ConfigStore
    private let claudeCLIManager: ClaudeCLIManager
    private let onConfigChanged: () -> Void
    private let soundManager: SoundManager

    init(configStore: ConfigStore, claudeCLIManager: ClaudeCLIManager, soundManager: SoundManager, onConfigChanged: @escaping () -> Void) {
        self.configStore = configStore
        self.claudeCLIManager = claudeCLIManager
        self.soundManager = soundManager
        self.onConfigChanged = onConfigChanged
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            configStore: configStore,
            claudeCLIManager: claudeCLIManager,
            onConfigChanged: onConfigChanged,
            soundManager: soundManager
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Bobber Settings"
        window.contentMinSize = NSSize(width: 500, height: 350)
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
