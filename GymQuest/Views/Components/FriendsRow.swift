import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Single merged crew member for the unified row.
struct FriendsMember: Identifiable {
    let id: UUID
    let name: String
    let username: String
    let avatarData: Data?
    let status: Status
    let statusText: String       // "Push · 6 min" or "yesterday" or "2d ago"

    enum Status {
        case live(workoutType: String?)  // green ring, currently training
        case recent                       // purple ring, posted recently
        case inactive                     // gray, >3 days no activity
    }
}

/// One horizontal row replacing both LiveNowStrip and FriendFeedSection.
/// Green ring = training now, purple = posted recently, gray = inactive.
/// ~70pt tall. Tap avatar → callback. [+] at the end starts a workout.
struct FriendsRow: View {
    let members: [FriendsMember]
    let onTapMember: (FriendsMember) -> Void
    let onStartWorkout: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        if members.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("FRIENDS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(1.2)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(members) { member in
                            memberCell(member)
                        }
                        startCell
                    }
                    .padding(.horizontal, 16)
                }
            }
            .onAppear { pulse = true }
        }
    }

    private func memberCell(_ member: FriendsMember) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onTapMember(member)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Thin green ring only on live members. Recent/inactive get
                    // no ring — just the avatar. Keeps the row clean and
                    // reserves accent color for the single "training now"
                    // signal, Apple-style.
                    if isLive(member) {
                        Circle()
                            .stroke(GQColors.success, lineWidth: 2)
                            .frame(width: 48, height: 48)
                            .scaleEffect(pulse ? 1.04 : 1.0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                    }

                    avatarImage(member)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .opacity(isInactive(member) ? 0.55 : 1.0)

                    if isLive(member) {
                        Circle()
                            .fill(GQColors.success)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(GQColors.background, lineWidth: 2))
                            .frame(width: 48, height: 48, alignment: .bottomTrailing)
                    }
                }

                Text(firstName(member))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 56)

                Text(member.statusText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 56)
            }
        }
        .buttonStyle(.plain)
    }

    private var startCell: some View {
        Button(action: onStartWorkout) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(GQColors.borderDefault, lineWidth: 1.5)
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                }
                Text("Start")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textSecondary)
                Text("workout")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func avatarImage(_ member: FriendsMember) -> some View {
        #if canImport(UIKit)
        if let data = member.avatarData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle().fill(isInactive(member) ? AnyShapeStyle(GQColors.surfaceSecondary) : AnyShapeStyle(GQGradients.primary))
                Text(String(member.name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        #else
        Circle().fill(GQColors.surfaceSecondary)
        #endif
    }

    private func isLive(_ member: FriendsMember) -> Bool {
        if case .live = member.status { return true }
        return false
    }

    private func isInactive(_ member: FriendsMember) -> Bool {
        if case .inactive = member.status { return true }
        return false
    }

    private func firstName(_ member: FriendsMember) -> String {
        member.name.split(separator: " ").first.map(String.init) ?? member.name
    }
}
