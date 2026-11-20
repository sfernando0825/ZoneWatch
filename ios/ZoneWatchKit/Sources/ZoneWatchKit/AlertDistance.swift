/// How far ahead of a camera the first alert plays (spec requirement F6).
///
/// The alert fires about 15 seconds of travel before the camera, never closer
/// than 300 m and never further than 1 km.
public enum AlertDistance {
    public static let defaultLeadTime: Double = 15
    public static let defaultMinimum: Double = 300
    public static let defaultMaximum: Double = 1_000

    /// Alert distance in metres for a speed in metres per second.
    ///
    /// An unknown, zero or negative speed (no GPS fix yet, or stopped) gives the minimum distance.
    public static func meters(
        forSpeed metersPerSecond: Double,
        leadTime: Double = defaultLeadTime,
        minimum: Double = defaultMinimum,
        maximum: Double = defaultMaximum
    ) -> Double {
        guard metersPerSecond.isFinite, metersPerSecond > 0 else { return minimum }
        return min(max(metersPerSecond * leadTime, minimum), maximum)
    }
}
