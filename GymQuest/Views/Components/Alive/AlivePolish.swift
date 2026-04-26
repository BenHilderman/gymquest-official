//
//  AlivePolish.swift
//  GymQuest
//
//  Phase 6 of the Alive release: friction removers + polish.
//
//  Shipped here:
//   - PushThrottle: max 1 "<friend started training>" push per friend per
//     day. UserDefaults-backed, fail-closed.
//   - GhostSelfOverlay: dim overlay on the user's own avatar when their
//     session is ghosted. Shown to self only — never broadcast.
//   - QuickReplyButtons: three structured-reply buttons for the Friend
//     profile sheet ("Heading there?" / "How was it?" / "Sets remaining?").
//
//  Deferred (touch large existing surfaces; out of conversation scope):
//   - No-caption-default in CreatePostView / post editor.
//   - Auto-tag clubmates suggestion when posting from a co-presence session.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Push throttling

/// One push per friend per day. UserDefaults dict keyed by friendId UUID
/// string → ISO date of last push. Read before scheduling, write after.
enum PushThrottle {
    private static let key = "alive.pushHistory"

    static func canPush(forFriend id: UUID, on date: Date = Date()) -> Bool {
        let history = load()
        guard let last = history[id.uuidString] else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: date)
    }

    static func recordPush(forFriend id: UUID, on date: Date = Date()) {
        var history = load()
        history[id.uuidString] = date
        save(history)
    }

    private static func load() -> [String: Date] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: TimeInterval] else { return [:] }
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func save(_ history: [String: Date]) {
        let raw: [String: TimeInterval] = history.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(raw, forKey: key)
    }
}

// MARK: - Ghost self overlay

/// Dim overlay on the user's OWN avatar when this session is ghosted.
/// Self-only — the network never sees this. The actual privacy comes from
/// `PresenceState.status = .ghost` which the ring modifier already hides.
/// This is purely a "hey, you're invisible right now" reminder.
struct GhostSelfOverlay: ViewModifier {
    let isGhosted: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .opacity(isGhosted ? 0.45 : 1.0)
            .overlay(
                Group {
                    if isGhosted {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .offset(x: 0, y: 0)
                    }
                }
            )
    }
}

extension View {
    func ghostSelfOverlay(_ isGhosted: Bool) -> some View {
        modifier(GhostSelfOverlay(isGhosted: isGhosted))
    }
}

// MARK: - Quick replies on friend profile

struct QuickReplyButtons: View {
    let toUserId: UUID
    let fromUserId: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var sentText: String? = nil

    private static let replies = [
        "Heading there?",
        "How was it?",
        "Sets remaining?"
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.replies, id: \.self) { text in
                Button {
                    send(text: text)
                } label: {
                    Text(text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(sentText == text ? AlivePresence.green.opacity(0.18) : GQColors.surfaceBase)
                        )
                        .overlay(Capsule().stroke(GQColors.borderDefault, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(sentText == text)
            }
        }
    }

    private func send(text: String) {
        let r = LiveReaction(
            fromUserId: fromUserId,
            toUserId: toUserId,
            sessionStartedAt: Date(),
            kind: "quickReply",
            quickReplyText: text
        )
        modelContext.insert(r)
        try? modelContext.save()
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { sentText = text }
    }
}
