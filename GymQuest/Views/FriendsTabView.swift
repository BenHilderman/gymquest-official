import SwiftUI
import SwiftData

/// Tab-level host for the Friends view. Wraps FriendsFeedView in a
/// NavigationStack so toolbar/title behavior works the same as when it was
/// presented from the old Feed sub-nav.
struct FriendsTabView: View {
    let profile: UserProfile

    var body: some View {
        NavigationStack {
            FriendsFeedView(profile: profile)
        }
    }
}

/// Tab-level host for the Clubs view. Same pattern — wraps ClubFeedView
/// so the clubs page renders as a standalone destination.
struct ClubsTabView: View {
    let profile: UserProfile
    @Query private var dmMessages: [DMMessage]

    /// v4.3 §6A — total unread DMs sent to this user. Powers the badge
    /// on the paper-airplane icon.
    private var unreadDMCount: Int {
        dmMessages.filter { $0.senderId != profile.id && $0.readAt == nil }.count
    }

    var body: some View {
        NavigationStack {
            ClubFeedView(profile: profile)
                .navigationTitle("Crews")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavAvatarButton(profile: profile)
                    }
                    // v4.3 §6A — paper-airplane access to Messages.
                    // Lives on Crews header here (Friends header is owned
                    // by the `home-feed-mix` worktree until merge).
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            MessagesListView(unreadCount: unreadDMCount,
                                             reactStreakConvoCount: 0,
                                             threads: [],
                                             suggestions: [])
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "paperplane")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.primary)
                                if unreadDMCount > 0 {
                                    Text(unreadDMCount > 9 ? "9+" : "\(unreadDMCount)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 14, minHeight: 14)
                                        .background(Circle().fill(GQGradients.primary))
                                        .offset(x: 8, y: -6)
                                }
                            }
                        }
                    }
                }
        }
    }
}
