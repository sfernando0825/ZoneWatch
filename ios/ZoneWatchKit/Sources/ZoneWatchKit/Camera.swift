/// One enforcement camera site.
public struct Camera: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: CameraType
    public var coordinate: Coordinate
    /// Direction of travel the camera enforces, in degrees. Nil means both directions.
    public var enforcedHeading: Double?
    public var road: String
    public var speedLimitKmh: Int?

    public init(
        id: String,
        type: CameraType,
        coordinate: Coordinate,
        enforcedHeading: Double?,
        road: String,
        speedLimitKmh: Int?
    ) {
        self.id = id
        self.type = type
        self.coordinate = coordinate
        self.enforcedHeading = enforcedHeading
        self.road = road
        self.speedLimitKmh = speedLimitKmh
    }
}
