import XCTest
@testable import Bobber

final class SessionManagerTests: XCTestCase {
    func testNewEventCreatesSession() {
        let manager = SessionManager()
        let event = makeEvent(sessionId: "s1", type: .sessionStart, projectName: "test")

        manager.handleEvent(event)

        let session = manager.sessions.first(where: { $0.id == "s1" })
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.projectName, "test")
    }

    func testPermissionEventCreatesAction() {
        let manager = SessionManager()
        let event = makeEvent(
            sessionId: "s1",
            type: .permissionPrompt,
            projectName: "test",
            tool: "Bash",
            command: "pnpm test"
        )

        manager.handleEvent(event)

        XCTAssertTrue(manager.pendingActions.contains(where: { $0.type == .permission && $0.sessionId == "s1" }))
        XCTAssertEqual(manager.sessions.first(where: { $0.id == "s1" })?.state, .blocked)
    }

    func testToolUseEventClearsBlockedState() {
        let manager = SessionManager()
        manager.handleEvent(makeEvent(sessionId: "s1", type: .permissionPrompt, projectName: "test"))
        manager.handleEvent(makeEvent(sessionId: "s1", type: .preToolUse, projectName: "test"))

        XCTAssertEqual(manager.sessions.first(where: { $0.id == "s1" })?.state, .active)
    }

    func testStaleSessionDetection() {
        let manager = SessionManager()
        manager.handleEvent(makeEvent(sessionId: "s-stale1", type: .sessionStart, projectName: "test"))
        // Simulate old timestamp
        if let idx = manager.sessions.firstIndex(where: { $0.id == "s-stale1" }) {
            manager.sessions[idx].lastEvent = Date().addingTimeInterval(-31 * 60)
        }

        manager.cleanupSessions()

        XCTAssertEqual(manager.sessions.first(where: { $0.id == "s-stale1" })?.state, .stale)
    }

    func testSetSessionPriority() {
        let manager = SessionManager()
        manager.handleEvent(makeEvent(sessionId: "s-prio1", type: .sessionStart, projectName: "prio-test"))

        manager.setSessionPriority("s-prio1", priority: .focus)

        let session = manager.sessions.first(where: { $0.id == "s-prio1" })
        XCTAssertEqual(session?.priority, .focus)
    }

    func testSetProjectPriority() {
        let manager = SessionManager()
        manager.handleEvent(makeEvent(sessionId: "s-proj1", type: .sessionStart, projectName: "proj-prio"))
        manager.handleEvent(makeEvent(sessionId: "s-proj2", type: .sessionStart, projectName: "proj-prio"))

        manager.setProjectPriority(projectPath: "/tmp/proj-prio", priority: .priority)

        let s1 = manager.sessions.first(where: { $0.id == "s-proj1" })
        let s2 = manager.sessions.first(where: { $0.id == "s-proj2" })
        XCTAssertEqual(s1?.priority, .priority)
        XCTAssertEqual(s2?.priority, .priority)
        XCTAssertEqual(manager.projectPriorityDefaults["/tmp/proj-prio"], .priority)
    }

    func testNewSessionInheritsProjectPriority() {
        let manager = SessionManager()
        manager.projectPriorityDefaults["/tmp/inherit-proj"] = .focus

        manager.handleEvent(makeEvent(sessionId: "s-inherit", type: .sessionStart, projectName: "inherit-proj"))

        let session = manager.sessions.first(where: { $0.id == "s-inherit" })
        XCTAssertEqual(session?.priority, .focus)
    }

    // Helper
    private func makeEvent(
        sessionId: String,
        type: BobberEvent.EventType,
        projectName: String,
        tool: String? = nil,
        command: String? = nil
    ) -> BobberEvent {
        BobberEvent(
            version: 1,
            timestamp: Date(),
            pid: 12345,
            sessionId: sessionId,
            projectPath: "/tmp/\(projectName)",
            projectName: projectName,
            sessionTitle: nil,
            eventType: type,
            details: tool != nil ? EventDetails(
                tool: tool, command: command, description: nil,
                question: nil, options: nil, message: nil
            ) : nil,
            terminal: nil
        )
    }
}
