/// What the Live Activity shows. Kept free of ActivityKit so it can be tested on macOS.
public struct AlertStatus: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Hashable, Sendable {
        case monitoring
        case cameraAhead
        case overLimit
    }

    public var phase: Phase
    public var cameraType: CameraType?
    public var road: String?
    public var distanceMeters: Double?
    public var speedLimitKmh: Int?
    /// True while driving inside a camera zone (a stretch of road rather than a point). Optional so
    /// statuses encoded by older builds still decode.
    public var inZone: Bool?

    public init(
        phase: Phase,
        cameraType: CameraType? = nil,
        road: String? = nil,
        distanceMeters: Double? = nil,
        speedLimitKmh: Int? = nil,
        inZone: Bool? = nil
    ) {
        self.phase = phase
        self.cameraType = cameraType
        self.road = road
        self.distanceMeters = distanceMeters
        self.speedLimitKmh = speedLimitKmh
        self.inZone = inZone
    }

    public static let monitoring = AlertStatus(phase: .monitoring)

    /// One line for the Live Activity, e.g. "Mobile camera ahead".
    public var headline: String {
        let name = cameraType?.displayName ?? "Camera"
        if inZone == true, phase != .monitoring {
            let zone = cameraType?.zoneName ?? "Camera zone"
            return phase == .overLimit ? "Check your speed: \(zone.lowercased())" : zone
        }
        switch phase {
        case .monitoring: return "Monitoring"
        case .cameraAhead: return "\(name) ahead"
        case .overLimit: return "Check your speed: \(name.lowercased()) ahead"
        }
    }

    /// Distance rounded for a glance: "600 m" under 1 km, "1.2 km" above. Nil when unknown.
    public var distanceText: String? {
        guard inZone != true, let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0 else { return nil }
        let roundedMeters = Int((distanceMeters / 50).rounded()) * 50
        if roundedMeters < 1_000 {
            return "\(roundedMeters) m"
        }
        let tenths = (distanceMeters / 100).rounded() / 10
        return "\(tenths.formatted(.number.precision(.fractionLength(1)))) km"
    }
}
