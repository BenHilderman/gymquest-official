//
//  ColiftWidgetsBundle.swift
//  ColiftWidgets
//
//  Widget Extension entry point. Two widgets:
//   - ColiftWorkoutLiveActivityWidget: lock-screen + Dynamic Island
//     rendering for own-workout Live Activity.
//   - ColiftActiveFriendsWidget: home/lock-screen tile showing up to 4
//     active friend avatars; tap → deep-links to reaction palette.
//

import WidgetKit
import SwiftUI

@main
struct ColiftWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ColiftWorkoutLiveActivityWidget()
        ColiftActiveFriendsWidget()
    }
}
