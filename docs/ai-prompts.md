# AI Prompt Templates — Lift AI (iOS)

Copy a template, fill in the bracketed bit, paste into a Claude session running in the matching worktree.

The default for almost everything is **template 1** (`/gym-feature-slice`). Most gym app features mix UI and logic — don't split them across sessions unless a session would be enormous.

---

## 1. Default — gym feature slice

Use `/gym-feature-slice`.

Task: [describe the feature]

Rules:
- Treat this as a scoped gym app feature slice.
- You may edit UI, state, services, API calls, types, and tests only if directly required for this feature.
- Do not touch unrelated screens, auth, database schema, global navigation, or unrelated shared components.
- Before editing, inspect the existing implementation and give a short plan.
- Reuse existing patterns before creating new ones.
- After editing, run typecheck, lint, and relevant tests.
- Summarize changed files, risks, and possible merge conflicts.

---

## 2. UI-only

Use `/ui-work`.

Task: [describe the UI improvement]

Rules:
- Only touch UI components, styles, layout, copy, and visual states related to this screen.
- Do not change auth logic.
- Do not change API clients.
- Do not change database schema.
- Do not change shared types unless absolutely required.
- Reuse existing design/component patterns.
- Run lint/typecheck after editing.

---

## 3. Bugfix

Use `/bugfix`.

Task: [describe the bug]

Rules:
- Understand the cause before editing.
- Make the smallest safe fix.
- Do not refactor unrelated code.
- Add or update a test if practical.
- Run relevant checks after editing.

---

## 4. Integration / merge review

Use `/integration-review`.

Branches/worktrees:
- [branch 1]
- [branch 2]
- [branch 3]

Rules:
- Review diffs before merging.
- Identify overlapping files.
- Identify likely conflicts.
- Recommend safest merge order.
- Do not merge until the plan is clear.

---

## 5. Schema change (high-risk)

Use `/schema-change`.

Task: [describe the schema change]

Rules:
- Confirm the migration design with me before generating any SQL.
- Identify frontend (iOS) and backend (Python) impact.
- Additive over destructive.
- Update models, services, seeders, and tests downstream of the migration.
- Do not auto-run `supabase db push` / `db reset` — hand the apply step back to me.
- Do not mix this with unrelated UI work.

---

## Tips for filling in the brackets

- Be specific about *which screen / service / table*. "the streak card on `HomeView`" beats "the streak feature".
- Name the files you expect to touch. Claude will respect that scope.
- Name a forbidden zone explicitly if there's risk of drift, e.g. "do not touch `PostCardComponents.swift`".
- If the task is unclear, ask Claude for a plan first, approve it, then say "go".
