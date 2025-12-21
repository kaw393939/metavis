import Foundation

/// Job tracking structure matching ei_cli VeoDatabase pattern
public struct RenderJob: Codable, Sendable {
    public let id: String
    public var status: JobStatus
    public let request: VisualizationRequest?
    public let animationConfigData: Data? // Encoded AnimationConfig
    public let imageAnimationData: Data? // Encoded ImageAnimationRequest
    public let compositionData: Data? // Encoded Composition
    public var progress: Double
    public var currentFrame: Int
    public var totalFrames: Int
    public var outputPath: String?
    public var error: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var estimatedDuration: Double

    public init(
        id: String = UUID().uuidString,
        status: JobStatus = .queued,
        request: VisualizationRequest? = nil,
        animationConfigData: Data? = nil,
        imageAnimationData: Data? = nil,
        compositionData: Data? = nil,
        progress: Double = 0.0,
        currentFrame: Int = 0,
        totalFrames: Int,
        outputPath: String? = nil,
        error: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        estimatedDuration: Double = 0.0
    ) {
        self.id = id
        self.status = status
        self.request = request
        self.animationConfigData = animationConfigData
        self.imageAnimationData = imageAnimationData
        self.compositionData = compositionData
        self.progress = progress
        self.currentFrame = currentFrame
        self.totalFrames = totalFrames
        self.outputPath = outputPath
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.estimatedDuration = estimatedDuration
    }

    public var isAnimated: Bool {
        return animationConfigData != nil
    }

    public var isImageAnimation: Bool {
        return imageAnimationData != nil
    }

    public var isComposition: Bool {
        return compositionData != nil
    }
}

public enum JobStatus: String, Codable, Sendable {
    case queued
    case rendering
    case completed
    case failed
}

/// API Response structures matching ei_cli patterns

public struct SubmitJobResponse: Codable, Sendable {
    public let jobId: String
    public let status: String
    public let estimatedTime: Double?

    public init(jobId: String, status: String, estimatedTime: Double? = nil) {
        self.jobId = jobId
        self.status = status
        self.estimatedTime = estimatedTime
    }
}

public struct JobStatusResponse: Codable, Sendable {
    public let jobId: String
    public let status: String
    public let progress: Double
    public let currentFrame: Int
    public let totalFrames: Int
    public let elapsedTime: Double?
    public let error: String?

    public init(
        jobId: String,
        status: String,
        progress: Double,
        currentFrame: Int,
        totalFrames: Int,
        elapsedTime: Double? = nil,
        error: String? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.progress = progress
        self.currentFrame = currentFrame
        self.totalFrames = totalFrames
        self.elapsedTime = elapsedTime
        self.error = error
    }
}

public struct JobResultResponse: Codable, Sendable {
    public let jobId: String
    public let status: String
    public let outputPath: String?
    public let duration: Double
    public let resolution: String
    public let fileSize: String?
    public let renderTime: Double
    public let error: String?

    public init(
        jobId: String,
        status: String,
        outputPath: String? = nil,
        duration: Double,
        resolution: String,
        fileSize: String? = nil,
        renderTime: Double,
        error: String? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.outputPath = outputPath
        self.duration = duration
        self.resolution = resolution
        self.fileSize = fileSize
        self.renderTime = renderTime
        self.error = error
    }
}

public struct ErrorResponse: Codable, Sendable {
    public let error: String
    public let details: String?

    public init(error: String, details: String? = nil) {
        self.error = error
        self.details = details
    }
}
