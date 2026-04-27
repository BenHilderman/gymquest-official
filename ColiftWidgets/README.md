# ColiftWidgets — Widget Extension setup

The Swift sources here implement the two Alive widgets:

- **`ColiftWorkoutLiveActivityWidget`** — Live Activity card on the lock
  screen + Dynamic Island for the user's own workout. Set count + elapsed
  time + progress.
- **`ColiftActiveFriendsWidget`** — Home/lock-screen tile showing up to
  4 active friend avatars. Each avatar deep-links to
  `liftai://reaction/<userId>`.

The data layer lives in the main app target:

- `ColiftWorkoutAttributes` (`AliveIntegrations.swift`) — the
  `ActivityAttributes` shared by app + widget.
- `ColiftWorkoutLiveActivity` driver — start/update/end called from
  `ActiveWorkoutView`.
- `AliveActiveFriendsBridge` — reads/writes the active-friends snapshot
  via `UserDefaults`. **For production, switch to `UserDefaults(suiteName:
  "group.com.liftai.shared")` so the widget process can read it across
  the App Group boundary.**

## Adding the target in Xcode (≈5 minutes)

1. Open `GymQuest.xcodeproj` in Xcode.
2. **File → New → Target → Widget Extension**.
3. Name it **`ColiftWidgets`**. Check **"Include Live Activity"**.
4. When prompted, **don't** create a fresh source file — Xcode will
   add a default one; delete what it generates.
5. Drag the contents of this `ColiftWidgets/` folder into the new
   target's group:
   - `ColiftWidgetsBundle.swift`
   - `ColiftWorkoutLiveActivityWidget.swift`
   - `ColiftActiveFriendsWidget.swift`
   - `Info.plist` — replace the auto-generated one
6. Select the main app target → **Build Phases → Embed Foundation
   Extensions** → confirm `ColiftWidgets.appex` is listed (Xcode does
   this automatically for new Widget Extension targets).
7. Select `ColiftWorkoutAttributes.swift` (in main app's
   `Components/Alive/AliveIntegrations.swift` — search for the type)
   → **File Inspector → Target Membership** → check both
   `GymQuest_iOS` AND `ColiftWidgets`. Same for
   `AliveActiveFriendsBridge` (same file).
8. **Edit Scheme** → ensure both the app and widget targets build.
9. (Optional, for production) **Signing & Capabilities** on both
   targets → add an **App Group**: `group.com.liftai.shared`. Update
   `AliveActiveFriendsBridge` to use
   `UserDefaults(suiteName: "group.com.liftai.shared")` instead of
   `UserDefaults.standard` so the widget can read across the process
   boundary.

## What unlocks after the target is added

- Live Activity automatically appears on lock screen + Dynamic Island
  the moment the user starts a workout in the app — driver code is
  already wired.
- Active Friends widget appears in the widget gallery; user adds it to
  home/lock screen.
- All four checklist items #10 + #11 from the Alive spec close.

## What to verify

- Start a workout → Live Activity appears on lock screen.
- Add the Active Friends widget → it shows up to 4 active friend
  avatars (cycle stale by 5 min via timeline `policy: .after`).
- Tap an avatar on the widget → app opens, navigates to the reaction
  palette pre-targeted to that friend (deep link handler may need
  to be wired in `LiftAIApp.scene(_:openURLContexts:)` if it isn't
  already — search for `URL.scheme == "liftai"`).
