import SwiftUI
import WidgetKit

/// The extension targets iOS 18 so the Live Activity can add the small family
/// (CarPlay Dashboard on iOS 26, Apple Watch). On iOS 17 the app still alerts by sound, without the card.
@main
struct ZoneWatchLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        CameraAlertLiveActivity()
    }
}
