// DM thread — design v4.3 §6A.
// Text + voice + photo + video + shared workouts/profiles/stories/crews + partner invite.

import SwiftUI

struct DMThreadView: View {
    let threadId: UUID
    let partnerDisplayName: String
    let partnerPresence: PresenceRingState
    @State private var messages: [DMMessageDisplay] = []
    @State private var draft: String = ""
    @State private var showOpeners: Bool = false
    var onSend: (String) -> Void = { _ in }
    var onSendVoice: (URL) -> Void = { _ in }
    var onSendPhoto: (URL) -> Void = { _ in }
    var onPartnerInvite: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { m in
                        bubble(m)
                    }
                }
                .padding(12)
            }
            if showOpeners {
                DMOpenerChipsRow { opener in
                    draft = opener
                    showOpeners = false
                }
                .padding(.bottom, 6)
            }
            inputBar
        }
        .navigationTitle(partnerDisplayName.lowercased())
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Circle().fill(partnerPresence.color).frame(width: 8, height: 8)
                    Text(partnerDisplayName.lowercased())
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ m: DMMessageDisplay) -> some View {
        HStack {
            if m.fromMe { Spacer(minLength: 50) }
            Group {
                switch m.kind {
                case .text:
                    Text(m.body)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                case .voice:
                    if let url = m.localURL {
                        VoiceReactionPlayButton(url: url, compact: false)
                    } else {
                        Text("[voice]")
                    }
                case .photo:
                    if let url = m.localURL {
                        PhotoReactionLoopThumb(url: url)
                    } else {
                        Text("[photo]")
                    }
                case .workoutShare:
                    Label("workout share", systemImage: "figure.strengthtraining.traditional")
                        .padding(.horizontal, 10).padding(.vertical, 6)
                case .partnerInvite:
                    Label("lift with me", systemImage: "person.2.fill")
                        .padding(.horizontal, 10).padding(.vertical, 6)
                default:
                    Text(m.body).padding(.horizontal, 10).padding(.vertical, 6)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(m.fromMe ? Color.blue.opacity(0.7) : Color.white.opacity(0.10)))
            .foregroundStyle(.white)
            if !m.fromMe { Spacer(minLength: 50) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                showOpeners.toggle()
            } label: {
                Image(systemName: "text.bubble.fill")
                    .padding(8)
            }
            TextField("message", text: $draft)
                .textFieldStyle(.roundedBorder)
            Menu {
                Button("invite to lift", action: onPartnerInvite)
                Button("share last workout") {}
                Button("share profile") {}
            } label: {
                Image(systemName: "plus.circle.fill").padding(8)
            }
            VoiceReactionRecordButton { url in
                onSendVoice(url)
            }
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

struct DMMessageDisplay: Identifiable {
    let id: UUID
    let fromMe: Bool
    let kind: DMMessageKind
    let body: String
    let localURL: URL?
    let createdAt: Date
}
