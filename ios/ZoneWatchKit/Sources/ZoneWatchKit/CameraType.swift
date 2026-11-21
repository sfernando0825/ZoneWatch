/// The kinds of enforcement camera ZoneWatch warns about.
public enum CameraType: String, Codable, Hashable, Sendable, CaseIterable {
    case fixedSpeed
    case redLightSpeed
    case pointToPointStart
    case pointToPointEnd
    /// A whole average speed section, enforced in the direction its path is drawn.
    case averageSpeedSection
    case mobileSpeed
    /// SA sites are labelled phone cameras until seatbelt enforcement is confirmed.
    case phoneCamera
    case phoneAndSeatbeltCamera

    /// Short name shown on the Live Activity and in lists.
    public var displayName: String {
        switch self {
        case .fixedSpeed: "Speed camera"
        case .redLightSpeed: "Red light camera"
        case .pointToPointStart, .averageSpeedSection: "Average speed zone"
        case .pointToPointEnd: "Average speed zone ends"
        case .mobileSpeed: "Mobile camera"
        case .phoneCamera: "Phone camera"
        case .phoneAndSeatbeltCamera: "Phone and seatbelt camera"
        }
    }

    /// Shown while driving inside a stretch of road where this kind of camera operates.
    public var zoneName: String {
        switch self {
        case .pointToPointStart, .pointToPointEnd, .averageSpeedSection: "Average speed zone"
        case .mobileSpeed: "Mobile camera site"
        default: "\(displayName) zone"
        }
    }
}
