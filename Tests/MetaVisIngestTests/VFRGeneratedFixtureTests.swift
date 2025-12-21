import XCTest
@testable import MetaVisIngest

final class VFRGeneratedFixtureTests: XCTestCase {

    func test_generated_vfr_fixture_is_detected_as_vfr_likely() async throws {
        try requireTool("ffmpeg")

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("metavis_vfr_fixture_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let framesDir = tmp.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

        // Generate 4 deterministic frames.
        let f1 = framesDir.appendingPathComponent("f1.png")
        let f2 = framesDir.appendingPathComponent("f2.png")
        let f3 = framesDir.appendingPathComponent("f3.png")
        let f4 = framesDir.appendingPathComponent("f4.png")

        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=red:s=320x180:r=60",
                "-frames:v", "1",
                f1.path
            ]
        )
        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=green:s=320x180:r=60",
                "-frames:v", "1",
                f2.path
            ]
        )
        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=blue:s=320x180:r=60",
                "-frames:v", "1",
                f3.path
            ]
        )
        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=white:s=320x180:r=60",
                "-frames:v", "1",
                f4.path
            ]
        )

        // Build a concat list with varying per-frame durations to force VFR-like PTS deltas.
        // Important: VideoTimingProbe defaults require >= 30 samples before it will label VFR-likely.
        let list = tmp.appendingPathComponent("list.txt")
        var listText = ""
        // Alternate two frames with two distinct durations to produce many distinct deltas.
        // 40 entries => 39 deltas (>= 30).
        for i in 0..<40 {
            let frameURL = (i % 2 == 0) ? f1 : f2
            let dur = (i % 2 == 0) ? 0.033 : 0.050
            listText += "file '\(frameURL.path)'\n"
            listText += String(format: "duration %.3f\n", dur)
        }
        // Concat demuxer requires the last file to be repeated without a duration.
        listText += "file '\(f2.path)'\n"
        try listText.write(to: list, atomically: true, encoding: .utf8)

        let out = tmp.appendingPathComponent("vfr.mp4")
        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "concat", "-safe", "0", "-i", list.path,
                "-vsync", "vfr",
                "-pix_fmt", "yuv420p",
                "-movflags", "+faststart",
                out.path
            ]
        )

        let profile = try await VideoTimingProbe.probe(url: out)

        // The core contract for this sprint: we can deterministically create and detect a VFR-likely fixture.
        XCTAssertTrue(profile.isVFRLikely, "Expected generated fixture to be detected as VFR-likely")

        if let deltas = profile.deltas {
            XCTAssertGreaterThanOrEqual(deltas.sampleCount, 30)
            XCTAssertGreaterThanOrEqual(deltas.maxSeconds, deltas.minSeconds)
            XCTAssertGreaterThan(deltas.maxSeconds - deltas.minSeconds, 0.0001, "Expected varying frame deltas")
        } else {
            XCTFail("Expected delta stats for generated fixture")
        }

        // And the policy layer should recommend normalization.
        let decision = VideoTimingNormalization.decide(profile: profile, fallbackFPS: 24.0)
        XCTAssertEqual(decision.mode, .normalizeToCFR)
        XCTAssertGreaterThan(decision.targetFPS, 0)
    }

    private func requireTool(_ name: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [name, "-version"]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw XCTSkip("\(name) not available")
        }
    }

    private func run(_ executablePath: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executablePath)
        p.arguments = args
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "MetaVisTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Command failed: \(args.joined(separator: " "))\n\(text)"])
        }
    }
}
