import Foundation

public struct DepthSidecarV1Manifest: Sendable, Codable, Equatable {

    public enum PixelFormat: String, Sendable, Codable, Equatable {
        case r16f
        case r32f

        public var bytesPerPixel: Int {
            switch self {
            case .r16f: return 2
            case .r32f: return 4
            }
        }
    }

    public enum Endianness: String, Sendable, Codable, Equatable {
        case little
        case big
    }

    public struct Calibration: Sendable, Codable, Equatable {
        /// 3x3 row-major matrix.
        public var intrinsics3x3RowMajor: [Double]
        public var referenceWidth: Int
        public var referenceHeight: Int

        public init(intrinsics3x3RowMajor: [Double], referenceWidth: Int, referenceHeight: Int) {
            self.intrinsics3x3RowMajor = intrinsics3x3RowMajor
            self.referenceWidth = referenceWidth
            self.referenceHeight = referenceHeight
        }
    }

    public var schemaVersion: Int

    public var width: Int
    public var height: Int

    public var pixelFormat: PixelFormat

    public var frameCount: Int

    public var startTimeSeconds: Double
    public var frameDurationSeconds: Double

    /// File name or relative path to the `.bin` containing tightly packed frames.
    public var dataFile: String

    public var endianness: Endianness

    public var calibration: Calibration?

    public init(
        schemaVersion: Int = 1,
        width: Int,
        height: Int,
        pixelFormat: PixelFormat,
        frameCount: Int,
        startTimeSeconds: Double,
        frameDurationSeconds: Double,
        dataFile: String,
        endianness: Endianness = .little,
        calibration: Calibration? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.frameCount = frameCount
        self.startTimeSeconds = startTimeSeconds
        self.frameDurationSeconds = frameDurationSeconds
        self.dataFile = dataFile
        self.endianness = endianness
        self.calibration = calibration
    }

    public var frameByteCount: Int {
        max(0, width) * max(0, height) * pixelFormat.bytesPerPixel
    }
}
