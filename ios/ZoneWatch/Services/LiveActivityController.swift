import ActivityKit
import Observation
import ZoneWatchKit

/// Starts, updates and ends the camera Live Activity. Updates are local (no push server).
@MainActor
@Observable
final class LiveActivityController {
    private(set) var isRunning = false
    private(set) var lastError: String?

    @ObservationIgnored private var activity: Activity<CameraAlertAttributes>?
    @ObservationIgnored private var lastStatus: AlertStatus?

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Picks up an activity left running from before the app was relaunched.
    func adoptExisting() {
        activity = Activity<CameraAlertAttributes>.activities.first
        isRunning = activity != nil
    }

    /// iOS may refuse to start an activity while the app is in the background; the caller retries when it is next opened.
    func start(_ status: AlertStatus) {
        if activity != nil {
            update(status)
            return
        }
        guard areActivitiesEnabled else {
            lastError = "Live Activities are turned off for ZoneWatch in Settings"
            return
        }
        do {
            activity = try Activity.request(
                attributes: CameraAlertAttributes(),
                content: ActivityContent(state: status, staleDate: nil),
                pushType: nil
            )
            lastStatus = status
            isRunning = true
            lastError = nil
        } catch {
            lastError = "Could not start: \(error.localizedDescription)"
        }
    }

    func update(_ status: AlertStatus) {
        guard let activity, status != lastStatus else { return }
        lastStatus = status
        Task {
            await activity.update(ActivityContent(state: status, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        lastStatus = nil
        isRunning = false
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
