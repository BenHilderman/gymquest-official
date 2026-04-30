//
//  WorkoutStartOptionsView.swift
//  GymQuest
//
//  Workout start hub — tap "+" → hub sheet → pick a route → navigates to dedicated page.
//

import SwiftUI
import SwiftData

// MARK: - Workout Start Options View

struct WorkoutStartOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Workout.date, order: .reverse) private var recentWorkouts: [Workout]
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var savedTemplates: [WorkoutTemplate]
    @Query private var v43Presence: [UserPresenceState]
    @Query private var v43Follows: [Friend]
    @Query private var v43UserProfiles: [UserProfile]
    @State private var v43PendingPartner: (name: String, id: UUID)?
    /// Session-stable seed so the default-pool subtitle doesn't re-roll on
    /// every render. Locked spec Item C: "rotation per open".
    @State private var v43HeroRotationSeed = RotationSeed()

    let profile: UserProfile

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    heroBand
                        .padding(.top, 4)

                    // v4.3 §4B — Workout-of-the-Day card.
                    v43WorkoutOfTheDay

                    // v4.3 §4B — Music row + Friends training row + social proof.
                    v43MusicRow
                    v43FriendsTrainingRow
                    v43SocialProofLine

                    sectionLabel("PICK HOW YOU WANT TO TRAIN")
                    pathSection

                    // v4.3 §4B — "lift with [friend]" pill below quick-start
                    // row when a followed friend is at the same saved gym.
                    if let pill = v43LiftWithFriendPillName {
                        LiftWithFriendPill(friendDisplayName: pill.name) {
                            v43PendingPartner = (pill.name, pill.id)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    sectionLabel("THIS MONTH")
                    momentumSection

                    Spacer(minLength: 34)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
            .background(GQColors.background)
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(GQColors.background, for: .navigationBar)
            .instagramBack()
        }
        .tint(GQColors.textPrimary)
    }

    // MARK: - v4.3 Plus polish (design §4B)

    @ViewBuilder
    private var v43WorkoutOfTheDay: some View {
        WorkoutOfTheDayCard(
            title: nextWODTitle,
            detail: nextWODDetail,
            source: nextWODSource,
            onStart: {}
        )
        .onAppear {
            // v4.3 §11 — Plus tab WOD card is one of the 5 allowed
            // Discover Engine surfaces. Audit on render.
            try? DiscoverEngineSurfaceAudit.allow(surface: .plusWOD)
        }
    }

    private var nextWODTitle: String {
        if let last = recentWorkouts.first { return "repeat \(last.type.rawValue.lowercased())" }
        return "trending push day"
    }

    private var nextWODDetail: String {
        if recentWorkouts.first != nil { return "your most recent workout — one tap to start" }
        return "47 ppl tried it today"
    }

    private var nextWODSource: WorkoutOfTheDayCard.Source {
        recentWorkouts.first != nil ? .saved : .trending
    }

    @ViewBuilder
    private var v43MusicRow: some View {
        GymPlaylistRow(
            resumeTitle: "resume your gym playlist",
            friendListeningSong: nil,
            friendListeningName: nil
        )
    }

    @ViewBuilder
    private var v43FriendsTrainingRow: some View {
        FriendsTrainingRow(items: v43FriendsTrainingItems,
                            onTap: { _ in
                                // Surface the Friends tab where live sessions
                                // render — keeps the Plus tab as a router
                                // (design §4B says Plus is fast, not destination).
                                appState.selectedTab = .friends
                            },
                            onLongPressLiftWith: { item in
            v43PendingPartner = (item.displayName, item.id)
        })
        .sheet(isPresented: Binding(
            get: { v43PendingPartner != nil },
            set: { if !$0 { v43PendingPartner = nil } }
        )) {
            if let p = v43PendingPartner {
                PartnerInviteSheet(partnerDisplayName: p.name) { _ in }
            }
        }
    }

    private var v43FriendsTrainingItems: [FriendTrainingRowItem] {
        let now = Date()
        let followedIds = Set(v43Follows.filter { $0.userId == profile.id }.map(\.odId))
        let liveStates = v43Presence.filter { state in
            guard followedIds.contains(state.userId) else { return false }
            switch state.status {
            case .training, .arriving, .resting:
                if let started = state.startedAt, now.timeIntervalSince(started) > 3 * 3600 {
                    return false
                }
                return true
            default: return false
            }
        }
        return liveStates.compactMap { state -> FriendTrainingRowItem? in
            let resolved = v43UserProfiles.first(where: { $0.id == state.userId })
            let displayName = resolved?.name ?? "friend"
            let kind = state.workoutTypeRaw?.lowercased() ?? "training"
            let mins: Int? = state.startedAt.map { Int(now.timeIntervalSince($0) / 60) }
            return FriendTrainingRowItem(
                id: state.userId,
                displayName: displayName,
                kindLabel: kind,
                elapsedMinutes: mins,
                avatarURL: nil,
                isLive: state.status == .training
            )
        }
    }

    @ViewBuilder
    private var v43SocialProofLine: some View {
        PlusSocialProofLine(nearbyTrainingCount: nil, mutualsTrainedTodayPercent: nil)
    }

    /// First followed friend currently active. Surfaces the "lift with X"
    /// pill below the quick-start row per design §4B.
    private var v43LiftWithFriendPillName: (name: String, id: UUID)? {
        guard let item = v43FriendsTrainingItems.first(where: { $0.isLive }) else { return nil }
        return (item.displayName, item.id)
    }

    // MARK: - Hero band (profile-style)

    private var heroBand: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(GQColors.deepBlue.opacity(0.08))
                    .frame(width: 56, height: 56)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }

            // v4.3 Item C locked: humanlike check-in subtitle
            // Format: `day [N] · [check-in line]` with context overrides.
            Text(v43HeroSubtitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// v4.3 Plus hero subtitle — Item C locked spec.
    /// Context overrides win over default pool. Day prefix prepended unless
    /// the line is intentionally prefix-less (e.g. "let's start").
    private var v43HeroSubtitle: String {
        let streakDays = max(0, recentWorkouts.count) // proxy for streak
        let goal = profile.showUpFor.trimmingCharacters(in: .whitespaces)
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: now)  // 1=Sun, 7=Sat
        let hour = cal.component(.hour, from: now)
        let lastWorkoutDate = recentWorkouts.first?.date
        let daysSinceLast = lastWorkoutDate.map { Int(now.timeIntervalSince($0) / 86_400) } ?? Int.max
        let trainedToday = daysSinceLast == 0

        // ── Context overrides (priority order) ──
        // First open ever — no streak prefix
        if streakDays == 0 && lastWorkoutDate == nil {
            return "let's start"
        }
        // Returning after >7 days off
        if daysSinceLast > 7 && daysSinceLast != Int.max {
            return "day \(streakDays) · welcome back"
        }
        // Long streak milestones
        if streakDays >= 365 { return "day \(streakDays) · a year in" }
        if streakDays >= 100 { return "day \(streakDays) · respect" }
        if streakDays == 1 { return "day 1 · here we go" }

        // v4.3 Item C locked — at saved gym override.
        if AliveLocationService.shared.currentGym != nil {
            return "day \(streakDays) · you're here"
        }

        // v4.3 Item C locked — first open after a PR session.
        // PR detected when last workout has any PR events.
        if let last = recentWorkouts.first,
           !last.prEvents.isEmpty,
           daysSinceLast <= 1 {
            return "day \(streakDays) · ride that PR"
        }

        // Time-of-day overrides
        if !trainedToday && hour >= 19 {
            return "day \(streakDays) · still got time"
        }
        if hour < 9 {
            return "day \(streakDays) · starting strong"
        }

        // Weekend
        if weekday == 1 || weekday == 7 {
            return "day \(streakDays) · weekend lift"
        }

        // ── Default pool — random per open ──
        let pool: [String] = {
            var lines = [
                "let's get to it",
                "ready when you are",
                "another one",
                "back at it",
                "in for one",
                "what's the move today?",
                "you came back",
                "good to see you",
                "let's lift"
            ]
            if !goal.isEmpty {
                lines.append("showing up for \(goal)")
            }
            return lines
        }()
        let pick = pool.isEmpty ? "let's lift" : pool[v43HeroRotationSeed.index % pool.count]
        return "day \(streakDays) · \(pick)"
    }

    // MARK: - Path section (friends-style list)

    private var pathSection: some View {
        VStack(spacing: 12) {
            pathRow(icon: "figure.strengthtraining.traditional",
                    title: "Custom Workout",
                    subtitle: "Choose your split and go") {
                WorkoutTypeSelectionView(profile: profile)
            }
            pathRow(icon: "clock.arrow.circlepath",
                    title: "Follow Previous",
                    subtitle: previousWorkoutSubtitle) {
                PreviousWorkoutsListView(profile: profile, workouts: nonRestWorkouts)
            }
            pathRow(icon: "bookmark.fill",
                    title: "Saved Workouts",
                    subtitle: savedWorkoutsSubtitle) {
                SavedWorkoutsListView(profile: profile, templates: savedTemplates)
            }
            pathRow(icon: "brain.head.profile",
                    title: "AI Generated",
                    subtitle: "Smart recommendation") {
                AIGeneratedPlaceholderView(profile: profile)
            }
        }
    }

    @ViewBuilder
    private func pathRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Circle()
                    .fill(GQColors.deepBlue.opacity(0.08))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(GQGradients.primary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(14)
            .homeSocialCard(cornerRadius: 14)
        }
        .buttonStyle(GQInteractiveStyle())
    }

    // MARK: - Momentum section

    private var momentumSection: some View {
        HStack(spacing: 0) {
            momentumCol(value: "\(streakDays)", label: "Streak", valueColor: streakDays > 0 ? AnyShapeStyle(GQGradients.primary) : AnyShapeStyle(GQColors.textPrimary))
            momentumDivider
            momentumCol(value: "\(workoutsThisWeek)", label: "This Week")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .homeSocialCard(cornerRadius: 14)
    }

    private var momentumDivider: some View {
        Rectangle()
            .fill(GQColors.borderDefault.opacity(0.4))
            .frame(width: 0.5)
            .padding(.vertical, 4)
    }

    private func momentumCol(value: String, label: String, valueColor: AnyShapeStyle = AnyShapeStyle(GQColors.textPrimary)) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(GQColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: - Hero

    /// Big "Start Workout" title moved to the nav bar, so the body
    /// hero only needs the motivation subline.
    private var heroSubtitle: some View {
        Text(profile.showUpFor.trimmingCharacters(in: .whitespaces).isEmpty
             ? "Pick how you want to train today."
             : "Showing up for \(profile.showUpFor).")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(GQColors.textSecondary)
    }

    /// Legacy hero alias kept only in case any other caller referenced it.
    private var heroSection: some View { heroSubtitle }

    // MARK: - Section Label

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(GQTypography.sectionHeader)
            .foregroundColor(GQColors.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    // MARK: - Route Card

    private func routeCard<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color,
        badgeText: String? = nil,
        useGradient: Bool = false,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Circle()
                    .fill(useGradient ? GQColors.deepBlue.opacity(0.08) : accent.opacity(0.10))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(useGradient ? GQGradients.primary : LinearGradient(colors: [accent, accent], startPoint: .leading, endPoint: .trailing))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)

                        if let badgeText {
                            Text(badgeText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent.opacity(0.80))
                                .clipShape(Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(GQColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(14)
            .homeSocialCard(cornerRadius: 14)
        }
        .buttonStyle(GQInteractiveStyle())
    }

    // MARK: - Motivational Stats

    private var motivationalStats: some View {
        HStack(spacing: 10) {
            progressCard(icon: "flame.fill", value: "\(streakDays)", label: "Streak")
            progressCard(icon: "calendar", value: "\(workoutsThisWeek)", label: "This Week")
            progressCard(icon: "star.fill", value: "Lv \(profile.level)", label: UserProfile.levelTitle(for: profile.level))
        }
    }

    private func progressCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(GQGradients.primary)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(GQColors.textPrimary)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .homeSocialCard(cornerRadius: 12)
    }

    // MARK: - Computed Properties

    private var nonRestWorkouts: [Workout] {
        recentWorkouts.filter { $0.type != .rest }
    }

    private var previousWorkoutSubtitle: String {
        if let last = nonRestWorkouts.first {
            return "Last: \(last.type.rawValue) · \(last.date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return "Repeat a recent workout"
    }

    private var savedWorkoutsSubtitle: String {
        let count = savedTemplates.count
        if count > 0 {
            return "\(count) saved template\(count == 1 ? "" : "s")"
        }
        return "No saved templates yet"
    }

    private var workoutsThisWeek: Int {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return nonRestWorkouts.filter { $0.date >= weekStart }.count
    }

    private var streakDays: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        let todayWorkouts = nonRestWorkouts.filter { calendar.isDate($0.date, inSameDayAs: checkDate) }
        if todayWorkouts.isEmpty {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            checkDate = yesterday
        }

        while true {
            let dayWorkouts = nonRestWorkouts.filter { calendar.isDate($0.date, inSameDayAs: checkDate) }
            if dayWorkouts.isEmpty { break }
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }
}

// MARK: - Previous Workouts List View

struct PreviousWorkoutsListView: View {
    @EnvironmentObject var appState: AppState

    let profile: UserProfile
    let workouts: [Workout]

    var body: some View {
        Group {
            if workouts.isEmpty {
                emptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No previous workouts",
                    body: "Complete a workout first, then come back to repeat it."
                )
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(workouts.prefix(20)) { workout in
                            workoutCard(workout)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 34)
                }
            }
        }
        .gqPageBackground()
        .navigationTitle("Previous Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .instagramBack()
    }

    @ViewBuilder
    private func workoutCard(_ workout: Workout) -> some View {
        let sortedExercises = workout.exercises.sorted { $0.order < $1.order }

        Button {
            startFromPrevious(workout)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(GQColors.deepBlue.opacity(0.08))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: workout.type.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(GQGradients.primary)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(workout.title ?? workout.type.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(workout.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 12))
                            .foregroundColor(GQColors.textTertiary)
                    }

                    Text("\(workout.duration)m · \(workout.exercises.count) exercises · \(workout.totalSets) sets")
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textSecondary)

                    if !sortedExercises.isEmpty {
                        Text(sortedExercises.prefix(3).map(\.name).joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundColor(GQColors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .homeSocialCard(cornerRadius: 14)
        }
        .buttonStyle(GQInteractiveStyle())
    }

    private func startFromPrevious(_ workout: Workout) {
        let exercises = workout.exercises.sorted(by: { $0.order < $1.order }).map { exercise in
            ActiveExercise(
                name: exercise.name,
                muscleGroup: exercise.muscleGroup,
                sets: exercise.sets.sorted(by: { $0.order < $1.order }).map { set in
                    ActiveSet(reps: set.reps, weight: set.weight)
                }
            )
        }
        appState.startWorkout(type: workout.type, exercises: exercises)
    }
}

// MARK: - Saved Workouts List View

struct SavedWorkoutsListView: View {
    @EnvironmentObject var appState: AppState

    let profile: UserProfile
    let templates: [WorkoutTemplate]

    private var scheduledTemplates: [WorkoutTemplate] {
        let today = Calendar.current.startOfDay(for: Date())
        return templates
            .filter { ($0.scheduledFor ?? .distantPast) >= today }
            .sorted { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }
    }

    private var groupedTemplates: [(type: WorkoutType, items: [WorkoutTemplate])] {
        let scheduledIds = Set(scheduledTemplates.map(\.id))
        let unscheduled = templates.filter { !scheduledIds.contains($0.id) }
        let grouped = Dictionary(grouping: unscheduled, by: { $0.workoutType })
        return WorkoutType.allCases.compactMap { type in
            guard let items = grouped[type], !items.isEmpty else { return nil }
            return (type, items.sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        Group {
            if templates.isEmpty {
                emptyStateView(
                    icon: "bookmark",
                    title: "No saved workouts",
                    body: "Tap the bookmark on any workout post to save it here."
                )
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        if !scheduledTemplates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(GQGradients.primary)
                                    Text("UP NEXT")
                                        .font(GQTypography.sectionHeader)
                                        .foregroundColor(GQColors.textTertiary)
                                        .tracking(0.5)
                                    Text("\(scheduledTemplates.count)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(GQColors.textTertiary)
                                }
                                VStack(spacing: 10) {
                                    ForEach(scheduledTemplates) { template in
                                        templateCard(template)
                                    }
                                }
                            }
                        }

                        ForEach(groupedTemplates, id: \.type) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: group.type.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(GQGradients.primary)
                                    Text(group.type.rawValue.uppercased())
                                        .font(GQTypography.sectionHeader)
                                        .foregroundColor(GQColors.textTertiary)
                                        .tracking(0.5)
                                    Text("\(group.items.count)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(GQColors.textTertiary)
                                }
                                VStack(spacing: 10) {
                                    ForEach(group.items) { template in
                                        templateCard(template)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 34)
                }
            }
        }
        .gqPageBackground()
        .navigationTitle("Saved Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .instagramBack()
    }

    @ViewBuilder
    private func templateCard(_ template: WorkoutTemplate) -> some View {
        let templateExercises = template.exercises

        Button {
            startFromTemplate(template)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(GQColors.deepBlue.opacity(0.08))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: template.workoutType.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(GQGradients.primary)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(template.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if let scheduled = template.scheduledFor {
                            Text(formatScheduled(scheduled))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(GQGradients.primary))
                        } else if let author = template.savedFromUsername, !author.isEmpty {
                            Text("@\(author)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(GQGradients.primary)
                        }
                    }

                    Text("\(template.estimatedDuration)m · \(templateExercises.count) exercises")
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textSecondary)

                    if !templateExercises.isEmpty {
                        Text(templateExercises.prefix(3).map(\.name).joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundColor(GQColors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .homeSocialCard(cornerRadius: 14)
        }
        .buttonStyle(GQInteractiveStyle())
    }

    private func startFromTemplate(_ template: WorkoutTemplate) {
        let activeExercises = WorkoutTemplate.toActiveExercises(template.exercises)
        appState.startWorkout(type: template.workoutType, exercises: activeExercises)
        template.useCount += 1
        template.lastUsedAt = Date()
        template.scheduledFor = nil
    }

    private func formatScheduled(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInTomorrow(date) { return "TOMORROW" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - AI Generated Placeholder

struct AIGeneratedPlaceholderView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState

    @State private var experienceLevel: ExperienceLevel = .intermediate
    @State private var preferredDuration: Int = 60
    @State private var selectedEquipment: Set<EquipmentType> = []
    @State private var showSettings = false
    @State private var isGenerating = false

    private var settingsDivider: some View {
        Rectangle()
            .fill(GQColors.adaptiveOverlay(0.08))
            .frame(height: 0.33)
            .padding(.vertical, 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {

                // MARK: Summary
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        aiStat(experienceLevel.rawValue, "level")
                        aiStatDivider
                        aiStat("\(preferredDuration)m", "duration")
                        aiStatDivider
                        aiStat("\(selectedEquipment.count)", "equipment")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .homeSocialCard(cornerRadius: 16)

                settingsDivider

                // MARK: Generate Button
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    isGenerating = true
                    // TODO: Call AI service to generate workout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isGenerating = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text(isGenerating ? "Generating..." : "Generate Workout")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(GQGradients.primary)
                    )
                }
                .buttonStyle(GQInteractiveStyle())
                .disabled(isGenerating)

                settingsDivider

                // MARK: Settings Toggle
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSettings.toggle()
                    }
                } label: {
                    HStack {
                        Text("Workout Settings")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GQGradients.primary.opacity(0.6))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(GQColors.textTertiary)
                            .rotationEffect(.degrees(showSettings ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if showSettings {
                    VStack(alignment: .leading, spacing: 12) {
                        // Experience
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Experience")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(GQColors.textTertiary)
                            HStack(spacing: 6) {
                                ForEach(ExperienceLevel.allCases, id: \.self) { level in
                                    let isSelected = experienceLevel == level
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                            experienceLevel = level
                                        }
                                    } label: {
                                        Text(level.rawValue)
                                            .font(.system(size: 12, weight: .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 7)
                                            .foregroundColor(isSelected ? .white : GQColors.textSecondary)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(isSelected ? AnyShapeStyle(GQGradients.primary.opacity(0.7)) : AnyShapeStyle(GQColors.adaptiveOverlay(0.05)))
                                            )
                                    }
                                    .buttonStyle(GQInteractiveStyle())
                                }
                            }
                        }

                        // Duration
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Duration")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(GQColors.textTertiary)
                            HStack(spacing: 6) {
                                ForEach([30, 45, 60, 90], id: \.self) { mins in
                                    let isSelected = preferredDuration == mins
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                            preferredDuration = mins
                                        }
                                    } label: {
                                        Text("\(mins) min")
                                            .font(.system(size: 12, weight: .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 7)
                                            .foregroundColor(isSelected ? .white : GQColors.textSecondary)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(isSelected ? AnyShapeStyle(GQGradients.primary.opacity(0.7)) : AnyShapeStyle(GQColors.adaptiveOverlay(0.05)))
                                            )
                                    }
                                    .buttonStyle(GQInteractiveStyle())
                                }
                            }
                        }

                        // Equipment
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Equipment")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(GQColors.textTertiary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], spacing: 6) {
                                ForEach(EquipmentType.allCases, id: \.self) { equipment in
                                    let isSelected = selectedEquipment.contains(equipment)
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                            if isSelected { selectedEquipment.remove(equipment) }
                                            else { selectedEquipment.insert(equipment) }
                                        }
                                    } label: {
                                        Text(equipment.rawValue)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 7)
                                            .foregroundColor(isSelected ? .white : GQColors.textSecondary)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(isSelected ? AnyShapeStyle(GQGradients.primary.opacity(0.7)) : AnyShapeStyle(GQColors.adaptiveOverlay(0.05)))
                                            )
                                    }
                                    .buttonStyle(GQInteractiveStyle())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .homeSocialCard(cornerRadius: 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .scrollContentBackground(.hidden)
        .gqPageBackground()
        .navigationTitle("AI Generated")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .instagramBack()
        #endif
        .onAppear {
            experienceLevel = profile.experienceLevel ?? .intermediate
            preferredDuration = profile.preferredWorkoutDuration
            selectedEquipment = Set(profile.availableEquipment)
        }
    }

    @ViewBuilder
    private func aiStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(GQColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(GQColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var aiStatDivider: some View {
        Rectangle()
            .fill(GQColors.borderSubtle)
            .frame(width: 0.5, height: 28)
    }
}

// MARK: - Empty State Helper

private func emptyStateView(icon: String, title: String, body: String) -> some View {
    VStack(spacing: 0) {
        Spacer()

        VStack(spacing: 16) {
            Circle()
                .fill(GQColors.deepBlue.opacity(0.08))
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 40))
                        .foregroundColor(GQColors.textTertiary)
                )

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(GQColors.textSecondary)

            Text(body)
                .font(.system(size: 13))
                .foregroundColor(GQColors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }

        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

// MARK: - Workout Favorite Button

struct WorkoutFavoriteButton: View {
    @Bindable var workout: Workout
    @State private var heartScale: CGFloat = 1.0

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                workout.isFavorite.toggle()
                heartScale = 1.3
            }
            HapticManager.shared.impact(.light)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    heartScale = 1.0
                }
            }
        } label: {
            Image(systemName: workout.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 20))
                .foregroundColor(workout.isFavorite ? GQColors.textSecondary : GQColors.textTertiary)
                .scaleEffect(heartScale)
        }
        .buttonStyle(.plain)
    }
}
