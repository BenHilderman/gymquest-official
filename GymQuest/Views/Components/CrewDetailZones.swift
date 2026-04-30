// Crew Detail zones — design v4.3 §5D.
// Zone 1 Header / Zone 2 Now & Next / Zone 3 Unified Feed + Streak Badge + Memories.

import SwiftUI

struct CrewDetailHeader: View {
    let coverImageURL: URL?
    let crewName: String
    let vibeTags: [String]
    let memberCount: Int
    let activeMemberCount: Int
    let location: String?
    let isJoined: Bool
    var onJoin: () -> Void = {}
    var onLeave: () -> Void = {}
    var onCreatePost: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if let coverImageURL {
                    AsyncImage(url: coverImageURL) { phase in
                        (phase.image ?? Image(systemName: "photo")).resizable().scaledToFill()
                    }
                    .frame(height: 140)
                    .clipped()
                } else {
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(height: 140)
                }

                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(crewName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        if let location {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.circle.fill").font(.caption)
                                Text(location).font(.caption)
                            }
                            .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("\(activeMemberCount) active")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.4)))
                }
                .padding(12)
            }

            HStack(spacing: 6) {
                ForEach(vibeTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                Spacer()
                Text("\(memberCount) members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)

            HStack(spacing: 10) {
                if isJoined {
                    Button("create", action: onCreatePost)
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Menu {
                        Button("leave crew", role: .destructive, action: onLeave)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                } else {
                    Button("join", action: onJoin)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

struct CrewNowAndNextZone: View {
    let activeMembers: [String]    // display names
    let nextEventTitle: String?
    let nextEventCountdown: String?
    let friendsGoingCount: Int
    var onSendHype: () -> Void = {}
    var onRSVP: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("now")
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if activeMembers.isEmpty {
                Text("no one is active rn — be the first")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(activeMembers.prefix(4), id: \.self) { name in
                        HStack {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text("\(name) is locked in")
                                .font(.system(size: 13))
                            Spacer()
                            Button("hype 🔥", action: onSendHype)
                                .font(.caption.bold())
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            }

            HStack {
                Text("next")
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let title = nextEventTitle {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if let countdown = nextEventCountdown {
                        Text(countdown).font(.caption).foregroundStyle(.secondary)
                    }
                    if friendsGoingCount > 0 {
                        Text("\(friendsGoingCount) friends going")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("RSVP", action: onRSVP)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            } else {
                Text("nothing scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            }
        }
    }
}

struct CrewStreakBadge: View {
    let daysInCrew: Int
    let attendanceRankPercent: Int?
    let nextMilestoneDays: Int?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("you've been in this crew for \(daysInCrew) days")
                    .font(.system(size: 13, weight: .semibold))
                if let pct = attendanceRankPercent {
                    Text("rank: top \(pct)% by attendance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let next = nextMilestoneDays {
                VStack(alignment: .trailing) {
                    Text("next")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(next) days")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }
}

struct CrewMemoriesSection: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                memoryRow(icon: "play.rectangle.fill", title: "weekly highlight reel")
                memoryRow(icon: "flame.fill", title: "streak anniversary")
                memoryRow(icon: "trophy.fill", title: "PR replay")
                memoryRow(icon: "music.note", title: "crew playlist")
                memoryRow(icon: "rectangle.grid.3x2.fill", title: "featured wall")
                memoryRow(icon: "calendar", title: "on this day")
                memoryRow(icon: "clock.arrow.circlepath", title: "your crew history")
            }
            .padding(.top, 6)
        } label: {
            Text("memories")
                .font(.system(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func memoryRow(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13))
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
