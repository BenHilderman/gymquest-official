# CoLift Maya MVP — QA Checklist

For the validation test build (`validationMVPEnabled = true`). Walk this list before handing the build to testers, then again after any change.

## Quick start

```bash
xcodebuild -project GymQuest.xcodeproj -scheme GymQuest_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath build_smoke build
xcrun simctl install booted build_smoke/Build/Products/Debug-iphonesimulator/GymQuest.app
xcrun simctl launch booted com.colift.app
```

The MVP flag defaults to true. To access the legacy full app for engineering work, flip `validationMVPEnabled` to false via debug settings.

## Set a research participant id (optional)

```bash
xcrun simctl spawn booted defaults write com.colift.app mayaParticipantId "p001"
```

Clears with:

```bash
xcrun simctl spawn booted defaults delete com.colift.app mayaParticipantId
```

## Reset local MVP state between sessions

In code (debug-only affordance): `MayaSessionStore.resetMVPState(in: modelContext)` deletes all SavedWin rows and the RunItBackState row.

In simctl: uninstall + reinstall the app:
```bash
xcrun simctl uninstall booted com.colift.app
```

## Manual acceptance checks

### Cold Start
- [ ] App launches directly to Cold Start (no auth screen, no tab bar)
- [ ] Wordmark "CoLift" renders in italic with brand gradient
- [ ] Headline reads `Don't lift\nalone.`
- [ ] Subhead reads `Start with Maya. No invite needed.`
- [ ] Differentiator line reads `made for days your friends can't lift with you`
- [ ] Replay card eyebrow reads `REPLAY` with `⟲` icon
- [ ] Default selected replay: `Upper Reset` · `22 min · no invite needed`
- [ ] Maya identity line: `M` avatar + `Maya` + `GUIDED REPLAY`
- [ ] Cue preview label reads `MAYA'S FORM CUE`
- [ ] Cue preview body reads `lower slow · stop before your shoulders shrug`
- [ ] Beginner hint chip reads `good first lift`
- [ ] Primary CTA reads `Start Replay →` with brand gradient fill
- [ ] Chip section header reads `pick today's replay`
- [ ] Five chips render in this order: `good first lift` (selected) · `returning after a break` · `upper body` · `lower body` · `quick lift`
- [ ] Selected chip uses violet text + soft brand gradient backdrop + violet border
- [ ] Tapping a chip updates the card title + meta + cue preview body in place
- [ ] Privacy summary pill reads `🔒 private by default · no strangers · you choose what friends see`
- [ ] Bridge line reads `🌿 Maya helps solo days · friends can leave real replays too`

### Active Replay · standard set
- [ ] Header shows pause button + `M Maya · Upper Reset` + `exercise N of 5 · X min in`
- [ ] Now-lifting card has a 3pt Maya-gradient stripe at the top
- [ ] Eyebrow reads `⚡ NOW LIFTING`
- [ ] Demo silhouette renders with a subtle violet motion bar
- [ ] Meta line includes set count, rep target, and last-set context when applicable
- [ ] Set indicator grid renders three boxes: done (✓), current (`go`), pending (`—`)
- [ ] Cue card label reads `MAYA'S FORM CUE` with `M` avatar
- [ ] Cue body matches the current exercise's `primaryFormCue`
- [ ] Primary CTA reads `✓ I did it`, 60pt tall, brand gradient
- [ ] Tertiary reads `skip · adjust weight`

### Active Replay · final set
- [ ] Header subtext shows `last set` instead of elapsed time
- [ ] Meta line includes `this is the last one`
- [ ] Demo silhouette is suppressed
- [ ] Third indicator box uses the brand-gradient `LAST SET · go` styling
- [ ] Cue card label reads `MAYA'S FORM CUE · LAST SET`
- [ ] Cue body matches the current exercise's `finalSetCue`
- [ ] Tapping `I did it` on the last set of the last exercise navigates to Shared Win completion

### Rest state
- [ ] Header reads `M Maya · Upper Reset` + `resting between sets`
- [ ] Eyebrow reads `MAYA'S PACE` with `M` avatar
- [ ] Conic-gradient timer ring renders, starts at `0:42`, counts down per second
- [ ] Pace line reads `rest here · one clean set left`
- [ ] Note card: `M` avatar + `MAYA'S NOTE` + current exercise's `restCue`
- [ ] Up-next card shows next exercise name + next set number
- [ ] Primary CTA reads `Start set N →` (violet outline variant)
- [ ] Tertiary reads `rest a bit longer`
- [ ] Tapping `Start set N` advances back to Active Replay before timer reaches zero
- [ ] No notification permission prompt fires
- [ ] No music, voice, photo, video, or reactions render

### Shared Win · completion
- [ ] Eyebrow reads `REPLAY COMPLETE`
- [ ] 🫶 emoji renders at 56pt
- [ ] Headline reads `You showed up` with the warm gradient accent on `showed up`
- [ ] Subhead reads `Upper Reset · 22 min`
- [ ] Question line reads `Save this win?`
- [ ] Value line reads `save this so tomorrow starts here`
- [ ] Privacy pill reads `🔒 saved privately · only you can see this`
- [ ] Primary CTA reads `Save Win` (brand gradient)
- [ ] Tertiary reads `Not now`
- [ ] No `Share`, `Send`, `Story`, `Thank Maya`, `Maya reacted`, `friend reaction` surfaces

### Shared Win · saved
- [ ] Eyebrow reads `WIN SAVED`
- [ ] Headline reads `Saved`
- [ ] Subhead reads `we'll keep it ready · tap when you open the app tomorrow`
- [ ] Saved card label reads `✓ SAVED PRIVATELY`, replay title shown, meta `showed up · 22 min · 5/5 exercises`
- [ ] Bridge line reads `🌿 Friends can leave real replays later.`
- [ ] Primary CTA reads `Run It Back` (warm gradient: violet → pink)
- [ ] Secondary CTA reads `Try another Maya replay`
- [ ] Tapping `Run It Back` queues the same replay (verify via `MayaSessionStore.peekQueuedReplay`)
- [ ] Tapping `Try another Maya replay` clears any queued replay and returns to Cold Start with default chip selected
- [ ] Neither path schedules a notification or calendar item

### Second-session behavior
- [ ] After tapping `Run It Back` and relaunching the app, Cold Start preselects the saved replay's chip
- [ ] Headline still reads `Don't lift\nalone.` (no "you've been gone" copy)
- [ ] No shame copy: no `you failed`, `you missed`, `streak at risk`, `don't break it`
- [ ] No notification fires before app open

### Privacy + notifications
- [ ] Notification permission prompt never appears in the MVP flow
- [ ] No friend-activity, no friend-just-finished, no async-invite messages render
- [ ] No exact gym names render
- [ ] No watcher counts render
- [ ] No "Sarah is watching you" or similar surveillance copy
- [ ] SavedWin rows have `isPrivate = true` (verify in SwiftData inspector)

### Hidden legacy surfaces
- [ ] No bottom tab bar
- [ ] No Discover, Crews, Squads, Watch, Profile, DMs, Stories, comments, music player, voice notes, photo/video capture, leaderboards, XP, badges, streak pressure, contacts import accessible from the MVP flow

## Banned-copy scan

Run from the repo root to confirm no banned strings landed in the Maya MVP source files:

```bash
banned=("template" "copy workout" "routine library" "program" "AI plan"
        "trending" "viral" "most popular" "leaderboard" "XP "
        "streak at risk" "don't break it" "you failed" "you missed"
        "crush" "beast mode" "shred" "transformation"
        "calories" "weight loss" "Sarah is watching"
        "Maya reacted" "Maya is proud" "Thank Maya" "Message Maya" "Follow Maya"
        "@colift" "CoLift guide" "Maya's CoLift Replay"
        "share to story" "TikTok" "Instagram" "DM "
        "strangers can watch")

for term in "${banned[@]}"; do
  result=$(grep -RIn --include="*.swift" "$term" GymQuest/Views/Maya GymQuest/Models/Maya GymQuest/Services/Maya 2>/dev/null)
  if [ -n "$result" ]; then
    echo "BANNED HIT: '$term'"
    echo "$result"
    echo
  fi
done
echo "Banned-copy scan complete."
```

A clean MVP build emits zero `BANNED HIT` lines.

## Research event verification

In debug builds, every screen logs to console with the `[research]` prefix and persists the buffer to `~/Library/Caches/research-events.json` inside the app sandbox. Required events:

- `app_opened`
- `cold_start_viewed`
- `replay_chip_selected`
- `start_replay_tapped`
- `active_replay_viewed`
- `set_completed`
- `rest_started`
- `rest_completed`
- `rest_extended`
- `next_set_started`
- `exercise_completed`
- `workout_completed`
- `shared_win_viewed`
- `save_win_tapped`
- `not_now_tapped`
- `saved_screen_viewed`
- `run_it_back_tapped`
- `try_another_replay_tapped`
- `session_abandoned`
- `skip_adjust_tapped`
- `notification_default_off_verified` (debug-only)

## Known gaps / TODOs

- The Maya MVP intentionally drops mid-session if the app is closed (Resume Card is in the deferred manifest).
- Exercise demo silhouettes use a single generic dumbbell glyph; per-exercise art is in the deferred manifest.
- Coach-tone, cycle-phase, and other psychology-pass surfaces from the legacy build are not accessible in the MVP route.
- The headline gradient accent on `showed up` uses a solid color in the SwiftUI native build (gradient on `AttributedString` body is not directly supported without a custom renderer).
