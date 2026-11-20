import Foundation

/// Writes recorded drives as GPX waypoints with times, the format Xcode replays under Debug > Simulate Location.
public enum GPX {
    public static func waypoints(_ fixes: [VehicleFix]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"ZoneWatch\">\n"
        for fix in fixes {
            let lat = String(format: "%.6f", fix.coordinate.latitude)
            let lon = String(format: "%.6f", fix.coordinate.longitude)
            xml += "  <wpt lat=\"\(lat)\" lon=\"\(lon)\"><time>\(fix.timestamp.formatted(.iso8601))</time></wpt>\n"
        }
        xml += "</gpx>\n"
        return xml
    }
}
