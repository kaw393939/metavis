// ExportManager.swift
// MetaVisRender
//
// Created for Sprint 13: Export & Delivery
// Orchestrates export jobs and manages the export pipeline

import Foundation
import AVFoundation

// MARK: - ExportJobID

/// Unique identifier for export jobs
public struct ExportJobID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    
    public init() {
        self.rawValue = UUID()
    }
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    public var description: String {
        rawValue.uuidString.prefix(8).description
    }
}

// MARK: - ExportJobState

/// State of an export job
public enum ExportJobState: Sendable, CustomStringConvertible {
    case queued
    case preparing
    case encoding(progress: Double)
    case muxing
    case writingMetadata
    case generatingThumbnails
    case completed
    case failed(Error)
    case cancelled
    
    public var description: String {
        switch self {
        case .queued: return "Queued"
        case .preparing: return "Preparing"
        case .encoding(let progress): return "Encoding (\(Int(progress * 100))%)"
        case .muxing: return "Muxing"
        case .writingMetadata: return "Writing Metadata"
        case .generatingThumbnails: return "Generating Thumbnails"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
    
    public var progress: Double {
        switch self {
        case .queued: return 0
        case .preparing: return 0.05
        case .encoding(let p): return 0.05 + p * 0.85
        case .muxing: return 0.92
        case .writingMetadata: return 0.95
        case .generatingThumbnails: return 0.98
        case .completed: return 1.0
        case .failed, .cancelled: return 0
        }
    }
}

// MARK: - ExportJob

/// Represents a single export job
public struct ExportJob: Identifiable, Sendable {
    public let id: ExportJobID
    public let configuration: ExportConfiguration
    public let outputURL: URL
    public let createdAt: Date
    public var state: ExportJobState
    public var startedAt: Date?
    public var completedAt: Date?
    public var error: Error?
    public var outputFileSize: Int64?
    public var thumbnailURLs: [URL]
    
    public init(
        id: ExportJobID = ExportJobID(),
        configuration: ExportConfiguration,
        outputURL: URL
    ) {
        self.id = id
        self.configuration = configuration
        self.outputURL = outputURL
        self.createdAt = Date()
        self.state = .queued
        self.thumbnailURLs = []
    }
    
    public var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }
}

// MARK: - ExportJobProgress

/// Progress update for export job
public struct ExportJobProgress: Sendable {
    public let jobID: ExportJobID
    public let state: ExportJobState
    public let framesEncoded: Int
    public let totalFrames: Int
    public let currentTime: TimeInterval
    public let totalDuration: TimeInterval
    public let estimatedTimeRemaining: TimeInterval?
    public let bytesWritten: Int64
    
    public var percentComplete: Double {
        state.progress
    }
}

// MARK: - ExportResult

/// Result of a completed export
public struct ExportResult: @unchecked Sendable {
    public let jobID: ExportJobID
    public let outputURL: URL
    public let fileSize: Int64
    public let duration: TimeInterval
    public let thumbnailURLs: [URL]
    public let encodingTime: TimeInterval
    public let metadata: [String: Any]
    
    public init(
        jobID: ExportJobID,
        outputURL: URL,
        fileSize: Int64,
        duration: TimeInterval,
        thumbnailURLs: [URL],
        encodingTime: TimeInterval,
        metadata: [String: Any] = [:]
    ) {
        self.jobID = jobID
        self.outputURL = outputURL
        self.fileSize = fileSize
        self.duration = duration
        self.thumbnailURLs = thumbnailURLs
        self.encodingTime = encodingTime
        self.metadata = metadata
    }
}

// MARK: - ExportError

/// Errors that can occur during export
public enum ExportError: Error, LocalizedError, Sendable {
    case jobNotFound(ExportJobID)
    case invalidConfiguration(String)
    case outputURLExists(URL)
    case encoderInitFailed(String)
    case frameEncodingFailed(Int, String)
    case muxingFailed(String)
    case writeMetadataFailed(String)
    case thumbnailGenerationFailed(String)
    case cancelled
    case unsupportedCodec(String)
    case resourceNotAvailable(String)
    
    public var errorDescription: String? {
        switch self {
        case .jobNotFound(let id):
            return "Export job not found: \(id)"
        case .invalidConfiguration(let msg):
            return "Invalid export configuration: \(msg)"
        case .outputURLExists(let url):
            return "Output file already exists: \(url.lastPathComponent)"
        case .encoderInitFailed(let msg):
            return "Failed to initialize encoder: \(msg)"
        case .frameEncodingFailed(let frame, let msg):
            return "Failed to encode frame \(frame): \(msg)"
        case .muxingFailed(let msg):
            return "Failed to mux streams: \(msg)"
        case .writeMetadataFailed(let msg):
            return "Failed to write metadata: \(msg)"
        case .thumbnailGenerationFailed(let msg):
            return "Failed to generate thumbnails: \(msg)"
        case .cancelled:
            return "Export was cancelled"
        case .unsupportedCodec(let codec):
            return "Unsupported codec: \(codec)"
        case .resourceNotAvailable(let resource):
            return "Resource not available: \(resource)"
        }
    }
}

// MARK: - ExportManagerDelegate

/// Protocol for receiving export updates
public protocol ExportManagerDelegate: AnyObject, Sendable {
    func exportManager(_ manager: ExportManager, didUpdateProgress progress: ExportJobProgress) async
    func exportManager(_ manager: ExportManager, didComplete result: ExportResult) async
    func exportManager(_ manager: ExportManager, didFail jobID: ExportJobID, error: Error) async
}

// MARK: - ExportManager

/// Manages the export pipeline and job queue
///
/// Coordinates video encoding, audio encoding, muxing, and metadata writing
/// to produce final output files. Supports concurrent exports and
/// priority-based scheduling.
///
/// ## Example
/// ```swift
/// let manager = ExportManager()
/// 
/// let config = ExportConfiguration(preset: .youtube1080p)
/// let jobID = try await manager.enqueue(
///     configuration: config,
///     outputURL: outputURL
/// )
/// 
/// // Wait for completion
/// let result = try await manager.waitForCompletion(jobID: jobID)
/// print("Exported to: \(result.outputURL)")
/// ```
public actor ExportManager {
    
    // MARK: - Types
    
    public typealias ProgressHandler = @Sendable (ExportJobProgress) -> Void
    
    // MARK: - Properties
    
    /// Active jobs
    private var jobs: [ExportJobID: ExportJob] = [:]
    
    /// Job queue ordered by priority
    private var queue: [ExportJobID] = []
    
    /// Currently running jobs
    private var runningJobs: Set<ExportJobID> = []
    
    /// Maximum concurrent exports
    public let maxConcurrent: Int
    
    /// Delegate for updates
    private weak var delegate: ExportManagerDelegate?
    
    /// Progress handlers per job
    private var progressHandlers: [ExportJobID: ProgressHandler] = [:]
    
    /// Continuations waiting for job completion
    private var completionContinuations: [ExportJobID: [CheckedContinuation<ExportResult, Error>]] = [:]
    
    /// Active export tasks
    private var exportTasks: [ExportJobID: Task<Void, Never>] = [:]
    
    // MARK: - Initialization
    
    public init(maxConcurrent: Int = 2) {
        self.maxConcurrent = maxConcurrent
    }
    
    // MARK: - Configuration
    
    public func setDelegate(_ delegate: ExportManagerDelegate?) {
        self.delegate = delegate
    }
    
    // MARK: - Queue Management
    
    /// Enqueue a new export job
    @discardableResult
    public func enqueue(
        configuration: ExportConfiguration,
        outputURL: URL,
        progress: ProgressHandler? = nil
    ) throws -> ExportJobID {
        // Validate configuration
        try validateConfiguration(configuration)
        
        // Check output URL
        if !configuration.replaceExisting && FileManager.default.fileExists(atPath: outputURL.path) {
            throw ExportError.outputURLExists(outputURL)
        }
        
        // Create job
        let job = ExportJob(
            configuration: configuration,
            outputURL: outputURL
        )
        
        jobs[job.id] = job
        
        if let progress = progress {
            progressHandlers[job.id] = progress
        }
        
        // Insert into queue by priority
        insertIntoQueue(jobID: job.id, priority: configuration.priority)
        
        // Start processing queue
        Task {
            await processQueue()
        }
        
        return job.id
    }
    
    /// Cancel an export job
    public func cancel(jobID: ExportJobID) throws {
        guard var job = jobs[jobID] else {
            throw ExportError.jobNotFound(jobID)
        }
        
        // Cancel running task
        if let task = exportTasks[jobID] {
            task.cancel()
            exportTasks.removeValue(forKey: jobID)
        }
        
        // Update state
        job.state = .cancelled
        jobs[jobID] = job
        
        // Remove from queue
        queue.removeAll { $0 == jobID }
        runningJobs.remove(jobID)
        
        // Notify waiting continuations
        if let continuations = completionContinuations[jobID] {
            for continuation in continuations {
                continuation.resume(throwing: ExportError.cancelled)
            }
            completionContinuations.removeValue(forKey: jobID)
        }
        
        // Continue processing
        Task {
            await processQueue()
        }
    }
    
    /// Cancel all jobs
    public func cancelAll() {
        for jobID in jobs.keys {
            try? cancel(jobID: jobID)
        }
    }
    
    /// Get job status
    public func status(jobID: ExportJobID) -> ExportJob? {
        jobs[jobID]
    }
    
    /// Get all jobs
    public func allJobs() -> [ExportJob] {
        Array(jobs.values)
    }
    
    /// Get queued jobs
    public func queuedJobs() -> [ExportJob] {
        queue.compactMap { jobs[$0] }
    }
    
    /// Wait for job completion
    public func waitForCompletion(jobID: ExportJobID) async throws -> ExportResult {
        guard let job = jobs[jobID] else {
            throw ExportError.jobNotFound(jobID)
        }
        
        // Already complete?
        if case .completed = job.state {
            return buildResult(for: job)
        }
        
        // Already failed?
        if case .failed(let error) = job.state {
            throw error
        }
        
        // Wait for completion
        return try await withCheckedThrowingContinuation { continuation in
            if completionContinuations[jobID] == nil {
                completionContinuations[jobID] = []
            }
            completionContinuations[jobID]?.append(continuation)
        }
    }
    
    // MARK: - Queue Processing
    
    private func insertIntoQueue(jobID: ExportJobID, priority: Int) {
        // Insert based on priority (higher priority = earlier in queue)
        let insertIndex = queue.firstIndex { existingID in
            guard let existing = jobs[existingID] else { return false }
            return existing.configuration.priority < priority
        } ?? queue.endIndex
        
        queue.insert(jobID, at: insertIndex)
    }
    
    private func processQueue() async {
        // Start jobs up to max concurrent
        while runningJobs.count < maxConcurrent, let nextJobID = queue.first {
            queue.removeFirst()
            runningJobs.insert(nextJobID)
            
            // Start export task
            let task = Task {
                await runExport(jobID: nextJobID)
            }
            exportTasks[nextJobID] = task
        }
    }
    
    private func runExport(jobID: ExportJobID) async {
        guard var job = jobs[jobID] else { return }
        
        job.startedAt = Date()
        job.state = .preparing
        jobs[jobID] = job
        
        await reportProgress(jobID: jobID)
        
        do {
            // Run the actual export
            let result = try await performExport(job: job)
            
            // Update job
            job.state = .completed
            job.completedAt = Date()
            job.outputFileSize = result.fileSize
            job.thumbnailURLs = result.thumbnailURLs
            jobs[jobID] = job
            
            // Notify completion
            await notifyCompletion(jobID: jobID, result: result)
            
        } catch {
            // Update job
            job.state = .failed(error)
            job.completedAt = Date()
            job.error = error
            jobs[jobID] = job
            
            // Notify failure
            await notifyFailure(jobID: jobID, error: error)
        }
        
        // Cleanup
        runningJobs.remove(jobID)
        exportTasks.removeValue(forKey: jobID)
        progressHandlers.removeValue(forKey: jobID)
        
        // Process next in queue
        await processQueue()
    }
    
    // MARK: - Export Implementation
    
    private func performExport(job: ExportJob) async throws -> ExportResult {
        let config = job.configuration
        
        // Ensure output directory exists
        let outputDir = job.outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true
        )
        
        // Remove existing file if needed
        if config.replaceExisting {
            try? FileManager.default.removeItem(at: job.outputURL)
        }
        
        // TODO: Integrate with full render pipeline
        // For now, create a placeholder implementation that demonstrates the API
        
        var jobCopy = job
        
        // Simulate encoding phases
        let totalFrames = Int(30.0 * 60.0)  // 60 seconds at 30fps placeholder
        let framesPerUpdate = max(1, totalFrames / 100)
        
        for frame in stride(from: 0, to: totalFrames, by: framesPerUpdate) {
            // Check for cancellation
            try Task.checkCancellation()
            
            // Update progress
            let progress = Double(frame) / Double(totalFrames)
            jobCopy.state = .encoding(progress: progress)
            jobs[job.id] = jobCopy
            
            await reportProgress(jobID: job.id)
            
            // Simulate work
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        
        // Muxing phase
        jobCopy.state = .muxing
        jobs[job.id] = jobCopy
        await reportProgress(jobID: job.id)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Metadata phase
        jobCopy.state = .writingMetadata
        jobs[job.id] = jobCopy
        await reportProgress(jobID: job.id)
        try await Task.sleep(nanoseconds: 50_000_000)
        
        // Generate thumbnails
        var thumbnailURLs: [URL] = []
        if config.thumbnails.enabled {
            jobCopy.state = .generatingThumbnails
            jobs[job.id] = jobCopy
            await reportProgress(jobID: job.id)
            
            thumbnailURLs = try await generateThumbnails(for: job)
        }
        
        // Create placeholder output file
        let placeholderData = "Placeholder export file".data(using: .utf8)!
        try placeholderData.write(to: job.outputURL)
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: job.outputURL.path)[.size] as? Int64 ?? 0
        
        return ExportResult(
            jobID: job.id,
            outputURL: job.outputURL,
            fileSize: fileSize,
            duration: config.timeRange?.duration ?? 60.0,
            thumbnailURLs: thumbnailURLs,
            encodingTime: job.startedAt.map { Date().timeIntervalSince($0) } ?? 0
        )
    }
    
    private func generateThumbnails(for job: ExportJob) async throws -> [URL] {
        let config = job.configuration.thumbnails
        guard config.enabled else { return [] }
        
        var urls: [URL] = []
        let baseURL = job.outputURL.deletingPathExtension()
        
        for i in 0..<config.count {
            let thumbURL = baseURL
                .appendingPathExtension("thumb\(i)")
                .appendingPathExtension(config.format.fileExtension)
            
            // TODO: Generate actual thumbnails
            // Placeholder
            let placeholderData = Data([0x89, 0x50, 0x4E, 0x47])  // PNG header
            try placeholderData.write(to: thumbURL)
            urls.append(thumbURL)
        }
        
        return urls
    }
    
    // MARK: - Validation
    
    private func validateConfiguration(_ config: ExportConfiguration) throws {
        // Validate preset
        let preset = config.preset
        
        // Check codec support
        switch preset.video.codec {
        case .h264, .hevc, .prores422, .prores422HQ, .prores4444:
            break  // Supported
        default:
            throw ExportError.unsupportedCodec(preset.video.codec.rawValue)
        }
        
        // Validate time range
        if let range = config.timeRange {
            if range.duration <= 0 {
                throw ExportError.invalidConfiguration("Time range duration must be positive")
            }
        }
        
        // Validate manual crop region
        if config.reframingMode == .manual {
            guard let region = config.manualCropRegion else {
                throw ExportError.invalidConfiguration("Manual reframing requires a crop region")
            }
            
            if region.width <= 0 || region.height <= 0 ||
               region.x < 0 || region.y < 0 ||
               region.x + region.width > 1 || region.y + region.height > 1 {
                throw ExportError.invalidConfiguration("Invalid crop region")
            }
        }
    }
    
    // MARK: - Notifications
    
    private func reportProgress(jobID: ExportJobID) async {
        guard let job = jobs[jobID] else { return }
        
        let progress = ExportJobProgress(
            jobID: jobID,
            state: job.state,
            framesEncoded: 0,
            totalFrames: 0,
            currentTime: 0,
            totalDuration: job.configuration.timeRange?.duration ?? 0,
            estimatedTimeRemaining: nil,
            bytesWritten: 0
        )
        
        // Call progress handler
        if let handler = progressHandlers[jobID] {
            handler(progress)
        }
        
        // Notify delegate
        await delegate?.exportManager(self, didUpdateProgress: progress)
    }
    
    private func notifyCompletion(jobID: ExportJobID, result: ExportResult) async {
        // Notify continuations
        if let continuations = completionContinuations[jobID] {
            for continuation in continuations {
                continuation.resume(returning: result)
            }
            completionContinuations.removeValue(forKey: jobID)
        }
        
        // Notify delegate
        await delegate?.exportManager(self, didComplete: result)
    }
    
    private func notifyFailure(jobID: ExportJobID, error: Error) async {
        // Notify continuations
        if let continuations = completionContinuations[jobID] {
            for continuation in continuations {
                continuation.resume(throwing: error)
            }
            completionContinuations.removeValue(forKey: jobID)
        }
        
        // Notify delegate
        await delegate?.exportManager(self, didFail: jobID, error: error)
    }
    
    private func buildResult(for job: ExportJob) -> ExportResult {
        ExportResult(
            jobID: job.id,
            outputURL: job.outputURL,
            fileSize: job.outputFileSize ?? 0,
            duration: job.configuration.timeRange?.duration ?? 0,
            thumbnailURLs: job.thumbnailURLs,
            encodingTime: job.duration ?? 0
        )
    }
}

// MARK: - Convenience Extensions

extension ExportManager {
    /// Quick export with default settings
    public func export(
        preset: ExportPreset,
        to outputURL: URL,
        progress: ProgressHandler? = nil
    ) async throws -> ExportResult {
        let config = ExportConfiguration(preset: preset)
        let jobID = try enqueue(
            configuration: config,
            outputURL: outputURL,
            progress: progress
        )
        return try await waitForCompletion(jobID: jobID)
    }
    
    /// Multi-output export
    public func exportMultiple(
        multiConfig: MultiOutputConfiguration,
        outputDirectory: URL,
        progress: ProgressHandler? = nil
    ) async throws -> [ExportResult] {
        var results: [ExportResult] = []
        
        if multiConfig.parallel {
            // Export in parallel with limited concurrency
            try await withThrowingTaskGroup(of: ExportResult.self) { group in
                for config in multiConfig.outputs {
                    let outputURL = outputDirectory
                        .appendingPathComponent(config.preset.id)
                        .appendingPathExtension(config.preset.container.fileExtension)
                    
                    group.addTask {
                        let jobID = try await self.enqueue(
                            configuration: config,
                            outputURL: outputURL,
                            progress: progress
                        )
                        return try await self.waitForCompletion(jobID: jobID)
                    }
                }
                
                for try await result in group {
                    results.append(result)
                }
            }
        } else {
            // Export sequentially
            for config in multiConfig.outputs {
                let outputURL = outputDirectory
                    .appendingPathComponent(config.preset.id)
                    .appendingPathExtension(config.preset.container.fileExtension)
                
                let jobID = try enqueue(
                    configuration: config,
                    outputURL: outputURL,
                    progress: progress
                )
                let result = try await waitForCompletion(jobID: jobID)
                results.append(result)
            }
        }
        
        return results
    }
}
