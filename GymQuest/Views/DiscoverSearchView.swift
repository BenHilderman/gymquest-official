import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen search across the four things people actually want to find:
/// workouts, exercises (with form cues), people, and clubs. Presented as a
/// sheet from Discover. Typing debounces 250ms, results group into tight
/// sections — Instagram/X pattern.
struct DiscoverSearchView: View {
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState

    @Query(sort: \Post.timestamp, order: .reverse) private var allPosts: [Post]
    @Query private var allUserProfiles: [UserProfile]
    @Query private var clubs: [Club]

    @State private var rawQuery: String = ""
    /// Debounced value — updates 250ms after typing stops so every
    /// keystroke doesn't re-scan the entire corpus.
    @State private var query: String = ""
    @FocusState private var focused: Bool

    @State private var tappedPost: Post?
    @State private var tappedProfileId: UUID?
    @State private var tappedExercise: ExerciseMetadata?

    private let sectionCap = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptyState
                } else if noResults {
                    noResultsState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if !matchedWorkouts.isEmpty { workoutsSection }
                            if !matchedExercises.isEmpty { exercisesSection }
                            if !matchedPeople.isEmpty { peopleSection }
                            if !matchedClubs.isEmpty { clubsSection }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .gqPageBackground()
            .navigationBarHidden(true)
            .onAppear { focused = true }
            .task(id: rawQuery) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                query = rawQuery
            }
            .fullScreenCover(item: $tappedPost) { post in
                PostDetailView(post: post, profile: profile)
            }
            .sheet(item: Binding(
                get: { tappedProfileId.map { IdentifiableUUID(id: $0) } },
                set: { tappedProfileId = $0?.id }
            )) { wrapped in
                UserProfileSheet(userId: wrapped.id, currentProfile: profile)
            }
            .sheet(item: $tappedExercise) { meta in
                NavigationStack { ExerciseDetailSheet(metadata: meta) }
            }
        }
        .tint(GQColors.textPrimary)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(GQColors.textTertiary)
                TextField("Workouts, exercises, people, clubs", text: $rawQuery)
                    .font(.system(size: 15))
                    .foregroundColor(GQColors.textPrimary)
                    .submitLabel(.search)
                    .focused($focused)
                    .autocorrectionDisabled()
                if !rawQuery.isEmpty {
                    Button {
                        rawQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(GQColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(GQColors.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GQColors.borderDefault, lineWidth: 1))

            Button("Cancel") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
                .buttonStyle(.plain)
        }
    }

    // MARK: - Matching

    private var q: String { query.lowercased().trimmingCharacters(in: .whitespaces) }

    private var noResults: Bool {
        matchedWorkouts.isEmpty && matchedExercises.isEmpty && matchedPeople.isEmpty && matchedClubs.isEmpty
    }

    /// Posts whose title, exercise highlight, workout type, author name/
    /// username match the query. Prefers posts with shared workout data
    /// (runnable) so searches bias toward actionable results.
    private var matchedWorkouts: [Post] {
        guard !q.isEmpty else { return [] }
        let scored = allPosts.compactMap { post -> (Post, Int)? in
            var score = 0
            if postTitle(post).lowercased().contains(q) { score += 4 }
            if (post.exerciseHighlight ?? "").lowercased().contains(q) { score += 3 }
            if (post.workoutType ?? "").lowercased().contains(q) { score += 2 }
            if post.authorName.lowercased().contains(q) { score += 2 }
            if post.authorUsername.lowercased().contains(q) { score += 2 }
            if post.sharedWorkoutData != nil { score += 1 }  // runnable tiebreak
            return score > 0 ? (post, score) : nil
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(sectionCap)
            .map { $0.0 }
    }

    private var matchedExercises: [ExerciseMetadata] {
        guard !q.isEmpty else { return [] }
        return ExtendedExerciseDatabase.exercises
            .filter { meta in
                meta.name.lowercased().contains(q) ||
                meta.aliases.contains(where: { $0.lowercased().contains(q) }) ||
                meta.primaryMuscles.contains(where: { $0.lowercased().contains(q) })
            }
            .prefix(sectionCap)
            .map { $0 }
    }

    private var matchedPeople: [UserProfile] {
        guard !q.isEmpty else { return [] }
        return allUserProfiles
            .filter { $0.id != profile.id }
            .filter { $0.name.lowercased().contains(q) || $0.username.lowercased().contains(q) }
            .prefix(sectionCap)
            .map { $0 }
    }

    private var matchedClubs: [Club] {
        guard !q.isEmpty else { return [] }
        return clubs
            .filter { club in
                club.name.lowercased().contains(q) ||
                (club.location?.lowercased().contains(q) ?? false) ||
                club.resolvedCategory.rawValue.lowercased().contains(q)
            }
            .prefix(sectionCap)
            .map { $0 }
    }

    // MARK: - Sections

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("WORKOUTS")
            VStack(spacing: 6) {
                ForEach(matchedWorkouts) { post in
                    Button { tappedPost = post } label: {
                        workoutRow(post)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func workoutRow(_ post: Post) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(GQGradients.primary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: post.sharedWorkoutData != nil ? "figure.strengthtraining.traditional" : "photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(postTitle(post))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Text(workoutSubtitle(post))
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if post.sharedWorkoutData != nil {
                Text("Try →")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GQGradients.primary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .homeSocialCard(cornerRadius: 12)
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("EXERCISES & FORM")
            VStack(spacing: 6) {
                ForEach(matchedExercises) { meta in
                    Button { tappedExercise = meta } label: {
                        exerciseRow(meta)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func exerciseRow(_ meta: ExerciseMetadata) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(GQColors.surfaceBase)
                    .frame(width: 44, height: 44)
                Image(systemName: "figure.core.training")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GQColors.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Text("\(meta.muscleGroup.rawValue.capitalized) · \(meta.equipment.rawValue.capitalized)")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .homeSocialCard(cornerRadius: 12)
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PEOPLE")
            VStack(spacing: 6) {
                ForEach(matchedPeople) { person in
                    Button { tappedProfileId = person.id } label: {
                        personRow(person)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func personRow(_ person: UserProfile) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(GQGradients.primary).frame(width: 40, height: 40)
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                if !person.username.isEmpty {
                    Text("@\(person.username)")
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .homeSocialCard(cornerRadius: 12)
    }

    private var clubsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("CLUBS")
            VStack(spacing: 6) {
                ForEach(matchedClubs) { club in
                    Button { openClub(club) } label: {
                        clubRow(club)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func clubRow(_ club: Club) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(GQGradients.primary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(club.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Text(clubSubtitle(club))
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .homeSocialCard(cornerRadius: 12)
    }

    private func openClub(_ club: Club) {
        dismiss()
        // Give the sheet dismiss a beat, then switch to Clubs tab. The
        // club itself is reachable from the Clubs landing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            appState.selectedTab = .clubs
        }
    }

    // MARK: - Empty / no-results states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(GQColors.textTertiary)
            Text("Find workouts, exercises, people, and clubs")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(GQColors.textTertiary)
            Text("No results for “\(query)”")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(GQColors.textTertiary)
    }

    private func postTitle(_ post: Post) -> String {
        if let data = post.sharedWorkoutData,
           let shared = try? JSONDecoder().decode(SharedWorkoutData.self, from: data),
           !shared.title.isEmpty { return shared.title }
        return post.exerciseHighlight ?? post.workoutType?.capitalized ?? "Workout"
    }

    private func workoutSubtitle(_ post: Post) -> String {
        var parts: [String] = []
        if let dur = post.duration, dur > 0 { parts.append("\(dur) min") }
        if let type = post.workoutType { parts.append(type.capitalized) }
        parts.append("@\(post.authorUsername)")
        return parts.joined(separator: " · ")
    }

    private func clubSubtitle(_ club: Club) -> String {
        var parts: [String] = [club.resolvedCategory.rawValue.capitalized]
        if let loc = club.location, !loc.isEmpty { parts.append(loc) }
        parts.append("\(club.memberIds.count) members")
        return parts.joined(separator: " · ")
    }
}

/// Minimal sheet for exercise details — reuses metadata cues/mistakes/
/// variations already in ExtendedExerciseDatabase. Kept local so search
/// ships without a new top-level view.
private struct ExerciseDetailSheet: View {
    let metadata: ExerciseMetadata
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(metadata.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(GQColors.textPrimary)
                    Text("\(metadata.muscleGroup.rawValue.capitalized) · \(metadata.equipment.rawValue.capitalized) · \(metadata.difficulty.rawValue.capitalized)")
                        .font(.system(size: 13))
                        .foregroundColor(GQColors.textTertiary)
                }

                if !metadata.cues.isEmpty {
                    infoBlock(title: "FORM CUES", items: metadata.cues, icon: "checkmark.circle.fill", tint: GQColors.success)
                }
                if !metadata.commonMistakes.isEmpty {
                    infoBlock(title: "COMMON MISTAKES", items: metadata.commonMistakes, icon: "exclamationmark.triangle.fill", tint: .orange)
                }
                if !metadata.variations.isEmpty {
                    infoBlock(title: "VARIATIONS", items: metadata.variations, icon: "arrow.triangle.branch", tint: GQColors.deepBlue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .gqPageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(GQColors.textPrimary)
            }
        }
    }

    private func infoBlock(title: String, items: [String], icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(GQColors.textTertiary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tint)
                            .padding(.top, 2)
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundColor(GQColors.textPrimary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .homeSocialCard(cornerRadius: 12)
        }
    }
}
