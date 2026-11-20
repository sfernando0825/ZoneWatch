import Foundation

/// One position report from the vehicle. Speed and course are negative when unknown, as in Core Location.
public struct VehicleFix: Sendable, Equatable {
    public var coordinate: Coordinate
    /// Metres per second, negative when unknown.
    public var speed: Double
    /// Degrees clockwise from north, negative when unknown.
    public var course: Double
    public var timestamp: Date

    public init(coordinate: Coordinate, speed: Double, course: Double, timestamp: Date) {
        self.coordinate = coordinate
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }
}

public enum ProximityEvent: Sendable, Equatable {
    case approaching(Camera, distance: Double)
    case passed(Camera)
}

/// Phase 1 alert trigger: a camera alerts once when it is ahead, enforces this direction of travel,
/// and is within the speed-scaled alert distance. It clears once it is behind the vehicle.
public struct ProximityTrigger: Sendable {
    public var cameras: [Camera]
    /// How far either side of straight ahead a camera can be, and how far the camera's
    /// enforced heading can differ from the vehicle's course.
    public var headingTolerance: Double = 45
    /// Distance past a camera before it counts as passed.
    public var passMargin: Double = 30

    public private(set) var activeCameras: [String: Camera] = [:]

    public init(cameras: [Camera]) {
        self.cameras = cameras
    }

    public mutating func update(with fix: VehicleFix) -> [ProximityEvent] {
        guard fix.course >= 0 else { return [] }
        var events: [ProximityEvent] = []

        for camera in activeCameras.values.sorted(by: { $0.id < $1.id }) {
            let distance = Geo.distance(fix.coordinate, camera.coordinate)
            let offAxis = Geo.angleBetween(fix.course, Geo.bearing(from: fix.coordinate, to: camera.coordinate))
            let isBehind = offAxis > 90 && distance > passMargin
            let isFarAway = distance > AlertDistance.defaultMaximum * 1.5
            if isBehind || isFarAway {
                activeCameras[camera.id] = nil
                events.append(.passed(camera))
            }
        }

        let alertDistance = AlertDistance.meters(forSpeed: fix.speed)
        var approaching: [(Camera, Double)] = []
        for camera in cameras where activeCameras[camera.id] == nil {
            let distance = Geo.distance(fix.coordinate, camera.coordinate)
            guard distance <= alertDistance, isAhead(camera, of: fix), enforcesDirection(camera, of: fix) else { continue }
            approaching.append((camera, distance))
        }
        for (camera, distance) in approaching.sorted(by: { $0.1 < $1.1 }) {
            activeCameras[camera.id] = camera
            events.append(.approaching(camera, distance: distance))
        }
        return events
    }

    /// The nearest camera that has alerted and is not yet passed.
    public func nearestActive(from fix: VehicleFix) -> (camera: Camera, distance: Double)? {
        activeCameras.values
            .map { ($0, Geo.distance(fix.coordinate, $0.coordinate)) }
            .min { $0.1 < $1.1 }
            .map { (camera: $0.0, distance: $0.1) }
    }

    private func isAhead(_ camera: Camera, of fix: VehicleFix) -> Bool {
        let bearing = Geo.bearing(from: fix.coordinate, to: camera.coordinate)
        return Geo.angleBetween(fix.course, bearing) <= headingTolerance
    }

    private func enforcesDirection(_ camera: Camera, of fix: VehicleFix) -> Bool {
        guard let heading = camera.enforcedHeading else { return true }
        return Geo.angleBetween(fix.course, heading) <= headingTolerance
    }
}

/// Fills in speed and course when Core Location reports them as unknown (common in the simulator and at low accuracy).
public struct MotionEstimator: Sendable {
    /// Below this movement between fixes, the course is too noisy to compute and the previous one is kept.
    public var minimumMoveForCourse: Double = 5
    private var last: VehicleFix?

    public init() {}

    public mutating func refine(_ fix: VehicleFix) -> VehicleFix {
        var refined = fix
        if let last, fix.timestamp > last.timestamp {
            let distance = Geo.distance(last.coordinate, fix.coordinate)
            let seconds = fix.timestamp.timeIntervalSince(last.timestamp)
            if refined.speed < 0 {
                refined.speed = distance / seconds
            }
            if refined.course < 0 {
                refined.course = distance >= minimumMoveForCourse
                    ? Geo.bearing(from: last.coordinate, to: fix.coordinate)
                    : last.course
            }
        }
        last = refined
        return refined
    }
}
