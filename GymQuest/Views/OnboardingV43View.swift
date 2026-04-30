// 4-step onboarding — design v4.3 §7C, compressed for time-to-first-content.
//
// Locked goal: "first content moment + first social signal in <2 min from
// cold install." The original 11-step flow blew that budget; this version
// keeps the four user-input steps the rest of the app actually reads
// (goal, experience, split + vibe, gym) and pushes everything else
// post-onboarding:
//   - Privacy default lives in Settings; defaults to .friends.
//   - Apple Health connect is prompted by the system the first time the
//     user opens a surface that needs it.
//   - "Land on Discover Watch", "Add friends after 3 min", and
//     "After first workout" are post-onboarding app states, not onboarding
//     steps — they fire from the launch router and other flows.

import SwiftUI

enum OnboardingV43Step: Int, CaseIterable {
    case goal
    case experience
    case styleAndVibe
    case savedGym

    var isLast: Bool { self == OnboardingV43Step.allCases.last }
}

enum FitnessGoalChoice: String, CaseIterable, Identifiable {
    case buildMuscle = "build muscle"
    case loseFat = "lose fat"
    case getStronger = "get stronger"
    case generalFitness = "general fitness"
    case sportPrep = "sport prep"
    var id: String { rawValue }
}

enum ExperienceChoice: String, CaseIterable, Identifiable {
    case beginner = "0–6 months"
    case intermediate = "6 months – 2 years"
    case advanced = "2+ years"
    var id: String { rawValue }
}

enum SplitChoice: String, CaseIterable, Identifiable {
    case ppl = "push / pull / legs"
    case upperLower = "upper / lower"
    case fullBody = "full body"
    case bro = "bro split"
    case custom = "custom"
    var id: String { rawValue }
}

enum GymVibeChoice: String, CaseIterable, Identifiable {
    case chill, serious, aesthetic, functional, social, silent
    var id: String { rawValue }
    var label: String { rawValue }
}

/// Optional first-impression "known for" — kept in the model so existing
/// downstream code that reads this choice doesn't break, but no longer
/// surfaced as its own onboarding step. Defaults to nil; user can fill it
/// later from Profile settings.
enum KnownForChoice: String, CaseIterable, Identifiable {
    case biggestLifts = "biggest lifts"
    case mostConsistent = "most consistent"
    case bestAesthetic = "best aesthetic"
    case funCrew = "fun crew"
    case justStarting = "just starting"
    case comingBack = "coming back"
    var id: String { rawValue }
}

struct OnboardingV43Selections {
    var knownFor: KnownForChoice?
    var goal: FitnessGoalChoice?
    var experience: ExperienceChoice?
    var split: SplitChoice?
    var vibe: GymVibeChoice?
    var savedGymName: String = ""
    var privacyDefault: PostAudience = .friends
    var connectAppleHealth: Bool = false
}

struct OnboardingV43View: View {
    @State private var step: OnboardingV43Step = .goal
    @State private var selections = OnboardingV43Selections()
    var onComplete: (OnboardingV43Selections) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
            }
            navButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
        }
        .background(GQColors.background.ignoresSafeArea())
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressBar: some View {
        let count = OnboardingV43Step.allCases.count
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(GQColors.overlayLight)
                Rectangle()
                    .fill(GQGradients.primary)
                    .frame(width: geo.size.width * CGFloat(step.rawValue + 1) / CGFloat(count))
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .goal:
            stepHeader(title: "what's your goal?",
                       subtitle: "we use this to shape your plan.")
            chipGrid(FitnessGoalChoice.allCases.map(\.rawValue),
                     selected: selections.goal?.rawValue) { v in
                selections.goal = FitnessGoalChoice(rawValue: v)
            }
        case .experience:
            stepHeader(title: "how long have you been training?",
                       subtitle: nil)
            chipGrid(ExperienceChoice.allCases.map(\.rawValue),
                     selected: selections.experience?.rawValue) { v in
                selections.experience = ExperienceChoice(rawValue: v)
            }
        case .styleAndVibe:
            stepHeader(title: "training style?",
                       subtitle: "pick a split. add a vibe if you want.")
            VStack(alignment: .leading, spacing: 22) {
                chipGrid(SplitChoice.allCases.map(\.rawValue),
                         selected: selections.split?.rawValue) { v in
                    selections.split = SplitChoice(rawValue: v)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("vibe — optional")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                    chipGrid(GymVibeChoice.allCases.map(\.label),
                             selected: selections.vibe?.label) { v in
                        selections.vibe = GymVibeChoice(rawValue: v)
                    }
                }
            }
        case .savedGym:
            stepHeader(title: "where do you train?",
                       subtitle: "we surface friends training with you. you can skip and add later.")
            VStack(alignment: .leading, spacing: 12) {
                TextField("gym name", text: $selections.savedGymName)
                    .textFieldStyle(LiftAITextFieldStyle())
                    .autocorrectionDisabled(true)
                Text("you can save up to 3 gyms in profile settings.")
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
    }

    // MARK: - Header + chips

    @ViewBuilder
    private func stepHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(GQColors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(GQColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func chipGrid(
        _ items: [String],
        selected: String?,
        onTap: @escaping (String) -> Void
    ) -> some View {
        let cols = [GridItem(.adaptive(minimum: 140), spacing: 10)]
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(items, id: \.self) { s in
                let isSelected = (selected == s)
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onTap(s)
                } label: {
                    Text(s)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected
                                      ? AnyShapeStyle(GQGradients.primary)
                                      : AnyShapeStyle(GQColors.adaptiveOverlay(0.06)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Color.clear : GQColors.borderDefault, lineWidth: 1)
                        )
                        .foregroundColor(isSelected ? .white : GQColors.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Nav

    @ViewBuilder
    private var navButtons: some View {
        HStack(spacing: 12) {
            if step.rawValue > 0 {
                Button {
                    step = OnboardingV43Step(rawValue: step.rawValue - 1) ?? .goal
                } label: {
                    Text("back")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GQColors.textSecondary)
                        .frame(width: 80, height: 52)
                }
                .buttonStyle(.plain)
            }
            Button(step.isLast ? "let's go" : "next") {
                advance()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isStepSatisfied)
            .opacity(isStepSatisfied ? 1.0 : 0.55)
        }
    }

    /// Each step needs at least one selection before `next` enables — except
    /// `savedGym`, which is optional (user can skip with empty name).
    private var isStepSatisfied: Bool {
        switch step {
        case .goal: return selections.goal != nil
        case .experience: return selections.experience != nil
        case .styleAndVibe: return selections.split != nil
        case .savedGym: return true
        }
    }

    private func advance() {
        if step.isLast {
            onComplete(selections)
            return
        }
        if let next = OnboardingV43Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }
}
