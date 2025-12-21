import Foundation
import CoreVideo

public enum DepthSidecarV1Error: Error, Sendable, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidManifest(String)
    case dataFileNotFound
    case unsupportedEndianness
    case invalidFrameIndex
    case readFailed
    case pixelBufferCreateFailed
}

/// Reads the `*.depth.v1.json` + `*.depth.v1.bin` format described in Sprint 24a.
public struct DepthSidecarV1Reader: Sendable {

    public let manifestURL: URL
    public let dataURL: URL
    public let manifest: DepthSidecarV1Manifest

    public init(manifestURL: URL) throws {
        self.manifestURL = manifestURL

        let data = try Data(contentsOf: manifestURL)
        let decoded = try JSONDecoder().decode(DepthSidecarV1Manifest.self, from: data)
        guard decoded.schemaVersion == 1 else {
            throw DepthSidecarV1Error.unsupportedSchemaVersion(decoded.schemaVersion)
        }
        guard decoded.width > 0, decoded.height > 0 else {
            throw DepthSidecarV1Error.invalidManifest("width/height must be > 0")
        }
        guard decoded.frameCount > 0 else {
            throw DepthSidecarV1Error.invalidManifest("frameCount must be > 0")
        }
        guard decoded.frameDurationSeconds > 0 else {
            throw DepthSidecarV1Error.invalidManifest("frameDurationSeconds must be > 0")
        }
        guard decoded.endianness == .little else {
            // v1 chooses simplicity: capture on Apple platforms; store little-endian.
            throw DepthSidecarV1Error.unsupportedEndianness
        }

        self.manifest = decoded

        let base = manifestURL.deletingLastPathComponent()
        let candidate = URL(fileURLWithPath: decoded.dataFile, relativeTo: base).standardizedFileURL
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw DepthSidecarV1Error.dataFileNotFound
        }
        self.dataURL = candidate
    }

    public var frameDurationSeconds: Double { manifest.frameDurationSeconds }

    public func frameIndex(at timeSeconds: Double) -> Int {
        let t = timeSeconds
        let start = manifest.startTimeSeconds
        let dur = manifest.frameDurationSeconds

        if !t.isFinite { return 0 }
        let raw = Int(floor((t - start) / dur))
        return min(max(0, raw), manifest.frameCount - 1)
    }

    public func readDepthFrame(at timeSeconds: Double) throws -> CVPixelBuffer {
        try readDepthFrame(index: frameIndex(at: timeSeconds))
    }

    public func readDepthFrame(index: Int) throws -> CVPixelBuffer {
        guard index >= 0, index < manifest.frameCount else {
            throw DepthSidecarV1Error.invalidFrameIndex
        }

        let frameSize = manifest.frameByteCount
        let offset = Int64(index) * Int64(frameSize)

        let handle = try FileHandle(forReadingFrom: dataURL)
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: frameSize)
            guard let data, data.count == frameSize else {
                throw DepthSidecarV1Error.readFailed
            }

            return try makePixelBuffer(from: data)
        } catch {
            throw DepthSidecarV1Error.readFailed
        }
    }

    private func makePixelBuffer(from rawFrameData: Data) throws -> CVPixelBuffer {
        let w = manifest.width
        let h = manifest.height

        let pixelFormat: OSType
        switch manifest.pixelFormat {
        case .r16f:
            pixelFormat = kCVPixelFormatType_DepthFloat16
        case .r32f:
            pixelFormat = kCVPixelFormatType_OneComponent32Float
        }

        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            w,
            h,
            pixelFormat,
            attrs as CFDictionary,
            &pb
        )

        guard status == kCVReturnSuccess, let out = pb else {
            throw DepthSidecarV1Error.pixelBufferCreateFailed
        }

        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }

        guard let base = CVPixelBufferGetBaseAddress(out) else {
            throw DepthSidecarV1Error.pixelBufferCreateFailed
        }

        // Copy rows respecting bytesPerRow.
        let bpr = CVPixelBufferGetBytesPerRow(out)
        let rowBytes = w * manifest.pixelFormat.bytesPerPixel

        rawFrameData.withUnsafeBytes { src in
            let srcBase = src.baseAddress!
            for y in 0..<h {
                let dstRow = base.advanced(by: y * bpr)
                let srcRow = srcBase.advanced(by: y * rowBytes)
                dstRow.copyMemory(from: srcRow, byteCount: rowBytes)
            }
        }

        return out
    }
}
