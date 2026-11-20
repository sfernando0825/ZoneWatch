#if os(iOS)
import ActivityKit

/// The Live Activity shared by the app (which starts and updates it) and the widget extension (which draws it).
public struct CameraAlertAttributes: ActivityAttributes {
    public typealias ContentState = AlertStatus

    public init() {}
}
#endif
