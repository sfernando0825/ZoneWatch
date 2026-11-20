import Foundation
import Observation
import UIKit
import ZoneWatchKit

/// Records each drive for the Phase 1 drive tests: a GPX track (replayable in Xcode) and a text log
/// with alerts, errors and battery use. Files are in the app's Documents folder, visible in the Files app.
@MainActor
@Observable
final class DriveRecorder {
    private(set) var recentLines: [String] = []

    @ObservationIgnored private var fixes: [VehicleFix] = []
    @ObservationIgnored private var driveLines: [String] = []
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var startBattery: Float?
    @ObservationIgnored private var distance: Double = 0

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    static var folder: URL {
        let folder = URL.documentsDirectory.appending(path: "Drives", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func begin() {
        fixes = []
        driveLines = []
        distance = 0
        startedAt = Date()
        startBattery = batteryLevel
        log("Drive started, battery \(batteryText(startBattery))")
    }

    func record(_ fix: VehicleFix) {
        guard startedAt != nil else { return }
        if let last = fixes.last { distance += Geo.distance(last.coordinate, fix.coordinate) }
        fixes.append(fix)
        // Save every 5 minutes or so, in case iOS stops the app mid-drive.
        if fixes.count % 300 == 0 { save() }
    }

    func log(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(message)"
        recentLines.insert(line, at: 0)
        if recentLines.count > 50 { recentLines.removeLast() }
        if startedAt != nil {
            driveLines.append(line)
            saveLog()
        }
    }

    func finish() {
        guard let startedAt else { return }
        let hours = Date().timeIntervalSince(startedAt) / 3_600
        let end = batteryLevel
        var summary = "Drive ended after \(String(format: "%.0f", hours * 60)) min, \(String(format: "%.1f", distance / 1_000)) km"
        if let start = startBattery, let end {
            let used = (start - end) * 100
            summary += ", battery \(batteryText(start)) to \(batteryText(end))"
            if hours > 0.1 { summary += " (\(String(format: "%.1f", used / Float(hours)))% an hour)" }
        }
        log(summary)
        save()
        self.startedAt = nil
    }

    private func save() {
        guard let base = fileBase else { return }
        try? GPX.waypoints(fixes).write(to: base.appendingPathExtension("gpx"), atomically: true, encoding: .utf8)
        saveLog()
    }

    /// The log is small, so it is saved after every line and survives the app being stopped.
    private func saveLog() {
        guard let base = fileBase else { return }
        try? driveLines.joined(separator: "\n").write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }

    private var fileBase: URL? {
        guard let startedAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return Self.folder.appending(path: "drive-\(formatter.string(from: startedAt))")
    }

    /// Nil in the simulator, which has no battery.
    private var batteryLevel: Float? {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : level
    }

    private func batteryText(_ level: Float?) -> String {
        level.map { "\(Int(($0 * 100).rounded()))%" } ?? "unknown"
    }
}
