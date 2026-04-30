// Settings v4.3 — design §8B.
// Sections + granular notification toggles + "what's new" line.

import SwiftUI

struct SettingsV43WhatsNewLine: View {
    let copy: String
    var onTap: () -> Void = {}
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text(copy)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.10)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsV43Sections: View {
    @State private var notifications: [NotificationCategory: Bool] = Dictionary(
        uniqueKeysWithValues: NotificationCategory.allCases.map { ($0, true) }
    )
    @State private var ghostLevel: GhostModeLevel = .friends
    @State private var defaultAudience: PostAudience = .friends

    var body: some View {
        Form {
            Section { SettingsV43WhatsNewLine(copy: "voice reactions are new — try one") }

            Section("account") {
                NavigationLink("profile") { Text("profile settings") }
                NavigationLink("subscription") { Text("subscription") }
                NavigationLink("login & security") { Text("login & security") }
            }

            Section("preferences") {
                NavigationLink("appearance") { Text("appearance") }
                NavigationLink("language") { Text("language") }
            }

            Section("privacy & trust") {
                NavigationLink("ghost mode (\(ghostLevel.label))") {
                    PrivacyTrustPanelView()
                }
                Picker("default post audience", selection: $defaultAudience) {
                    ForEach(PostAudience.allCases) { a in
                        Label(a.label, systemImage: a.systemIcon).tag(a)
                    }
                }
                NavigationLink("saved gyms") { Text("saved gyms") }
                NavigationLink("trusted friends per gym") { Text("trusted friends per gym") }
                NavigationLink("close friends") { Text("close friends") }
                NavigationLink("blocked + muted") { Text("blocked + muted") }
            }

            Section("notifications") {
                ForEach(NotificationCategory.allCases) { cat in
                    Toggle(cat.label, isOn: Binding(
                        get: { notifications[cat] ?? true },
                        set: { notifications[cat] = $0 }
                    ))
                }
            }

            Section("integrations") {
                NavigationLink("strava") { Text("strava") }
                NavigationLink("whoop") { Text("whoop") }
                NavigationLink("apple health") { Text("apple health") }
                NavigationLink("google") { Text("google") }
                NavigationLink("spotify") { Text("spotify") }
            }

            Section("health") {
                NavigationLink("body metrics") { Text("body metrics") }
                NavigationLink("sleep") { Text("sleep") }
                NavigationLink("heart rate") { Text("heart rate") }
            }

            Section("training") {
                NavigationLink("split & goal") { Text("split & goal") }
                NavigationLink("rpe + units") { Text("rpe + units") }
                NavigationLink("rest timer defaults") { Text("rest timer defaults") }
            }

            Section("social") {
                NavigationLink("comparison stats") { Text("comparison stats") }
                NavigationLink("auto-react preferences") { Text("auto-react preferences") }
                NavigationLink("partner mode") { Text("partner mode") }
            }

            Section("coach mode") {
                NavigationLink("AI coach prompts") { Text("AI coach prompts") }
                NavigationLink("training load") { Text("training load") }
            }

            Section("founder") {
                NavigationLink("founder updates") { Text("founder updates") }
                NavigationLink("feedback") { Text("feedback") }
                NavigationLink("about lift") { Text("about lift") }
            }
        }
        .navigationTitle("settings")
    }
}
