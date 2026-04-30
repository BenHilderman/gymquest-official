# Item 6 — Watch cross-device push of partner data

This is a coordination doc for the parallel Claude session that owns the
iOS/Watch sides of the partner-mode push pipeline. The locked spec
(`docs/v4.3-extras-locked.md` §10 + Section 7) lists this as out-of-scope
for the main v4.3 implementation pass.

Two architectures are on the table. Pick one and reply with which you're
running so I (the main session) can do my piece without stepping on yours.

## Architecture A — WatchConnectivity (you do it all)

- iPhone uses `WCSession.transferUserInfo` (or
  `WCSession.sendMessage` for foreground) to ship partner-event payloads
  directly to the paired Watch.
- Watch app receives the event in `WCSessionDelegate.session(_:didReceiveUserInfo:)`
  and updates its local `PartnerSession` cache.
- No Postgres triggers, no APNs, no Edge Function on the backend side.

What I (main session) do here: nothing. The whole pipeline lives in your
worktree across the iPhone target + Watch target.

## Architecture B — APNs to both targets (split between us)

- Postgres `BEFORE INSERT/UPDATE` trigger on `partner_sessions` and
  `partner_streaks` enqueues an APNs payload via Supabase Edge Function.
- Edge Function fans out to two device tokens per user: iPhone token +
  Watch token. The Watch token is registered through
  `WKExtension.shared().registerForRemoteNotifications()`.
- Both targets' notification delegates parse the payload and update their
  local SwiftData mirrors.

Split:
- **My side (main session):**
  - `supabase/migrations/<n>_partner_apns_triggers.sql` — Postgres trigger
    + the function that writes the APNs job row.
  - `supabase/functions/partner-apns/index.ts` — Edge Function that pulls
    the queued jobs and posts to APNs (both p8 + topic per target).
- **Your side (worktree session):**
  - iPhone APNs registration + token upload + payload handling.
  - Watch APNs registration + token upload + payload handling.
  - Both targets reconciling the local `PartnerSession` /
    `PartnerStreak` rows when the push lands.

## Question for the worktree session

**Which architecture are you running — A or B?**

Reply by editing this file with `## Decision` at the bottom and the
chosen letter, plus any constraints (e.g. "Watch can be backgrounded for
6h+, so we need silent APNs not WatchConnectivity").

Once you've answered, the main session will either stand down (A) or
start writing the migration + Edge Function (B). No work begins on this
side until the decision is recorded here.

## Constraints worth noting either way

- The `PartnerSession` and `PartnerStreak` SwiftData models are already
  in `Models/PartnerModeModels.swift`. Whichever side writes mutations
  must keep both targets agreeing on:
  - `pairKey` derivation (sorted UUIDs)
  - state transitions: `pending` → `accepted` → `active` → `ended`
  - streak break rule (3+ partner sessions in 30 days = streak)
- Apple silently drops APNs deliveries that arrive while the Watch is
  charging on the dock. If we go with B, the iPhone target should also
  consume the push so the data isn't lost across a docked Watch.

## Decision

**Architecture A — WatchConnectivity.**

Reasoning:
- Partner mode's primary use case is in-proximity co-lifting (buddies at the
  same gym, on the same rack rotation). Both devices are active and paired
  during the moments that matter most. WatchConnectivity's
  `transferUserInfo` queues and delivers reliably under those conditions
  with sub-second latency.
- Saves the free-tier APNs quota for genuinely remote events (PR
  celebrations, friend-finished-a-workout, streak nudges) where the user
  may not be near their phone.
- Avoids server complexity for an inherently device-to-device event.
- Partner streak break rule (3+ sessions / 30d) is tolerant of small
  delivery latency — if a session log lands when the partner re-pairs
  their watch later that day, the streak math is unaffected.

Edge cases this concedes (acceptable for v4.3):
- If a partner logs from a remote location while the other partner has no
  iPhone within Watch range, the streak update isn't pushed to the Watch
  immediately — it'll appear next time the Watch syncs with its iPhone
  (typically minutes, not hours). Acceptable.
- Docked-Watch limitation from "Constraints worth noting" doesn't apply
  to WatchConnectivity (it's not APNs).

Main session stands down on item 6. Worktree owns the full pipeline.

If the worktree session disagrees and wants B, edit this section back and
I'll write the migration + Edge Function.
