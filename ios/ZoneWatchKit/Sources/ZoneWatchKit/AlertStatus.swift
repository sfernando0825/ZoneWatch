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

    public init(
        phase: Phase,
        cameraType: CameraType? = nil,
        road: String? = nil,
        distanceMeters: Double? = nil,
        speedLimitKmh: Int? = nil
    ) {
        self.phase = phase
        self.cameraType = cameraType
        self.road = road
        self.distanceMeters = distanceMeters
        self.speedLimitKmh = speedLimitKmh
    }

    public static let monitoring = AlertStatus(phase: .monitoring)

    /// One line for the Live Activity, e.g. "Mobile camera ahead".
    public var headline: String {
        let name = cameraType?.displayName ?? "Camera"
        switch phase {
        case .monitoring: return "Monitoring"
        case .cameraAhead: return "\(name) ahead"
        case .overLimit: return "Check your speed: \(name.lowercased()) ahead"
        }
    }

    /// Distance rounded for a glance: "600 m" under 1 km, "1.2 km" above. Nil when unknown.
    public var distanceText: String? {
        guard let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0 else { return nil }
        let roundedMeters = Int((distanceMeters / 50).rounded()) * 50
        if roundedMeters < 1_000 {
            return "\(roundedMeters) m"
        }
        let tenths = (distanceMeters / 100).rounded() / 10
        return "\(tenths.formatted(.number.precision(.fractionLength(1)))) km"
    }
}
