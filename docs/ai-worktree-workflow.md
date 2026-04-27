# AI Worktree Workflow — Lift AI (iOS)

This is the canonical workflow for running multiple Claude sessions in parallel on this repo without stepping on each other.

## The one rule

**One task = one worktree = one branch = one Claude session.**

Don't run two parallel sessions in the same checkout. Don't run two tasks in the same worktree.

Most gym app work is a feature slice → use `/gym-feature-slice`. UI-only polish → `/ui-work`. Bug → `/bugfix`. Schema → `/schema-change`. Merging branches → `/integration-review`.

## Default skill = `/gym-feature-slice`

A gym app feature usually involves UI + state + a service call + maybe a type. That's a feature slice. Don't try to split a single feature across "UI" and "logic" sessions — you'll lose context and create merge conflicts.

Use `/ui-work` only when zero logic / data / API changes are required.

## How to create a worktree

From the repo root:

```bash
# 1. Pick a short, kebab-case name describing the task (becomes branch + path).
WT=streak-card-polish

# 2. Create the worktree on a new branch off origin/HEAD.
git worktree add .claude/worktrees/$WT -b feat/$WT origin/HEAD

# 3. cd into it.
cd .claude/worktrees/$WT
```

Or via Claude Code:

```bash
# From the repo root, this spins up a Claude session inside a fresh worktree.
claude --worktree streak-card-polish
```

Claude creates `.claude/worktrees/streak-card-polish/` on branch `worktree-streak-card-polish` from `origin/HEAD`.

## Branch naming

- `feat/<short-name>` for features
- `fix/<short-name>` for bugfixes
- `ui/<short-name>` for visual-only polish
- `schema/<short-name>` for migrations
- `integ/<short-name>` for integration / merge-prep branches

Keep names < 30 chars, kebab-case, descriptive.

## Starting multiple Claude sessions

Open one terminal per worktree:

```bash
# Terminal A
cd .claude/worktrees/log-workout-flow
claude

# Terminal B
cd .claude/worktrees/streak-card-polish
claude

# Terminal C
cd .claude/worktrees/profile-feed-polish
claude
```

Each session is isolated. Each session runs **one** task.

## First action in every parallel session

Before editing anything, the session must:

1. Update the **Active parallel sessions** table in the root `CLAUDE.md` with its row (worktree name / branch / focus / primary files / forbidden files / status).
2. Print a scope contract (see `/gym-feature-slice` skill).
3. Confirm the scope with the user.

## How to detect overlapping files between worktrees

From the main checkout:

```bash
# Files touched on each worktree branch vs origin/HEAD
for B in feat/log-workout-flow feat/streak-card-polish feat/profile-feed-polish; do
  echo "=== $B ==="
  git diff --name-only origin/HEAD..."$B"
done

# Find files touched by more than one branch
git diff --name-only origin/HEAD...feat/log-workout-flow > /tmp/a.txt
git diff --name-only origin/HEAD...feat/streak-card-polish > /tmp/b.txt
comm -12 <(sort /tmp/a.txt) <(sort /tmp/b.txt)
```

Or just run `/integration-review` and let it produce the matrix for you.

## Merging safely

1. Run `/integration-review` with all branches under review **before merging anything**.
2. Apply the recommended merge order.
3. After each merge: build, run targeted tests, smoke-test in the simulator.
4. After the last merge, delete the worktrees and prune branches.

```bash
# After merge, from the main checkout
git worktree remove .claude/worktrees/streak-card-polish
git branch -d feat/streak-card-polish
```

## What to do when two branches touch the same file

Options, in order of preference:

1. **Re-scope.** If the overlap is small, move one branch's change to a different file or extract a small sub-component.
2. **Serialize.** Merge the simpler branch first, rebase the second branch onto the new tip, resolve conflicts in the second branch.
3. **Combine.** If the changes are tightly related, abandon both branches and redo the work in a single new branch with `/gym-feature-slice`.

Avoid resolving conflicts under time pressure during the merge itself — rebase first, resolve in the worktree, build and test, *then* fast-forward into the integration target.

## `.worktreeinclude` and secrets — read this carefully

This repo has a `.worktreeinclude` file that copies these gitignored files into every new worktree:

- `backend/.env`
- `backend/.env.local`
- `.env`
- `.env.local`

**This is convenient for local builds but means real secrets are duplicated across worktrees.** Implications:

- Do not push a worktree branch to a public remote without verifying `.gitignore` is doing its job. (`block-git-push.sh` already hard-blocks `git push` from this repo — only push from `~/claude-gymquest`.)
- If you delete a worktree with `rm -rf` instead of `git worktree remove`, you may leave the copied env file on disk. Always use `git worktree remove`.
- Claude is configured to **deny** reading `.env*` files. Don't override that. If you need a value from `.env`, ask the user.
- Prefer pointing `.worktreeinclude` at `.env.example` and having each worktree fill in the secrets it needs. This is **not** the current default in this repo — switching it is a deliberate user decision.

## Worked examples

### Example 1 — Workout logging feature

```bash
git worktree add .claude/worktrees/log-workout-flow -b feat/log-workout-flow origin/HEAD
cd .claude/worktrees/log-workout-flow
claude
```

Then in the session:

> Use `/gym-feature-slice`. Task: Add a "rest timer" to the active workout flow that auto-starts when a set is logged. Allowed: `ActiveWorkoutView.swift`, `ActiveWorkoutViewModel.swift`, a new view component for the timer, a unit test. Forbidden: auth, schema, design tokens, `ContentView`, other tabs.

### Example 2 — Workout streak card (UI-only polish)

```bash
git worktree add .claude/worktrees/streak-card-polish -b ui/streak-card-polish origin/HEAD
cd .claude/worktrees/streak-card-polish
claude
```

> Use `/ui-work`. Task: Tighten the streak card spacing and update the heading copy on `HomeView`/`HeroWidgetsView`. UI only. No service or state changes.

### Example 3 — Profile / social feed polish

```bash
git worktree add .claude/worktrees/profile-feed-polish -b ui/profile-feed-polish origin/HEAD
cd .claude/worktrees/profile-feed-polish
claude
```

> Use `/gym-feature-slice` (since it touches feed ranking inputs as well as visual changes). Task: Show a "shared with X friends" footer on profile feed cards. Allowed: `ProfileView.swift`, `FriendsFeedView.swift`, the per-card view, `FriendsRecapService.swift` *if* a method is missing. Forbidden: shared `PostCardComponents.swift`, design tokens, schema.

### Example 4 — Onboarding flow

```bash
git worktree add .claude/worktrees/onboarding-goals -b feat/onboarding-goals origin/HEAD
cd .claude/worktrees/onboarding-goals
claude
```

> Use `/gym-feature-slice`. Task: Add a "primary goal" step to onboarding (build muscle / lose fat / general fitness) that persists into user profile. Allowed: `OnboardingFlow.swift`, an enum/type local to onboarding, the user-profile service method (extend, don't add a new service). Forbidden: `AuthService.swift`, schema, tab bar.

### Example 5 — Auth / session fix

Auth is high-conflict. Confirm scope with the user before opening a worktree.

```bash
git worktree add .claude/worktrees/auth-token-refresh-fix -b fix/auth-token-refresh origin/HEAD
cd .claude/worktrees/auth-token-refresh-fix
claude
```

> Use `/bugfix`. Task: `AuthService.refreshToken()` is firing twice on cold launch. Root-cause first, then minimal fix. Allowed: `AuthService.swift`, one regression test under `Tests/Unit/`. Forbidden: routing, design system, schema.

### Example 6 — Supabase schema change

```bash
git worktree add .claude/worktrees/schema-add-streak-shield -b schema/streak-shield origin/HEAD
cd .claude/worktrees/schema-add-streak-shield
claude
```

> Use `/schema-change`. Task: Add a `streak_shields_remaining INT NOT NULL DEFAULT 0` column to the user-stats table. Confirm migration design with me before generating SQL. Update model + service + seeder + a unit test.

## Quick reference

| Situation | Skill |
|---|---|
| Most feature work | `/gym-feature-slice` |
| Visual polish, no logic | `/ui-work` |
| Specific bug | `/bugfix` |
| Merging multiple branches | `/integration-review` |
| Supabase / DB / migrations | `/schema-change` |
