// Activity filter chips + emotional groupings — design v4.3 §5C.

import SwiftUI

enum ActivityV43Filter: String, CaseIterable, Identifiable {
    case all
    case reactions
    case comments
    case tags
    case followers
    case system
    var id: String { rawValue }
}

enum ActivityV43Group: String, CaseIterable, Identifiable {
    case reactedToSessions = "people reacted to your sessions"
    case askedAboutRoutines = "friends asked about your routines"
    case squadNoticed = "your squad noticed you"
    case newFollowers = "new followers"
    case tagsMentions = "tags + mentions"
    case storyViews = "story views"
    case crewActivity = "crew activity"
    var id: String { rawValue }
}

struct ActivityFilterChipsBar: View {
    @Binding var selected: ActivityV43Filter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityV43Filter.allCases) { f in
                    Button {
                        selected = f
                    } label: {
                        Text(f.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selected == f
                                    ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(Color.white.opacity(0.10)))
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct ActivityV43GroupHeader: View {
    let title: String
    let count: Int
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .textCase(.lowercase)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

struct TodayOnLiftEmptyState: View {
    /// Ambient, NOT personal. Per design — keeps the page warm without faking activity.
    let reactionsToday: Int
    let prsToday: Int
    let snippets: [String]

    var body: some View {
        VStack(spacing: 12) {
            Text("your circle is quiet right now")
                .font(.system(size: 15, weight: .semibold))
            Text("today on lift")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 16) {
                metricColumn(value: reactionsToday, label: "reactions sent")
                metricColumn(value: prsToday, label: "PRs hit")
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(snippets, id: \.self) { s in
                    Text("• \(s)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }

    private func metricColumn(value: Int, label: String) -> some View {
        VStack {
            Text(value > 999 ? "\(value/1000).\((value%1000)/100)k" : "\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
