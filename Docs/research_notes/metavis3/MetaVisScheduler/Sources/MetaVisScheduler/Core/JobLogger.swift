import Foundation
import MetaVisCore

public struct JobProgress: Codable, Sendable {
    public let jobId: UUID
    public let progress: Double // 0.0 to 1.0
    public let message: String
    public let step: String
    public let timestamp: Date
    
    public init(jobId: UUID, progress: Double, message: String, step: String, timestamp: Date = Date()) {
        self.jobId = jobId
        self.progress = progress
        self.message = message
        self.step = step
        self.timestamp = timestamp
    }
}

public enum JobLogType: String, Codable, Sendable {
    case info
    case warning
    case error
    case success
    case analysis
}

public struct JobLogEntry: Codable, Sendable {
    public let id: UUID
    public let jobId: UUID
    public let type: JobLogType
    public let message: String
    public let details: [String: String]?
    public let timestamp: Date
    
    public init(jobId: UUID, type: JobLogType, message: String, details: [String: String]? = nil) {
        self.id = UUID()
        self.jobId = jobId
        self.type = type
        self.message = message
        self.details = details
        self.timestamp = Date()
    }
}

/// Actor responsible for centralizing job logs and progress updates.
public actor JobLogger {
    public static let shared = JobLogger()
    
    private var progressContinuations: [UUID: AsyncStream<JobProgress>.Continuation] = [:]
    private var logContinuations: [UUID: AsyncStream<JobLogEntry>.Continuation] = [:]
    
    // Global listeners (e.g. for CLI dashboard)
    private var globalProgressContinuations: [UUID: AsyncStream<JobProgress>.Continuation] = [:]
    
    private init() {}
    
    // MARK: - Reporting
    
    public func report(progress: JobProgress) {
        // Notify specific listeners
        // (In a real app, we might want to multicast this more efficiently)
        for (_, continuation) in globalProgressContinuations {
            continuation.yield(progress)
        }
        
        // Log to console for debug
        // print("[\(progress.jobId.uuidString.prefix(6))] \(Int(progress.progress * 100))% - \(progress.message)")
    }
    
    public func log(_ entry: JobLogEntry) {
        // Notify listeners
        // print("[\(entry.type.rawValue.uppercased())] \(entry.message)")
    }
    
    // MARK: - Listening
    
    public func progressStream() -> AsyncStream<JobProgress> {
        let id = UUID()
        return AsyncStream { continuation in
            self.globalProgressContinuations[id] = continuation
            
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeListener(id: id)
                }
            }
        }
    }
    
    private func removeListener(id: UUID) {
        globalProgressContinuations.removeValue(forKey: id)
    }
}
