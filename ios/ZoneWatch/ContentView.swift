import SwiftUI
import ZoneWatchKit

/// Placeholder home screen for Phase 0. Phase 1 replaces it with monitoring status and the proof-of-concept controls.
struct ContentView: View {
    private let status = AlertStatus.monitoring

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.center.weighted")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("ZoneWatch")
                .font(.largeTitle.bold())
            Text("Speed camera alerts")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(status.headline)
                .font(.headline)
                .padding(.top, 24)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
