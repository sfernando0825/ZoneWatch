import CoreLocation
import Observation
import ZoneWatchKit

/// Ties the Phase 1 pieces together: a detected drive starts tracking, each location goes through the
/// proximity trigger, an approach plays the alarm and updates the Live Activity, and the drive is recorded.
@MainActor
@Observable
final class MonitoringCoordinator {
    static let shared = MonitoringCoordinator()

    let location = LocationService()
    let drive = DriveDetector()
    let audio = AudioAlerts()
    let liveActivity = LiveActivityController()
    let recorder = DriveRecorder()

    private(set) var status = AlertStatus.monitoring
    private(set) var speedKmh: Double?

    @ObservationIgnored private var trigger = ProximityTrigger(cameras: PrototypeCameras.adelaideTest)
    @ObservationIgnored private var estimator = MotionEstimator()
    @ObservationIgnored private var booted = false

    private init() {}

    /// Called once per launch, including background relaunches by Core Location.
    func boot(launchedForLocation: Bool) {
        guard !booted else { return }
        booted = true

        location.onLocation = { [weak self] location in self?.handle(location) }
        drive.onChange = { [weak self] driving in
            if driving { self?.driveStarted() } else { self?.driveEnded() }
        }
        drive.start()
        liveActivity.adoptExisting()
        location.startWakeMonitoring()
        recorder.log(launchedForLocation ? "Relaunched by iOS for a location event" : "App launched")
        Task { await audio.prepare() }

        // Automated simulator tests: launch with `-ZWStartTestDrive YES`.
        if UserDefaults.standard.bool(forKey: "ZWStartTestDrive") {
            drive.manualOverride = true
        }
    }

    /// Things iOS only allows in the foreground.
    func appBecameActive() {
        location.startBackgroundSessionIfActive()
        if drive.isDriving, !liveActivity.isRunning {
            liveActivity.start(status)
        }
    }

    func testAlarm() {
        audio.play(.test)
        recorder.log("Test alarm played (media volume \(Int(audio.outputVolume * 100))%)")
    }

    private func driveStarted() {
        recorder.begin()
        trigger = ProximityTrigger(cameras: PrototypeCameras.adelaideTest)
        estimator = MotionEstimator()
        status = .monitoring
        location.startTracking()
        liveActivity.start(status)
        if let error = liveActivity.lastError { recorder.log("Live Activity: \(error)") }
        if audio.outputVolume == 0 { recorder.log("Warning: media volume is 0, alerts will be silent") }
    }

    private func driveEnded() {
        location.stopTracking()
        liveActivity.end()
        recorder.finish()
        status = .monitoring
        speedKmh = nil
    }

    private func handle(_ location: CLLocation) {
        drive.noteSpeed(location.speed)
        guard drive.isDriving else {
            drive.checkRecentActivity()
            return
        }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return }

        let fix = estimator.refine(VehicleFix(
            coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            speed: location.speed,
            course: location.course,
            timestamp: location.timestamp
        ))
        recorder.record(fix)
        speedKmh = fix.speed >= 0 ? fix.speed * 3.6 : nil

        for event in trigger.update(with: fix) {
            switch event {
            case let .approaching(camera, distance):
                audio.play(.forCamera(camera.type))
                recorder.log("Alert: \(camera.type.displayName), \(Int(distance)) m, \(camera.road)")
                if let error = audio.lastError { recorder.log("Audio: \(error)") }
            case let .passed(camera):
                recorder.log("Passed \(camera.road)")
            }
        }

        status = currentStatus(for: fix)
        liveActivity.update(status)
    }

    private func currentStatus(for fix: VehicleFix) -> AlertStatus {
        guard let active = trigger.nearestActive(from: fix) else { return .monitoring }
        let camera = active.camera
        let overLimit = camera.speedLimitKmh.map { Double($0) < (speedKmh ?? 0) } ?? false
        return AlertStatus(
            phase: overLimit ? .overLimit : .cameraAhead,
            cameraType: camera.type,
            road: camera.road,
            // Rounded so the Live Activity only updates when the shown distance changes.
            distanceMeters: (active.distance / 50).rounded() * 50,
            speedLimitKmh: camera.speedLimitKmh
        )
    }
}
