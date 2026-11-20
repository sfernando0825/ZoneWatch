import ActivityKit
import SwiftUI
import WidgetKit
import ZoneWatchKit

/// Lock Screen, Dynamic Island, and the small family used by CarPlay Dashboard and Apple Watch.
struct CameraAlertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CameraAlertAttributes.self) { context in
            FamilyAwareView(status: context.state)
        } dynamicIsland: { context in
            CameraAlertIsland.make(status: context.state)
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct FamilyAwareView: View {
    @Environment(\.activityFamily) private var family
    let status: AlertStatus

    var body: some View {
        switch family {
        case .small:
            SmallView(status: status)
        default:
            LockScreenView(status: status)
        }
    }
}

private enum CameraAlertIsland {
    static func make(status: AlertStatus) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                StatusIcon(status: status)
            }
            DynamicIslandExpandedRegion(.trailing) {
                if let distance = status.distanceText {
                    Text(distance).font(.title3.bold()).monospacedDigit()
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(alignment: .leading) {
                    Text(status.headline).font(.headline)
                    if let road = status.road {
                        Text(road).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } compactLeading: {
            StatusIcon(status: status)
        } compactTrailing: {
            if let distance = status.distanceText {
                Text(distance).monospacedDigit()
            }
        } minimal: {
            StatusIcon(status: status)
        }
    }
}

private struct StatusIcon: View {
    let status: AlertStatus

    var body: some View {
        Image(systemName: status.phase == .monitoring ? "location.fill" : "camera.fill")
            .foregroundStyle(status.phase == .overLimit ? .red : .orange)
            .accessibilityHidden(true)
    }
}

/// Lock Screen banner: camera type, road and distance.
private struct LockScreenView: View {
    let status: AlertStatus

    var body: some View {
        HStack(spacing: 12) {
            StatusIcon(status: status).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.headline).font(.headline)
                if let road = status.road {
                    Text(road).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let distance = status.distanceText {
                Text(distance).font(.title2.bold()).monospacedDigit()
            }
        }
        .padding()
    }
}

/// Small family (CarPlay Dashboard, Apple Watch): as few words as possible, readable at a glance.
private struct SmallView: View {
    let status: AlertStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                StatusIcon(status: status)
                if let distance = status.distanceText {
                    Text(distance).font(.headline).monospacedDigit()
                }
            }
            Text(status.headline).font(.caption).lineLimit(2)
        }
        .padding(8)
    }
}
