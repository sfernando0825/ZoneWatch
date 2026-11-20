import Foundation

/// Decides when a drive starts and ends from CarPlay, motion activity and speed.
///
/// A drive starts on any evidence of driving and ends only after `stopAfter` seconds without evidence,
/// so a stop at traffic lights or a short loss of signal does not end it. CarPlay keeps a drive going.
public struct DriveStateMachine: Sendable {
    public enum Input: Sendable, Equatable {
        case motion(automotive: Bool, confident: Bool)
        case carPlay(connected: Bool)
        case speed(metersPerSecond: Double)
    }

    public enum Change: Sendable, Equatable {
        case started
        case stopped
    }

    public private(set) var isDriving = false
    /// About 25 km/h.
    public var startSpeed: Double = 7
    public var stopAfter: TimeInterval = 180

    private var carPlayConnected = false
    private var lastEvidence: Date?

    public init() {}

    public mutating func handle(_ input: Input, at date: Date) -> Change? {
        switch input {
        case let .motion(automotive, confident):
            if automotive && confident { lastEvidence = date }
        case let .carPlay(connected):
            carPlayConnected = connected
            if connected { lastEvidence = date }
        case let .speed(metersPerSecond):
            if metersPerSecond >= startSpeed { lastEvidence = date }
        }
        return evaluate(at: date)
    }

    /// Call regularly (every 30 seconds) so a drive can end when evidence stops arriving.
    public mutating func tick(at date: Date) -> Change? {
        evaluate(at: date)
    }

    private mutating func evaluate(at date: Date) -> Change? {
        let recentEvidence = lastEvidence.map { date.timeIntervalSince($0) < stopAfter } ?? false
        let shouldDrive = carPlayConnected || recentEvidence
        guard shouldDrive != isDriving else { return nil }
        isDriving = shouldDrive
        return shouldDrive ? .started : .stopped
    }
}
