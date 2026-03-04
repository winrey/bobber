import SwiftUI

struct SessionsListView: View {
    @ObservedObject var sessionManager: SessionManager
    var onSelectSession: ((String) -> Void)?

    /// Sessions grouped by projectPath, sorted by most recent activity (hidden sessions filtered out)
    private var groupedSessions: [(projectName: String, sessions: [Session])] {
        let visible = sessionManager.sessions.filter { !sessionManager.hiddenSessionIds.contains($0.id) }
        let grouped = Dictionary(grouping: visible) { $0.projectPath }
        return grouped.map { (path, sessions) in
            let name = sessions.first?.projectName ?? URL(fileURLWithPath: path).lastPathComponent
            let sorted = sessions.sorted { $0.lastEvent > $1.lastEvent }
            return (projectName: name, sessions: sorted)
        }
        .sorted { group1, group2 in
            let latest1 = group1.sessions.first?.lastEvent ?? .distantPast
            let latest2 = group2.sessions.first?.lastEvent ?? .distantPast
            return latest1 > latest2
        }
    }

    var body: some View {
        if sessionManager.sessions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "fish")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No active sessions")
                    .foregroundColor(.secondary)
                Text("Start a Claude Code session\nwith the Bobber plugin to see it here")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(groupedSessions, id: \.projectName) { group in
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

                            // Session rows
                            ForEach(group.sessions) { session in
                                Button {
                                    onSelectSession?(session.id)
                                } label: {
                                    SessionRowView(session: session, sessionManager: sessionManager)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }
}

struct SessionRowView: View {
    let session: Session
    @ObservedObject var sessionManager: SessionManager
    @State private var pulsePhase: Bool = false
    @State private var showRenameAlert: Bool = false
    @State private var nicknameInput: String = ""

    private var needsAttention: Bool {
        session.state == .blocked || session.state == .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Title row: dot + title + time
            HStack(spacing: 6) {
                Circle()
                    .fill(session.state.color.opacity(needsAttention ? (pulsePhase ? 1.0 : 0.3) : 1.0))
                    .frame(width: 8, height: 8)
                    .scaleEffect(needsAttention && pulsePhase ? 1.4 : 1.0)
                    .shadow(color: needsAttention ? session.state.color.opacity(pulsePhase ? 0.8 : 0.0) : .clear, radius: pulsePhase ? 8 : 0)
                if let nickname = sessionManager.sessionNicknames[session.id] {
                    Text(nickname)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .lineLimit(1)
                    Text(session.displayTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(session.displayTitle)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .lineLimit(1)
                }
                Spacer()
                if needsAttention {
                    Text(session.state.label)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(session.state.color)
                }
                Text(session.lastEvent.relativeDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Activity line: command/tool summary
            if let summary = session.activitySummary {
                Text(summary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            ZStack {
                // Base card background (always present)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
                // Attention gradient overlay
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [
                            session.state.color.opacity(pulsePhase ? 0.15 : 0.05),
                            session.state.color.opacity(pulsePhase ? 0.08 : 0.02)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .opacity(needsAttention ? 1 : 0)
                // Attention border
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(session.state.color.opacity(pulsePhase ? 0.4 : 0.15), lineWidth: 1)
                    .opacity(needsAttention ? 1 : 0)
            }
        )
        .onAppear {
            if needsAttention {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsePhase = true
                }
            }
        }
        .onChange(of: needsAttention) { attention in
            if attention {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsePhase = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    pulsePhase = false
                }
            }
        }
        .contextMenu {
            Button {
                nicknameInput = sessionManager.sessionNicknames[session.id] ?? ""
                showRenameAlert = true
            } label: {
                Label("Rename Session", systemImage: "pencil")
            }
            if sessionManager.sessionNicknames[session.id] != nil {
                Button {
                    sessionManager.renameSession(session.id, nickname: "")
                } label: {
                    Label("Clear Nickname", systemImage: "xmark.circle")
                }
            }
            Divider()
            Button {
                withAnimation {
                    sessionManager.hideSession(session.id)
                }
            } label: {
                Label("Hide Session", systemImage: "eye.slash")
            }
        }
        .alert("Rename Session", isPresented: $showRenameAlert) {
            TextField("Nickname", text: $nicknameInput)
            Button("OK") {
                sessionManager.renameSession(session.id, nickname: nicknameInput)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a nickname for this session")
        }
    }
}

extension SessionState {
    var color: Color {
        switch self {
        case .active: return .green
        case .blocked: return .green
        case .idle: return .yellow
        case .completed: return .gray
        case .stale: return .gray.opacity(0.5)
        }
    }

    var label: String {
        switch self {
        case .active: return "Active"
        case .blocked: return "Blocked"
        case .idle: return "Idle"
        case .completed: return "Done"
        case .stale: return "Stale"
        }
    }
}

extension Session {
    /// Title: custom title > session title from Claude > short session ID
    var displayTitle: String {
        if let title = sessionTitle, !title.isEmpty {
            return title
        }
        // Truncate long IDs (UUIDs) to first 8 chars
        if id.count > 12 {
            return "Session \(id.prefix(8))"
        }
        return id
    }

    /// Cleaned-up tool summary for display, nil if nothing meaningful
    var activitySummary: String? {
        guard let summary = lastToolSummary,
              !summary.trimmingCharacters(in: .whitespaces).isEmpty,
              summary != "$", summary != "$ " else {
            // Fall back to tool name if summary is empty
            if let tool = lastTool, !tool.isEmpty {
                return tool
            }
            return state == .active ? "Working..." : nil
        }
        return summary
    }
}

extension Date {
    var relativeDescription: String {
        let interval = -self.timeIntervalSinceNow
        if interval < 5 { return "now" }
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        return "\(Int(interval / 3600))h"
    }
}
