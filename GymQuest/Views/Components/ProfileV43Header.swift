// Profile v4.3 header surfaces — design §5A & §5B.
// Live State Line, Year So Far, Training Identity, Streak tier visual,
// Train Like Them, Lift With Them, VS You.

import SwiftUI

/// Profile Live State Line state — design v4.3 §5A + Item E locked spec.
/// Rotating pool with thresholds; training-state always priority, stat fills
/// only fill the rest-day slot. Self-derived data only — no Discover injection.
enum ProfileLiveStateKind {
    case trainingNow(label: String)    // green dot — "in it · push · 32 min"
    case recent(label: String)         // gray dot — "last lifted yesterday · push · 64 min"
    case statFill(label: String)       // purple dot — "87% of weeks this year — consistent"
    case prompt(label: String)         // gray dot — "back tomorrow?" / "let's start"
    case restDay
    case restDayEarned                 // gray dot — "rest day · earned" (recent + sustained training)
    case unknown

    // Legacy compatibility for existing callers using `.lastTrained(label:)`.
    static func lastTrained(label: String) -> ProfileLiveStateKind { .recent(label: label) }
}

struct ProfileLiveStateLine: View {
    let state: ProfileLiveStateKind

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var dotColor: Color {
        switch state {
        case .trainingNow: return .green
        case .statFill: return .purple
        case .recent, .prompt, .restDay, .restDayEarned: return .gray
        case .unknown: return .clear
        }
    }

    private var text: String {
        switch state {
        case .trainingNow(let l): return l
        case .recent(let l): return l
        case .statFill(let l): return l
        case .prompt(let l): return l
        case .restDay: return "rest day"
        case .restDayEarned: return "rest day · earned"
        case .unknown: return ""
        }
    }
}

struct YearSoFarCard: View {
    let totalSessions: Int
    let totalVolumeTons: Double
    let heaviestLiftLabel: String
    let mostConsistentMonth: String
    let prCount: Int
    var onShare: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("year so far")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
            }
            HStack(spacing: 14) {
                stat(label: "sessions", value: "\(totalSessions)")
                stat(label: "tons lifted", value: String(format: "%.1f", totalVolumeTons))
                stat(label: "PRs", value: "\(prCount)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("heaviest: \(heaviestLiftLabel)")
                Text("most consistent: \(mostConsistentMonth)")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(
            colors: [.purple.opacity(0.25), .blue.opacity(0.25)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )))
    }

    private func stat(label: String, value: String) -> some View {
        VStack {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct TrainingIdentityCard: View {
    let split: String
    let goal: String
    let experience: String
    let favoriteLifts: [String]
    let trainingStyle: String
    let vibeTag: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("training identity")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(split.lowercased()) · \(goal.lowercased()) · \(experience.lowercased())")
                    .font(.system(size: 13, weight: .medium))
                if !favoriteLifts.isEmpty {
                    Text("favs: \(favoriteLifts.joined(separator: ", ").lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("style: \(trainingStyle.lowercased()) · vibe: \(vibeTag.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
    }
}

enum StreakTier { case bronze, silver, gold, none

    static func from(days: Int) -> StreakTier {
        if days >= 365 { return .gold }
        if days >= 100 { return .silver }
        if days >= 30 { return .bronze }
        return .none
    }

    var label: String {
        switch self {
        case .bronze: return "30 days"
        case .silver: return "100 days"
        case .gold: return "365 days"
        case .none: return ""
        }
    }

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: return Color(red: 0.75, green: 0.75, blue: 0.78)
        case .gold: return .yellow
        case .none: return .gray
        }
    }
}

struct StreakVisualBadge: View {
    let days: Int
    var tier: StreakTier { .from(days: days) }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(tier.color)
            Text("\(days) day streak")
                .font(.system(size: 12, weight: .semibold))
            if tier != .none {
                Text("· \(tier.label)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}

struct PartnerStreakBadgeRow: View {
    let partnerDisplayName: String
    let days: Int
    var body: some View {
        HStack(spacing: 6) {
            Text("🤝")
            Text("\(days)-day partner streak with \(partnerDisplayName.lowercased())")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}

/// Other-user PRIMARY ACTION button + LIFT WITH THEM + VS YOU toggle.
struct OtherProfilePrimaryActions: View {
    let canLiftWithThem: Bool
    @Binding var vsYouEnabled: Bool
    var onTrainLikeThem: () -> Void = {}
    var onLiftWithThem: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onTrainLikeThem) {
                Text("train like them")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(LinearGradient(colors: [.purple, .blue],
                                                  startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if canLiftWithThem {
                Button(action: onLiftWithThem) {
                    Label("lift with them", systemImage: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.10))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Toggle("vs you", isOn: $vsYouEnabled)
                .font(.caption)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
