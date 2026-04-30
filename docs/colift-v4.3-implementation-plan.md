# Colift / Lift AI v4.3 — Full Implementation Strategy

**Source design:** `~/Downloads/colift_final_design_v4_3 (2).txt`
**Codebase:** `/Users/benjaminhilderman/HybridHub_Web_Demo_v3/GymQuest-iOS`
**Goal:** Ship every aspect of the v4.3 design — 6 page tiers, 25/25 user cases, every competitor bar.

---

## 0. Executive summary

**What's already production-ready:**

- Tab bar (5 buttons, with center workout indicator), Floating tab bar, NowPlayingBar
- Live Activity + Dynamic Island (lock-screen workout timer, set count, rest timer)
- HealthKit (comprehensive read of workouts, vitals, sleep, body metrics)
- Watch app target (`GymQuestWatch/`, 9 files, real `WatchActiveWorkoutView`)
- Strava / Whoop / Spotify integrations (OAuth + token handling)
- AI Coach (real Groq-backed LLM via FastAPI backend)
- Workout logging (sets, reps, weight, RPE, PR indicator, add-set)
- PostCardV2 (basic shape — header, proof, actions, comments, save, share)
- Comments with 1-level reply threading
- ProofCardView (6 of 9 design variants: first / pr / comeback / streak / longest / default)
- Supabase schema for posts, comments, reactions, follow graph, crews/squads/pods, basic notifications

**What is missing or only partially built:**

| Pillar | State | Notes |
|---|---|---|
| Smart Contextual Landing (15-priority router) | MISSING | Only 1.5 of 15 priorities exist (default tab; partial deep-link). |
| DMs (1-on-1) | MISSING | No model, view, or schema. |
| Squad Chat (group) | MISSING | `Squad` model exists; no chat infrastructure. |
| Stories (viewing + creation + highlights) | MISSING | `StoriesRail` shell only. |
| Partner Mode (3 entry points → invite → live → shared post → streaks) | MISSING | `WorkoutPartnerStatus` enum only. |
| Day-of-Week Ritual (Home Slot 5) | MISSING | `WeeklyPromptGenerator` exists but not on Home. |
| Live session cards (in feed + Home Slot 4) | MISSING | Presence rings only. |
| Suggested users (own card type) | MISSING | |
| Profile (own) — Live State Line, Year So Far, Training Identity, Streak visual, Partner Streaks, Privacy pill, tab toggles | MISSING / PARTIAL | Only basic header + post grid. |
| Profile (other) — Train Like Them, Lift With Them, VS You, Alive friend actions row | MISSING | |
| Activity — filter chips, 7 emotional groupings, voice/photo previews, "today on Lift" empty state | PARTIAL | Time-grouped only. |
| Crew Detail — Zones 2/3, Crew Streak Badge, Memories | PARTIAL | Header + feed only. |
| Discover — Today's Mix, Trending Now, Friends sub-tab, Tips sub-tab, Discover Streak | PARTIAL | Single Watch feed; no rails or sub-tabs. |
| Friends Feed — segments, 4 filter chips, PostCardV2 anatomy upgrades, live session cards, suggested users card type, empty state | PARTIAL | Basic feed only. |
| PostCardV2 anatomy — presence ring + gym, top-set/volume/PR strip, crossover row, primary action variants, voice/photo reactions, partner indicator | PARTIAL | |
| Privacy & Trust — Ghost Mode 4 levels, close friends, granular reaction/DM/invite toggles, per-post audience | PARTIAL | Only 2 of 4 Ghost levels; no granular toggles. |
| Saved Gyms UI — drop pin, trusted friends per gym | PARTIAL | Limit + nickname only. |
| Alive Layer — 4 ring colors, voice/photo capture+playback, decay rules, max-3-elements, live tab dots wired | PARTIAL | Skeleton only. |
| Active Workout — rest-timer reactions, social layer, "X watching" pill, finish-moment 3-sec pre-proof | PARTIAL | Header + log + finish only. |
| PR Moment — auto-record 3 sec, share prompt routing | PARTIAL | Confetti only. |
| Post-Workout — 9-variant proof picker, video proof, slow-mo PR replay, partner proof, smart captions, What's Next, anticipation hooks, external share with watermark | PARTIAL | 6 variants, manual editor. |
| Onboarding — 11-step flow with auto-land Discover Watch, post-3-min add friends, post-first-workout join crew | PARTIAL | 4-page tour only. |
| Settings — Coach mode, Subscription, Founder, Health, Training, Social sections; granular notification toggles; "what's new" line | PARTIAL | Notification skeleton only. |
| Discover Engine — backend ML scoring (currently `DiscoverSeeder` hardcoded) | PARTIAL | |
| Push notifications | PARTIAL | Local only; no APNs server wiring. |
| Schema — stories, DMs, squad messages, partner sessions, presence, PR events, audience-scoped posts, ghost mode | MISSING | |

**Naming alignment:** "Today" tab → "Home" in design; "Clubs" → "Crews". Either rename, or document the equivalence and stop. **Rename, with display-only adapter, before pillar work.**

---

## 1. Sequencing principle

The design says every page must beat its competitor; that cannot be done one screen at a time because pillars share infrastructure. We work in three layers:

1. **Foundation** — naming, schema, the 15-priority router, push, presence, audience scoping. Touches every page; must serialize.
2. **Vertical pillars** — Stories, Messaging, Partner Mode, etc. Each is a self-contained slice that can run in its own worktree once foundation lands.
3. **Polish + acceptance** — Alive Layer fidelity, animation, onboarding, the 25-user-case audit.

Ordering rule: foundation before pillars; pillars whose surface area touches Home/Friends/Profile before pillars that touch Crews/Discover; flows and identity polish last because they consume everything before them.

---

## 2. Phase plan

Each phase has: **scope** (what gets built), **deliverables** (concrete artifacts), **acceptance** (the tests that prove it's done), **dependencies**, **parallelizable?**, **owner skill** (which `/skill` to invoke).

### Phase 0 — Naming alignment + workflow seeding (1-2 days, single session)

**Scope:** Rename "Today" → "Home" and "Clubs" → "Crews" at the user-facing level. Keep file/symbol names where they live (no mass rename — same policy as the GymQuest → Lift AI rename). Document the equivalence in `CLAUDE.md`.

**Deliverables:**
- Display-text changes only (tab labels, view titles, copy strings).
- New rows in `CLAUDE.md` glossary: "Home = Today (legacy on disk)", "Crews = Clubs (legacy on disk)".
- Test: snapshot tests of tab bar + headers regenerated.

**Acceptance:**
- App displays "Home" / "Crews" everywhere user-visible.
- No Swift symbol renames inside `*View.swift`, services, or models.

**Dependencies:** None.
**Parallel?** No — touches every screen's strings.
**Skill:** `/ui-work`.

---

### Phase 1 — Schema foundation (3-5 days, single session)

**Scope:** Add the missing tables, columns, and indexes in `supabase/migrations/`. This is forward-only schema work — every later pillar depends on it.

**Deliverables (one migration per logical domain):**

1. `presence` table — `(user_id, state, gym_id, started_at, last_ping_at, expires_at)`. State enum: `live / recently_finished / inactive / ghost`. RLS: visibility scoped by trusted-friends graph + Ghost Mode level.
2. `stories` table — `(id, author_id, kind, media_ref, sticker_payload, audience, posted_at, expires_at)`. Audience enum: `friends / close_friends / squad / public`.
3. `story_views` table — `(story_id, viewer_id, viewed_at)`.
4. `story_highlights` table — `(user_id, slot_index, story_id, pinned_at)` (for profile highlight reels).
5. `dm_threads` + `dm_messages` tables — `(thread_id, participant_a, participant_b, last_message_at)` + `(id, thread_id, sender_id, kind, body, media_ref, voice_data_ref, photo_data_ref, expires_at, vanish_mode_enabled)`. Reactions to messages live in `dm_message_reactions`.
6. `squad_threads` + `squad_messages` + `squad_message_reactions` tables (analogous to DM, plus `system_event_kind` column for auto-shared workout finishes — stays a real event row, not bot speech).
7. `partner_sessions` table — `(id, initiator_id, partner_id, workout_a_id, workout_b_id, started_at, ended_at, shared_post_id, post_together_enabled)`.
8. `partner_streaks` table — `(user_a, user_b, streak_count, last_session_at, broken_at)`.
9. `pr_events` table — `(id, user_id, workout_id, exercise_id, value, value_unit, set_id, created_at)`. Drives PR Moment + activity.
10. `posts` audience columns — `audience` enum (`friends / close_friends / squad / public`), `partner_session_id` (nullable, links partner posts).
11. `reactions` granularity — `kind` enum extended to `emoji / voice / photo`; `voice_data_ref`, `photo_data_ref`, `photo_expires_at` (7-day server expiry per design §9).
12. `notifications` granular categories — `category` enum mirroring design §8B notification list (friend-starts, friend-finishes, reaction-emoji, reaction-voice, reaction-photo, comment, dm, story-view, tag-mention, crew-event, squad-chat, squad-reminder, partner-invite, streak-nudge, ai-coach-prompt).
13. `ghost_mode` — `(user_id, level)` with level enum `public / friends / squad / ghost`. Migrate existing `is_ghost` boolean.
14. `trusted_friends_per_gym` — `(user_id, friend_id, gym_id, created_at)` — asymmetric, design §8A.
15. `close_friends` table — `(user_id, friend_id, added_at)`.
16. `discover_streak_counters` table — `(user_id, kind, week_starting, count)` where kind is `workout_saved / tip_applied / clip_reacted / etc.`
17. RLS policies for every new table — never weaker than the existing `posts` policy. Audience scoping enforced server-side.

**Acceptance:**
- All 17 migrations applied to a local Supabase, validated by `supabase db diff` showing no drift.
- A typed Swift API client (`GymQuest/Services/Supabase*.swift`) compiles against the new schema.
- A read-only query test from the iOS app proves each new table is visible to the app's auth context.

**Dependencies:** Phase 0 (naming) for clarity; otherwise none.
**Parallel?** No — one writer to `supabase/migrations/`.
**Skill:** `/schema-change` (mandatory).

---

### Phase 2 — Push notifications + APNs server wiring (2-3 days)

**Scope:** Stand up a push pipeline so every later pillar can notify users. Local-only `UNUserNotificationCenter` is not sufficient for Live Activity reaction haptics, Partner invites, DMs, friend-starts, tags.

**Deliverables:**
- APNs auth key checked into Supabase secrets (user-managed; not committed).
- A Supabase Edge Function `send-push` that takes `(user_id, category, payload)` and routes to APNs.
- An iOS `PushTokenService` that registers the device token to a `device_tokens` table on every cold launch.
- DB triggers (or Edge Function calls) for the highest-priority categories: friend-finishes (auto-share into squad chat + activity), partner-invite, DM, tag-mention.
- A category-to-permission map enforcing Notification Settings toggles before send.

**Acceptance:**
- A test posts row → friend-finishes event triggers a real push that wakes Live Activity reaction haptics on a paired device.
- A user with `reaction-voice` toggled OFF receives no voice-reaction pushes.

**Dependencies:** Phase 1 (notifications schema).
**Parallel?** Partial — server work and iOS work can run in two worktrees with a clean interface contract first.
**Skill:** `/gym-feature-slice` (with backend touch).

---

### Phase 3 — Smart Contextual Landing router (3-5 days)

**Scope:** Implement the 15-priority order from design §2. This is the launch experience.

**Deliverables:**
- New service `LaunchRouter` (`GymQuest/Services/LaunchRouter.swift`).
- Inputs: active workout state, last-tab + timestamp, deep-link (URL or push payload), tagged-posts inbox, unread DM count + last-arrived timestamp, follow graph + friend-post timestamps, geofence vs `SavedGym`, last-finish timestamp, unread reactions count, account age, account inactivity window, day-of-week + clock, friends-live count.
- Output: `enum LandingTarget { activeWorkout, postById(UUID), tab(Tab), feed(scrolledTo: PostId), messages(thread: ThreadId), discoverWatch, homeWeekend, homeLiveStrip }`.
- Hooked into `LiftAIApp` cold-launch sequence; replaces the current 2-state branch in `ContentView`.
- Telemetry event `launch_routed` with the chosen rule index — for iteration.

**Acceptance:**
- Each of the 15 rules covered by a unit test that constructs the input snapshot and asserts the chosen target.
- Manual smoke: kill app at gym, relaunch → Home Slot 1 "start at goodlife".
- Manual smoke: tap a friend-post push → app cold-launches at that post.

**Dependencies:** Phase 1 (presence, PR events, notifications), Phase 2 (push payload).
**Parallel?** Yes (fresh service file).
**Skill:** `/gym-feature-slice`.

---

### Phase 4 — Alive Layer foundation (3-4 days)

**Scope:** The presence + reaction substrate every other pillar consumes. Design §9.

**Deliverables:**
- `PresenceService` (real-time channel subscription to `presence` table) + decay rules: green ring 5 min after last ping, purple 60 min, gray after, ghost when `ghost_mode.level = ghost`.
- `LiveTabDots` wiring on Friends (followed users live), Crews (joined-crew members live), Plus (gold pulse at saved gym + Partner Mode invite pending dot).
- Reaction sender + renderer for `voice` (hold-to-record max 5 sec, plays once with haptic, appears in Activity + Lock Screen + Active Workout) and `photo` (tap-to-capture 2-sec loop, server expiry 7 days).
- "Max 3 Alive elements per page" enforcement: a `AliveBudget` per-view modifier that counts and degrades surplus elements.
- Reaction vocabulary: 🦍 / 🐐 / 💀 / 😤 / 🤝 / 🥶 + standard 🔥 / 💪 / 👀.

**Acceptance:**
- A friend on the same gym with `presence.state = live` appears with a green ring inside 5 sec; ring decays to purple at 5+ min.
- A voice reaction sent from device A plays once with haptic on device B's Active Workout, auto-collapses after 4 sec.
- A page with > 3 Alive elements degrades the lowest-priority ones gracefully (no blink, no jank).

**Dependencies:** Phase 1 (presence + reactions schema), Phase 2 (push for haptics).
**Parallel?** Yes once Phase 1+2 land.
**Skill:** `/gym-feature-slice`.

---

### Phase 5 — Stories pillar (5-7 days)

**Scope:** Design §3C and §3 cross-references on Home + Profile + Friends Feed.

**Deliverables:**
- **Story Composer** (`StoryComposerView`): camera modes (photo / video max 15 sec / text-only / workout share); gym sticker pack (workout type / PR / gym name / song / mood / countdown / poll); audience picker (friends default / close friends / squad / public).
- **Story Viewer** (`StoryViewerView`): vertical full-screen, swipe between, tap right next, tap left previous, hold pause, swipe up reply (sends to DM), react quick emoji, view count visible to poster.
- **Stories+Presence row** integration on Home (top), Friends Feed (top), Profile (Story Highlights row, auto-cycling 3-5 user-curated).
- Empty state — "you're caught up · X new tomorrow"; **no auto-fill of stranger stories**. Optional one-button "see public stories" only.
- DM-thread auto-routing for swipe-up replies.

**Acceptance:**
- User posts a 12-sec video story with a "PR" sticker, audience = close friends. Only close friends see it; expires 24 h.
- All-friend-stories-watched empty state shows "you're caught up", no fallback feed.
- Story Highlights on Profile auto-cycles through user-pinned stories.

**Dependencies:** Phase 1 (stories schema), Phase 4 (presence rings around story bubbles).
**Parallel?** Yes — no overlap with messaging or partner mode.
**Skill:** `/gym-feature-slice`.

---

### Phase 6 — Messaging pillar (DMs + Squad Chat + Comments upgrades) (7-10 days)

**Scope:** Design §6 in full.

**Deliverables:**

1. **DMs** (`MessagesListView`, `DMThreadView`):
   - Entry points: paper-airplane top-right of Friends + "Message" button on profile + story reply + share-workout "send to friend".
   - Threads list with unread badges, presence rings, search, status line ("12 unread messages", "react streak conversations: 3").
   - "People you might DM" section when < 3 active threads (friends-reacted-to-but-not-DMed, same-gym followers, one-tap pre-built openers: "wsg 🦍" / "drop your routine pls" / "lifting today?" / "see u tomorrow").
   - Content types: text / voice notes (hold-to-record max 60 sec) / photos / videos / shared workout posts / shared profile cards / shared story / shared crew or event / "lift with me" Partner-Mode invite.
   - Message reactions (long-press emoji + voice + photo).
   - Typing indicators, read receipts (toggleable).
   - Privacy: DM only people who follow you back (default toggle); block / mute / report inside thread; vanish mode (24 h auto-delete).
   - DM-specific templates: "ask routine", "lift with me", "see you tonight" with auto-attached gym address.

2. **Squad Chat** (`SquadChatView`):
   - Discord/group-chat style: text / voice / photo / video / share workouts directly.
   - Reactions, polls (created by humans, never bots), typing indicators, read receipts.
   - **Auto-shared workout completions** as system events (NOT bot speech) — "marcus just crushed push day · 17 sets" with one-tap react buttons inline. Distinction enforced in schema: `squad_messages.system_event_kind != null` is the only way these messages are written.
   - Quiet > 24 h gentle nudge: "haven't heard from y'all in a while" — system note, opt-in per squad, disabled by default.

3. **Comments upgrades** (`CommentsSheet`):
   - Quick-comment chips: "wsg 🦍" / "form check?" / "sets?" / "drop routine pls" / "🐐" / "see u tomorrow" / "ts brutal" / "easy work".
   - Voice/photo reactions to comments (long-press).
   - Threading already exists — keep at max 1 level.

**Acceptance:**
- Two devices: A taps profile → Message → DM thread opens, A sends voice note → B receives with haptic + auto-play once.
- Squad with no human messages for 30 h shows opt-in nudge (if enabled).
- A user with a workout-finishes event sees a real `squad_messages` row with `system_event_kind = workout_finished`, reacted via tap.
- Vanish mode toggled in a thread auto-deletes messages > 24 h.

**Dependencies:** Phase 1 (DMs / squad messages schema), Phase 2 (push), Phase 4 (presence rings, voice/photo reactions).
**Parallel?** DMs / Squad Chat / Comments-upgrade can each run in their own worktree.
**Skill:** `/gym-feature-slice` per worktree.

---

### Phase 7 — Partner Mode end-to-end (5-7 days)

**Scope:** Design §10 — three entry points, invite flow, sync, post merge, streaks, privacy.

**Deliverables:**
- 3 entry points: Plus tab "lift with [friend]" pill (visible iff a followed friend is at the same saved gym OR has accepted a recent invite); long-press a friend's live session card; DM "/lift" or "+ → lift with me".
- Invite sheet → push → recipient gets two buttons "let's go" / "not now" → workouts auto-link via `partner_sessions`.
- Active Partner Mode UI: single small avatar + their last completed set in workout header; tap → Partner Sheet; collapses with one tap.
- Auto-sync: set log → reaction-style haptic on partner; PR moments push to partner.
- Post-workout: "post together?" toggle (default ON) → single shared post, both auto-tagged, `posts.partner_session_id` set, single post in both feeds.
- **Partner Streaks**: 3+ partner sessions in 30 days → streak; visible on Profile near regular streak; breaks if 14 days without partner session.
- Privacy: uses trusted-friends gym visibility; either user can end anytime; auto-disabled if user enters `ghost_mode.level = ghost`.

**Acceptance:**
- Two devices at the same gym: A taps "lift with B" → B receives push → "let's go" → both workouts link → A logs a set → B feels haptic → both finish → "post together?" → single shared post in both feeds with both avatars side-by-side.
- A Partner Streak appears on Profile after the 3rd qualifying session in 30 days; breaks correctly after 14 days idle.

**Dependencies:** Phase 1 (partner_sessions, partner_streaks), Phase 2 (push), Phase 4 (haptics), Phase 6 (DM entry point).
**Parallel?** Yes after Phase 6 starts.
**Skill:** `/gym-feature-slice`.

---

### Phase 8 — Active Workout transformations (4-6 days)

**Scope:** Design §7A, especially the rest-timer transformation, social layer, PR moment, finish moment.

**Deliverables:**
- Header: privacy/ghost toggle visible; live broadcast indicator (default trusted-friends only); "X watching" pill when ≥ 1 viewer; Partner indicator (from Phase 7).
- Rest timer transformed: friend reaction inbox during rest; peer signal "marcus just finished his last set"; one Watch clip auto-plays muted (skippable); music controls; quick reply if reactions came in; voice/photo reaction inbox.
- Social Layer collapsed by default: tiny reaction bubble with haptic, auto-dismiss 4 sec; "3 friends hyped you" pill at bottom expands on tap; voice reactions auto-play once with haptic, then collapse.
- PR Moment: full-screen 2-sec celebration ("NEW PR · 225 x 5 🐐"); confetti + animation + vibration; auto-records last 3 sec via camera (opt-in); then "share this PR?" prompt routes to friends / squad / crew / story / external (IG/TikTok). Partner Mode: synced PR notification to partner.
- Pause overlay: resume / save draft / end workout.
- Finish Workout: gated by minimum completed sets; pre-proof "finish moment" 3 sec — total time / volume / PRs counted up / heart rate decay viz (Apple Watch) / "X people are about to see this" / Partner Mode shared moment.
- Live Activity polish: reaction-haptic patterns differ by emoji / voice / photo; finish button on Lock Screen; Partner indicator.

**Acceptance:**
- A friend's voice reaction during rest plays once with haptic, then collapses.
- A new PR triggers full-screen celebration → 3-sec auto-record → share prompt.
- Finish flow shows pre-proof 3-sec summary before proof card.
- Lock-screen finish button ends the workout.

**Dependencies:** Phase 4 (Alive Layer), Phase 7 (Partner Mode for indicator + sync).
**Parallel?** Partial — depends on Phase 4 ready.
**Skill:** `/gym-feature-slice`.

---

### Phase 9 — Post-Workout pillar (4-6 days)

**Scope:** Design §7B end-to-end.

**Deliverables:**
- WorkoutCompletionExperience: celebration / summary / PRs unlocked / streak progress / squad-crew contribution / partner contribution / milestone badges (30/100/365 day streak, 100th workout).
- ProofCardView complete 9-variant set: clean flex / cinematic / funny / PR-focused / crew-squad recap / partner recap / streak card / black-white / photo overlay. (6 exist; add the missing 3-4: cinematic, funny, crew-squad recap, black-white, photo overlay.)
- **Video Proof Card**: 6-second auto-edited reel; stats overlay; song from NowPlayingBar; slow-mo on PR sets.
- **Slow-mo PR Replay**: dedicated card type, full-screen vertical, optimized for IG/TikTok export.
- **Partner Proof Card**: both avatars side-by-side, shared duration, combined volume, "lifted together · 64 min".
- EnhancedPostEditorView: default share = friends; one-tap upgrade to profile / crew / squad / story / public. Smart caption suggestions (Gen Z): "ts brutal 🥲" / "locked in" / "🐐 behavior" / "easy work" / "i pray" / "send help" / ":/" / "first one of the week 🤝". Partner Mode: default caption "lifted with [partner]", both auto-tagged, shared-post toggle (default ON).
- External Share: Instagram Story / Post / TikTok / Snapchat Story / iMessage/SMS / copy link. **All carry subtle Lift watermark** — implement watermark compositor.
- **What's Next moment**: small card after publish with rotating content ("react to marcus's workout · he just finished" / "save this workout as a template?" / "your squad needs 1 more session this week" / "tip of the moment" / "tomorrow's plan: pull day"). Tap → relevant page; skip → close to landing surface.
- Anticipation hooks: "reactions usually start in 5 min 👀" / "this might pop off" / "your squad's gonna see this".

**Acceptance:**
- Workout with a PR generates Video Proof + Slow-mo PR Replay; both shareable to IG with watermark.
- Friends-only default share with one-tap upgrade to public.
- What's Next card appears after publish, rotates across opens, dismissible.

**Dependencies:** Phase 7 (partner proof / shared post), Phase 8 (PR moment data).
**Parallel?** Partial.
**Skill:** `/gym-feature-slice`.

---

### Phase 10 — Discover refit + Engine (5-7 days)

**Scope:** Design §3A and §11 — Discover destination + corrected Discover Engine scope.

**Deliverables:**

1. **Discover top tabs** (3): `[ watch ] [ friends ] [ tips ]` segmented control replacing the current single-feed.
2. **Watch sub-tab**: Today's Mix rail (5-7 cards rotating daily) at top + Trending Now rail; single-clip immersive feed below; long-press menu (save / not interested / share); inline CTAs (react / save / follow / try workout / join crew).
3. **Friends sub-tab**: people user follows only, posts within last 7 days, vertical scroll, same CTAs as Watch.
4. **Tips sub-tab**: short videos (max 30 sec); one tip per clip; categories (fix your form / beginner mistakes / hidden hacks / PR breakdowns / nutrition basics / recovery quick wins); inline CTAs (save / try today / ask AI).
5. **Search bar** across all sub-tabs.
6. **Discover Streak**: small always-visible counter — "3 workouts saved this week" / "5 tips applied" / etc. Synced with global Identity (XP / level / Profile Year So Far).
7. **Discover Engine scope correction** — engine feeds ONLY: Discover tab itself, Stories opt-in "see public stories" button, Friends Feed empty state (0 follows, clearly labeled), Plus Workout-of-the-Day card, Onboarding curated reel. Verify it does NOT feed: Squad Chat, DMs, Profile, Crew Detail's quiet states, Friends Feed mid-stream. Add an audit test that fails if engine output appears on a forbidden surface.
8. Replace `DiscoverSeeder` hardcoded content with a real backend recommendation pipeline (FastAPI endpoint `/discover/feed?user_id=&surface=watch|friends|tips|today_mix|trending`). Initial ranking: recency × interaction × follow signal. Iterate later.

**Acceptance:**
- Discover shows 3 sub-tabs with the correct content per the design.
- Today's Mix rotates daily; Trending Now updates from backend.
- Tips clip > 30 sec is rejected by the upload pipeline.
- Audit test: posting a Discover-engine candidate on Squad Chat throws.

**Dependencies:** Phase 1 (discover_streak_counters), Phase 5 (Stories opt-in).
**Parallel?** Yes.
**Skill:** `/gym-feature-slice` (with backend touch).

---

### Phase 11 — Friends Feed refit (4-6 days)

**Scope:** Design §3B — bring Friends Feed up to 30+/35.

**Deliverables:**
- Two segments at top: `[ feed ] [ activity ]` (Activity surface lives in Phase 12 but the segment is wired here).
- Paper-airplane DM icon top-right (delegates to Phase 6 DMs).
- Stories+Presence row at top.
- 4 filter chips: `all / training now / just posted / same gym` + "more" sheet (PRs / same workout / clubmates / squad).
- Pattern interrupt cards: "vs your friends this week" stat card + "1 year ago" memory card, every 8-10 posts, FRIEND-derived (your network's stats, your own memory). NO Discover content mid-stream.
- **Suggested users own card type** (clearly labeled, NEVER inline as posts): reasons "you've seen marcus at goodlife 12 times" / "sarah trains at the same time as you" / "alex has the same split + 2 of your friends follow him" / "12 mutuals from your high school".
- **Live session cards** new card type: "marcus is locked in at goodlife · 47 min in" / last completed set / music if shared / primary "send hype 🔥" / secondary "ask sets left?" / "join him" / "lift with him".
- **Empty state** for new user (< 1 follow): "follow people to fill your feed" header + Discover preview labeled "while your feed is empty, here's what's trending" + one-tap follow suggestions; disappears forever once user follows ≥ 3 people.

**PostCardV2 anatomy upgrades:**
- Top strip: avatar + presence ring + "marcus did push day · 64 min · goodlife" (gym name).
- Stats strip: top set / volume / PR badge.
- Crossover row: "marcus, sarah also did push this week".
- Primary action variants: "try this workout" / "ask routine" / "send hype" / "view crew".
- Secondary actions: voice + photo reactions added (long-press picker), "follow next session".
- Partner post indicator: both avatars side-by-side, "marcus + sarah lifted together".

**Acceptance:**
- Filter "training now" returns only friends with `presence.state = live`.
- A "1 year ago" card appears when the user has ≥ 1 post from this calendar day a year ago.
- Suggested users render in their own card type, never as a post in the stream.
- New user with 0 follows sees the labeled empty state; user with 3 follows never sees it again.

**Dependencies:** Phase 4 (presence rings, voice/photo), Phase 6 (DM entry), Phase 7 (partner indicator).
**Parallel?** Yes.
**Skill:** `/gym-feature-slice`.

---

### Phase 12 — Identity surfaces (Profile own, Profile other, Activity, Crew Detail) (8-12 days, 4 worktrees)

**Scope:** Design §5 in full. Four sub-pillars; each can run as its own worktree.

#### 12a. Profile (own)

- Identity header: avatar (with optional video loop), name/username, level / XP / streak, custom 1-line bio.
- Live State Line: "last trained: yesterday · push day · 64 min" / "training now · push day · 32 min in" / "rest day". Updates on workout-event triggers.
- Story Highlights row (auto-cycling 3-5 user-pinned).
- Year So Far Card: total sessions / total volume ("X tons lifted") / heaviest lift / most consistent month / PR count; **refreshes weekly via cron**, not per-open. Shareable card (one-tap to story / external).
- Stats row: followers / following / posts / sessions / crews / streak.
- Partner Streaks row.
- Privacy & Trust shortcut pill below header (Phase 13).
- Training Identity Card: split / goal / experience / favorite lifts / training style / vibe tag.
- Squad badges row.
- Streak visual: 30-day bronze / 100-day silver / 365-day gold + animation.
- Crews joined row.
- Posts area toggle: Highlights (default, user-curated) / All workouts / PRs.
- Tabs: Posts / Workouts / PRs / Saves / Crews.
- Settings gear → SettingsView.
- **Removed by design**: no "people like you" surface; no Profile Pulse rotating insights.

#### 12b. Profile (other user)

- Header: avatar + presence ring / name / username / training identity 1-line / bio / follow / DM (paper airplane).
- Live state line, story highlights row, Year So Far card (if shared).
- **PRIMARY ACTION** "TRAIN LIKE THEM" button → try latest workout / save routine / ask for routine.
- "LIFT WITH THEM" button (Partner Mode, conditional — same gym OR recent partner accept).
- "VS YOU" toggle: side-by-side stats; user can disable comparison globally.
- Shared context: mutual friends / shared crews / similar style / same gym (only if trusted).
- Alive friend actions row: send hype / quick reply DM / follow workout / trust with gym / auto-react toggle / reaction streak badge.
- Block / mute / report in profile menu.

#### 12c. Activity

- Reached via top-right button on Home/Friends/Crews/Discover AND tab segment inside Friends.
- Filter chips: `[ all ] [ reactions ] [ comments ] [ tags ] [ followers ] [ system ]`.
- Grouped by emotional category (default): "people reacted to your sessions" / "friends asked about your routines" / "your squad noticed you" / "new followers" / "tags + mentions" / "story views" / "crew activity".
- Wording (Gen Z lowercase): "marcus reacted 🔥 to your push day" / "sarah commented: 'lmaooo pls'" / "daniel saved your workout" / "alex is at goodlife rn" / "🦍 23-day react streak with marcus" / "12 ppl watched your story" / "your turn to react to sarah's session".
- Voice reactions render with play button + waveform; photo reactions with thumbnail (tap to play 2-sec loop).
- Quick actions per row: react back / reply (DM) / follow / view workout / view profile / invite to lift.
- **Empty state for lurkers**: "your circle is quiet right now" + "today on Lift" globals (12,400 reactions today / 3,200 PRs / sample anonymized snippets). Clearly labeled as "today on Lift".

#### 12d. Crew Detail

- **Zone 1 — Header**: cover image / crew name / vibe tags / member count / active members count (live) / location / join state / FAB (create post / event / challenge / story) / leave option.
- **Zone 2 — Now & Next**: crew stories row (24 h ephemeral); "now" active members + live sessions + send hype to live members; "next" upcoming event card (countdown / friends going / RSVP); post-event prompt if ended within 60 min. Quiet state: "no one is active rn — be the first" — DO NOT inject other crews' members.
- **Zone 3 — Unified feed** (Discord-style): pinned active challenge / posts (proof, photos, videos) / events inline with RSVP CTA / milestone announcements (streaks, PRs, member joins) / "Members" pill at top → list. Quiet: "this crew is quiet — be the spark" + quick actions (post photo / start challenge / drop event idea). DO NOT inject other crews' content.
- **Crew Streak Badge** footer: "you've been in [crew name] for 47 days" / "your crew rank: top 12% by attendance" / "next milestone: 60 days".
- **Memories** collapsible at bottom: weekly highlight reel / streak anniversary / PR replay / crew playlist / featured wall (3x3) / on this day / your crew history.

**Acceptance per sub-pillar:** identity checklist from design §5 passes — identity reinforced, stats meaningful, updates visible, comparison/context available, privacy clear, stable format.

**Dependencies:** Phase 1, 4, 6, 7.
**Parallel?** All four sub-pillars in their own worktrees (use `/integration-review` before merging).
**Skill:** `/gym-feature-slice` per sub-pillar.

---

### Phase 13 — Privacy & Trust panel (3-4 days)

**Scope:** Design §8A in full.

**Deliverables:**
- Entry points: Profile pill below header / Active Workout header Ghost toggle / Settings.
- Saved gyms (up to 3) UI: drop pin from current location, radius, nickname, trusted-friends list per gym.
- Trusted friends per gym (asymmetric).
- **Ghost Mode 4 levels**: public / friends / squad / ghost — currently only 2; migrate.
- Close friends list.
- Granular toggles: who can react (emoji / voice / photo), who can DM, who can invite to Partner Mode.
- Block list / mute list (UI exposure of existing service).
- Per-post audience: friends / close friends / squad / public (default friends) — wire into post editor.
- Privacy copy rule: "let trusted friends know when you're at the same gym" (avoid "share your location").

**Acceptance:**
- Ghost Mode set to "ghost" hides user from all presence surfaces and disables Partner Mode auto-link.
- Per-post audience "close friends" only delivers post to that list.
- Voice reactions toggled off prevents both inbound and outbound voice reactions.

**Dependencies:** Phase 1 (ghost_mode, close_friends, trusted_friends_per_gym), Phase 4 (presence ring respects ghost), Phase 6 (DM and reaction toggles).
**Parallel?** Yes.
**Skill:** `/gym-feature-slice`.

---

### Phase 14 — Home final pass (3-4 days)

**Scope:** Design §4A — bring Home up to router standard with all 5 slots correct.

**Deliverables:**
- Stories+Presence Row at top with `+` to post (tap behaviors: "+" → composer; bubble with story → vertical viewer; bubble with live ring → live preview; bubble with finished proof → proof card preview; inactive → profile). When < 3 friends with stories, compact "post your first story" CTA — DO NOT pull stranger stories in.
- **Slot 1 — Smart Top Card**: 12-candidate priority pool (resume active workout / at saved gym → start / someone you follow at your gym / friend posted within 20 min / friends training now ≥ 2 / crew event within 6 h with ≥ 2 friends going / today's planned workout / unread reactions ≥ 3 / friend just finished within 10 min / mutual just hit a PR / streak danger / squad challenge near completion). Re-evaluates on every open.
- **Slot 2 — Squad / Activity / Build Network**: squad name + avatar stack + today's status + weekly goal progress + chat preview + quick actions; OR "X people noticed your last session" + tap → Activity; OR FOMO empty state (contact-based suggestions, "12 ppl from your school are on Lift", "47 lift at goodlife barrhaven").
- **Slot 3 — My Training Today**: planned / saved template / repeat last / new-user "try beginner-friendly push day · 35 min". Inline social comparison: "your 3rd push this week. marcus on his 4th." / "2 friends did legs this week" / "your crew is doing pull tonight". CTAs: start now / edit / generate / "lift with friend" (Partner Mode).
- **Slot 4 — Live Now Strip**: avatars with context tags ("push · 23 min in · goodlife", "just hit a PR 💪", "first leg day this week"); quick actions (send fire / ask "sets left?" / view session / start similar). Empty (< 2 friends live): "people training your split now" labeled as "from your gym" / "training now" — router context cue, not a feed.
- **Slot 5 — Day-of-Week Ritual** (RESTORED from v4.1):
  - Mon: weekly goal setup
  - Tue: tip of the day (Learn content)
  - Wed: mid-week progress check-in
  - Thu: "who's training friday?"
  - Fri: "train this weekend?" with friend availability
  - Sat: weekend crew events
  - Sun: crew recap (highest-engagement)
- **Identity Footer**: "+12 XP today" / "streak: 17 days 🔥" / "level 6 · 240 XP to level 7". Refreshes after every interaction. Tap to expand → Profile.
- **Global Lifter Footer**: "3,412 lifting right now" — small text, never a card. (Already exists; keep.)

**Router checklist:** < 500 ms perceived load; contextual hero (Slot 1 always reflects current state); smart defaults; max 3 clicks to action; personalized.

**Dependencies:** Phase 3, 4, 5, 6, 7, 11 (most pillars).
**Parallel?** No — touches the central home view.
**Skill:** `/gym-feature-slice`.

---

### Phase 15 — Plus final pass + Crews list final pass (3-4 days)

#### 15a. Plus

- Hero band dynamic copy ("let's lift" / "you're at goodlife. start?" / "marcus is also doing push" / "your squad needs 1 more session").
- **Workout-of-the-Day** single rotating card: "today's workout from your crew" / "trending push day · 47 ppl tried it today" / "your saved workout from last week" / "AI suggested for you".
- Music row: "resume your gym playlist" / "marcus is listening to [song]" / one-tap to start music + workout together.
- Friends training row (horizontal scroll): "marcus · push · 23 min in" / "sarah · just finished legs" / "alex · cardio · 8 min in"; tap → live preview; long-press → "lift with [name]" Partner Mode invite.
- Quick start row (today's planned / repeat last / start empty / start from squad-crew challenge).
- Social proof line ("73 ppl training near you rn" / "67% of your mutuals trained today").
- Workout type picker (6 most-used 2x3 grid + "More types").
- 4 cards: Custom / Follow Previous / Saved / **AI Generated (conversational, NOT a form)** — `Prompt: "what's the move today?"`; user types naturally; AI generates plan with reasoning. **Rule from design**: if AI Generated isn't ready, REMOVE the card. No placeholders. (Exists; verify it's a real conversational flow.)
- "Lift with friend" pill (Partner Mode entry — visible iff condition met).
- This Month Stats footer.

#### 15b. Crews list

- 6 sections in **fixed order**: Now in your crews / Next up / My crews / [button] Explore on map / Nearby crews / Weekly rituals.
- Map mode (button entry, NOT default): pulse pins / heat areas / time scrubber (now / tonight / tomorrow AM / weekend / next week) / tap pin → mini hero / drag bottom sheet → details.
- Empty state: "find your gym crew" hero + 3 suggested crews based on gym + split + vibe + "browse by area" → Map.
- Privacy: gym-level only, no exact user location.
- **No algorithmic Discover injection** — verify.

**Dependencies:** Phase 3, 7, 10, 12.
**Parallel?** Plus and Crews can each run as their own worktree.
**Skill:** `/gym-feature-slice` per worktree.

---

### Phase 16 — Onboarding redesign (3-4 days)

**Scope:** Design §7C — 11 steps + auto-land Discover Watch + post-3-min add friends + post-first-workout join crew.

**Deliverables:**
1. "what do you want to be known for?" picker (biggest lifts / most consistent / best aesthetic / fun crew / just starting / coming back).
2. Pick goal.
3. Experience level.
4. Training style / split.
5. "what's your gym vibe?" (chill / serious / aesthetic / functional / social / silent).
6. Add saved gym.
7. Privacy default (friends-only recommended).
8. Connect Apple Health (optional — wire existing `HealthKitService`).
9. AUTO-LAND on Discover Watch (curated beginner reel).
10. After 3 min of Watch: "ready to add friends?" with smart suggestions / "follow some creators" / skip available.
11. After first workout: join crew / try a squad / post first proof / if friend at same gym → "lift with [name]" prompt.

**Acceptance:** First content moment + first social signal in < 2 min from cold install.

**Dependencies:** Phase 5 (stories), Phase 10 (Discover Watch), Phase 13 (privacy default), Phase 7 (Partner prompt).
**Parallel?** Yes.
**Skill:** `/gym-feature-slice`.

---

### Phase 17 — Settings completeness (2-3 days)

**Scope:** Design §8B.

**Deliverables:**
- Sections present: Account / Preferences / Privacy & Trust / Notifications / Integrations (Strava ✓, Whoop ✓, Apple Health ✓, Google → add, Spotify ✓) / Health / Training / Social / Coach mode / Subscription / Founder.
- Granular notification categories (per design list of 14 categories).
- "What's new" rotating line at top: "voice reactions are new — try one".

**Dependencies:** Phase 1 (notifications schema), Phase 13 (Privacy & Trust shortcut).
**Parallel?** Yes.
**Skill:** `/gym-feature-slice`.

---

### Phase 18 — Acceptance + competitor bar audit (3-5 days)

**Scope:** Design §13 + §14.

**Deliverables:**
- 25 user-case test plan executed (manual + scripted where possible). Each case from design §14 must pass.
- Per-tier scoring rubric: Tier 1 ≥ 30/35; Tiers 2-6 pass their checklists.
- Competitor bar audit: each page beats its competitor (Friends Feed > IG, Profile > IG, Squad Chat > Snapchat, Plus > Strava, Crews > Discord, DMs > iMessage for gym friends, Discover > TikTok in fitness, Active Workout > Strava + RP Hypertrophy).
- Bug-fix sprint: anything found in audit gets a `/bugfix` worktree.

**Dependencies:** All previous.
**Parallel?** Audit cases can be split across worktrees; fixes serialize.
**Skill:** `/bugfix` per defect.

---

## 3. Cross-cutting workstreams

These run in parallel with phases above and affect multiple pillars:

### CC1 — Watch + Live Activity polish (continuous)

Live Activity exists; finishing touches per design §9:
- Reaction haptic patterns differ by emoji / voice / photo.
- Finish button on lock screen.
- Partner Mode indicator on Watch + Lock Screen.
- Watch app: surface friend reactions during rest.

### CC2 — Telemetry + iteration loop

A `Telemetry` event for every design milestone:
- `launch_routed { rule_index }`
- `home_slot_tapped { slot_index, tile_kind }`
- `pr_moment_shown`
- `partner_invite_sent / accepted / declined`
- `reaction_sent { kind: emoji|voice|photo }`
- `feed_pattern_interrupt_shown { kind: vs_friends|memory }`
- `discover_streak_incremented { kind }`

Pipe into Supabase or a third-party (PostHog / Amplitude). Required for tuning the Smart Landing thresholds, ranking, retention.

### CC3 — Test infrastructure

- Snapshot tests for every PostCardV2 variant + every ProofCardView variant + every Home Slot state.
- Integration tests for the 15 Smart Landing rules.
- E2E test: 25 user cases scripted via XCUI on a seeded test account.

### CC4 — Naming + glossary

- Project-level: keep `Today*.swift`, `Clubs*.swift` on disk. User-visible strings show "Home" / "Crews".
- A `CLAUDE.md` glossary maps display name → on-disk symbol so future sessions don't get confused.

### CC5 — Backend hardening

- Move `DiscoverSeeder` content out of the iOS bundle into the backend.
- Replace local recency-only feed ordering with a backend ranking endpoint.
- Add the `/discover/feed` endpoint and a basic content moderation layer for user-uploaded clips.
- Cron job: Year So Far weekly refresh; Discover Streak weekly reset.

---

## 4. Dependencies + sequencing summary

```
Phase 0 (rename)
  ↓
Phase 1 (schema)
  ↓
Phase 2 (push) ─── Phase 3 (router) ─── Phase 4 (Alive Layer)
                                            ↓
       ┌────────────────────────────────────┼────────────────────────────────────┐
       ↓                                    ↓                                    ↓
   Phase 5 (Stories)              Phase 6 (Messaging)              Phase 10 (Discover refit)
                                            ↓                                    ↓
                                  Phase 7 (Partner Mode)                         │
                                            ↓                                    │
                                  Phase 8 (Active Workout)                       │
                                            ↓                                    │
                                  Phase 9 (Post-Workout)                         │
                                            ↓                                    │
                                            └────────────────────────────────────┘
                                                              ↓
                       Phase 11 (Friends Feed) ─── Phase 12 (Identity surfaces) ─── Phase 13 (Privacy)
                                                              ↓
                                            Phase 14 (Home) ─── Phase 15 (Plus + Crews)
                                                              ↓
                                                  Phase 16 (Onboarding)
                                                              ↓
                                                  Phase 17 (Settings)
                                                              ↓
                                                  Phase 18 (Acceptance)
```

**Parallel windows:**

- **Window A** (after Phase 4): Phase 5 (Stories) || Phase 6 (Messaging) || Phase 10 (Discover refit).
- **Window B** (after Phase 6): Phase 7 (Partner Mode) || finish CC2 telemetry.
- **Window C** (after Phase 9): Phase 11 (Friends Feed) || Phase 12a/b/c/d (Identity sub-pillars) || Phase 13 (Privacy) || Phase 17 (Settings).
- **Window D** (after Phase 13): Phase 14 (Home) || Phase 15a (Plus) || Phase 15b (Crews list) || Phase 16 (Onboarding).

Up to 4 worktrees run in parallel during Windows A, C, and D. Use `/integration-review` before each merge wave.

---

## 5. Effort sketch (single-engineer-equivalent days)

| Phase | Days | Notes |
|---|---|---|
| 0. Naming | 1-2 | Strings only |
| 1. Schema | 3-5 | 17 migrations + RLS |
| 2. Push | 2-3 | APNs + Edge Function |
| 3. Smart Landing | 3-5 | 15 rules + tests |
| 4. Alive Layer | 3-4 | Presence + voice/photo |
| 5. Stories | 5-7 | Composer + Viewer + Highlights |
| 6. Messaging | 7-10 | DMs + Squad Chat + Comments |
| 7. Partner Mode | 5-7 | End-to-end |
| 8. Active Workout | 4-6 | Rest timer + PR moment + finish |
| 9. Post-Workout | 4-6 | 9 variants + video + What's Next |
| 10. Discover refit | 5-7 | 3 sub-tabs + engine scope |
| 11. Friends Feed | 4-6 | PostCardV2 + chips + suggested + live cards |
| 12. Identity (4 sub-pillars) | 8-12 | Profile own/other + Activity + Crew Detail |
| 13. Privacy & Trust | 3-4 | Ghost 4 levels + granular toggles |
| 14. Home | 3-4 | 5 slots + Day ritual |
| 15. Plus + Crews list | 3-4 | WOD + Music row + 6 fixed sections |
| 16. Onboarding | 3-4 | 11 steps |
| 17. Settings | 2-3 | Sections + categories |
| 18. Acceptance | 3-5 | 25 cases + competitor bar |
| **Total** | **70-104** | Single-engineer sequential |

With up to 4 parallel worktrees during Windows A/C/D and disciplined `/integration-review` cadence, a small team can compress this to **~6-9 calendar weeks**.

---

## 6. Risks

- **R1 — Schema rework risk.** Phase 1 must be designed correctly the first time. A wrong audience or RLS shape will be expensive to migrate. Mitigation: have the design reviewed by a second pair of eyes (use `ios-architect` agent before generating SQL); never edit a committed migration; only add follow-ups.
- **R2 — Discover Engine scope creep.** The biggest v4.2 mistake the design corrects is letting Discover bleed into every page. Add an audit test in Phase 10 that fails the build if engine output appears on a forbidden surface. Run that test in CI.
- **R3 — Authenticity in Squad Chat.** Auto-shared workout completions are real events; gentle nudges are opt-in only; bots never speak. Keep `squad_messages.system_event_kind` enum strict; reject any insert without a real event row backing it.
- **R4 — Voice/photo reaction storage.** Photos auto-expire 7 days server-side. Need a Supabase Edge cron or DB-level expiry to actually delete media. Without this, storage bills compound.
- **R5 — Live Activity entitlement.** Reaction haptics on lock screen require a Live Activity update path that respects iOS budget. Test on a real device early; do not assume the simulator behavior matches.
- **R6 — Naming drift.** "Today" / "Clubs" persist in code while UI says "Home" / "Crews". A new contributor will be confused. Phase 0's glossary in `CLAUDE.md` is the only mitigation; revisit if friction grows.
- **R7 — Partner Mode privacy edge cases.** "Auto-disabled if user ghosts session" must be implemented as a real check. Test: user A in active partner session toggles ghost mode → session ends, partner notified, no shared post.
- **R8 — Onboarding < 2 min.** Design says first content moment + first social signal in under 2 min. Must instrument a timer and tune steps to hit it.

---

## 7. How this plan maps to the multi-Claude workflow

Now that `.claude/skills/` and the worktree workflow exist (see `docs/ai-worktree-workflow.md`):

- **Each phase = one branch, one worktree, one Claude session** with `/gym-feature-slice` (or `/schema-change` for Phase 1, `/bugfix` for Phase 18 defects).
- **Parallel windows** map to up to 4 simultaneous worktrees. Update the active-sessions table in `CLAUDE.md` on session start.
- **Before each merge wave**, run `/integration-review` from the main checkout against all branches in the wave.
- **Merge order rule of thumb**: schema first; then services / models that depend on schema; then UI surfaces.

**Worktree naming convention for this plan:**

```
feat/p01-schema-foundation
feat/p02-push-pipeline
feat/p03-smart-landing
feat/p04-alive-layer
feat/p05-stories
feat/p06a-dms
feat/p06b-squad-chat
feat/p06c-comments-upgrade
feat/p07-partner-mode
feat/p08-active-workout
feat/p09-post-workout
feat/p10-discover-refit
feat/p11-friends-feed
feat/p12a-profile-own
feat/p12b-profile-other
feat/p12c-activity
feat/p12d-crew-detail
feat/p13-privacy-trust
feat/p14-home-final
feat/p15a-plus-final
feat/p15b-crews-list-final
feat/p16-onboarding
feat/p17-settings
schema/p01-*  (per migration domain — tag the specific table set)
```

---

## 7c. Final implementation status — 2026-04-27 (later)

**Build:** all changes on `feat/alive` compile via `xcodebuild GymQuest_iOS` for iPhone 16 Pro. 6 migrations queued.

**Beyond the earlier checkpoint, this session added:**

- **LaunchRouter rule 3 live**: `AppState.lastBackgroundedAt` set on `scenePhase != .active`; ContentView passes both `lastBackgroundedAt` and `lastSurface` (mapped via `mapTabToLandingHint`) into `LaunchContext`.
- **Plus tab FriendsTrainingRow real data**: fetches followed users with active `UserPresenceState`, taps land on Friends tab, **long-press → `PartnerInviteSheet`** sheet.
- **Active Workout header**: `WorkoutGhostToggle` + `XWatchingPill` (when broadcasting) + bottom-anchored `FriendsHypedPill` (state-driven).
- **DiscoverFeedView**: 3 sub-tabs **with real routing** (Friends = followed authors only, last 7 days; Tips = videos; Watch = full ranking). All 4 surface audits live (`discoverWatch`, `discoverFriends`, `discoverTips`, `plusWOD`, `onboardingReel`).
- **Discover Streak counter** increments on every Discover post like via `DiscoverStreakService.shared.increment(.clipReacted)`.
- **Profile `YearSoFarCard` real data**: aggregates current-year `Workout` rows for sessions, `totalVolume / 1000` tons, top PR by `newValue`, most-consistent month, total PR event count.
- **Profile other-user `OtherProfilePrimaryActions`** rendered for `isOtherUser`: TRAIN LIKE THEM + LIFT WITH THEM + VS YOU toggle.
- **OnboardingV43View 3-min auto-advance**: step 10 (`addFriendsAfter3Min`) fires automatically after 3 minutes on Watch.
- **OnboardingV43View persistence**: `applyV43OnboardingSelections(_:)` writes `knownFor` → `profile.showUpFor`, `experience` → `profile.experienceLevelRaw`, `savedGymName` → `profile.gymName`.
- **`coliftV43Enabled` FeatureFlag**: default ON; legacy `OnboardingFlow` reachable by toggling off in Settings → Preferences → "Colift v4.3 Design".
- **CLAUDE.md parallel-sessions table**: `feat/alive` row added with status `ready-for-review` and full file list.

**Net session totals:**

| Metric | Count |
|---|---|
| New Swift files | 39 |
| Existing Swift files modified | 17 |
| SQL migrations | 6 |
| Lines added (existing files) | ~1,260 |
| Build green at every checkpoint | yes |
| Commits made | 0 |

**What still gates a fully-shipped v4.3 (each `/gym-feature-slice`-sized):**

1. **Friends Feed wiring** — `LiveSessionCard`, `SuggestedUserCard`, `QuickCommentChipsRow`, pattern-interrupt cards. `FriendsFeedView.swift` is owned by the `home-feed-mix` worktree per CLAUDE.md. Run `/integration-review` ⊕ merge ⊕ wire.
2. **Apply migrations**: `supabase db push` (in `ask` per settings.json).
3. **APNs**: p8 key + Edge Function on user's Apple Developer console.
4. **PresenceServiceTests fix** (pre-existing breakage; `PresenceStatus.done` no longer exists). Out of v4.3 scope but blocks the test target build.
5. **25-user-case audit** per design §14 — manual on-device.

## 7b. Implementation status — 2026-04-27 checkpoint

**Build state:** all changes on `feat/alive` compile via `xcodebuild` for iPhone 16 Pro simulator. 6 migrations queued (forward-only); user-applied via `supabase db push`.

| Phase | State | Notes |
|---|---|---|
| 0. Naming | ✅ shipped | "Today" was already labeled "Home"; "Clubs" → "Crews" in `ContentView`, `FriendsTabView`, `ClubsView` (Search/Create/Find), `FeedVariantsView`. On-disk symbols stay `Clubs*`. |
| 1. Schema | ✅ migrations written | 6 SQL files in `supabase/migrations/2026042712*.sql`. RLS audience-aware. User to apply. |
| 2. Push | ⚠️ partial | `PushTokenService` + `device_tokens` table done. APNs key + Edge Function on user. |
| 3. Smart Landing | ✅ wired | `LaunchRouter` 15-rule dispatcher + `LaunchRouterIntegration` + `ContentView` cold-launch. **15-rule unit tests** under `Tests/Unit/Services/LaunchRouterTests.swift`. |
| 4. Alive Layer | ✅ foundation | `AliveBudget` (max-3), `PresenceRingState` (4 colors + decay), `LiftReaction` vocabulary, `VoiceReactionRecorder` (5-sec hold), `PhotoReactionCapture` (2-sec loop), all in iOS-only-guarded code. |
| 5. Stories | ✅ surfaces | `StoryComposerView` + `StoryViewerView` + `StoryHighlightSlot` `@Model`. Composer/viewer reachable from Settings preview. |
| 6. Messaging | ✅ surfaces | `MessagesListView` + `DMThreadView` + `SquadChatView` + comment quick chips + voice-reaction integrated. Paper-airplane on **Crews tab** (Friends header is locked by `home-feed-mix`). |
| 7. Partner Mode | ✅ surfaces | `PartnerSession` + `PartnerStreak` `@Model`, `PartnerModeService`, `PartnerInviteSheet`, `PartnerActiveHeaderIndicator`. End-to-end runtime hookup in next pass. |
| 8. Active Workout | ✅ wired | Header now has `WorkoutGhostToggle` + `XWatchingPill`; bottom-anchored `FriendsHypedPill`; transformed rest timer + finish moment + PR celebration components ready. |
| 9. Post-Workout | ✅ wired | `EnhancedPostEditorView` has `SmartCaptionChipsRow` + `AnticipationHookBanner`; 9-variant proof picker + `PartnerProofCard` + `WhatsNextCardView` reachable from preview. `ExternalShareWatermark` compositor in place. |
| 10. Discover refit | ✅ wired | `DiscoverSubTabsHeader` (Watch/Friends/Tips) + Discover Streak chip overlayed on actual `DiscoverFeedView`. `DiscoverEngineSurfaceAudit.allow()` audit calls live at 3 of 5 surfaces (Watch / WOD / onboarding reel). |
| 11. Friends Feed | ⚠️ blocked | `LiveSessionCard`, `SuggestedUserCard`, `QuickCommentChipsRow` built; integration into `FriendsFeedView` deferred — file owned by `home-feed-mix` worktree. |
| 12. Identity | ✅ wired | `ProfileV43Header` set rendered below avatar (Live State Line + Year So Far + Training Identity + Privacy pill). `ActivityFilterChipsBar` above activity list. `CrewDetailZones` reachable from preview. |
| 13. Privacy & Trust | ✅ shipped | `PrivacyTrustPanelView` reachable from Settings; full Ghost Mode 4 levels + per-post audience + 16 notification toggles. |
| 14. Home | ✅ partial | `DayOfWeekRitualCard()` between challenges and `GlobalLifterFooter()`. Slot 1 still uses existing top-card priority logic (already roughly satisfies design intent). |
| 15. Plus | ✅ wired | WOD card + music row + friends training row + social proof line + audit call. "lift with friend" pill component exists, runtime hookup next pass. |
| 16. Onboarding | ✅ surface | `OnboardingV43View` (11 steps) reachable from Settings preview. Existing `OnboardingFlow` still runs at cold install. |
| 17. Settings | ✅ wired | `SettingsV43Sections` reachable from existing Settings; `PrivacyTrustShortcutPill`; v4.3 PREVIEW section exposes 12+ design surfaces. |
| 18. Acceptance | ⏳ deferred | Manual on-device pass. Run `xcodebuild test` for `LaunchRouterTests`. |

**File totals**: 39 new Swift files + 6 migrations + 14 existing Swift files modified. **Branch**: `feat/alive`. **Commits/pushes**: 0 / 0.

## 8. Definition of done — final v4.3

The app ships when **every** condition holds:

1. All 17 schema migrations applied; no domain on the spec lacks tables.
2. The 15-priority Smart Landing dispatcher routes every cold launch correctly.
3. Six tier checklists pass per design §12.
4. All 25 user cases verified per design §14.
5. Each page beats its competitor per design §13.
6. Discover Engine scope audit passes (feeds only the 5 allowed surfaces, never the 5 forbidden ones).
7. Authenticity audit: Squad Chat has zero bot speech rows; quiet states stay quiet.
8. Telemetry event coverage = 100% of CC2 list.
9. No design item from this doc is `MISSING` or `PARTIAL` in a re-survey.
10. App store build passes review with all integrations live.
