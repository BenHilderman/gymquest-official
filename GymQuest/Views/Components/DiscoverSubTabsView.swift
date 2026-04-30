// Discover 3 sub-tabs + Today's Mix + Trending Now + Discover Streak chip.
// Design v4.3 §3A.

import SwiftUI

enum DiscoverSubTab: String, CaseIterable, Identifiable {
    case watch
    case friends
    case tips
    var id: String { rawValue }
}

struct DiscoverSubTabsHeader: View {
    @Binding var selected: DiscoverSubTab
    let streakSummary: String?
    var onTapStreak: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                ForEach(DiscoverSubTab.allCases) { sub in
                    Button {
                        selected = sub
                    } label: {
                        VStack(spacing: 4) {
                            Text(sub.rawValue)
                                .font(.system(size: 14, weight: selected == sub ? .bold : .medium))
                            Capsule()
                                .fill(selected == sub ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.clear))
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
                Spacer()
                if let s = streakSummary, !s.isEmpty {
                    Button(action: onTapStreak) {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill").font(.caption)
                            Text(s).font(.caption2)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.10)))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct TodayMixCard: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let imageURL: URL?
    let kindLabel: String
}

struct TodayMixRail: View {
    let cards: [TodayMixCard]
    var onTap: (TodayMixCard) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("today's mix")
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("rotates daily").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cards) { c in
                        Button {
                            onTap(c)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    if let url = c.imageURL {
                                        AsyncImage(url: url) { phase in
                                            (phase.image ?? Image(systemName: "photo"))
                                                .resizable().scaledToFill()
                                        }
                                    } else {
                                        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    }
                                    Text(c.kindLabel)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(.black.opacity(0.4)))
                                        .foregroundStyle(.white)
                                        .padding(6)
                                }
                                .frame(width: 160, height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 14))

                                Text(c.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                    .foregroundStyle(.white)
                                Text(c.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(width: 160)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct TrendingNowChipsRail: View {
    let titles: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("trending now")
                .font(.system(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(titles, id: \.self) { t in
                        Text(t)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(.white.opacity(0.10)))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
