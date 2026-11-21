import Foundation

public enum ZoneEvent: Sendable, Equatable {
    /// The start of a zone is ahead on this road, within the alert distance.
    case approaching(CameraZone, distance: Double)
    /// The vehicle joined the zone part-way (from a side street, say) without an approach alert.
    case entered(CameraZone)
    case left(CameraZone)
}

/// Alerts for stretches of road with a camera somewhere along them. A zone alerts once when its start
/// is ahead on the same road and facing the same way, or when the vehicle turns into the middle of it,
/// and not again until the vehicle has left it and `rearmInterval` has passed.
public struct ZoneTrigger: Sendable {
    public var headingTolerance: Double = 45
    /// Within this distance of a zone's line, travelling along it, counts as being on that road.
    public var onRoadDistance: Double = 35
    /// Further than this from the zone's line counts as having left it.
    public var leaveDistance: Double = 60
    public var rearmInterval: TimeInterval = 120
    /// How closely the course must follow the zone's line to count as driving along it. Tighter than
    /// `headingTolerance` so a road crossing or branching off at a shallow angle doesn't count.
    public var alongTolerance: Double = 25
    /// How far to the side of a zone's starting line the vehicle can be and still be approaching it.
    public var lateralTolerance: Double = 20

    public private(set) var zones: [CameraZone]
    private var boxes: [Box]
    public private(set) var active: [String: Active] = [:]
    private var clearedAt: [String: Date] = [:]

    public enum State: Sendable, Equatable {
        case approaching(entry: Coordinate)
        case inside
    }

    public struct Active: Sendable, Equatable {
        public var zone: CameraZone
        public var state: State
    }

    public init(zones: [CameraZone]) {
        self.zones = zones
        let margin = AlertDistance.defaultMaximum + 100
        boxes = zones.map { Box(paths: $0.paths, marginMeters: margin) }
    }

    public mutating func update(with fix: VehicleFix) -> [ZoneEvent] {
        guard fix.course >= 0 else { return [] }
        var events: [ZoneEvent] = []

        for id in active.keys.sorted() {
            guard var entry = active[id] else { continue }
            let match = onRoad(entry.zone, fix)
            switch entry.state {
            case .inside:
                if match.distance > leaveDistance {
                    clear(id, at: fix.timestamp)
                    events.append(.left(entry.zone))
                }
            case let .approaching(entryPoint):
                if match.distance <= onRoadDistance, match.aligned {
                    entry.state = .inside
                    active[id] = entry
                    continue
                }
                let distance = Geo.distance(fix.coordinate, entryPoint)
                let offAxis = Geo.angleBetween(fix.course, Geo.bearing(from: fix.coordinate, to: entryPoint))
                if (offAxis > 90 && distance > 30) || distance > AlertDistance.defaultMaximum * 1.5 {
                    clear(id, at: fix.timestamp)
                    events.append(.left(entry.zone))
                }
            }
        }

        let alertDistance = AlertDistance.meters(forSpeed: fix.speed)
        var found: [(ZoneEvent, Active, Double)] = []
        for (index, zone) in zones.enumerated() where active[zone.id] == nil {
            guard boxes[index].contains(fix.coordinate) else { continue }
            if let cleared = clearedAt[zone.id], fix.timestamp.timeIntervalSince(cleared) < rearmInterval { continue }
            let match = onRoad(zone, fix)
            if match.distance <= onRoadDistance, match.aligned {
                found.append((.entered(zone), Active(zone: zone, state: .inside), 0))
                continue
            }
            if let (point, distance) = nearestEntryAhead(zone, fix, within: alertDistance) {
                found.append((.approaching(zone, distance: distance), Active(zone: zone, state: .approaching(entry: point)), distance))
            }
        }
        for (event, entry, _) in found.sorted(by: { $0.2 < $1.2 }) {
            active[entry.zone.id] = entry
            events.append(event)
        }
        return events
    }

    /// The zone to show: one the vehicle is in, else the nearest one ahead.
    public func current(from fix: VehicleFix) -> (zone: CameraZone, distance: Double, inside: Bool)? {
        if let inside = active.values.filter({ $0.state == .inside }).min(by: { $0.zone.id < $1.zone.id }) {
            return (inside.zone, 0, true)
        }
        return active.values.compactMap { entry -> (CameraZone, Double, Bool)? in
            guard case let .approaching(point) = entry.state else { return nil }
            return (entry.zone, Geo.distance(fix.coordinate, point), false)
        }
        .min { $0.1 < $1.1 }
        .map { (zone: $0.0, distance: $0.1, inside: $0.2) }
    }

    private mutating func clear(_ id: String, at time: Date) {
        active[id] = nil
        clearedAt[id] = time
    }

    /// Distance to the zone's line, and whether the vehicle travels along it in an enforced direction.
    /// Being just beyond one end of the line doesn't count as travelling along it: that is where side
    /// roads meet it.
    private func onRoad(_ zone: CameraZone, _ fix: VehicleFix) -> (distance: Double, aligned: Bool) {
        var best: (distance: Double, bearing: Double, atEnd: Bool)?
        for path in zone.paths {
            if let match = Geo.nearest(on: path, to: fix.coordinate), best == nil || match.distance < best!.distance {
                best = match
            }
        }
        guard let best else { return (.infinity, false) }
        let angle = Geo.angleBetween(fix.course, best.bearing)
        let aligned = !best.atEnd && (angle <= alongTolerance || (!zone.oneWay && angle >= 180 - alongTolerance))
        return (best.distance, aligned)
    }

    /// The nearest end of a zone path that is ahead and leads into the zone in the direction of travel.
    private func nearestEntryAhead(_ zone: CameraZone, _ fix: VehicleFix, within limit: Double) -> (Coordinate, Double)? {
        var best: (Coordinate, Double)?
        for path in zone.paths where path.count >= 2 {
            var entries = [(path[0], Geo.bearing(from: path[0], to: path[1]))]
            if !zone.oneWay {
                let n = path.count
                entries.append((path[n - 1], Geo.bearing(from: path[n - 1], to: path[n - 2])))
            }
            for (point, heading) in entries {
                let distance = Geo.distance(fix.coordinate, point)
                // Closer than this, any road near the zone's start looks in line with it; a vehicle that
                // turns onto the zone's road this late gets the `entered` alert once it is on the zone.
                guard distance >= 100, distance <= limit, best == nil || distance < best!.1 else { continue }
                let bearingToEntry = Geo.bearing(from: fix.coordinate, to: point)
                let ahead = Geo.angleBetween(fix.course, bearingToEntry) <= headingTolerance
                let sameWay = Geo.angleBetween(fix.course, heading) <= alongTolerance
                // The vehicle must be roughly on the line the zone starts along, not on a road that
                // meets it at a shallow angle (a side street leaving a diagonal arterial, say).
                let offset = distance * sin(Geo.angleBetween(heading, bearingToEntry).radians)
                let inLine = offset <= lateralTolerance + distance * 0.15
                if ahead, sameWay, inLine { best = (point, distance) }
            }
        }
        return best
    }
}

/// A latitude/longitude box around a zone, for skipping far-away zones cheaply.
struct Box: Sendable {
    var south, west, north, east: Double

    init(paths: [[Coordinate]], marginMeters: Double) {
        let points = paths.flatMap { $0 }
        let lat = points.map(\.latitude), lon = points.map(\.longitude)
        let dLat = marginMeters / 111_000
        let dLon = marginMeters / (111_000 * max(0.1, cos((lat.min() ?? 0).radians)))
        south = (lat.min() ?? 0) - dLat
        north = (lat.max() ?? 0) + dLat
        west = (lon.min() ?? 0) - dLon
        east = (lon.max() ?? 0) + dLon
    }

    func contains(_ c: Coordinate) -> Bool {
        c.latitude >= south && c.latitude <= north && c.longitude >= west && c.longitude <= east
    }
}
