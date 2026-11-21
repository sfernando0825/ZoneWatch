import Foundation
import Observation
import ZoneWatchKit

/// Loads the signed camera dataset. Phase 2 ships a snapshot in the app; Phase 4 adds downloads, saved
/// to Application Support/Datasets and used instead of the snapshot when newer and correctly signed.
@MainActor
@Observable
final class CameraData {
    private(set) var dataset: CameraDataset?
    private(set) var source = "none"
    private(set) var lastError: String?

    /// Mobile camera sites alert unless turned off. Stored so the choice survives relaunches.
    var includeMobile: Bool {
        get {
            access(keyPath: \.includeMobile)
            return UserDefaults.standard.object(forKey: Self.mobileKey) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.includeMobile) {
                UserDefaults.standard.set(newValue, forKey: Self.mobileKey)
            }
        }
    }

    /// Automated simulator tests of Phase 1: launch with `-ZWPrototypeCameras YES` for the made-up test points.
    var usePrototypeCameras: Bool { UserDefaults.standard.bool(forKey: "ZWPrototypeCameras") }

    private static let mobileKey = "ZWMobileSites"
    private static let name = "sa-cameras"

    func load() {
        let candidates: [(String, URL?)] = [
            ("downloaded", URL.applicationSupportDirectory.appending(path: "Datasets/\(Self.name).json")),
            ("built in", Bundle.main.url(forResource: Self.name, withExtension: "json")),
        ]
        var errors: [String] = []
        var best: (CameraDataset, String)?
        for (label, url) in candidates {
            guard let url, FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let data = try Data(contentsOf: url)
                let signature = try String(contentsOf: url.appendingPathExtension("sig"), encoding: .utf8)
                let loaded = try CameraDataset.load(data: data, signatureBase64: signature, publicKeyBase64: DatasetSignature.publicKey)
                if best == nil || loaded.version > best!.0.version { best = (loaded, label) }
            } catch {
                errors.append("\(label): \(error)")
            }
        }
        dataset = best?.0
        source = best?.1 ?? "none"
        lastError = errors.isEmpty ? nil : errors.joined(separator: "; ")
    }

    /// What to alert for on this drive.
    func alertSet() -> (cameras: [Camera], zones: [CameraZone]) {
        if usePrototypeCameras { return (PrototypeCameras.adelaideTest, []) }
        return dataset?.alertSet(includeMobile: includeMobile) ?? ([], [])
    }
}
