import Foundation
@testable import ZoneWatchKit

/// Drives along a polyline at a steady speed, one fix per second, like a GPS replay.
enum RouteSimulator {
    static func fixes(
        along route: [Coordinate],
        speed: Double,
        start: Date = Date(timeIntervalSince1970: 1_800_000_000),
        reportCourse: Bool = true
    ) -> [VehicleFix] {
        var fixes: [VehicleFix] = []
        var time = start
        for (from, to) in zip(route, route.dropFirst()) {
            let length = Geo.distance(from, to)
            let course = Geo.bearing(from: from, to: to)
            var travelled = 0.0
            while travelled < length {
                let t = travelled / length
                let point = Coordinate(
                    latitude: from.latitude + (to.latitude - from.latitude) * t,
                    longitude: from.longitude + (to.longitude - from.longitude) * t
                )
                fixes.append(VehicleFix(
                    coordinate: point,
                    speed: reportCourse ? speed : -1,
                    course: reportCourse ? course : -1,
                    timestamp: time
                ))
                travelled += speed
                time += 1
            }
        }
        return fixes
    }
}
