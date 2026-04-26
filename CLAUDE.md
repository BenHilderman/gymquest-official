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
