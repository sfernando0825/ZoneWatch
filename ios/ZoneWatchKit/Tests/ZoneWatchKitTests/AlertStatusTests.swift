import Foundation
import Testing
@testable import ZoneWatchKit

@Suite("Live Activity status text")
struct AlertStatusTests {
    @Test func headlines() {
        #expect(AlertStatus.monitoring.headline == "Monitoring")
        #expect(AlertStatus(phase: .cameraAhead, cameraType: .mobileSpeed).headline == "Mobile camera ahead")
        #expect(AlertStatus(phase: .overLimit, cameraType: .fixedSpeed).headline == "Check your speed: speed camera ahead")
        #expect(AlertStatus(phase: .cameraAhead).headline == "Camera ahead")
    }

    @Test("Distances round for a glance", arguments: [
        (612.0, "600 m"),
        (240.0, "250 m"),
        (0.0, "0 m"),
        (1_240.0, "1.2 km"),
        (999.0, "1.0 km"),
    ])
    func distanceText(meters: Double, expected: String) {
        #expect(AlertStatus(phase: .cameraAhead, distanceMeters: meters).distanceText == expected)
    }

    @Test func unknownDistanceHasNoText() {
        #expect(AlertStatus.monitoring.distanceText == nil)
        #expect(AlertStatus(phase: .cameraAhead, distanceMeters: -1).distanceText == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let status = AlertStatus(phase: .cameraAhead, cameraType: .phoneCamera, road: "South Rd", distanceMeters: 600, speedLimitKmh: 60)
        let data = try JSONEncoder().encode(status)
        #expect(try JSONDecoder().decode(AlertStatus.self, from: data) == status)
    }
}

@Suite("Alert status in a zone")
struct AlertStatusZoneTests {
    @Test("Inside a zone the headline names the zone and no distance is shown")
    func zone() {
        let status = AlertStatus(phase: .cameraAhead, cameraType: .mobileSpeed, road: "Port Road", distanceMeters: 0, inZone: true)
        #expect(status.headline == "Mobile camera site")
        #expect(status.distanceText == nil)
        let over = AlertStatus(phase: .overLimit, cameraType: .averageSpeedSection, inZone: true)
        #expect(over.headline == "Check your speed: average speed zone")
    }
}
