// Plus tab v4.3 polish — design §4B.
// WOD card / Music row / Friends training row / Lift With Friend pill / social proof.

import SwiftUI

struct WorkoutOfTheDayCard: View {
    enum Source: String { case crew = "from your crew", trending, saved = "saved last week", aiSuggested = "AI suggested" }
    let title: String
    let detail: String
    let source: Source
    var onStart: () -> Void = {}

    var body: some View {
        Button(action: onStart) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("workout of the day")
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(source.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.10)))
                }
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack {
                    Spacer()
                    Text("start").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(LinearGradient(colors: [.purple, .blue],
                                                                     startPoint: .leading,
                                                                     endPoint: .trailing)))
                        .foregroundStyle(.white)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

struct GymPlaylistRow: View {
    let resumeTitle: String
    let friendListeningSong: String?
    let friendListeningName: String?
    var onResume: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onResume) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                    Text(resumeTitle).font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.10)))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if let song = friendListeningSong, let name = friendListeningName {
                Text("\(name.lowercased()) → \(song)")
                    .font(.caption).lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct FriendTrainingRowItem: Identifiable {
    let id: UUID
    let displayName: String
    let kindLabel: String
    let elapsedMinutes: Int?
    let avatarURL: URL?
    let isLive: Bool
}

struct FriendsTrainingRow: View {
    let items: [FriendTrainingRowItem]
    var onTap: (FriendTrainingRowItem) -> Void = { _ in }
    var onLongPressLiftWith: (FriendTrainingRowItem) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        onTap(item)
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(item.isLive ? Color.green : Color.gray.opacity(0.5),
                                            lineWidth: item.isLive ? 2 : 1)
                                    .frame(width: 56, height: 56)
                                Circle().fill(.gray.opacity(0.3)).frame(width: 50, height: 50)
                                if let url = item.avatarURL {
                                    AsyncImage(url: url) { phase in
                                        (phase.image ?? Image(systemName: "person.fill"))
                                            .resizable().scaledToFill()
                                    }
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                                }
                            }
                            Text(item.displayName.lowercased())
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(detail(for: item))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 76)
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture {
                        onLongPressLiftWith(item)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func detail(for item: FriendTrainingRowItem) -> String {
        if let m = item.elapsedMinutes { return "\(item.kindLabel) · \(m)m" }
        return item.kindLabel
    }
}

struct LiftWithFriendPill: View {
    let friendDisplayName: String
    var onTap: () -> Void = {}
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill").font(.caption)
                Text("lift with \(friendDisplayName.lowercased())")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(LinearGradient(colors: [.purple, .blue],
                                                         startPoint: .leading,
                                                         endPoint: .trailing)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct PlusSocialProofLine: View {
    let nearbyTrainingCount: Int?
    let mutualsTrainedTodayPercent: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let n = nearbyTrainingCount {
                Text("\(n) ppl training near you rn")
                    .font(.system(size: 12, weight: .medium))
            }
            if let p = mutualsTrainedTodayPercent {
                Text("\(p)% of your mutuals trained today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }
}
