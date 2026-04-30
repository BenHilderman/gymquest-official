// Squad Chat — design v4.3 §6B.
// Group chat. Auto-shared workout completions are real event rows
// (system_event_kind != null), NOT bot speech. Quiet states stay quiet.

import SwiftUI

struct SquadChatView: View {
    let squadName: String
    let memberCount: Int
    @State private var messages: [SquadMessageDisplay] = []
    @State private var draft: String = ""
    @State private var quietNudgesEnabled: Bool = false
    var onSend: (String) -> Void = { _ in }
    var onPoll: (String, [String]) -> Void = { _, _ in }
    var onShareWorkout: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(messages) { m in
                        row(m)
                    }
                    if messages.isEmpty {
                        quietState
                    }
                }
                .padding(12)
            }
            inputBar
        }
        .navigationTitle(squadName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("quiet nudges", isOn: $quietNudgesEnabled)
                    Button("share last workout", action: onShareWorkout)
                    Button("create poll") { onPoll("legs tonight?", ["yes","no","maybe"]) }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ m: SquadMessageDisplay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(.gray.opacity(0.3)).frame(width: 32, height: 32).overlay(
                Text(String(m.senderInitial)).font(.caption)
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.senderName.lowercased()).font(.caption).foregroundStyle(.secondary)
                    if m.isSystemEvent {
                        Text("· event").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(m.body).font(.system(size: 14))
                if m.isWorkoutFinishEvent {
                    HStack(spacing: 8) {
                        ForEach([LiftReaction.fire, .goat, .monke], id: \.self) { r in
                            Button { } label: {
                                Text(r.rawValue).font(.system(size: 16))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(.white.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private var quietState: some View {
        VStack(spacing: 4) {
            Text("nothing here yet")
                .font(.system(size: 14, weight: .semibold))
            Text("real conversations only — quiet is honest")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("message squad", text: $draft).textFieldStyle(.roundedBorder)
            Button {
                let body = draft.trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { return }
                onSend(body)
                draft = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
            }
        }
        .padding(8)
    }
}

struct SquadMessageDisplay: Identifiable {
    let id: UUID
    let senderName: String
    let senderInitial: Character
    let body: String
    let isSystemEvent: Bool
    let isWorkoutFinishEvent: Bool
    let createdAt: Date
}
