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
