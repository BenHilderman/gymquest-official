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

    var body: some View {
        NavigationStack {
            ClubFeedView(profile: profile)
                .navigationTitle("Clubs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavAvatarButton(profile: profile)
                    }
                }
        }
    }
}
