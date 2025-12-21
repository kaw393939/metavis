import XCTest
import MetaVisGraphics
@testable import MetaVisSimulation

final class RegistryLoaderTests: XCTestCase {
    private func makeTemporaryBundle(resources: [(relativePath: String, data: Data)]) throws -> Bundle {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("metavis_test_\(UUID().uuidString)", isDirectory: true)
        let bundleURL = root.appendingPathComponent("Test.bundle", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.metavis.tests.tempbundle.\(UUID().uuidString)",
            "CFBundleName": "Test",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plistData.write(to: infoPlistURL)

        for item in resources {
            let fileURL = resourcesURL.appendingPathComponent(item.relativePath)
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try item.data.write(to: fileURL)
        }

        guard let b = Bundle(url: bundleURL) else {
            XCTFail("Failed to create Bundle at \(bundleURL.path)")
            throw NSError(domain: "RegistryLoaderTests", code: 1)
        }
        return b
    }

    func testLoadsManifestsFromGraphicsBundle() throws {
        let loader = FeatureRegistryLoader(bundle: GraphicsBundleHelper.bundle)
        let manifests = try loader.loadManifests()

        XCTAssertFalse(manifests.isEmpty)
        XCTAssertTrue(manifests.contains(where: { $0.id == "com.metavis.fx.smpte_bars" }))
        XCTAssertTrue(manifests.contains(where: { $0.id == "audio.dialogCleanwater.v1" && $0.domain == .audio }))
        XCTAssertTrue(manifests.contains(where: { $0.id == "mv.retime" && $0.domain == .intrinsic }))
        XCTAssertTrue(manifests.contains(where: { $0.id == "mv.colorGrade" && $0.domain == .intrinsic }))
    }

    func testRegistersManifestsIntoRegistry() async throws {
        let registry = FeatureRegistry()
        let loader = FeatureRegistryLoader(bundle: GraphicsBundleHelper.bundle)

        _ = try await loader.load(into: registry)
        let bars = await registry.feature(for: "com.metavis.fx.smpte_bars")
        XCTAssertEqual(bars?.kernelName, "fx_smpte_bars")

        let retime = await registry.feature(for: "mv.retime")
        XCTAssertEqual(retime?.domain, .intrinsic)
    }

    func testRejectsDuplicateManifestIDsAcrossBundle() throws {
        let manifest1 = Data("""
        {"schemaVersion":1,"domain":"intrinsic","id":"mv.dup","version":"1.0.0","name":"Dup A","category":"utility","inputs":[],"parameters":[],"kernelName":""}
        """.utf8)
        let manifest2 = Data("""
        {"schemaVersion":1,"domain":"intrinsic","id":"mv.dup","version":"1.0.1","name":"Dup B","category":"utility","inputs":[],"parameters":[],"kernelName":""}
        """.utf8)

        let bundle = try makeTemporaryBundle(resources: [
            (relativePath: "Manifests/dup_a.json", data: manifest1),
            (relativePath: "Manifests/dup_b.json", data: manifest2)
        ])

        let loader = FeatureRegistryLoader(bundle: bundle, subdirectory: "Manifests")

        do {
            _ = try loader.loadManifests()
            XCTFail("Expected duplicate id validation failure")
        } catch let err as FeatureRegistryLoaderError {
            switch err {
            case .validationFailed(_, let errors):
                XCTAssertTrue(errors.contains(where: { $0.code == "MVFM050" && $0.featureID == "mv.dup" }))
            default:
                XCTFail("Unexpected error: \(err)")
            }
        }
    }

    func testRejectsMissingKernelNameInBundleMetalSources() throws {
        let manifest = Data("""
        {"schemaVersion":1,"id":"com.metavis.fx.missing_kernel","version":"1.0.0","name":"Missing Kernel","category":"utility","inputs":[],"parameters":[],"kernelName":"fx_definitely_missing_kernel"}
        """.utf8)

        let bundle = try makeTemporaryBundle(resources: [
            (relativePath: "Manifests/missing_kernel.json", data: manifest)
        ])

        let loader = FeatureRegistryLoader(bundle: bundle, subdirectory: "Manifests")

        do {
            _ = try loader.loadManifests()
            XCTFail("Expected missing kernel validation failure")
        } catch let err as FeatureRegistryLoaderError {
            switch err {
            case .validationFailed(_, let errors):
                XCTAssertTrue(errors.contains(where: { $0.code == "MVFM051" && $0.featureID == "com.metavis.fx.missing_kernel" }))
            default:
                XCTFail("Unexpected error: \(err)")
            }
        }
    }
}
