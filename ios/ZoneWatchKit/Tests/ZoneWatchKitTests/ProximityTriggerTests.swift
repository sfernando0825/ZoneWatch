import Foundation
import Testing
@testable import ZoneWatchKit

@Suite("Proximity trigger on the Anzac Highway test route")
struct ProximityTriggerTests {
    let sixtyKmh = 60 / 3.6

    private func run(_ fixes: [VehicleFix]) -> [ProximityEvent] {
        var trigger = ProximityTrigger(cameras: PrototypeCameras.adelaideTest)
        return fixes.flatMap { trigger.update(with: $0) }
    }

    private func approachedIDs(_ events: [ProximityEvent]) -> [String] {
        events.compactMap { if case let .approaching(camera, _) = $0 { camera.id } else { nil } }
    }

    private func passedIDs(_ events: [ProximityEvent]) -> [String] {
        events.compactMap { if case let .passed(camera) = $0 { camera.id } else { nil } }
    }

    @Test("Towards Glenelg alerts every on-route camera except the city-bound one, once each")
    func towardsGlenelg() {
        let events = run(RouteSimulator.fixes(along: PrototypeCameras.anzacHighwayRoute, speed: sixtyKmh))
        #expect(approachedIDs(events) == ["test-01", "test-02", "test-04", "test-05", "test-06"])
        #expect(passedIDs(events) == ["test-01", "test-02", "test-04", "test-05", "test-06"])
    }

    @Test("Towards the city alerts only the city-bound and both-direction cameras")
    func towardsCity() {
        let route = Array(PrototypeCameras.anzacHighwayRoute.reversed())
        let events = run(RouteSimulator.fixes(along: route, speed: sixtyKmh))
        #expect(approachedIDs(events) == ["test-04", "test-03"])
    }

    @Test("First alert comes at about the 300 m minimum at 60 km/h")
    func alertDistance() throws {
        let events = run(RouteSimulator.fixes(along: PrototypeCameras.anzacHighwayRoute, speed: sixtyKmh))
        guard case let .approaching(_, distance) = try #require(events.first) else {
            Issue.record("First event was not an approach")
            return
        }
        #expect(distance <= 300)
        #expect(distance > 300 - sixtyKmh)
    }

    @Test("No course means no alerts until the estimator fills it in")
    func needsCourse() {
        let raw = RouteSimulator.fixes(along: PrototypeCameras.anzacHighwayRoute, speed: sixtyKmh, reportCourse: false)
        #expect(run(raw).isEmpty)

        var estimator = MotionEstimator()
        let refined = raw.map { estimator.refine($0) }
        #expect(approachedIDs(run(refined)) == ["test-01", "test-02", "test-04", "test-05", "test-06"])
    }

    @Test("Nearest active camera reports distance until it is passed")
    func nearestActive() {
        var trigger = ProximityTrigger(cameras: PrototypeCameras.adelaideTest)
        var sawActive = false
        for fix in RouteSimulator.fixes(along: PrototypeCameras.anzacHighwayRoute, speed: sixtyKmh) {
            _ = trigger.update(with: fix)
            if let active = trigger.nearestActive(from: fix) {
                sawActive = true
                #expect(active.distance <= 300 + 30)
            }
        }
        #expect(sawActive)
        #expect(trigger.activeCameras.isEmpty)
    }
}

@Suite("Motion estimator")
struct MotionEstimatorTests {
    @Test func keepsReportedValues() {
        var estimator = MotionEstimator()
        let fix = VehicleFix(coordinate: Coordinate(latitude: -34.9, longitude: 138.6), speed: 10, course: 90, timestamp: .now)
        #expect(estimator.refine(fix) == fix)
    }

    @Test func keepsPreviousCourseWhenBarelyMoving() {
        var estimator = MotionEstimator()
        let start = Date(timeIntervalSince1970: 0)
        let a = VehicleFix(coordinate: Coordinate(latitude: -34.9, longitude: 138.6), speed: -1, course: 120, timestamp: start)
        let b = VehicleFix(coordinate: Coordinate(latitude: -34.90001, longitude: 138.6), speed: -1, course: -1, timestamp: start + 1)
        _ = estimator.refine(a)
        let refined = estimator.refine(b)
        #expect(refined.course == 120)
        #expect(refined.speed > 0 && refined.speed < 2)
    }
}
