import XCTest
@testable import MetaVisIngest
import MetaVisCore

final class FITSReaderTests: XCTestCase {

    func test_read_minimalFloat32FITS_parsesAndConvertsEndianness() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = tmpDir.appendingPathComponent("tiny.fits")
        let fits = Self.makeMinimalFloat32FITS(width: 2, height: 2, values: [1, 2, 3, 4])
        try fits.write(to: url, options: [.atomic])

        let asset = try FITSReader().read(url: url)
        XCTAssertEqual(asset.width, 2)
        XCTAssertEqual(asset.height, 2)
        XCTAssertEqual(asset.bitpix, -32)

        XCTAssertEqual(asset.statistics.min, 1, accuracy: 1e-6)
        XCTAssertEqual(asset.statistics.max, 4, accuracy: 1e-6)
        XCTAssertEqual(asset.statistics.mean, 2.5, accuracy: 1e-6)

        // Validate payload conversion by reading first float.
        let first: Float = asset.rawData.withUnsafeBytes { raw in
            raw.bindMemory(to: Float.self).first ?? .nan
        }
        XCTAssertEqual(first, 1, accuracy: 1e-6)
    }

    func test_read_doesNotReadTrailingGarbageEagerly() throws {
        #if !DEBUG
        throw XCTSkip("Diagnostics are only available in DEBUG builds")
        #else
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = tmpDir.appendingPathComponent("tiny_plus_trailing.fits")
        var fits = Self.makeMinimalFloat32FITS(width: 2, height: 2, values: [1, 2, 3, 4])

        // Append a large trailing region that should not be read.
        fits.append(Data(repeating: 0xAB, count: 10 * 1024 * 1024))
        try fits.write(to: url, options: [.atomic])

        let asset = try FITSReader().read(url: url)
        XCTAssertEqual(asset.width, 2)
        XCTAssertEqual(asset.height, 2)

        // The streaming reader should read header blocks + payload, not the trailing bytes.
        XCTAssertLessThan(FITSReader.Diagnostics.lastBytesRead, 1_000_000)
        #endif
    }

    func test_readFloat32Scanline_readsIncrementallyAndConvertsEndianness() throws {
        #if !DEBUG
        throw XCTSkip("Diagnostics are only available in DEBUG builds")
        #else
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = tmpDir.appendingPathComponent("tiny_scanline.fits")
        let fits = Self.makeMinimalFloat32FITS(width: 2, height: 2, values: [1, 2, 3, 4])
        try fits.write(to: url, options: [.atomic])

        let row0 = try FITSReader().readFloat32Scanline(url: url, row: 0)
        XCTAssertEqual(row0.count, 2)
        XCTAssertEqual(row0[0], 1, accuracy: 1e-6)
        XCTAssertEqual(row0[1], 2, accuracy: 1e-6)

        // Structural check: scanline read should not pull the entire file.
        XCTAssertLessThan(FITSReader.Diagnostics.lastBytesRead, 1_000_000)
        #endif
    }

    private static func makeMinimalFloat32FITS(width: Int, height: Int, values: [Float]) -> Data {
        precondition(values.count == width * height)

        func card(_ key: String, _ value: String) -> String {
            // FITS cards are 80 bytes ASCII.
            // Keyword in first 8 chars, value after '='.
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
            // END card (keyword only; rest spaces)
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
