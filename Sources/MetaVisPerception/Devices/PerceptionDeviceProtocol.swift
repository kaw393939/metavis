import Foundation
import CoreVideo

/// Standardized device contract for MetaVisPerception.
///
/// Notes:
/// - This is intentionally lightweight: it standardizes lifecycle + a single `infer(_:)` entrypoint.
/// - Devices keep their existing APIs; this protocol is an adapter layer to support consistency
///   (benchmarks, orchestration, future refactors) without churn.
public protocol PerceptionDevice: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    func warmUp() async throws
    func coolDown() async

    func infer(_ input: Input) async throws -> Output
}

// MARK: - MaskDevice

public struct MaskDeviceInput: @unchecked Sendable, Equatable {
    public var pixelBuffer: CVPixelBuffer
    public var kind: MaskDevice.Kind
    public var timeSeconds: Double?

    public init(pixelBuffer: CVPixelBuffer, kind: MaskDevice.Kind = .foreground, timeSeconds: Double? = nil) {
        self.pixelBuffer = pixelBuffer
        self.kind = kind
        self.timeSeconds = timeSeconds
    }
}

extension MaskDevice: PerceptionDevice {
    public typealias Input = MaskDeviceInput
    public typealias Output = MaskResult

    public func infer(_ input: MaskDeviceInput) async throws -> MaskResult {
        try await generateMaskResult(in: input.pixelBuffer, kind: input.kind, timeSeconds: input.timeSeconds)
    }

    public func warmUp() async throws {
        try await warmUp(kind: .foreground)
    }
}

// MARK: - FacePartsDevice

public struct FacePartsDeviceInput: @unchecked Sendable, Equatable {
    public var pixelBuffer: CVPixelBuffer

    public init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

extension FacePartsDevice: PerceptionDevice {
    public typealias Input = FacePartsDeviceInput
    public typealias Output = FacePartsResult

    public func infer(_ input: FacePartsDeviceInput) async throws -> FacePartsResult {
        try await facePartsResult(in: input.pixelBuffer)
    }
}

// MARK: - TracksDevice

public struct TracksDeviceInput: @unchecked Sendable, Equatable {
    public var pixelBuffer: CVPixelBuffer

    public init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

extension TracksDevice: PerceptionDevice {
    public typealias Input = TracksDeviceInput
    public typealias Output = TrackResult

    public func infer(_ input: TracksDeviceInput) async throws -> TrackResult {
        try await trackResult(in: input.pixelBuffer)
    }
}

// MARK: - FlowDevice

public struct FlowDeviceInput: @unchecked Sendable, Equatable {
    public var previous: CVPixelBuffer
    public var current: CVPixelBuffer

    public init(previous: CVPixelBuffer, current: CVPixelBuffer) {
        self.previous = previous
        self.current = current
    }
}

extension FlowDevice: PerceptionDevice {
    public typealias Input = FlowDeviceInput
    public typealias Output = FlowResult

    public func infer(_ input: FlowDeviceInput) async throws -> FlowResult {
        try await flowResult(previous: input.previous, current: input.current)
    }
}

// MARK: - DepthDevice

public struct DepthDeviceInput: @unchecked Sendable, Equatable {
    public var rgbFrame: CVPixelBuffer
    public var depthSample: CVPixelBuffer?
    public var confidenceSample: CVPixelBuffer?

    public init(rgbFrame: CVPixelBuffer, depthSample: CVPixelBuffer?, confidenceSample: CVPixelBuffer? = nil) {
        self.rgbFrame = rgbFrame
        self.depthSample = depthSample
        self.confidenceSample = confidenceSample
    }
}

extension DepthDevice: PerceptionDevice {
    public typealias Input = DepthDeviceInput
    public typealias Output = DepthResult

    public func infer(_ input: DepthDeviceInput) async throws -> DepthResult {
        try await depthResult(in: input.rgbFrame, depthSample: input.depthSample, confidenceSample: input.confidenceSample)
    }
}

// MARK: - MobileSAMDevice

public struct MobileSAMDeviceInput: @unchecked Sendable, Equatable {
    public var pixelBuffer: CVPixelBuffer
    public var prompt: MobileSAMDevice.PointPrompt
    public var cacheKey: String?

    public init(pixelBuffer: CVPixelBuffer, prompt: MobileSAMDevice.PointPrompt, cacheKey: String? = nil) {
        self.pixelBuffer = pixelBuffer
        self.prompt = prompt
        self.cacheKey = cacheKey
    }
}

extension MobileSAMDevice: PerceptionDevice {
    public typealias Input = MobileSAMDeviceInput
    public typealias Output = MobileSAMResult

    public func infer(_ input: MobileSAMDeviceInput) async throws -> MobileSAMResult {
        await segment(pixelBuffer: input.pixelBuffer, prompt: input.prompt, cacheKey: input.cacheKey)
    }
}
