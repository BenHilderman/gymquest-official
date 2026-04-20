import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Global top-right nav avatar. Tap opens ProfileView as a sheet.
/// Replaces the old "You" bottom tab — since Profile is a low-touch
/// destination, a persistent avatar button is the iOS-native pattern
/// (IG, Threads, X all do this).
///
/// Apply via `.toolbar { ToolbarItem(placement: .topBarTrailing) { NavAvatarButton(profile: profile) } }`
/// on every top-level tab view.
struct NavAvatarButton: View {
    let profile: UserProfile

    @State private var presenting: Bool = false

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            presenting = true
        } label: {
            avatarImage
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .overlay(Circle().stroke(GQColors.borderDefault, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presenting) {
            NavigationStack {
                ProfileView(profile: profile)
            }
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        #if canImport(UIKit)
        if let data = profile.profilePhotoData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle().fill(GQGradients.primary)
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        #else
        Circle().fill(GQColors.surfaceSecondary)
        #endif
    }
}
