import AVFoundation
import CoreMotion
import Observation
import ZoneWatchKit

/// Feeds motion activity, CarPlay connection and speed into `DriveStateMachine`.
@MainActor
@Observable
final class DriveDetector {
    private(set) var isDriving = false
    private(set) var activityText = "Unknown"
    private(set) var carPlayConnected = false

    /// Lets testing in the simulator (which has no motion data) start a drive by hand.
    var manualOverride = false {
        didSet { publish() }
    }

    @ObservationIgnored var onChange: ((Bool) -> Void)?
    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private var machine = DriveStateMachine()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var routeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var lastRecentActivityCheck = Date.distantPast

    func start() {
        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                let automotive = activity.automotive
                let confident = activity.confidence != .low
                let text = Self.describe(activity)
                MainActor.assumeIsolated {
                    self?.activityText = text
                    self?.handle(.motion(automotive: automotive, confident: confident))
                }
            }
        } else {
            activityText = "Motion not available (simulator)"
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAudioRoute() }
        }
        checkAudioRoute()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func noteSpeed(_ metersPerSecond: Double) {
        guard metersPerSecond >= 0 else { return }
        handle(.speed(metersPerSecond: metersPerSecond))
    }

    /// After a background wake-up, ask Core Motion whether the last few minutes were in a vehicle.
    func checkRecentActivity() {
        let now = Date()
        guard !isDriving, CMMotionActivityManager.isActivityAvailable(),
              now.timeIntervalSince(lastRecentActivityCheck) > 60 else { return }
        lastRecentActivityCheck = now
        motion.queryActivityStarting(from: now.addingTimeInterval(-180), to: now, to: .main) { [weak self] activities, _ in
            let driving = activities?.contains { $0.automotive && $0.confidence != .low } ?? false
            MainActor.assumeIsolated {
                if driving { self?.handle(.motion(automotive: true, confident: true)) }
            }
        }
    }

    private func checkAudioRoute() {
        let connected = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
        guard connected != carPlayConnected else { return }
        carPlayConnected = connected
        handle(.carPlay(connected: connected))
    }

    private func handle(_ input: DriveStateMachine.Input) {
        if machine.handle(input, at: Date()) != nil { publish() }
    }

    private func tick() {
        if machine.tick(at: Date()) != nil { publish() }
    }

    private func publish() {
        let driving = machine.isDriving || manualOverride
        guard driving != isDriving else { return }
        isDriving = driving
        onChange?(driving)
    }

    private nonisolated static func describe(_ activity: CMMotionActivity) -> String {
        let kind = activity.automotive ? "Driving"
            : activity.cycling ? "Cycling"
            : activity.running ? "Running"
            : activity.walking ? "Walking"
            : activity.stationary ? "Stationary" : "Unknown"
        let confidence = switch activity.confidence {
        case .high: "high"
        case .medium: "medium"
        default: "low"
        }
        return "\(kind) (\(confidence) confidence)"
    }
}
