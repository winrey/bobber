import Foundation

enum BobberError: Error {
    case cannotWatchDirectory(String)
}

class EventFileWatcher {
    private let eventsDir: URL
    private let onChange: (BobberEvent) -> Void
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?
    private var processedFiles: Set<String> = []
    private var failedFiles: [String: Int] = [:]  // name -> retry count

    init(eventsDir: URL = defaultEventsDir, onChange: @escaping (BobberEvent) -> Void) {
        self.eventsDir = eventsDir
        self.onChange = onChange
    }

    static var defaultEventsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bobber/events")
    }

    func start() throws {
        // Ensure directory exists
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        NSLog("[Bobber] EventFileWatcher starting, watching: \(eventsDir.path)")

        // Primary: DispatchSource file system watcher
        let fd = open(eventsDir.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[Bobber] EventFileWatcher failed to open directory fd")
            throw BobberError.cannotWatchDirectory(eventsDir.path)
        }
        NSLog("[Bobber] EventFileWatcher got fd: \(fd)")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scanForNewEvents() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        self.dispatchSource = source

        // Fallback: 2-second polling timer
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scanForNewEvents()
        }

        // Process any existing files
        scanForNewEvents()
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func scanForNewEvents() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: eventsDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            NSLog("[Bobber] EventFileWatcher: failed to list directory contents")
            return
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if !jsonFiles.isEmpty {
            NSLog("[Bobber] EventFileWatcher: found \(jsonFiles.count) JSON file(s)")
        }

        for file in jsonFiles {
            let name = file.lastPathComponent
            guard !processedFiles.contains(name) else { continue }

            // Skip empty files (still being written)
            let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
            let size = attrs?[.size] as? UInt64 ?? 0
            if size == 0 { continue }

            do {
                let event = try Self.parseEventFile(at: file)
                NSLog("[Bobber] EventFileWatcher: parsed event \(event.eventType.rawValue) for session \(event.sessionId)")
                processedFiles.insert(name)
                failedFiles.removeValue(forKey: name)
                onChange(event)
                try? FileManager.default.removeItem(at: file)
            } catch {
                let retries = (failedFiles[name] ?? 0) + 1
                failedFiles[name] = retries
                if retries >= 5 {
                    // Give up after 5 retries (~10s), remove corrupt file
                    NSLog("[Bobber] EventFileWatcher: giving up on \(name) after \(retries) retries: \(error)")
                    processedFiles.insert(name)
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    static func parseEventFile(at url: URL) throws -> BobberEvent {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.bobber.decode(BobberEvent.self, from: data)
    }
}
