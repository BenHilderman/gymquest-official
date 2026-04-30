// Messages list — design v4.3 §6A.

import SwiftUI

struct MessagesListEntry: Identifiable {
    let id: UUID
    let threadId: UUID
    let displayName: String
    let username: String
    let avatarURL: URL?
    let lastSnippet: String
    let lastAt: Date
    let unreadCount: Int
    let presence: PresenceRingState
}

struct MessagesPeopleSuggestion: Identifiable {
    let id: UUID
    let displayName: String
    let username: String
    let avatarURL: URL?
    let reasonLine: String  // "you reacted to their last 3 sessions"
}

struct MessagesListView: View {
    let unreadCount: Int
    let reactStreakConvoCount: Int
    let threads: [MessagesListEntry]
    let suggestions: [MessagesPeopleSuggestion]
    var onSelectThread: (UUID) -> Void = { _ in }
    var onStartFromSuggestion: (MessagesPeopleSuggestion, String) -> Void = { _, _ in }

    var body: some View {
        List {
            Section {
                if unreadCount > 0 || reactStreakConvoCount > 0 {
                    HStack(spacing: 10) {
                        if unreadCount > 0 {
                            Label("\(unreadCount) unread", systemImage: "envelope.badge.fill").font(.caption)
                        }
                        if reactStreakConvoCount > 0 {
                            Label("\(reactStreakConvoCount) react streaks", systemImage: "flame.fill").font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Section("messages") {
                ForEach(threads) { t in
                    Button { onSelectThread(t.threadId) } label: {
                        threadRow(t)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !suggestions.isEmpty {
                Section("people you might DM") {
                    ForEach(suggestions) { s in
                        suggestionRow(s)
                    }
                }
            }
        }
        .navigationTitle("messages")
    }

    @ViewBuilder
    private func threadRow(_ t: MessagesListEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(t.presence.color, lineWidth: t.presence.ringWidth)
                    .frame(width: 50, height: 50)
                Circle().fill(.gray.opacity(0.3)).frame(width: 44, height: 44)
                if let url = t.avatarURL {
                    AsyncImage(url: url) { phase in
                        (phase.image ?? Image(systemName: "person.fill"))
                            .resizable().scaledToFill()
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Text(t.lastSnippet)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(relative(t.lastAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if t.unreadCount > 0 {
                    Text("\(t.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.blue))
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func suggestionRow(_ s: MessagesPeopleSuggestion) -> some View {
        HStack(spacing: 12) {
            Circle().fill(.gray.opacity(0.3)).frame(width: 40, height: 40).overlay(
                Group {
                    if let url = s.avatarURL {
                        AsyncImage(url: url) { phase in
                            (phase.image ?? Image(systemName: "person.fill"))
                                .resizable().scaledToFill()
                        }
                        .clipShape(Circle())
                    }
                }
            )
            VStack(alignment: .leading) {
                Text(s.displayName).font(.system(size: 14, weight: .semibold))
                Text(s.reasonLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(DMOpener.allCases) { o in
                    Button(o.rawValue) {
                        onStartFromSuggestion(s, o.rawValue)
                    }
                }
            } label: {
                Text("dm")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(.blue.opacity(0.6)))
                    .foregroundStyle(.white)
            }
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: .init())
    }
}
