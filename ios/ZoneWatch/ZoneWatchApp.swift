import SwiftUI
import UIKit

@main
struct ZoneWatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: .shared)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { MonitoringCoordinator.shared.appBecameActive() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Runs on background relaunches too, so monitoring resumes without the user opening the app.
        MonitoringCoordinator.shared.boot(launchedForLocation: launchOptions?[.location] != nil)
        return true
    }
}
