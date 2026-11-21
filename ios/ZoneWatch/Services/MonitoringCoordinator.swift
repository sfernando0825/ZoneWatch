import CoreLocation
import Observation
import ZoneWatchKit

/// Ties the pieces together: a detected drive starts tracking, each location goes through the point
/// camera and zone triggers, an alert plays the alarm and updates the Live Activity, and the drive is recorded.
@MainActor
@Observable
final class MonitoringCoordinator {
    static let shared = MonitoringCoordinator()

    let location = LocationService()
    let drive = DriveDetector()
    let audio = AudioAlerts()
    let liveActivity = LiveActivityController()
    let recorder = DriveRecorder()
    let cameras = CameraData()

    private(set) var status = AlertStatus.monitoring
    private(set) var speedKmh: Double?

    @ObservationIgnored private var trigger = ProximityTrigger(cameras: [])
    @ObservationIgnored private var zoneTrigger = ZoneTrigger(zones: [])
    @ObservationIgnored private var estimator = MotionEstimator()
    @ObservationIgnored private var booted = false

    private init() {}

    /// Called once per launch, including background relaunches by Core Location.
    func boot(launchedForLocation: Bool) {
        guard !booted else { return }
        booted = true

        cameras.load()
        location.onLocation = { [weak self] location in self?.handle(location) }
        drive.onChange = { [weak self] driving in
            if driving { self?.driveStarted() } else { self?.driveEnded() }
        }
        drive.start()
        liveActivity.adoptExisting()
        location.startWakeMonitoring()
        recorder.log(launchedForLocation ? "Relaunched by iOS for a location event" : "App launched")
        if let dataset = cameras.dataset {
            recorder.log("Cameras: \(cameras.source) dataset \(dataset.version), \(dataset.cameras.count) points, \(dataset.zones.count) zones")
        }
        if let error = cameras.lastError { recorder.log("Camera data: \(error)") }
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
        let set = cameras.alertSet()
        trigger = ProximityTrigger(cameras: set.cameras)
        zoneTrigger = ZoneTrigger(zones: set.zones)
        recorder.log("Watching \(set.cameras.count) cameras and \(set.zones.count) zones"
            + (cameras.usePrototypeCameras ? " (prototype test points)" : ""))
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
        for event in zoneTrigger.update(with: fix) {
            switch event {
            case let .approaching(zone, distance):
                audio.play(.forCamera(zone.type))
                recorder.log("Alert: \(zone.type.zoneName) starts in \(Int(distance)) m, \(zone.road)\(zone.suburb.map { ", \($0)" } ?? "")")
                if let error = audio.lastError { recorder.log("Audio: \(error)") }
            case let .entered(zone):
                audio.play(.forCamera(zone.type))
                recorder.log("Alert: joined \(zone.type.zoneName), \(zone.road)\(zone.suburb.map { ", \($0)" } ?? "")")
                if let error = audio.lastError { recorder.log("Audio: \(error)") }
            case let .left(zone):
                recorder.log("Left \(zone.type.zoneName), \(zone.road)")
            }
        }

        status = currentStatus(for: fix)
        liveActivity.update(status)
    }

    /// A point camera or zone start ahead wins over a zone the vehicle is already in, nearest first.
    private func currentStatus(for fix: VehicleFix) -> AlertStatus {
        let point = trigger.nearestActive(from: fix)
        let zone = zoneTrigger.current(from: fix)
        let overLimit: (Int?) -> Bool = { limit in limit.map { Double($0) < (self.speedKmh ?? 0) } ?? false }

        if let point, zone == nil || zone!.inside || point.distance <= zone!.distance {
            let camera = point.camera
            return AlertStatus(
                phase: overLimit(camera.speedLimitKmh) ? .overLimit : .cameraAhead,
                cameraType: camera.type,
                road: camera.road,
                // Rounded so the Live Activity only updates when the shown distance changes.
                distanceMeters: (point.distance / 50).rounded() * 50,
                speedLimitKmh: camera.speedLimitKmh
            )
        }
        guard let zone else { return .monitoring }
        return AlertStatus(
            phase: overLimit(zone.zone.speedLimitKmh) ? .overLimit : .cameraAhead,
            cameraType: zone.zone.type,
            road: zone.zone.road,
            distanceMeters: zone.inside ? nil : (zone.distance / 50).rounded() * 50,
            speedLimitKmh: zone.zone.speedLimitKmh,
            inZone: zone.inside ? true : nil
        )
    }
}
