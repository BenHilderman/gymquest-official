// Privacy & Trust panel — design v4.3 §8A.
// Reachable from Profile pill / Active Workout Ghost toggle / Settings.

import SwiftUI

struct PrivacyTrustPanelView: View {
    @State var settings: PrivacyTrustSettings = .init()
    var onSave: (PrivacyTrustSettings) -> Void = { _ in }

    var body: some View {
        Form {
            Section {
                Picker("ghost mode", selection: $settings.ghostModeLevel) {
                    ForEach(GhostModeLevel.allCases) { level in
                        VStack(alignment: .leading) {
                            Text(level.label)
                            Text(level.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }.tag(level)
                    }
                }
            } header: {
                Text("ghost mode")
            } footer: {
                Text(settings.ghostModeLevel.subtitle)
            }

            Section("default post audience") {
                Picker("default audience", selection: $settings.defaultPostAudience) {
                    ForEach(PostAudience.allCases) { aud in
                        Label(aud.label, systemImage: aud.systemIcon).tag(aud)
                    }
                }
            }

            Section("who can react") {
                permissionPicker("emoji reactions", selection: $settings.canReactEmoji)
                permissionPicker("voice reactions", selection: $settings.canReactVoice)
                permissionPicker("photo reactions", selection: $settings.canReactPhoto)
            }

            Section("messages + invites") {
                permissionPicker("who can DM", selection: $settings.canDM)
                permissionPicker("who can invite to partner mode", selection: $settings.canInviteToPartner)
            }

            Section("comparison") {
                Toggle("let others compare stats with you", isOn: $settings.enableComparisonStats)
                Toggle("auto-react to friends i react to often", isOn: $settings.allowAutoReact)
            }

            Section("notifications") {
                ForEach(NotificationCategory.allCases) { cat in
                    Toggle(cat.label, isOn: Binding(
                        get: { settings.notifications[cat] ?? true },
                        set: { settings.notifications[cat] = $0 }
                    ))
                }
            }

            Section("blocked + muted") {
                NavigationLink("block list") { Text("blocked users").padding() }
                NavigationLink("mute list") { Text("muted users").padding() }
            }

            Section {
                Button("save") { onSave(settings) }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle("privacy & trust")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func permissionPicker(_ title: String, selection: Binding<SocialPermissionScope>) -> some View {
        Picker(title, selection: selection) {
            ForEach(SocialPermissionScope.allCases) { scope in
                Text(scope.label).tag(scope)
            }
        }
    }
}

/// Privacy pill that lives below Profile header per design §5A.
struct PrivacyTrustShortcutPill: View {
    var ghostLevel: GhostModeLevel = .friends
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: ghostLevel == .ghost ? "eye.slash.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 12, weight: .semibold))
                Text("privacy & trust · \(ghostLevel.label)")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.5))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
