//
//  AliveSavedGyms.swift
//  GymQuest
//
//  Saved Gyms management UI for Alive Phase 3. Lightweight: list existing
//  gyms (max 3 per spec), add a new one from current device location, or
//  remove. No drop-pin map yet — the user-flow is "I'm at this gym now,
//  save it" rather than "browse a map and pick a spot."
//

import SwiftUI
import SwiftData
import CoreLocation

struct SavedGymsManagementSheet: View {
    let userId: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var savedGyms: [SavedGym]
    @Query private var allUserProfiles: [UserProfile]
    @StateObject private var locationService = AliveLocationService.shared
    @State private var newName: String = ""
    @State private var savingError: String? = nil
    @State private var trustTick: Int = 0

    private var myGyms: [SavedGym] {
        savedGyms.filter { $0.userId == userId }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Lightweight projection so we don't need to materialize a full
    /// UserProfile @Model (the seeded fake users don't have one on
    /// device — only their info in SocialSeeder.fakeUsers).
    private struct TrustedFriend: Identifiable {
        let id: UUID
        let name: String
    }

    private var trustedFriends: [TrustedFriend] {
        _ = trustTick
        let trustedIds = LocationTrustedFriendsStore.load()
        var result: [TrustedFriend] = []
        var seen: Set<UUID> = []
        for p in allUserProfiles where trustedIds.contains(p.id) {
            result.append(TrustedFriend(id: p.id, name: p.name))
            seen.insert(p.id)
        }
        for fake in SocialSeeder.fakeUsers where trustedIds.contains(fake.id) && !seen.contains(fake.id) {
            result.append(TrustedFriend(id: fake.id, name: fake.name))
            seen.insert(fake.id)
        }
        return result.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Up to 3 saved gyms. Friends only see the name when you opt in per session.")
                        .font(.system(size: 13))
                        .foregroundColor(GQColors.textSecondary)
                        .padding(.horizontal, 16)

                    ForEach(myGyms) { gym in
                        gymRow(gym)
                    }

                    if myGyms.count < 3 {
                        addGymCard
                    } else {
                        Text("Limit reached. Remove a gym to add another.")
                            .font(.system(size: 12))
                            .foregroundColor(GQColors.textTertiary)
                            .padding(.horizontal, 16)
                    }

                    trustedFriendsSection

                    if let savingError {
                        Text(savingError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AlivePresence.red)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .gqPageBackground()
            .navigationTitle("Saved Gyms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gymRow(_ gym: SavedGym) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(GQColors.deepBlue.opacity(0.10)).frame(width: 40, height: 40)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(gym.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Text(String(format: "%.4f, %.4f · %.0fm", gym.latitude, gym.longitude, gym.radiusMeters))
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }
            Spacer()
            Button {
                modelContext.delete(gym)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AlivePresence.red)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var addGymCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADD GYM")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(GQGradients.primary)
            HStack(spacing: 10) {
                TextField("Gym name (e.g. The ARC)", text: $newName)
                    .textFieldStyle(LiftAITextFieldStyle())
                Button {
                    addFromCurrentLocation()
                } label: {
                    Text("Save here")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(GQGradients.primary))
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
            Text("Uses your current location. Permissioned each session — friends only see the name when you opt in.")
                .font(.system(size: 11))
                .foregroundColor(GQColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
        .padding(.horizontal, 16)
        .onAppear {
            LocationOptInStore.enabled = true
            locationService.requestPermission()
            locationService.startMonitoring()
        }
    }

    @ViewBuilder
    private var trustedFriendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRUSTED WITH MY GYM")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(GQGradients.primary)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            if trustedFriends.isEmpty {
                Text("No friends are trusted yet. Toggle this on a friend's profile to share your gym with them. Strangers and untrusted friends never see it.")
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            } else {
                ForEach(trustedFriends) { friend in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(GQGradients.primary)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(String(friend.name.prefix(1)).uppercased())
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .presenceRing(friend.id, size: 32)
                        Text(friend.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                        Spacer()
                        Button {
                            LocationTrustedFriendsStore.remove(friend.id)
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            trustTick &+= 1
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(GQColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .homeSocialCard(cornerRadius: 14)
                    .padding(.horizontal, 16)
                }
            }
        }
        .id(trustTick)
    }

    private func addFromCurrentLocation() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let loc = locationService.lastLocation else {
            savingError = "Need a location fix — wait a moment then try again."
            return
        }
        savingError = nil
        let gym = SavedGym(
            userId: userId,
            name: trimmed,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            radiusMeters: 80
        )
        modelContext.insert(gym)
        try? modelContext.save()
        newName = ""
    }
}
