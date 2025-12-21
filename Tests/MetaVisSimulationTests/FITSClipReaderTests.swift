import XCTest
import Metal
@testable import MetaVisSimulation

final class FITSClipReaderTests: XCTestCase {

    func test_clipReader_canDecodeFITSStill_toTexture() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fitsURL = tmpDir.appendingPathComponent("tiny.fits")
        let fits = Self.makeMinimalFloat32FITS(width: 2, height: 2, values: [0, 1, 2, 3])
        try fits.write(to: fitsURL, options: [.atomic])

        let reader = ClipReader(device: device, maxCachedFrames: 2)
        let tex = try await reader.texture(assetURL: fitsURL, timeSeconds: 0, width: 2, height: 2)

        XCTAssertEqual(tex.width, 2)
        XCTAssertEqual(tex.height, 2)
    }

    private static func makeMinimalFloat32FITS(width: Int, height: Int, values: [Float]) -> Data {
        precondition(values.count == width * height)

        func card(_ key: String, _ value: String) -> String {
            var s = key.padding(toLength: 8, withPad: " ", startingAt: 0)
            s += "= "
            s += value
            if s.count > 80 { s = String(s.prefix(80)) }
            if s.count < 80 { s = s.padding(toLength: 80, withPad: " ", startingAt: 0) }
            return s
        }

        let headerCards: [String] = [
            card("SIMPLE", "T"),
            card("BITPIX", "-32"),
            card("NAXIS", "2"),
            card("NAXIS1", "\(width)"),
            card("NAXIS2", "\(height)"),
            ("END" + String(repeating: " ", count: 77))
        ]

        var header = headerCards.joined().data(using: .ascii) ?? Data()
        let headerPad = (2880 - (header.count % 2880)) % 2880
        if headerPad > 0 { header.append(Data(repeating: 0x20, count: headerPad)) }

        var payload = Data()
        payload.reserveCapacity(values.count * 4)
        for v in values {
            var bits = v.bitPattern.bigEndian
            withUnsafeBytes(of: &bits) { payload.append(contentsOf: $0) }
        }
        let payloadPad = (2880 - (payload.count % 2880)) % 2880
        if payloadPad > 0 { payload.append(Data(repeating: 0x00, count: payloadPad)) }

        return header + payload
    }
}
