import Foundation
import Testing
@testable import ZoneWatchKit

@Suite("Zone trigger")
struct ZoneTriggerTests {
    let sixtyKmh = 60 / 3.6
    // A 2 km zone running north along longitude 138.6, starting 2 km north of the origin.
    static let origin = Coordinate(latitude: -34.95, longitude: 138.6)
    static func north(_ meters: Double, east: Double = 0) -> Coordinate {
        Coordinate(
            latitude: origin.latitude + meters / 111_195,
            longitude: origin.longitude + east / (111_195 * cos(origin.latitude * .pi / 180))
        )
    }
    static let zonePath = [north(2_000), north(3_000), north(4_000)]

    private func zone(oneWay: Bool = false, type: CameraType = .mobileSpeed) -> CameraZone {
        CameraZone(id: "z1", type: type, paths: [Self.zonePath], oneWay: oneWay, road: "Test Road", speedLimitKmh: 60)
    }

    private func run(_ zones: [CameraZone], _ fixes: [VehicleFix]) -> [ZoneEvent] {
        var trigger = ZoneTrigger(zones: zones)
        return fixes.flatMap { trigger.update(with: $0) }
    }

    @Test("Driving along the road alerts once before the zone, then leaves it at the far end")
    func alongTheRoad() throws {
        let fixes = RouteSimulator.fixes(along: [Self.north(0), Self.north(6_000)], speed: sixtyKmh)
        let events = run([zone()], fixes)
        #expect(events.count == 2)
        guard case let .approaching(z, distance) = events.first else { Issue.record("no approach"); return }
        #expect(z.id == "z1")
        #expect(distance <= AlertDistance.meters(forSpeed: sixtyKmh) && distance > 200)
        guard case .left = events.last else { Issue.record("never left"); return }
    }

    @Test("A two-way zone alerts from the other end too")
    func otherDirection() {
        let fixes = RouteSimulator.fixes(along: [Self.north(6_000), Self.north(0)], speed: sixtyKmh)
        let events = run([zone()], fixes)
        #expect(events.first.map { if case .approaching = $0 { true } else { false } } == true)
    }

    @Test("A one-way zone stays quiet against its direction")
    func oneWayAgainst() {
        let fixes = RouteSimulator.fixes(along: [Self.north(6_000), Self.north(0)], speed: sixtyKmh)
        #expect(run([zone(oneWay: true)], fixes).isEmpty)
        let forward = RouteSimulator.fixes(along: [Self.north(0), Self.north(6_000)], speed: sixtyKmh)
        #expect(!run([zone(oneWay: true)], forward).isEmpty)
    }

    @Test("Crossing the zone's road at right angles doesn't alert")
    func crossing() {
        let fixes = RouteSimulator.fixes(along: [Self.north(3_000, east: -2_000), Self.north(3_000, east: 2_000)], speed: sixtyKmh)
        #expect(run([zone()], fixes).isEmpty)
    }

    @Test("A road meeting the zone's start at a shallow angle doesn't alert")
    func shallowSideStreet() {
        // Heading north-east (36° off the zone's direction) towards the zone's southern end, like a
        // driver on a diagonal arterial passing a side street that branches off northwards.
        let start = Self.north(2_000 - 400 * cos(36 * .pi / 180), east: -400 * sin(36 * .pi / 180))
        let past = Self.north(2_000 + 400 * cos(36 * .pi / 180), east: 400 * sin(36 * .pi / 180))
        let fixes = RouteSimulator.fixes(along: [start, past], speed: sixtyKmh)
        #expect(run([zone()], fixes).isEmpty)
    }

    @Test("Turning into the middle of a zone alerts as entered")
    func joinMidway() {
        let route = [Self.north(2_500, east: -1_500), Self.north(2_500), Self.north(3_200)]
        let events = run([zone()], RouteSimulator.fixes(along: route, speed: sixtyKmh))
        #expect(events.first == .entered(zone()))
    }

    @Test("Doesn't alert again straight after leaving, but does once the rearm interval has passed")
    func rearm() {
        func alerts(_ events: [ZoneEvent]) -> Int {
            events.filter { if case .left = $0 { false } else { true } }.count
        }
        var trigger = ZoneTrigger(zones: [zone()])
        let out = RouteSimulator.fixes(along: [Self.north(2_500), Self.north(4_500)], speed: sixtyKmh)
        let back = RouteSimulator.fixes(along: [Self.north(4_500), Self.north(3_500)], speed: sixtyKmh, start: out.last!.timestamp + 1)
        #expect(alerts((out + back).flatMap { trigger.update(with: $0) }) == 1)
        let later = RouteSimulator.fixes(along: [Self.north(3_500), Self.north(2_500)], speed: sixtyKmh, start: back.last!.timestamp + 200)
        #expect(alerts(later.flatMap { trigger.update(with: $0) }) == 1)
    }

    @Test("Current zone reports inside with no distance")
    func current() {
        var trigger = ZoneTrigger(zones: [zone()])
        let fixes = RouteSimulator.fixes(along: [Self.north(1_500), Self.north(2_500)], speed: sixtyKmh)
        for fix in fixes { _ = trigger.update(with: fix) }
        let now = trigger.current(from: fixes.last!)
        #expect(now?.inside == true)
        #expect(now?.zone.id == "z1")
    }

    @Test("Nearest point on a polyline gives distance and drawn bearing")
    func nearest() throws {
        let match = try #require(Geo.nearest(on: Self.zonePath, to: Self.north(2_500, east: 100)))
        #expect(abs(match.distance - 100) < 1)
        #expect(Geo.angleBetween(match.bearing, 0) < 0.5)
    }
}
