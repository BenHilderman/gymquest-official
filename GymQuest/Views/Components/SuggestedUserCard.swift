// Suggested user own card type — design v4.3 §3B
// Renders in the friends feed in its own card (NEVER inline as a post).

import SwiftUI

enum SuggestedUserReason: Equatable {
    case sameGym(gym: String, count: Int)
    case sameTime(window: String)
    case sameSplitMutuals(split: String, mutualCount: Int)
    case schoolMutuals(count: Int, school: String)
    case crewMember(crewName: String)

    var headline: String {
        switch self {
        case .sameGym(let gym, let count): return "you've seen them at \(gym) \(count) times"
        case .sameTime(let window): return "trains at the same time as you (\(window))"
        case .sameSplitMutuals(let split, let mutualCount): return "same \(split) split + \(mutualCount) mutuals"
        case .schoolMutuals(let count, let school): return "\(count) mutuals from \(school)"
        case .crewMember(let crewName): return "in your crew \(crewName)"
        }
    }
}

struct SuggestedUserCard: View {
    let username: String
    let displayName: String
    let avatarURL: URL?
    let reason: SuggestedUserReason
    var onFollow: () -> Void = {}
    var onTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("suggested for you")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                AvatarBubble(url: avatarURL, size: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("@\(username)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(reason.headline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)

                Button(action: onFollow) {
                    Text("follow")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

private struct AvatarBubble: View {
    let url: URL?
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.purple.opacity(0.5), .blue.opacity(0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
