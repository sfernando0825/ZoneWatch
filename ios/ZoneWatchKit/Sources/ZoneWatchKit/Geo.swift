import Foundation

/// A latitude and longitude in degrees (WGS 84).
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Small-distance geometry for alerting. Accurate to well under a metre over the few kilometres that matter here.
public enum Geo {
    static let earthRadius = 6_371_000.0

    /// Great-circle distance in metres.
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude.radians, lat2 = b.latitude.radians
        let dLat = (b.latitude - a.latitude).radians
        let dLon = (b.longitude - a.longitude).radians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b` in degrees, 0 = north, clockwise, in 0..<360.
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude.radians, lat2 = b.latitude.radians
        let dLon = (b.longitude - a.longitude).radians
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalized(atan2(y, x).degrees)
    }

    /// Smallest angle between two headings in degrees, 0...180.
    public static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let diff = abs(normalized(a) - normalized(b))
        return diff > 180 ? 360 - diff : diff
    }

    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

extension Geo {
    /// Nearest point of a polyline to `point`: the distance in metres and the bearing of that
    /// stretch of line in its drawn direction, and whether that nearest point is one of the line's two
    /// ends (the point lies beyond the line rather than beside it). Uses a flat projection around `point`.
    public static func nearest(on line: [Coordinate], to point: Coordinate) -> (distance: Double, bearing: Double, atEnd: Bool)? {
        guard line.count >= 2 else { return nil }
        let kx = cos(point.latitude.radians) * earthRadius * .pi / 180
        let ky = earthRadius * .pi / 180
        func xy(_ c: Coordinate) -> (Double, Double) {
            ((c.longitude - point.longitude) * kx, (c.latitude - point.latitude) * ky)
        }
        var best: (distance: Double, bearing: Double, atEnd: Bool)?
        var previous = xy(line[0])
        for index in 1..<line.count {
            let current = xy(line[index])
            let dx = current.0 - previous.0, dy = current.1 - previous.1
            let length2 = dx * dx + dy * dy
            let t = length2 == 0 ? 0 : max(0, min(1, -(previous.0 * dx + previous.1 * dy) / length2))
            let distance = hypot(previous.0 + t * dx, previous.1 + t * dy)
            if length2 > 0, best == nil || distance < best!.distance {
                let atEnd = (index == 1 && t == 0) || (index == line.count - 1 && t == 1)
                best = (distance, normalized(atan2(dx, dy).degrees), atEnd)
            }
            previous = current
        }
        return best
    }
}
