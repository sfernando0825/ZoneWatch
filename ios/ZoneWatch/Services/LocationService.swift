import CoreLocation
import Observation
import UIKit

/// Core Location wrapper: "Always" permission, full-accuracy tracking during a drive, and
/// significant-change monitoring so iOS relaunches ZoneWatch after it has been stopped.
@MainActor
@Observable
final class LocationService: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastLocation: CLLocation?
    private(set) var isTracking = false
    private(set) var lastError: String?

    @ObservationIgnored var onLocation: ((CLLocation) -> Void)?
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var authorizationText: String {
        switch authorization {
        case .notDetermined: "Not asked yet"
        case .restricted: "Restricted"
        case .denied: "Denied: turn on in Settings"
        case .authorizedWhenInUse: "While Using only: background alerts need Always"
        case .authorizedAlways: "Always"
        @unknown default: "Unknown"
        }
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Full-accuracy updates for a drive, including in the background with the screen locked.
    func startTracking() {
        guard !isTracking else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isTracking = true
        startBackgroundSessionIfActive()
    }

    func stopTracking() {
        guard isTracking else { return }
        manager.stopUpdatingLocation()
        backgroundSession?.invalidate()
        backgroundSession = nil
        isTracking = false
    }

    /// Low-power wake-ups (about every 500 m) that relaunch the app if iOS has stopped it.
    func startWakeMonitoring() {
        guard authorization == .authorizedAlways,
              CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    /// A background activity session (iOS 17) can only be created while the app is in the foreground.
    func startBackgroundSessionIfActive() {
        guard isTracking, backgroundSession == nil, UIApplication.shared.applicationState == .active else { return }
        backgroundSession = CLBackgroundActivitySession()
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            if status == .authorizedAlways { startWakeMonitoring() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            for location in locations {
                lastLocation = location
                onLocation?(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { lastError = message }
    }
}
