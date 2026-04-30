# Lift AI (iOS) — Project Guide for Claude

App displays as **"Lift AI"** (renamed from GymQuest). The on-disk names, Xcode scheme, and `GQ`-prefixed design types were kept to avoid a mass rename.

- Entry struct: `LiftAIApp` in `GymQuest/GymQuestApp.swift`
- Xcode scheme: `GymQuest_iOS` (not `GymQuest`)
- Output binary: `Lift AI.app`
- Bundle IDs: `com.liftai.pro.*`, `com.liftai.strava`, `com.liftai.whoop`
- URL schemes: `liftai://` (strava-callback, whoop-callback, post links)

## Stack

- SwiftUI, iOS 17+ / macOS 14+, Swift 5.9
- SwiftData (`@Model`) for persistence
- `@Observable` macro (Observation framework) for ViewModels
- Dual-platform: guard UIKit-only APIs (haptics, etc.) with `#if canImport(UIKit)`

## Design System

Single source of truth: `GymQuest/Views/DesignSystem.swift`.

- Tokens: `GQColors`, `GQGradients`, `GQTypography`
- Card styles: `GlassCard`, `HeroCard`, `.homeSocialCard(cornerRadius:)`
- Buttons: `PrimaryButtonStyle`, `HomeSocialPrimaryButtonStyle` (solid `GQGradients.primary` fill, white text)
- Brand accent: blue→purple gradient (`GQGradients.primary`)
- TextField style: `LiftAITextFieldStyle`
- `breathingFloat()` is kept as a no-op extension for backward compatibility — do not revive animation.
- Removed dead decorations: `StarfieldOverlay`, `AuroraFlowBackground`, `ShimmerSweepOverlay`, `DriftingGlow`, `AmbientLightSweep`, `SilkNoiseTexture`, `GrainOverlay`. Do not reintroduce.

## Architecture

- **In-memory structs during workout** (`ActiveExercise`, `ActiveSet`) → convert to `@Model` objects on save.
- **Services are `@MainActor` singletons**: `PRService.shared`, `QuestService.shared`, `CrewRecapService.shared`, etc.
- **Feature flags**: `FeatureFlags.swift`, persisted via UserDefaults.
- **Exercise DB**: `ExtendedExerciseDatabase.exercises` / `.find(name)` in `Models.swift`.

## Build

```bash
xcodebuild -project GymQuest.xcodeproj \
  -scheme GymQuest_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath build_smoke build
```

Install + launch on booted sim:

```bash
xcrun simctl install booted "build_smoke/Build/Products/Debug-iphonesimulator/GymQuest.app"
xcrun simctl launch booted com.gymquest.app
```

## Gotchas

- **SourceKit false positives**: cross-file "cannot find type" errors often resolve at build time — trust the build.
- **`ExerciseSet` init accepts `rpe: Int? = nil`** — always pass RPE when available from `ActiveSet`.
- **Complex SwiftUI view bodies time out the type-checker** — extract into `@ViewBuilder` sub-properties.
- **`HapticManager.swift` exists on disk but NOT in the Xcode project** — use inline UIKit haptic calls instead.

---

# App Overview

Lift AI is a **gym / social fitness app**. Most tasks are *feature slices* that cut vertically through UI, state, services, API calls, types, and tests. Treat work this way unless told otherwise.

# Default Session Rule

**Every new Claude session must treat the task as a scoped gym feature slice unless the user explicitly says otherwise.** When in doubt, invoke the `gym-feature-slice` skill.

# Feature Slice Doctrine

A feature slice **may** include:

- UI components (a screen, a card, a sheet)
- styles / layout local to that screen
- local or feature-specific state (`@Observable` ViewModels, view-local `@State`)
- feature-specific services (a new `*Service.swift` only if no existing one fits)
- API calls (Supabase queries scoped to this feature)
- shared types **only when required**
- tests (unit + snapshot for the feature's surface)

A feature slice **must not** touch:

- unrelated screens or unrelated tabs
- auth / session / login plumbing
- routing or tab-bar structure
- global app state (`AppState` in `GymQuestApp.swift`)
- shared API clients beyond the scope of the feature
- DB schema or migrations
- shared components or design tokens beyond minor reuse

## Before editing, every session must identify

1. **Feature area** — one-line scope (e.g. "streak card on Home").
2. **Allowed files / folders** — explicit list.
3. **Forbidden files / folders** — what NOT to touch.
4. **Likely conflict areas** — anything in the high-conflict list below.
5. **Checks to run after changes** — typecheck-equivalent (build), lint if available, the smallest relevant test target.

Print this scope contract before the first edit.

## High-Conflict Areas (require explicit user approval to touch)

| Area | Files / folders |
|---|---|
| Auth / session | `GymQuest/Services/AuthService.swift`, `GymQuest/Views/Auth/` |
| Global state / routing | `GymQuest/GymQuestApp.swift` (`AppState`, `LiftAIApp`), `GymQuest/Views/ContentView.swift` |
| API clients | `GymQuest/Services/*Service.swift` (Supabase singletons) |
| DB schema / migrations | `supabase/migrations/`, `supabase/config.toml` |
| Shared types | `GymQuest/Models/Models.swift`, `ExerciseDatabase.swift` |
| Shared components | `GymQuest/Views/Components/`, `PostCardComponents.swift` |
| Design system | `GymQuest/Views/DesignSystem.swift` (`GQColors`, `GQGradients`, `GQTypography`) |

If a task plausibly requires touching any of these, **stop and confirm with the user before editing**. If a feature change "feels like" it needs a schema migration, route through the `schema-change` skill.

# Sensitive Files (never read, never paste, never log)

- `backend/.env`, anything matching `.env*` other than `.env.example`
- `GymQuest/GoogleService-Info.plist`
- `GymQuest/GymQuest.entitlements`
- private keys, tokens, credentials, OAuth secrets
- Supabase service-role keys

If a task needs a value from one of these, ask the user to provide just the variable you need.

# Task Examples (with default skill)

- **Workout logging feature** — `gym-feature-slice`. Touches `LogWorkoutView`, `ActiveWorkoutView`, `ActiveWorkoutViewModel`. Avoid global state.
- **Dashboard / streak UI** — `gym-feature-slice` or `ui-work` if visual-only. Touches `HomeView`, `HeroWidgetsView`. Don't change services.
- **Social feed / profile** — `gym-feature-slice`. Touches `FeedView`, `FriendsFeedView`, `ProfileView`. Don't touch shared `PostCardComponents` unless required.
- **Onboarding flow** — `gym-feature-slice`. Touches `OnboardingFlow.swift` and supporting auth-adjacent UI. Confirm before changing `AuthService`.
- **Auth / session fix** — High-conflict. Use `bugfix` only after explicit user approval; touches `AuthService.swift` and `Views/Auth/`.
- **Supabase / DB change** — Use `schema-change`. Touches `supabase/migrations/`, plus model + service updates downstream.

# Strict Coding Rules

- Reuse existing patterns before creating new ones (`GlassCard`, `HeroCard`, `.homeSocialCard`, existing services).
- Do not duplicate services or components — search first.
- Do not rewrite a whole file when a focused edit works.
- Do not edit unrelated screens.
- Do not change schema, auth, or global state unless the task requires it AND the user has approved it.
- Always run checks after edits (the post-edit hook handles fast checks; run the full xcodebuild manually for non-trivial Swift changes).
- No AI attribution in code, commits, comments, or pushes.

---

# Parallel Work Protocol

Multiple Claude sessions can run on this repo simultaneously using git worktrees. Keep them from colliding by updating the table below on session start and session end.

## How to start a parallel session

```bash
# From the repo root:
claude --worktree <short-kebab-name>
```

Claude creates `.claude/worktrees/<name>/` on branch `worktree-<name>` from `origin/HEAD`. `.worktreeinclude` copies gitignored secrets (e.g. `backend/.env`) into the new worktree automatically.

In the new worktree's session, **first action** is to add a row to the table below and commit to that worktree's branch.

## Active parallel sessions

| Worktree / branch | Owner focus | Primary files | Do NOT edit | Status | Updated |
|---|---|---|---|---|---|
| home-feed-mix / feat/home-feed-mix | Friends feed surface: notifications icon polish (bell→heart + dot indicator, simplified banner). Recommendation injection scoped out — already implemented in mixedFeed. | GymQuest/Views/FriendsFeedView.swift | GymQuest/Views/ClubsView.swift, GymQuest/Views/TodayView.swift (user actively editing on main) | in-progress | 2026-04-25 |
| feat/alive (main checkout) | **Colift v4.3 implementation pass.** New: 40 Swift files (services / models / components / views) + 6 supabase migrations + LaunchRouter tests. Modified: ContentView (LaunchRouter cold-launch + onboarding branch + Crews tab label), TodayView (Slot 5 day-of-week ritual + Slot 1 SmartTopCard), ProfileView (v4.3 identity row + Year So Far real data + Training Identity + Settings preview section + v4.3 toggle + other-profile primary actions), ActivityView (filter chips + chip-driven filtering), WorkoutStartOptionsView (WOD + music + friends row + social proof + audit), EnhancedPostEditorView (smart caption chips + anticipation banner), DiscoverFeedView (3 sub-tabs + sub-tab routing + 3 surface audits), FriendsTabView (Crews title + paper-airplane to Messages), ClubsView (Search/Create/Find Crews), FeedVariantsView, FeatureFlags (`coliftV43Enabled`). | 40 new files + 18 modified | (don't edit) FriendsFeedView.swift — owned by `home-feed-mix` | ready-for-review | 2026-04-27 |

**Status values**: `planning` · `in-progress` · `ready-for-review` · `merged`

## Handoff rules

1. **Before editing**, check the table. If someone else lists a file under "Primary files" or "Do NOT edit", coordinate or pick a different scope.
2. **On finishing**, set your row to `ready-for-review`, push your worktree branch, open a PR or notify the main session.
3. **After merge**, delete your row and run `git worktree remove <path>` from the main checkout.
4. **Orphaned subagent worktrees** with no uncommitted changes are auto-cleaned after `cleanupPeriodDays` (see `.claude/settings.json`). Manual `--worktree` sessions persist until you remove them.

## Role subagents (project-scoped)

Defined in `.claude/agents/`. Invoke via the Agent tool from any session:

- **`ios-architect`** (opus, read-only) — designs refactors, plans multi-file changes, writes specs. No worktree.
- **`ios-implementer`** (sonnet, full tools, **runs inside its own worktree**) — executes an approved plan end-to-end.
- **`ios-reviewer`** (haiku, read-only) — checks diffs for GQ design-system consistency, SwiftUI pitfalls, test coverage.

Recommended flow for non-trivial work:

1. Architect produces a plan → writes `PLAN.md` at repo root (or prints it).
2. Implementer reads the plan, works inside `isolation: worktree`, commits to its worktree branch.
3. Reviewer inspects the branch diff and reports.
4. Main session merges.

## When NOT to use parallel sessions

- Tight UI iteration loops (build → screenshot → tweak) — stay in one session. Worktree spin-up overhead kills the feedback loop.
- Work that touches the design system broadly — serialize it, one session, to avoid merge pain.
- Anything under 15 minutes — just do it inline.

---

# Attribution

No AI attribution in commits, code, comments, or pushed content. No `Co-Authored-By`, no "Generated by" lines.
