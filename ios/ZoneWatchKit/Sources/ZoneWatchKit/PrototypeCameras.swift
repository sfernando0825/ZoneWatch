/// Phase 1 test data only. These are made-up points for testing the alert trigger,
/// NOT real camera locations. Phase 2 replaces them with the SAPOL dataset.
public enum PrototypeCameras {
    /// An approximate south-west run down Anzac Highway, from the city edge to Glenelg.
    public static let anzacHighwayRoute: [Coordinate] = [
        Coordinate(latitude: -34.9365, longitude: 138.5900),
        Coordinate(latitude: -34.9440, longitude: 138.5790),
        Coordinate(latitude: -34.9510, longitude: 138.5690),
        Coordinate(latitude: -34.9560, longitude: 138.5600),
        Coordinate(latitude: -34.9620, longitude: 138.5500),
        Coordinate(latitude: -34.9690, longitude: 138.5390),
        Coordinate(latitude: -34.9760, longitude: 138.5270),
        Coordinate(latitude: -34.9800, longitude: 138.5160),
    ]

    /// Heading of travel along the route towards Glenelg, in degrees.
    public static let towardsGlenelg = 234.0
    public static let towardsCity = 54.0

    /// Ten test points: six on the route (one facing the other way, one for both directions), four elsewhere.
    public static let adelaideTest: [Camera] = [
        Camera(id: "test-01", type: .fixedSpeed, coordinate: Coordinate(latitude: -34.94025, longitude: 138.5845),
               enforcedHeading: towardsGlenelg, road: "Test point 1, Anzac Hwy", speedLimitKmh: 60),
        Camera(id: "test-02", type: .mobileSpeed, coordinate: Coordinate(latitude: -34.9535, longitude: 138.5645),
               enforcedHeading: towardsGlenelg, road: "Test point 2, Anzac Hwy", speedLimitKmh: 60),
        Camera(id: "test-03", type: .phoneCamera, coordinate: Coordinate(latitude: -34.9590, longitude: 138.5550),
               enforcedHeading: towardsCity, road: "Test point 3, Anzac Hwy (city-bound only)", speedLimitKmh: 60),
        Camera(id: "test-04", type: .redLightSpeed, coordinate: Coordinate(latitude: -34.9655, longitude: 138.5445),
               enforcedHeading: nil, road: "Test point 4, Anzac Hwy (both directions)", speedLimitKmh: 60),
        Camera(id: "test-05", type: .phoneCamera, coordinate: Coordinate(latitude: -34.9725, longitude: 138.5330),
               enforcedHeading: towardsGlenelg, road: "Test point 5, Anzac Hwy", speedLimitKmh: 60),
        Camera(id: "test-06", type: .fixedSpeed, coordinate: Coordinate(latitude: -34.9780, longitude: 138.5215),
               enforcedHeading: towardsGlenelg, road: "Test point 6, Anzac Hwy", speedLimitKmh: 50),
        Camera(id: "test-07", type: .fixedSpeed, coordinate: Coordinate(latitude: -34.9255, longitude: 138.5999),
               enforcedHeading: 0, road: "Test point 7, city", speedLimitKmh: 50),
        Camera(id: "test-08", type: .mobileSpeed, coordinate: Coordinate(latitude: -34.9100, longitude: 138.5650),
               enforcedHeading: 290, road: "Test point 8, Port Rd", speedLimitKmh: 60),
        Camera(id: "test-09", type: .redLightSpeed, coordinate: Coordinate(latitude: -34.8800, longitude: 138.6100),
               enforcedHeading: nil, road: "Test point 9, Main North Rd", speedLimitKmh: 60),
        Camera(id: "test-10", type: .phoneAndSeatbeltCamera, coordinate: Coordinate(latitude: -34.9300, longitude: 138.6400),
               enforcedHeading: 0, road: "Test point 10, Portrush Rd", speedLimitKmh: 60),
    ]
}
