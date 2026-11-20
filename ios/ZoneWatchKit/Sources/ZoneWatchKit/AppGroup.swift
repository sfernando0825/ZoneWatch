import Foundation

/// The App Group shared by the app and its Live Activity extension (camera dataset, settings).
public enum AppGroup {
    public static let identifier = "group.com.zonewatch.app"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
