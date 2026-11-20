import Testing
@testable import ZoneWatchKit

@Suite("Geometry")
struct GeoTests {
    let adelaide = Coordinate(latitude: -34.9285, longitude: 138.6007)

    @Test func distanceOfOneDegreeLatitude() {
        let south = Coordinate(latitude: adelaide.latitude - 1, longitude: adelaide.longitude)
        #expect(abs(Geo.distance(adelaide, south) - 111_195) < 50)
    }

    @Test func distanceToSelfIsZero() {
        #expect(Geo.distance(adelaide, adelaide) == 0)
    }

    @Test("Bearings point the right way", arguments: [
        (0.01, 0.0, 0.0),
        (0.0, 0.01, 90.0),
        (-0.01, 0.0, 180.0),
        (0.0, -0.01, 270.0),
    ])
    func bearings(dLat: Double, dLon: Double, expected: Double) {
        let target = Coordinate(latitude: adelaide.latitude + dLat, longitude: adelaide.longitude + dLon)
        #expect(Geo.angleBetween(Geo.bearing(from: adelaide, to: target), expected) < 0.1)
    }

    @Test func angleBetweenWrapsAroundNorth() {
        #expect(Geo.angleBetween(350, 10) == 20)
        #expect(Geo.angleBetween(10, 350) == 20)
        #expect(Geo.angleBetween(0, 180) == 180)
        #expect(Geo.angleBetween(-90, 270) == 0)
    }

    @Test func testRouteHeadsSouthWest() {
        let route = PrototypeCameras.anzacHighwayRoute
        let bearing = Geo.bearing(from: route.first!, to: route.last!)
        #expect(Geo.angleBetween(bearing, PrototypeCameras.towardsGlenelg) < 5)
    }
}
