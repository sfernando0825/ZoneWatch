import Testing
@testable import ZoneWatchKit

private func metersPerSecond(kmh: Double) -> Double { kmh / 3.6 }

@Suite("Alert distance (F6)")
struct AlertDistanceTests {
    @Test("Slow traffic gets the 300 m minimum")
    func minimumAtLowSpeed() {
        #expect(AlertDistance.meters(forSpeed: metersPerSecond(kmh: 50)) == 300)
        #expect(AlertDistance.meters(forSpeed: metersPerSecond(kmh: 60)) == 300)
    }

    @Test("Highway speed scales with 15 seconds of travel")
    func scalesWithSpeed() {
        let at100 = AlertDistance.meters(forSpeed: metersPerSecond(kmh: 100))
        #expect(abs(at100 - 416.67) < 0.01)
        let at110 = AlertDistance.meters(forSpeed: metersPerSecond(kmh: 110))
        #expect(abs(at110 - 458.33) < 0.01)
    }

    @Test("Very high speed is capped at 1 km")
    func cappedAtMaximum() {
        #expect(AlertDistance.meters(forSpeed: metersPerSecond(kmh: 300)) == 1_000)
    }

    @Test("Unknown or zero speed falls back to the minimum", arguments: [0, -5, .nan, .infinity])
    func invalidSpeed(_ speed: Double) {
        #expect(AlertDistance.meters(forSpeed: speed) == 300)
    }

    @Test("Custom settings are respected")
    func customSettings() {
        let distance = AlertDistance.meters(forSpeed: 20, leadTime: 20, minimum: 200, maximum: 800)
        #expect(distance == 400)
    }
}
