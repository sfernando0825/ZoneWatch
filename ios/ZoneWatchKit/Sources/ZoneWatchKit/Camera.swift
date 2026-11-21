/// One enforcement camera at a known point.
public struct Camera: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: CameraType
    public var coordinate: Coordinate
    /// Direction of travel the camera enforces, in degrees. Nil means every direction.
    public var enforcedHeading: Double?
    public var road: String
    public var suburb: String?
    public var speedLimitKmh: Int?

    public init(
        id: String,
        type: CameraType,
        coordinate: Coordinate,
        enforcedHeading: Double?,
        road: String,
        suburb: String? = nil,
        speedLimitKmh: Int?
    ) {
        self.id = id
        self.type = type
        self.coordinate = coordinate
        self.enforcedHeading = enforcedHeading
        self.road = road
        self.suburb = suburb
        self.speedLimitKmh = speedLimitKmh
    }
}

/// A stretch of road where a camera operates somewhere along it: a mobile camera site, a fixed
/// camera whose exact spot isn't published, or a whole average speed section.
public struct CameraZone: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: CameraType
    /// One or more polylines along the road.
    public var paths: [[Coordinate]]
    /// True when only travel in the direction the (single) path is drawn is enforced.
    public var oneWay: Bool
    public var road: String
    public var suburb: String?
    public var speedLimitKmh: Int?

    public init(
        id: String,
        type: CameraType,
        paths: [[Coordinate]],
        oneWay: Bool,
        road: String,
        suburb: String? = nil,
        speedLimitKmh: Int?
    ) {
        self.id = id
        self.type = type
        self.paths = paths
        self.oneWay = oneWay
        self.road = road
        self.suburb = suburb
        self.speedLimitKmh = speedLimitKmh
    }
}
