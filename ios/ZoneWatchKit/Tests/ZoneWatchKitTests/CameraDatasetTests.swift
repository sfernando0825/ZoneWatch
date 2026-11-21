import CryptoKit
import Foundation
import Testing
@testable import ZoneWatchKit

@Suite("Camera dataset")
struct CameraDatasetTests {
    static let json = """
    {"schemaVersion":1,"region":"SA","version":20261122,"generatedAt":"2026-11-22T03:00:00Z","dataThrough":"2026-10-31",
     "attribution":["test"],
     "cameras":[
       {"id":"sa-f-51","type":"redLightSpeed","lat":-34.9405,"lon":138.6127,"heading":null,"road":"Greenhill Road & Hutt Road","suburb":"Adelaide","speedLimitKmh":60,"lastSeen":"2026-10-30","notices":414},
       {"id":"sa-f-x","type":"hoverCamera","lat":-34.9,"lon":138.6,"heading":null,"road":"Future","suburb":"Adelaide","speedLimitKmh":60,"lastSeen":"2026-10-30","notices":1},
       {"id":"broken"}
     ],
     "zones":[
       {"id":"sa-m-1","type":"mobileSpeed","paths":[[[-34.9,138.5],[-34.91,138.5]]],"oneWay":false,"road":"Port Road","suburb":"Cheltenham","speedLimitKmh":60,"lastSeen":"2026-09-01","notices":30,"lengthM":1100},
       {"id":"sa-m-2","type":"mobileSpeed","paths":[[[-34.9,138.6],[-34.91,138.6]]],"oneWay":false,"road":"Old Road","suburb":"Somewhere","speedLimitKmh":60,"lastSeen":"2025-07-02","notices":3,"lengthM":1100},
       {"id":"sa-f-608","type":"averageSpeedSection","paths":[[[-35.56,139.79],[-35.68,139.85]]],"oneWay":true,"road":"Dukes Highway","suburb":"Ki Ki to Coonalpyn","speedLimitKmh":110,"lastSeen":"2026-10-31","notices":124,"lengthM":14757}
     ]}
    """

    @Test("Loads a correctly signed dataset and skips entries it doesn't understand")
    func loads() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data(Self.json.utf8)
        let signature = try key.signature(for: data).base64EncodedString()
        let dataset = try CameraDataset.load(
            data: data, signatureBase64: signature, publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()
        )
        #expect(dataset.version == 20261122)
        #expect(dataset.cameras.map(\.value.id) == ["sa-f-51"])
        #expect(dataset.cameras[0].value.coordinate == Coordinate(latitude: -34.9405, longitude: 138.6127))
        #expect(dataset.zones.map(\.value.id) == ["sa-m-1", "sa-m-2", "sa-f-608"])
        #expect(dataset.zones[2].value.oneWay)
        #expect(dataset.zones[2].value.type == .averageSpeedSection)
    }

    @Test("Rejects a dataset changed after signing, or signed by another key")
    func rejectsTampering() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data(Self.json.utf8)
        let signature = try key.signature(for: data).base64EncodedString()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        var tampered = data
        tampered.append(contentsOf: Array(" ".utf8))
        #expect(throws: CameraDataset.LoadError.badSignature) {
            try CameraDataset.load(data: tampered, signatureBase64: signature, publicKeyBase64: publicKey)
        }
        #expect(throws: CameraDataset.LoadError.badSignature) {
            try CameraDataset.load(data: data, signatureBase64: signature, publicKeyBase64: DatasetSignature.publicKey)
        }
    }

    @Test("Mobile sites can be turned off, and ones unused for a year are dropped")
    func alertSet() throws {
        let dataset = try CameraDataset.decode(Data(Self.json.utf8))
        let all = dataset.alertSet(includeMobile: true)
        #expect(all.zones.map(\.id) == ["sa-m-1", "sa-f-608"])
        let noMobile = dataset.alertSet(includeMobile: false)
        #expect(noMobile.zones.map(\.id) == ["sa-f-608"])
        #expect(noMobile.cameras.map(\.id) == ["sa-f-51"])
    }

    @Test("Newer schema versions are refused rather than misread")
    func schema() {
        let newer = Self.json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
        #expect(throws: CameraDataset.LoadError.unsupportedSchema(2)) {
            try CameraDataset.decode(Data(newer.utf8))
        }
    }
}
