/// The kinds of enforcement camera ZoneWatch warns about.
public enum CameraType: String, Codable, Hashable, Sendable, CaseIterable {
    case fixedSpeed
    case redLightSpeed
    case pointToPointStart
    case pointToPointEnd
    case mobileSpeed
    /// SA sites are labelled phone cameras until seatbelt enforcement is confirmed.
    case phoneCamera
    case phoneAndSeatbeltCamera

    /// Short name shown on the Live Activity and in lists.
    public var displayName: String {
        switch self {
        case .fixedSpeed: "Speed camera"
        case .redLightSpeed: "Red light camera"
        case .pointToPointStart: "Average speed zone"
        case .pointToPointEnd: "Average speed zone ends"
        case .mobileSpeed: "Mobile camera"
        case .phoneCamera: "Phone camera"
        case .phoneAndSeatbeltCamera: "Phone and seatbelt camera"
        }
    }
}
