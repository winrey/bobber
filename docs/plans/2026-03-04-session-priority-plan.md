# Session Priority Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Focus/Priority/Standard priority levels to sessions with global sorting, project-level defaults, and per-session overrides.

**Architecture:** New `SessionPriority` enum on `Session` model. `SessionManager` gains `projectPriorityDefaults` dict and methods for setting priority. `SessionsListView` sorting changes to 3-layer (priority → project → lastEvent). Context menus and detail view gain priority controls.

**Tech Stack:** Swift, SwiftUI, AppKit, SPM

---

### Task 1: Add SessionPriority Enum

**Files:**
- Create: `Sources/Bobber/Models/SessionPriority.swift`
- Test: `Tests/BobberTests/ModelTests.swift`

**Step 1: Write the failing test**

Add to `Tests/BobberTests/ModelTests.swift`:

```swift
func testSessionPriorityOrdering() {
    XCTAssertTrue(SessionPriority.focus < SessionPriority.priority)
    XCTAssertTrue(SessionPriority.priority < SessionPriority.standard)
    XCTAssertEqual(SessionPriority.allCases.count, 3)
}

func testSessionPriorityDefaultIsStandard() {
    let session = Session(id: "s1", projectName: "test", projectPath: "/tmp/test")
    XCTAssertEqual(session.priority, .standard)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ModelTests 2>&1 | tail -20`
Expected: FAIL — `SessionPriority` not defined

**Step 3: Write minimal implementation**

Create `Sources/Bobber/Models/SessionPriority.swift`:

```swift
import Foundation

enum SessionPriority: Int, Codable, CaseIterable, Comparable {
    case focus = 0
    case priority = 1
    case standard = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .focus: return "专注"
        case .priority: return "优先"
        case .standard: return "标准"
        }
    }
}
```

Then add `var priority: SessionPriority = .standard` to `Session` struct in `Sources/Bobber/Models/Session.swift:28` (after the `sessionTitle` line). No CodingKeys change needed — it will encode/decode automatically, and the default value handles missing keys on decode.

Wait — `Session` has explicit `CodingKeys` (line 38-41) which excludes `priority`. Add `priority` to the CodingKeys enum:

```swift
enum CodingKeys: String, CodingKey {
    case id, projectName, projectPath, sessionTitle, state
    case lastEvent, lastTool, lastToolSummary, pendingAction, terminal, pid, priority
}
```

Since `priority` has a default value and `Session` uses auto-synthesized `Codable`, existing JSON without a `priority` field will need a custom decoder. Add a custom `init(from:)`:

```swift
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
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ModelTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/Bobber/Models/SessionPriority.swift Sources/Bobber/Models/Session.swift Tests/BobberTests/ModelTests.swift
git commit -m "feat: add SessionPriority enum and priority field to Session"
```

---

### Task 2: Add Backward-Compatible Decoding Test

**Files:**
- Test: `Tests/BobberTests/ModelTests.swift`

**Step 1: Write the failing test**

Add to `Tests/BobberTests/ModelTests.swift`:

```swift
func testSessionDecodesWithoutPriorityField() throws {
    let json = """
    {
        "id": "s1",
        "projectName": "test",
        "projectPath": "/tmp/test",
        "state": "active",
        "lastEvent": "2026-03-04T10:00:00Z"
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let session = try decoder.decode(Session.self, from: json)
    XCTAssertEqual(session.priority, .standard)
}

func testSessionDecodesWithPriorityField() throws {
    let json = """
    {
        "id": "s1",
        "projectName": "test",
        "projectPath": "/tmp/test",
        "state": "active",
        "lastEvent": "2026-03-04T10:00:00Z",
        "priority": 0
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let session = try decoder.decode(Session.self, from: json)
    XCTAssertEqual(session.priority, .focus)
}
```

**Step 2: Run test to verify it passes**

Run: `swift test --filter ModelTests 2>&1 | tail -20`
Expected: PASS (if Task 1 custom decoder was implemented correctly)

**Step 3: Commit**

```bash
git add Tests/BobberTests/ModelTests.swift
git commit -m "test: add backward-compatible Session decoding tests for priority"
```

---

### Task 3: Add Priority Methods to SessionManager

**Files:**
- Modify: `Sources/Bobber/Services/SessionManager.swift`
- Test: `Tests/BobberTests/SessionManagerTests.swift`

**Step 1: Write the failing tests**

Add to `Tests/BobberTests/SessionManagerTests.swift`:

```swift
func testSetSessionPriority() {
    let manager = SessionManager()
    manager.handleEvent(makeEvent(sessionId: "s1", type: .sessionStart, projectName: "test"))

    manager.setSessionPriority("s1", priority: .focus)

    XCTAssertEqual(manager.sessions.first?.priority, .focus)
}

func testSetProjectPriority() {
    let manager = SessionManager()
    manager.handleEvent(makeEvent(sessionId: "s1", type: .sessionStart, projectName: "test"))
    manager.handleEvent(makeEvent(sessionId: "s2", type: .sessionStart, projectName: "test"))

    manager.setProjectPriority(projectPath: "/tmp/test", priority: .priority)

    XCTAssertEqual(manager.sessions[0].priority, .priority)
    XCTAssertEqual(manager.sessions[1].priority, .priority)
    XCTAssertEqual(manager.projectPriorityDefaults["/tmp/test"], .priority)
}

func testNewSessionInheritsProjectPriority() {
    let manager = SessionManager()
    manager.projectPriorityDefaults["/tmp/test"] = .focus

    manager.handleEvent(makeEvent(sessionId: "s1", type: .sessionStart, projectName: "test"))

    XCTAssertEqual(manager.sessions.first?.priority, .focus)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SessionManagerTests 2>&1 | tail -20`
Expected: FAIL — `setSessionPriority`, `setProjectPriority`, `projectPriorityDefaults` not defined

**Step 3: Write minimal implementation**

In `Sources/Bobber/Services/SessionManager.swift`:

1. Add published property after line 9:

```swift
@Published var projectPriorityDefaults: [String: SessionPriority] = [:] { didSet { saveState() } }
```

2. Add `projectPriorityDefaults` to `PersistedState` struct (around line 54):

```swift
private struct PersistedState: Codable {
    let sessions: [Session]
    let pendingActions: [PendingAction]
    var hiddenSessionIds: Set<String> = []
    var sessionNicknames: [String: String] = [:]
    var acknowledgedSessionIds: Set<String> = []
    var projectPriorityDefaults: [String: SessionPriority] = [:]
}
```

3. Update `loadState()` to restore it (after line 34):

```swift
projectPriorityDefaults = state.projectPriorityDefaults
```

4. Update `saveState()` to include it:

```swift
let state = PersistedState(
    sessions: sessions,
    pendingActions: pendingActions,
    hiddenSessionIds: hiddenSessionIds,
    sessionNicknames: sessionNicknames,
    acknowledgedSessionIds: acknowledgedSessionIds,
    projectPriorityDefaults: projectPriorityDefaults
)
```

5. Add methods after `acknowledgeSession` (after line 77):

```swift
func setSessionPriority(_ sessionId: String, priority: SessionPriority) {
    guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
    sessions[index].priority = priority
}

func setProjectPriority(projectPath: String, priority: SessionPriority) {
    projectPriorityDefaults[projectPath] = priority
    for i in sessions.indices where sessions[i].projectPath == projectPath {
        sessions[i].priority = priority
    }
}
```

6. In `handleEvent`, when creating a new session (around line 110-133), after `session.pid = event.pid`, add:

```swift
session.priority = projectPriorityDefaults[event.projectPath] ?? .standard
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter SessionManagerTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/Bobber/Services/SessionManager.swift Tests/BobberTests/SessionManagerTests.swift
git commit -m "feat: add priority methods and project defaults to SessionManager"
```

---

### Task 4: Refactor SessionsListView Sorting Logic

**Files:**
- Modify: `Sources/Bobber/UI/SessionRowView.swift` (SessionsListView is in this file)

**Step 1: Update the `groupedSessions` computed property**

Replace the existing `groupedSessions` property (lines 8-21 of `SessionsListView`) with the new 3-layer sorting:

```swift
/// Sections: priority group → project groups → sessions sorted by lastEvent
private var sections: [(priority: SessionPriority, projectGroups: [(projectName: String, projectPath: String, sessions: [Session])])] {
    let visible = sessionManager.sessions.filter { !sessionManager.hiddenSessionIds.contains($0.id) }

    // Layer 1: group by priority
    let byPriority = Dictionary(grouping: visible) { $0.priority }

    return SessionPriority.allCases.compactMap { priority in
        guard let sessionsAtPriority = byPriority[priority], !sessionsAtPriority.isEmpty else { return nil }

        // Layer 2: group by projectPath
        let byProject = Dictionary(grouping: sessionsAtPriority) { $0.projectPath }
        let projectGroups = byProject.map { (path, sessions) -> (projectName: String, projectPath: String, sessions: [Session]) in
            let name = sessions.first?.projectName ?? URL(fileURLWithPath: path).lastPathComponent
            // Layer 3: sort by lastEvent within project
            let sorted = sessions.sorted { $0.lastEvent > $1.lastEvent }
            return (projectName: name, projectPath: path, sessions: sorted)
        }
        .sorted { g1, g2 in
            let latest1 = g1.sessions.first?.lastEvent ?? .distantPast
            let latest2 = g2.sessions.first?.lastEvent ?? .distantPast
            return latest1 > latest2
        }

        return (priority: priority, projectGroups: projectGroups)
    }
}
```

**Step 2: Update the body to use new sections**

Replace the `ScrollView` content in body (lines 38-66) with:

```swift
ScrollView {
    LazyVStack(spacing: 12) {
        ForEach(sections, id: \.priority) { section in
            // Priority group header (skip for .standard)
            if section.priority != .standard {
                HStack(spacing: 6) {
                    Text(section.priority.displayName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(section.priority.accentColor)
                        .textCase(.uppercase)
                    Rectangle()
                        .fill(section.priority.accentColor.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal, 4)
                .padding(.top, section.priority == .focus ? 0 : 4)
            }

            ForEach(section.projectGroups, id: \.projectPath) { group in
                VStack(alignment: .leading, spacing: 4) {
                    // Project header
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(group.projectName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 4)
                    .contextMenu {
                        priorityMenu(for: group.projectPath)
                    }

                    // Session rows
                    ForEach(group.sessions) { session in
                        SessionRowView(session: session, sessionManager: sessionManager)
                            .onTapGesture {
                                onSelectSession?(session.id)
                            }
                    }
                }
            }
        }
    }
    .padding(8)
}
```

**Step 3: Add helper methods to SessionsListView**

```swift
@ViewBuilder
private func priorityMenu(for projectPath: String) -> some View {
    let current = sessionManager.projectPriorityDefaults[projectPath] ?? .standard
    Menu("设置项目优先级") {
        ForEach(SessionPriority.allCases, id: \.self) { priority in
            Button {
                sessionManager.setProjectPriority(projectPath: projectPath, priority: priority)
            } label: {
                HStack {
                    Text(priority.displayName)
                    if priority == current {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}
```

**Step 4: Add `accentColor` to SessionPriority**

In `Sources/Bobber/Models/SessionPriority.swift`, add:

```swift
import SwiftUI

// Add to the enum:
var accentColor: Color {
    switch self {
    case .focus: return .orange
    case .priority: return .blue
    case .standard: return .secondary
    }
}
```

**Step 5: Build and verify**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeded

**Step 6: Commit**

```bash
git add Sources/Bobber/Models/SessionPriority.swift Sources/Bobber/UI/SessionRowView.swift
git commit -m "feat: refactor session list to 3-layer priority sorting"
```

---

### Task 5: Add Priority Context Menu to SessionRowView

**Files:**
- Modify: `Sources/Bobber/UI/SessionRowView.swift` (the `SessionRowView` struct)

**Step 1: Add priority submenu to context menu**

In the existing `.contextMenu` on `SessionRowView` (around line 168-190), add a priority submenu before the Divider:

```swift
.contextMenu {
    Menu("优先级") {
        ForEach(SessionPriority.allCases, id: \.self) { priority in
            Button {
                sessionManager.setSessionPriority(session.id, priority: priority)
            } label: {
                HStack {
                    Text(priority.displayName)
                    if priority == session.priority {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
    Button { /* existing rename */ } label: { ... }
    // ... rest of existing menu
}
```

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add Sources/Bobber/UI/SessionRowView.swift
git commit -m "feat: add priority submenu to session row context menu"
```

---

### Task 6: Add Priority Picker to SessionDetailView

**Files:**
- Modify: `Sources/Bobber/UI/SessionDetailView.swift`

**Step 1: Add priority picker to status tab**

In `statusTab` (around line 78-145), after the State row (line 88) and before the first Divider (line 90), add:

```swift
// Priority
HStack(spacing: 8) {
    Text("Priority")
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 70, alignment: .leading)
    Picker("", selection: Binding(
        get: { session.priority },
        set: { newPriority in
            sessionManager.setSessionPriority(session.id, priority: newPriority)
        }
    )) {
        ForEach(SessionPriority.allCases, id: \.self) { priority in
            Text(priority.displayName).tag(priority)
        }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
}
```

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add Sources/Bobber/UI/SessionDetailView.swift
git commit -m "feat: add priority picker to session detail view"
```

---

### Task 7: Run Full Test Suite and Verify

**Files:** None (verification only)

**Step 1: Run all tests**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass

**Step 2: Build and run app**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeded

**Step 3: Final commit if any fixups needed**

If tests fail, fix and commit. Otherwise this task is a verification checkpoint.
