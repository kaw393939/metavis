import Foundation
import XCTest

@testable import MetaVisLab
import MetaVisPerception

final class SensorsIngestEmitBitesE2ETests: XCTestCase {
    func test_sensorsIngest_emitBites_writesSidecarAndIsDecodable() async throws {
        let fm = FileManager.default
        let outDir = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("test_outputs/_e2e_sensors_emit_bites")
            .appendingPathComponent(UUID().uuidString)

        try? fm.removeItem(at: outDir)
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        let options = SensorsIngestCommand.Options(
            inputMovieURL: URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov"),
            outputDirURL: outDir,
            strideSeconds: 0.5,
            maxVideoSeconds: 10.0,
            audioSeconds: 10.0,
            emitBites: true,
            allowLarge: true,
            enableFaces: true,
            enableSegmentation: true,
            enableAudio: true,
            enableWarnings: true,
            enableDescriptors: true,
            enableAutoStart: true
        )

        try await SensorsIngestCommand.run(options: options)

        let sensorsURL = outDir.appendingPathComponent("sensors.json")
        let bitesURL = outDir.appendingPathComponent("bites.v1.json")

        XCTAssertTrue(fm.fileExists(atPath: sensorsURL.path))
        XCTAssertTrue(fm.fileExists(atPath: bitesURL.path))

        let bitesData = try Data(contentsOf: bitesURL)
        let bites = try JSONDecoder().decode(BiteMap.self, from: bitesData)

        XCTAssertEqual(bites.schemaVersion, BiteMap.schemaVersion)
        XCTAssertFalse(bites.bites.isEmpty, "Expected bites for keith_talk.mov")

        // Single-person fixture expectation.
        let personIds = Set(bites.bites.map { $0.personId })
        XCTAssertEqual(personIds, ["P0"])
    }
}
