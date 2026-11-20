import SwiftUI
import ZoneWatchKit

/// Phase 1 proof-of-concept screen: everything needed to run and judge a drive test.
/// Phase 6 replaces it with the real driving view and onboarding.
struct ContentView: View {
    let coordinator: MonitoringCoordinator

    var body: some View {
        NavigationStack {
            List {
                statusSection
                driveSection
                permissionsSection
                audioSection
                liveActivitySection
                logSection
            }
            .navigationTitle("ZoneWatch")
        }
    }

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(coordinator.status.headline).font(.title2.bold())
                if let distance = coordinator.status.distanceText {
                    Text(distance).font(.title3).monospacedDigit()
                }
                if let road = coordinator.status.road {
                    Text(road).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            LabeledContent("Speed", value: coordinator.speedKmh.map { "\(Int($0)) km/h" } ?? "–")
        } footer: {
            Text("Phase 1 uses 10 made-up test points along Anzac Highway, not real camera locations.")
        }
    }

    private var driveSection: some View {
        @Bindable var drive = coordinator.drive
        return Section("Drive") {
            LabeledContent("Driving", value: drive.isDriving ? "Yes" : "No")
            LabeledContent("Motion", value: drive.activityText)
            LabeledContent("CarPlay", value: drive.carPlayConnected ? "Connected" : "Not connected")
            LabeledContent("Location updates", value: coordinator.location.isTracking ? "On" : "Off")
            Toggle("Start a drive by hand (testing)", isOn: $drive.manualOverride)
        }
    }

    private var permissionsSection: some View {
        Section("Permissions") {
            LabeledContent("Location", value: coordinator.location.authorizationText)
            if coordinator.location.authorization != .authorizedAlways {
                Button("Allow location Always") { coordinator.location.requestAlwaysAuthorization() }
            }
            LabeledContent("Live Activities", value: coordinator.liveActivity.areActivitiesEnabled ? "On" : "Off")
            if let error = coordinator.location.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    private var audioSection: some View {
        Section {
            LabeledContent("Prompts ready", value: "\(coordinator.audio.preparedCount) of \(coordinator.audio.promptCount)")
            LabeledContent("Media volume", value: "\(Int(coordinator.audio.outputVolume * 100))%")
            Button("Play test alarm") { coordinator.testAlarm() }
            if let error = coordinator.audio.lastError {
                Text(error).foregroundStyle(.red)
            }
        } header: {
            Text("Alarm")
        } footer: {
            Text("Test with the ringer switch on silent and music playing. The alarm uses media volume.")
        }
    }

    private var liveActivitySection: some View {
        Section("Live Activity") {
            LabeledContent("Running", value: coordinator.liveActivity.isRunning ? "Yes" : "No")
            if let error = coordinator.liveActivity.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    private var logSection: some View {
        Section {
            if coordinator.recorder.recentLines.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary)
            }
            ForEach(coordinator.recorder.recentLines, id: \.self) { line in
                Text(line).font(.caption.monospaced())
            }
        } header: {
            Text("Log")
        } footer: {
            Text("Each drive is saved as GPX and text in Files › On My iPhone › ZoneWatch › Drives.")
        }
    }
}
