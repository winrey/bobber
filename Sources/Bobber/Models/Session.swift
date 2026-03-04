import Foundation

enum SessionState: String, Codable {
    case active, blocked, idle, completed, stale
}

struct SessionEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let type: BobberEvent.EventType
    let tool: String?
    let summary: String?

    init(timestamp: Date, type: BobberEvent.EventType, tool: String?, summary: String?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.type = type
        self.tool = tool
        self.summary = summary
    }
}

struct Session: Identifiable, Codable {
    let id: String
    let projectName: String
    let projectPath: String
    var sessionTitle: String?
    var state: SessionState = .active
    var lastEvent: Date = Date()
    var lastTool: String?
    var lastToolSummary: String?
    var pendingAction: PendingAction?
    var terminal: TerminalInfo?
    var pid: Int32?
    var priority: SessionPriority = .standard
    var recentEvents: [SessionEvent] = []

    init(
        id: String,
        projectName: String,
        projectPath: String,
        sessionTitle: String? = nil,
        state: SessionState = .active,
        lastEvent: Date = Date(),
        lastTool: String? = nil,
        lastToolSummary: String? = nil,
        pendingAction: PendingAction? = nil,
        terminal: TerminalInfo? = nil,
        pid: Int32? = nil,
        priority: SessionPriority = .standard,
        recentEvents: [SessionEvent] = []
    ) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.sessionTitle = sessionTitle
        self.state = state
        self.lastEvent = lastEvent
        self.lastTool = lastTool
        self.lastToolSummary = lastToolSummary
        self.pendingAction = pendingAction
        self.terminal = terminal
        self.pid = pid
        self.priority = priority
        self.recentEvents = recentEvents
    }

    // recentEvents deliberately excluded — transient runtime data, rebuilds from live events
    enum CodingKeys: String, CodingKey {
        case id, projectName, projectPath, sessionTitle, state
        case lastEvent, lastTool, lastToolSummary, pendingAction, terminal, pid, priority
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectName = try c.decode(String.self, forKey: .projectName)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        sessionTitle = try c.decodeIfPresent(String.self, forKey: .sessionTitle)
        state = try c.decode(SessionState.self, forKey: .state)
        lastEvent = try c.decode(Date.self, forKey: .lastEvent)
        lastTool = try c.decodeIfPresent(String.self, forKey: .lastTool)
        lastToolSummary = try c.decodeIfPresent(String.self, forKey: .lastToolSummary)
        pendingAction = try c.decodeIfPresent(PendingAction.self, forKey: .pendingAction)
        terminal = try c.decodeIfPresent(TerminalInfo.self, forKey: .terminal)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        priority = try c.decodeIfPresent(SessionPriority.self, forKey: .priority) ?? .standard
    }

    mutating func handleEvent(type: BobberEvent.EventType) {
        lastEvent = Date()
        switch type {
        case .permissionPrompt, .elicitationDialog:
            state = .blocked
        case .preToolUse, .userPromptSubmit, .sessionStart:
            state = .active
            pendingAction = nil
        case .stop, .taskCompleted:
            state = .idle
        case .sessionEnd:
            state = .completed
        case .idlePrompt:
            state = .idle
        case .notification:
            break
        }
    }
}
