import XCTest
import Foundation
import MetaVisGraphics

final class ACESOCIOBakeReferenceTests: XCTestCase {

    private struct CommandResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private func runEnv(_ args: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func repoRoot() -> URL {
        // This test file lives at: <root>/Tests/MetaVisSimulationTests/ACESOCIOBakeReferenceTests.swift
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func bakeCubeLUT(
        configURL: URL,
        inputSpace: String,
        display: String,
        view: String,
        shaperSize: Int,
        cubeSize: Int,
        outputURL: URL
    ) throws -> Data {
        let result = try runEnv([
            "ociobakelut",
            "--iconfig", configURL.path,
            "--inputspace", inputSpace,
            "--displayview", display, view,
            "--shapersize", String(shaperSize),
            "--cubesize", String(cubeSize),
            "--format", "iridas_cube",
            outputURL.path
        ])

        guard result.exitCode == 0 else {
            throw XCTSkip("ociobakelut failed (exit=\(result.exitCode)). stderr=\(result.stderr)")
        }

        return try Data(contentsOf: outputURL)
    }

    private func compareCubePayloads(
        testName: String,
        name: String,
        bakedInRepo: Data,
        bakedFromOCIO: Data,
        maxAbsTolerance: Float
    ) -> (meanAbs: Double, maxAbs: Float) {
        guard let (sizeA, payloadA) = LUTHelper.parseCube(data: bakedInRepo) else {
            XCTFail("Failed to parse baked-in LUT: \(name)")
            return (0, Float.greatestFiniteMagnitude)
        }
        guard let (sizeB, payloadB) = LUTHelper.parseCube(data: bakedFromOCIO) else {
            XCTFail("Failed to parse OCIO-baked LUT: \(name)")
            return (0, Float.greatestFiniteMagnitude)
        }

        XCTAssertEqual(sizeA, sizeB)
        XCTAssertEqual(payloadA.count, payloadB.count)

        var maxAbs: Float = 0
        var sumAbs: Double = 0
        let n = min(payloadA.count, payloadB.count)
        for i in 0..<n {
            let d = abs(payloadA[i] - payloadB[i])
            maxAbs = max(maxAbs, d)
            sumAbs += Double(d)
        }
        let meanAbs = (n > 0) ? (sumAbs / Double(n)) : 0

        print(String(format: "[ColorCert] OCIO bake match (%@): meanAbsErr=%.8f maxAbsErr=%.8f", name, meanAbs, Double(maxAbs)))
        XCTAssertLessThanOrEqual(maxAbs, maxAbsTolerance)

        if PerfLogger.isEnabled() {
            var e = PerfLogger.makeBaseEvent(
                suite: "ColorCertRef",
                test: testName,
                label: "OCIOBakeMatch",
                width: 0,
                height: 0,
                frames: 0
            )
            e.ocioBakeName = name
            e.ocioBakeMeanAbsErr = meanAbs
            e.ocioBakeMaxAbsErr = Double(maxAbs)
            PerfLogger.write(e)
        }

        return (meanAbs, maxAbs)
    }

    func test_ocio_bake_matches_committed_sdr_lut_opt_in() throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_COLOR_CERT"] == "1",
              ProcessInfo.processInfo.environment["METAVIS_RUN_OCIO_REF"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_COLOR_CERT=1 and METAVIS_RUN_OCIO_REF=1")
        }

        // Ensure tool is available.
        do {
            let which = try runEnv(["which", "ociobakelut"])
            guard which.exitCode == 0 else {
                throw XCTSkip("ociobakelut not found in PATH")
            }
        }

        let configURL = repoRoot().appendingPathComponent(".tmp/ocio/cg-config.ocio")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw XCTSkip("Missing OCIO config at \(configURL.path)")
        }

        guard let repoLUT = LUTResources.aces13SDRSRGBDisplayRRTODT33() else {
            XCTFail("Missing committed SDR LUT resource")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("metavis_ocio_ref_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let outURL = tempDir.appendingPathComponent("aces13_sdr_ref.cube")

        let ocioLUT = try bakeCubeLUT(
            configURL: configURL,
            inputSpace: "ACEScg",
            display: "sRGB - Display",
            view: "ACES 1.0 - SDR Video",
            shaperSize: 4096,
            cubeSize: 33,
            outputURL: outURL
        )

        // Allow tiny formatting/implementation differences across OCIO versions.
        _ = compareCubePayloads(
            testName: "test_ocio_bake_matches_committed_sdr_lut_opt_in",
            name: "SDR sRGB - Display / ACES 1.0 - SDR Video",
            bakedInRepo: repoLUT,
            bakedFromOCIO: ocioLUT,
            maxAbsTolerance: 0.001
        )
    }

    func test_ocio_bake_matches_committed_hdr_pq1000_lut_opt_in() throws {
        guard ProcessInfo.processInfo.environment["METAVIS_RUN_COLOR_CERT"] == "1",
              ProcessInfo.processInfo.environment["METAVIS_RUN_OCIO_REF"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_COLOR_CERT=1 and METAVIS_RUN_OCIO_REF=1")
        }

        // Ensure tool is available.
        do {
            let which = try runEnv(["which", "ociobakelut"])
            guard which.exitCode == 0 else {
                throw XCTSkip("ociobakelut not found in PATH")
            }
        }

        let configURL = repoRoot().appendingPathComponent(".tmp/ocio/cg-config.ocio")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw XCTSkip("Missing OCIO config at \(configURL.path)")
        }

        guard let repoLUT = LUTResources.aces13HDRRec2100PQ1000DisplayRRTODT33() else {
            XCTFail("Missing committed HDR PQ1000 LUT resource")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("metavis_ocio_ref_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let outURL = tempDir.appendingPathComponent("aces13_hdr_pq1000_ref.cube")

        let ocioLUT = try bakeCubeLUT(
            configURL: configURL,
            inputSpace: "ACEScg",
            display: "Rec.2100-PQ - Display",
            view: "ACES 1.1 - HDR Video (1000 nits & Rec.2020 lim)",
            shaperSize: 4096,
            cubeSize: 33,
            outputURL: outURL
        )

        _ = compareCubePayloads(
            testName: "test_ocio_bake_matches_committed_hdr_pq1000_lut_opt_in",
            name: "HDR Rec.2100-PQ - Display / ACES 1.1 - HDR Video (1000 nits & Rec.2020 lim)",
            bakedInRepo: repoLUT,
            bakedFromOCIO: ocioLUT,
            maxAbsTolerance: 0.001
        )
    }
}
