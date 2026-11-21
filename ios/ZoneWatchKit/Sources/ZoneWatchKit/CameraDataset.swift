import CryptoKit
import Foundation

/// The signed camera dataset built by `pipeline/` (format described in pipeline/zonewatch_pipeline/dataset.py).
public struct CameraDataset: Sendable, Equatable {
    public static let supportedSchemaVersion = 1

    public var region: String
    public var version: Int
    public var generatedAt: String
    /// Date of the newest offence the dataset is built from, "yyyy-MM-dd".
    public var dataThrough: String?
    public var attribution: [String]
    public var cameras: [Entry<Camera>]
    public var zones: [Entry<CameraZone>]

    public struct Entry<Value: Sendable & Equatable>: Sendable, Equatable {
        public var value: Value
        /// Date the site last issued a notice, "yyyy-MM-dd".
        public var lastSeen: String?
        public var notices: Int
    }

    public enum LoadError: Error, Equatable {
        case badSignature
        case unsupportedSchema(Int)
        case malformed(String)
    }

    /// Checks the signature over the exact bytes, then decodes. Entries of a type this app version
    /// doesn't know are skipped, so newer datasets still load.
    public static func load(data: Data, signatureBase64: String, publicKeyBase64: String) throws -> CameraDataset {
        guard DatasetSignature.isValid(data: data, signatureBase64: signatureBase64, publicKeyBase64: publicKeyBase64) else {
            throw LoadError.badSignature
        }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> CameraDataset {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw LoadError.malformed(String(describing: error))
        }
        guard file.schemaVersion == supportedSchemaVersion else { throw LoadError.unsupportedSchema(file.schemaVersion) }
        return CameraDataset(
            region: file.region,
            version: file.version,
            generatedAt: file.generatedAt,
            dataThrough: file.dataThrough,
            attribution: file.attribution,
            cameras: file.cameras.compactMap(\.value).compactMap { raw in
                guard let type = CameraType(rawValue: raw.type) else { return nil }
                let camera = Camera(
                    id: raw.id, type: type, coordinate: Coordinate(latitude: raw.lat, longitude: raw.lon),
                    enforcedHeading: raw.heading, road: raw.road, suburb: raw.suburb, speedLimitKmh: raw.speedLimitKmh
                )
                return Entry(value: camera, lastSeen: raw.lastSeen, notices: raw.notices ?? 0)
            },
            zones: file.zones.compactMap(\.value).compactMap { raw in
                guard let type = CameraType(rawValue: raw.type) else { return nil }
                let paths = raw.paths.map { $0.compactMap { $0.count == 2 ? Coordinate(latitude: $0[0], longitude: $0[1]) : nil } }
                    .filter { $0.count >= 2 }
                guard !paths.isEmpty else { return nil }
                let zone = CameraZone(
                    id: raw.id, type: type, paths: paths, oneWay: raw.oneWay ?? false,
                    road: raw.road, suburb: raw.suburb, speedLimitKmh: raw.speedLimitKmh
                )
                return Entry(value: zone, lastSeen: raw.lastSeen, notices: raw.notices ?? 0)
            }
        )
    }

    /// What to alert for. Mobile sites can be left out, and old ones always are: a mobile site
    /// not used within `mobileSeenWithinDays` of the dataset's newest data is probably retired.
    public func alertSet(includeMobile: Bool, mobileSeenWithinDays: Int = 365) -> (cameras: [Camera], zones: [CameraZone]) {
        let cutoff = dataThrough.flatMap(Self.day(from:)).map { $0.addingTimeInterval(-Double(mobileSeenWithinDays) * 86_400) }
        func keep(_ type: CameraType, _ lastSeen: String?) -> Bool {
            guard type == .mobileSpeed else { return true }
            guard includeMobile else { return false }
            guard let cutoff, let seen = lastSeen.flatMap(Self.day(from:)) else { return true }
            return seen >= cutoff
        }
        return (
            cameras.filter { keep($0.value.type, $0.lastSeen) }.map(\.value),
            zones.filter { keep($0.value.type, $0.lastSeen) }.map(\.value)
        )
    }

    static func day(from text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: JSON shape

    private struct File: Decodable {
        var schemaVersion: Int
        var region: String
        var version: Int
        var generatedAt: String
        var dataThrough: String?
        var attribution: [String]
        var cameras: [Lossy<RawCamera>]
        var zones: [Lossy<RawZone>]
    }

    private struct RawCamera: Decodable {
        var id: String
        var type: String
        var lat: Double
        var lon: Double
        var heading: Double?
        var road: String
        var suburb: String?
        var speedLimitKmh: Int?
        var lastSeen: String?
        var notices: Int?
    }

    private struct RawZone: Decodable {
        var id: String
        var type: String
        var paths: [[[Double]]]
        var oneWay: Bool?
        var road: String
        var suburb: String?
        var speedLimitKmh: Int?
        var lastSeen: String?
        var notices: Int?
    }

    /// Decodes an element if it can, so one bad entry doesn't fail the whole dataset.
    private struct Lossy<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: any Decoder) throws {
            value = try? T(from: decoder)
        }
    }
}

/// Ed25519 signature check for the dataset. The private key never leaves the developer's machine
/// and the CI secret; see pipeline/README.md.
public enum DatasetSignature {
    /// Public half of ~/.config/zonewatch/dataset-signing-key.pem.
    public static let publicKey = "caPT6N8Wo7qb35XXBCaowYWqtah+UzyZz/PlZSurPXw="

    public static func isValid(data: Data, signatureBase64: String, publicKeyBase64: String = publicKey) -> Bool {
        guard
            let keyData = Data(base64Encoded: publicKeyBase64),
            let signature = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return key.isValidSignature(signature, for: data)
    }
}
