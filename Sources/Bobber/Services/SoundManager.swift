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

    func shouldPlay() -> Bool {
        guard let last = lastPlayTime else { return true }
        return Date().timeIntervalSince(last) >= cooldownSeconds
    }

    func recordPlay() {
        lastPlayTime = Date()
    }
}