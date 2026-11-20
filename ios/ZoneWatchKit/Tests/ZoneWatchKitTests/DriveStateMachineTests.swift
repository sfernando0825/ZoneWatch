import Foundation
import Testing
@testable import ZoneWatchKit

@Suite("Drive detection")
struct DriveStateMachineTests {
    let t0 = Date(timeIntervalSince1970: 0)

    @Test func confidentAutomotiveStartsADrive() {
        var machine = DriveStateMachine()
        #expect(machine.handle(.motion(automotive: true, confident: true), at: t0) == .started)
        #expect(machine.isDriving)
    }

    @Test func lowConfidenceOrWalkingDoesNotStart() {
        var machine = DriveStateMachine()
        #expect(machine.handle(.motion(automotive: true, confident: false), at: t0) == nil)
        #expect(machine.handle(.motion(automotive: false, confident: true), at: t0) == nil)
        #expect(machine.handle(.speed(metersPerSecond: 3), at: t0) == nil)
        #expect(!machine.isDriving)
    }

    @Test func speedAboveTwentyFiveKmhStarts() {
        var machine = DriveStateMachine()
        #expect(machine.handle(.speed(metersPerSecond: 8), at: t0) == .started)
    }

    @Test func driveEndsThreeMinutesAfterLastEvidence() {
        var machine = DriveStateMachine()
        _ = machine.handle(.motion(automotive: true, confident: true), at: t0)
        #expect(machine.tick(at: t0 + 120) == nil)
        #expect(machine.tick(at: t0 + 180) == .stopped)
        #expect(!machine.isDriving)
    }

    @Test func stoppingAtLightsDoesNotEndTheDrive() {
        var machine = DriveStateMachine()
        _ = machine.handle(.speed(metersPerSecond: 15), at: t0)
        _ = machine.handle(.speed(metersPerSecond: 0), at: t0 + 60)
        #expect(machine.tick(at: t0 + 90) == nil)
        _ = machine.handle(.speed(metersPerSecond: 12), at: t0 + 100)
        #expect(machine.tick(at: t0 + 250) == nil)
        #expect(machine.isDriving)
    }

    @Test func carPlayKeepsTheDriveGoingUntilDisconnected() {
        var machine = DriveStateMachine()
        #expect(machine.handle(.carPlay(connected: true), at: t0) == .started)
        #expect(machine.tick(at: t0 + 3_600) == nil)
        #expect(machine.handle(.carPlay(connected: false), at: t0 + 3_600) == .stopped)
    }
}

@Suite("GPX")
struct GPXTests {
    @Test func writesXcodeStyleWaypoints() {
        let fix = VehicleFix(
            coordinate: Coordinate(latitude: -34.9365, longitude: 138.59),
            speed: 16, course: 234, timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let xml = GPX.waypoints([fix])
        #expect(xml.contains("<wpt lat=\"-34.936500\" lon=\"138.590000\"><time>2027-01-15T08:00:00Z</time></wpt>"))
        #expect(xml.hasPrefix("<?xml"))
        #expect(xml.hasSuffix("</gpx>\n"))
    }
}
