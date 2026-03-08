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
                guard !modifiers.isEmpty else { return event }
                self.onRecord(key, modifiers)
                return nil
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
