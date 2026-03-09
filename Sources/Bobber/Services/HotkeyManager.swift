import AppKit

class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var toggleKey: String = "b"
    var toggleModifiers: Set<String> = ["option"]
    var onTogglePanel: (() -> Void)?
    var onJumpToSession: ((Int) -> Void)?
    var isPanelVisible: (() -> Bool)?

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

    func reconfigure(key: String, modifiers: [String]) {
        toggleKey = key
        toggleModifiers = Set(modifiers)
        stop()
        start()
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

    private func handleKeyDown(_ event: NSEvent) {
        // Toggle shortcut -> toggle panel
        if matchesToggleShortcut(event) {
            onTogglePanel?()
            return
        }

        // Only handle number keys and escape when panel is visible
        guard isPanelVisible?() == true else { return }

        // Number keys 1-9 (no modifier) -> jump to session
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let char = event.charactersIgnoringModifiers,
           let digit = Int(char),
           digit >= 1 && digit <= 9 {
            onJumpToSession?(digit - 1)
        }

        // Escape -> hide panel
        if event.keyCode == 53 {
            onTogglePanel?()
        }
    }
}
