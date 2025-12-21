// ProgressReporter.swift
// MetaVisRender
//
// Created for Sprint 03: Progress reporting for long-running operations
// Provides AsyncStream-based progress updates with stages and ETA

import Foundation

// MARK: - Progress Stage

/// Represents a stage in a multi-stage operation
public struct ProgressStage: Codable, Sendable, Equatable, Identifiable {
    /// Unique identifier for this stage
    public let id: String
    
    /// Human-readable name
    public let name: String
    
    /// Stage order (0-based)
    public let order: Int
    
    /// Weight of this stage for overall progress (0.0-1.0)
    public let weight: Double
    
    public init(id: String, name: String, order: Int, weight: Double) {
        self.id = id
        self.name = name
        self.order = order
        self.weight = max(0, min(1, weight))
    }
}

// MARK: - Progress Event

/// A progress update event
public struct ProgressEvent: Codable, Sendable {
    /// Timestamp of this event
    public let timestamp: Date
    
    /// Current stage (if applicable)
    public let stage: ProgressStage?
    
    /// Progress within current stage (0.0-1.0)
    public let stageProgress: Double
    
    /// Overall progress (0.0-1.0)
    public let overallProgress: Double
    
    /// Current operation description
    public let message: String
    
    /// Items processed so far
    public let itemsCompleted: Int
    
    /// Total items to process
    public let itemsTotal: Int
    
    /// Bytes processed so far
    public let bytesProcessed: UInt64
    
    /// Total bytes to process
    public let bytesTotal: UInt64
    
    /// Estimated time remaining (seconds)
    public let estimatedTimeRemaining: TimeInterval?
    
    /// Processing rate (items per second)
    public let itemsPerSecond: Double?
    
    /// Processing rate (bytes per second)
    public let bytesPerSecond: Double?
    
    /// Whether this is the final event
    public let isComplete: Bool
    
    /// Error if operation failed
    public let error: String?
    
    public init(
        timestamp: Date = Date(),
        stage: ProgressStage? = nil,
        stageProgress: Double,
        overallProgress: Double,
        message: String,
        itemsCompleted: Int = 0,
        itemsTotal: Int = 0,
        bytesProcessed: UInt64 = 0,
        bytesTotal: UInt64 = 0,
        estimatedTimeRemaining: TimeInterval? = nil,
        itemsPerSecond: Double? = nil,
        bytesPerSecond: Double? = nil,
        isComplete: Bool = false,
        error: String? = nil
    ) {
        self.timestamp = timestamp
        self.stage = stage
        self.stageProgress = max(0, min(1, stageProgress))
        self.overallProgress = max(0, min(1, overallProgress))
        self.message = message
        self.itemsCompleted = itemsCompleted
        self.itemsTotal = itemsTotal
        self.bytesProcessed = bytesProcessed
        self.bytesTotal = bytesTotal
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.itemsPerSecond = itemsPerSecond
        self.bytesPerSecond = bytesPerSecond
        self.isComplete = isComplete
        self.error = error
    }
}

// MARK: - Progress Format

/// Output format for progress display
public enum ProgressFormat: String, Codable, Sendable {
    case animated = "animated"  // Terminal-friendly animated display
    case json = "json"          // JSON output for parsing
    case quiet = "quiet"        // Minimal output
    case verbose = "verbose"    // Detailed output
}

// MARK: - Progress Reporter

/// Actor that tracks and reports progress for operations
public actor ProgressReporter {
    
    // MARK: - Properties
    
    /// Unique identifier for this operation
    public let operationId: UUID
    
    /// Operation name
    public let operationName: String
    
    /// Defined stages for this operation
    private let stages: [ProgressStage]
    
    /// Current stage index
    private var currentStageIndex: Int = 0
    
    /// Progress within current stage
    private var stageProgress: Double = 0
    
    /// Operation start time
    private let startTime: Date
    
    /// Total items to process
    private var totalItems: Int = 0
    
    /// Completed items
    private var completedItems: Int = 0
    
    /// Total bytes to process
    private var totalBytes: UInt64 = 0
    
    /// Processed bytes
    private var processedBytes: UInt64 = 0
    
    /// Stream continuation for progress updates
    private var continuation: AsyncStream<ProgressEvent>.Continuation?
    
    /// Whether operation is complete
    private var isComplete: Bool = false
    
    /// Final error if any
    private var finalError: Error?
    
    /// Recent progress history for rate calculation
    private var progressHistory: [(Date, Int, UInt64)] = []
    
    // MARK: - Initialization
    
    /// Create a progress reporter
    /// - Parameters:
    ///   - name: Operation name
    ///   - stages: Stages for this operation (optional)
    public init(
        name: String,
        stages: [ProgressStage] = []
    ) {
        self.operationId = UUID()
        self.operationName = name
        self.stages = stages.isEmpty ? [
            ProgressStage(id: "default", name: "Processing", order: 0, weight: 1.0)
        ] : stages
        self.startTime = Date()
    }
    
    // MARK: - Stream Access
    
    /// Get an AsyncStream of progress events
    public func events() -> AsyncStream<ProgressEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            
            // Send initial event
            Task {
                self.emitProgress(message: "Starting \(operationName)")
            }
            
            continuation.onTermination = { _ in
                Task {
                    await self.cleanup()
                }
            }
        }
    }
    
    // MARK: - Progress Updates
    
    /// Set the total work to be done
    public func setTotal(items: Int, bytes: UInt64 = 0) {
        self.totalItems = items
        self.totalBytes = bytes
    }
    
    /// Update progress for current stage
    public func update(
        message: String,
        itemsCompleted: Int? = nil,
        bytesProcessed: UInt64? = nil
    ) async {
        if let items = itemsCompleted {
            self.completedItems = items
        }
        if let bytes = bytesProcessed {
            self.processedBytes = bytes
        }
        
        // Update stage progress based on items
        if totalItems > 0 {
            stageProgress = Double(completedItems) / Double(totalItems)
        }
        
        // Record for rate calculation
        progressHistory.append((Date(), completedItems, processedBytes))
        if progressHistory.count > 100 {
            progressHistory.removeFirst()
        }
        
        emitProgress(message: message)
    }
    
    /// Update progress with a direct percentage
    public func update(message: String, progress: Double) async {
        stageProgress = max(0, min(1, progress))
        emitProgress(message: message)
    }
    
    /// Increment completed items
    public func increment(by count: Int = 1, bytes: UInt64 = 0, message: String? = nil) async {
        completedItems += count
        processedBytes += bytes
        
        if totalItems > 0 {
            stageProgress = Double(completedItems) / Double(totalItems)
        }
        
        progressHistory.append((Date(), completedItems, processedBytes))
        if progressHistory.count > 100 {
            progressHistory.removeFirst()
        }
        
        let msg = message ?? "Processing item \(completedItems)/\(totalItems)"
        emitProgress(message: msg)
    }
    
    /// Move to next stage
    public func nextStage(message: String? = nil) async {
        if currentStageIndex < stages.count - 1 {
            currentStageIndex += 1
            stageProgress = 0
            completedItems = 0
            processedBytes = 0
            totalItems = 0
            totalBytes = 0
            progressHistory.removeAll()
        }
        
        let msg = message ?? "Starting \(stages[currentStageIndex].name)"
        emitProgress(message: msg)
    }
    
    /// Move to a specific stage by ID
    public func setStage(_ stageId: String, message: String? = nil) async {
        if let index = stages.firstIndex(where: { $0.id == stageId }) {
            currentStageIndex = index
            stageProgress = 0
            completedItems = 0
            processedBytes = 0
            totalItems = 0
            totalBytes = 0
            progressHistory.removeAll()
        }
        
        let msg = message ?? "Starting \(stages[currentStageIndex].name)"
        emitProgress(message: msg)
    }
    
    /// Complete the operation successfully
    public func complete(message: String = "Complete") async {
        isComplete = true
        stageProgress = 1.0
        emitProgress(message: message, isComplete: true)
        continuation?.finish()
    }
    
    /// Fail the operation with an error
    public func fail(error: Error, message: String? = nil) async {
        isComplete = true
        finalError = error
        let msg = message ?? "Failed: \(error.localizedDescription)"
        emitProgress(message: msg, isComplete: true, error: error)
        continuation?.finish()
    }
    
    // MARK: - Private Methods
    
    private func emitProgress(
        message: String,
        isComplete: Bool = false,
        error: Error? = nil
    ) {
        let currentStage = stages[currentStageIndex]
        let overallProgress = calculateOverallProgress()
        let rates = calculateRates()
        let eta = calculateETA(overallProgress: overallProgress, rates: rates)
        
        let event = ProgressEvent(
            stage: currentStage,
            stageProgress: stageProgress,
            overallProgress: overallProgress,
            message: message,
            itemsCompleted: completedItems,
            itemsTotal: totalItems,
            bytesProcessed: processedBytes,
            bytesTotal: totalBytes,
            estimatedTimeRemaining: eta,
            itemsPerSecond: rates.itemsPerSecond,
            bytesPerSecond: rates.bytesPerSecond,
            isComplete: isComplete,
            error: error?.localizedDescription
        )
        
        continuation?.yield(event)
    }
    
    private func calculateOverallProgress() -> Double {
        var overall: Double = 0
        var weightUsed: Double = 0
        
        for (index, stage) in stages.enumerated() {
            if index < currentStageIndex {
                // Completed stage
                overall += stage.weight
                weightUsed += stage.weight
            } else if index == currentStageIndex {
                // Current stage
                overall += stage.weight * stageProgress
                weightUsed += stage.weight
            }
            // Future stages: don't add anything
        }
        
        // Normalize if weights don't sum to 1
        let totalWeight = stages.reduce(0) { $0 + $1.weight }
        if totalWeight > 0 {
            overall /= totalWeight
        }
        
        return overall
    }
    
    private func calculateRates() -> (itemsPerSecond: Double?, bytesPerSecond: Double?) {
        guard progressHistory.count >= 2 else {
            return (nil, nil)
        }
        
        let oldest = progressHistory.first!
        let newest = progressHistory.last!
        
        let timeDiff = newest.0.timeIntervalSince(oldest.0)
        guard timeDiff > 0.1 else {
            return (nil, nil)
        }
        
        let itemsDiff = Double(newest.1 - oldest.1)
        let bytesDiff = Double(newest.2 - oldest.2)
        
        return (
            itemsDiff / timeDiff,
            bytesDiff / timeDiff
        )
    }
    
    private func calculateETA(
        overallProgress: Double,
        rates: (itemsPerSecond: Double?, bytesPerSecond: Double?)
    ) -> TimeInterval? {
        guard overallProgress > 0.01 else {
            return nil
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Method 1: Based on overall progress
        let remainingProgress = 1.0 - overallProgress
        let etaFromProgress = elapsed * (remainingProgress / overallProgress)
        
        // Method 2: Based on item rate
        var etaFromRate: TimeInterval?
        if let itemRate = rates.itemsPerSecond, itemRate > 0, totalItems > 0 {
            let remainingItems = totalItems - completedItems
            etaFromRate = Double(remainingItems) / itemRate
        }
        
        // Prefer rate-based if available, otherwise use progress-based
        return etaFromRate ?? etaFromProgress
    }
    
    private func cleanup() {
        continuation = nil
    }
}

// MARK: - Progress Formatter

/// Formats progress events for display
public struct ProgressFormatter: Sendable {
    
    public let format: ProgressFormat
    
    public init(format: ProgressFormat = .animated) {
        self.format = format
    }
    
    /// Format a progress event for display
    public func format(_ event: ProgressEvent) -> String {
        switch format {
        case .animated:
            return formatAnimated(event)
        case .json:
            return formatJSON(event)
        case .quiet:
            return formatQuiet(event)
        case .verbose:
            return formatVerbose(event)
        }
    }
    
    private func formatAnimated(_ event: ProgressEvent) -> String {
        let percent = Int(event.overallProgress * 100)
        let barWidth = 30
        let filled = Int(Double(barWidth) * event.overallProgress)
        let empty = barWidth - filled
        
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        
        var line = "\r[\(bar)] \(percent)%"
        
        if let stage = event.stage {
            line += " \(stage.name)"
        }
        
        if let eta = event.estimatedTimeRemaining {
            line += " ETA: \(formatDuration(eta))"
        }
        
        // Pad to clear previous line
        line += String(repeating: " ", count: 20)
        
        if event.isComplete {
            line += "\n"
        }
        
        return line
    }
    
    private func formatJSON(_ event: ProgressEvent) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(event),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        
        return json
    }
    
    private func formatQuiet(_ event: ProgressEvent) -> String {
        if event.isComplete {
            return event.error != nil ? "FAILED: \(event.error!)" : "DONE"
        }
        return ""
    }
    
    private func formatVerbose(_ event: ProgressEvent) -> String {
        var lines: [String] = []
        
        let timestamp = ISO8601DateFormatter().string(from: event.timestamp)
        lines.append("[\(timestamp)]")
        
        if let stage = event.stage {
            lines.append("Stage: \(stage.name) (\(stage.order + 1)/\(stage.order + 1))")
        }
        
        let percent = String(format: "%.1f%%", event.overallProgress * 100)
        lines.append("Progress: \(percent)")
        
        if event.itemsTotal > 0 {
            lines.append("Items: \(event.itemsCompleted)/\(event.itemsTotal)")
        }
        
        if event.bytesTotal > 0 {
            lines.append("Bytes: \(formatBytes(event.bytesProcessed))/\(formatBytes(event.bytesTotal))")
        }
        
        if let rate = event.itemsPerSecond {
            lines.append(String(format: "Rate: %.1f items/sec", rate))
        }
        
        if let eta = event.estimatedTimeRemaining {
            lines.append("ETA: \(formatDuration(eta))")
        }
        
        lines.append("Message: \(event.message)")
        
        if let error = event.error {
            lines.append("Error: \(error)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

// MARK: - Standard Stages

/// Common progress stage definitions
public enum StandardStages {
    
    /// File ingestion stages
    public static let ingest: [ProgressStage] = [
        ProgressStage(id: "scan", name: "Scanning", order: 0, weight: 0.1),
        ProgressStage(id: "probe", name: "Probing", order: 1, weight: 0.2),
        ProgressStage(id: "extract", name: "Extracting", order: 2, weight: 0.3),
        ProgressStage(id: "analyze", name: "Analyzing", order: 3, weight: 0.3),
        ProgressStage(id: "index", name: "Indexing", order: 4, weight: 0.1)
    ]
    
    /// Transcription stages
    public static let transcribe: [ProgressStage] = [
        ProgressStage(id: "extract", name: "Extracting Audio", order: 0, weight: 0.2),
        ProgressStage(id: "vad", name: "Speech Detection", order: 1, weight: 0.1),
        ProgressStage(id: "transcribe", name: "Transcribing", order: 2, weight: 0.5),
        ProgressStage(id: "diarize", name: "Speaker Identification", order: 3, weight: 0.15),
        ProgressStage(id: "caption", name: "Generating Captions", order: 4, weight: 0.05)
    ]
    
    /// Render stages
    public static let render: [ProgressStage] = [
        ProgressStage(id: "prepare", name: "Preparing", order: 0, weight: 0.1),
        ProgressStage(id: "decode", name: "Decoding", order: 1, weight: 0.3),
        ProgressStage(id: "process", name: "Processing", order: 2, weight: 0.3),
        ProgressStage(id: "encode", name: "Encoding", order: 3, weight: 0.25),
        ProgressStage(id: "finalize", name: "Finalizing", order: 4, weight: 0.05)
    ]
    
    /// Analysis stages
    public static let analyze: [ProgressStage] = [
        ProgressStage(id: "load", name: "Loading", order: 0, weight: 0.2),
        ProgressStage(id: "vision", name: "Vision Analysis", order: 1, weight: 0.4),
        ProgressStage(id: "audio", name: "Audio Analysis", order: 2, weight: 0.3),
        ProgressStage(id: "report", name: "Generating Report", order: 3, weight: 0.1)
    ]
}
