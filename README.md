# claude-gymquest

Private snapshot of the Claude Code configuration for the Lift AI (GymQuest) iOS project.

The iOS app repos are public on GitHub, so this config lives separately to keep tooling choices out of those repos' history.

## Contents

- **`CLAUDE.md`** — project guide (stack, design system, build command, gotchas) plus the Parallel Work Protocol that coordinates multiple concurrent sessions via an active-sessions table.
- **`.worktreeinclude`** — list of gitignored files (secrets, `.env`) that get auto-copied into new git worktrees created by `claude --worktree`.
- **`.claude/settings.json`** — `cleanupPeriodDays` plus a permission allowlist for iOS build/sim commands.
- **`.claude/agents/`** — three role subagents:
  - `ios-architect` (opus, read-only) — produces `PLAN.md` for non-trivial changes
  - `ios-implementer` (sonnet, `isolation: worktree`) — executes a plan end-to-end in its own worktree
  - `ios-reviewer` (haiku, read-only) — reviews a branch diff for design-system consistency and SwiftUI pitfalls

## Installing into the iOS project

The iOS project dir is `~/HybridHub_Web_Demo_v3/GymQuest-iOS`. Claude Code reads config from the current working directory, so the files need to live there to take effect.

Two supported flows:

### A. Copy (simplest)

```bash
cd ~/claude-gymquest
cp CLAUDE.md .worktreeinclude ~/HybridHub_Web_Demo_v3/GymQuest-iOS/
cp -R .claude ~/HybridHub_Web_Demo_v3/GymQuest-iOS/
```

After tweaking anything in the iOS project dir, reverse the copy to keep this repo as source of truth:

```bash
cd ~/HybridHub_Web_Demo_v3/GymQuest-iOS
cp CLAUDE.md .worktreeinclude ~/claude-gymquest/
cp -R .claude ~/claude-gymquest/
```

### B. Symlinks (always in sync)

```bash
cd ~/HybridHub_Web_Demo_v3/GymQuest-iOS
rm -rf CLAUDE.md .worktreeinclude .claude
ln -s ~/claude-gymquest/CLAUDE.md CLAUDE.md
ln -s ~/claude-gymquest/.worktreeinclude .worktreeinclude
ln -s ~/claude-gymquest/.claude .claude
```

Edits in either location are visible in both. The iOS project's `.gitignore` already blocks these paths from tracking.

## Why it's private

The iOS repos are on a resume. Keeping AI tooling config out of their public git history is intentional.
