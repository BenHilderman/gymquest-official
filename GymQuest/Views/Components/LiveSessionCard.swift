// Live session card — design v4.3 §3B
// "marcus is locked in at goodlife · 47 min in" + last set + send hype + ask sets.

import SwiftUI

struct LiveSessionCardData {
    let username: String
    let displayName: String
    let workoutLabel: String        // "push" / "legs" etc.
    let gymLabel: String?           // "goodlife"
    let elapsedMinutes: Int
    let lastSetSummary: String?     // "just hit 225 x 8"
    let songTitle: String?
    let avatarURL: URL?
}

struct LiveSessionCard: View {
    let data: LiveSessionCardData
    var onSendHype: () -> Void = {}
    var onAskSetsLeft: () -> Void = {}
    var onJoin: () -> Void = {}
    var onLiftWith: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.green, lineWidth: 2.5)
                        .frame(width: 50, height: 50)
                    Circle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                    if let url = data.avatarURL {
                        AsyncImage(url: url) { phase in
                            (phase.image ?? Image(systemName: "person.fill")).resizable().scaledToFill()
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.white)
                    }
                }
                .modifier(LivePulseModifier())

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(data.displayName.lowercased()) is locked in" + (data.gymLabel.map { " at \($0)" } ?? ""))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("\(data.workoutLabel) · \(data.elapsedMinutes) min in")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let lastSet = data.lastSetSummary {
                Text(lastSet)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }

            if let song = data.songTitle {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11))
                    Text(song)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(action: onSendHype) {
                    Text("send hype 🔥")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading, endPoint: .trailing
                        )))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("ask sets left?") { onAskSetsLeft() }
                    Button("join him") { onJoin() }
                    Button("lift with him") { onLiftWith() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct LivePulseModifier: ViewModifier {
    @State private var pulse = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
