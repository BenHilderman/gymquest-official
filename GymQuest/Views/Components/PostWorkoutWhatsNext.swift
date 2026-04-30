// Post-Workout — What's Next + anticipation hooks + smart caption row.
// Design v4.3 §7B.

import SwiftUI

enum WhatsNextCardKind: CaseIterable {
    case reactToFriend
    case saveAsTemplate
    case squadProgress
    case tipOfTheMoment
    case tomorrowsPlan

    var headline: String {
        switch self {
        case .reactToFriend: return "react to a friend's workout"
        case .saveAsTemplate: return "save this workout as a template?"
        case .squadProgress: return "your squad needs 1 more session this week"
        case .tipOfTheMoment: return "tip of the moment"
        case .tomorrowsPlan: return "tomorrow's plan"
        }
    }

    var icon: String {
        switch self {
        case .reactToFriend: return "heart.fill"
        case .saveAsTemplate: return "bookmark.fill"
        case .squadProgress: return "person.3.sequence.fill"
        case .tipOfTheMoment: return "lightbulb.fill"
        case .tomorrowsPlan: return "calendar.badge.plus"
        }
    }
}

struct WhatsNextCardView: View {
    let kind: WhatsNextCardKind
    let detailLine: String?
    var onTap: () -> Void = {}
    var onSkip: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("before you go...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 12) {
                Image(systemName: kind.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LinearGradient(colors: [.purple, .blue],
                                                                 startPoint: .topLeading,
                                                                 endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.headline).font(.system(size: 14, weight: .semibold))
                    if let d = detailLine {
                        Text(d).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button("open", action: onTap).buttonStyle(.borderedProminent)
                Button("skip", action: onSkip)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }
}

struct AnticipationHookBanner: View {
    enum Tone { case soonReactions, mightPopOff, squadGonnaSee }

    let tone: Tone
    var copy: String {
        switch tone {
        case .soonReactions: return "reactions usually start in 5 min 👀"
        case .mightPopOff: return "this might pop off"
        case .squadGonnaSee: return "your squad's gonna see this"
        }
    }

    var body: some View {
        Text(copy)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.10)))
            .foregroundStyle(.white)
    }
}

/// Variants of ProofCardView added per design §7B (currently 6/9 exist in repo).
enum ProofCardVariantV43: String, CaseIterable, Identifiable {
    case cleanFlex = "clean flex"
    case cinematic
    case funny
    case prFocused = "PR-focused"
    case crewSquadRecap = "crew recap"
    case partnerRecap = "partner"
    case streak
    case blackWhite = "b&w"
    case photoOverlay = "photo overlay"
    var id: String { rawValue }
}

struct ProofVariantPicker: View {
    @Binding var selected: ProofCardVariantV43
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProofCardVariantV43.allCases) { v in
                    Button {
                        selected = v
                    } label: {
                        Text(v.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(selected == v
                                ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue],
                                                                 startPoint: .leading,
                                                                 endPoint: .trailing))
                                : AnyShapeStyle(.white.opacity(0.10))))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

/// Partner Proof Card — both avatars side-by-side, "lifted together · 64 min".
struct PartnerProofCard: View {
    let partnerADisplayName: String
    let partnerBDisplayName: String
    let partnerAAvatar: URL?
    let partnerBAvatar: URL?
    let sharedDurationLabel: String
    let combinedVolumeLabel: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: -10) {
                avatarBubble(partnerAAvatar)
                avatarBubble(partnerBAvatar)
            }
            Text("\(partnerADisplayName.lowercased()) + \(partnerBDisplayName.lowercased())")
                .font(.system(size: 16, weight: .semibold))
            Text("lifted together · \(sharedDurationLabel)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(combinedVolumeLabel)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.10)))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(LinearGradient(
            colors: [.purple.opacity(0.4), .blue.opacity(0.4)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )))
    }

    private func avatarBubble(_ url: URL?) -> some View {
        Circle()
            .fill(.gray.opacity(0.4))
            .frame(width: 56, height: 56)
            .overlay(
                Group {
                    if let url {
                        AsyncImage(url: url) { phase in
                            (phase.image ?? Image(systemName: "person.fill")).resizable().scaledToFill()
                        }
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill").foregroundStyle(.white)
                    }
                }
            )
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}
