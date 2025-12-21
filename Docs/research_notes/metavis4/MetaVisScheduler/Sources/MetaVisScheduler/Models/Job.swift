import Foundation
import GRDB

// MARK: - Enums

public enum JobStatus: String, Codable, DatabaseValueConvertible, Sendable {
    case pending
    case blocked
    case running
    case completed
    case failed
    case cancelled
}

public enum JobType: String, Codable, DatabaseValueConvertible, Sendable {
    case ingest
    case generate
    case render
    case export
    case analysis
}

// MARK: - Job Model

public struct Job: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    public let id: UUID
    public let type: JobType
    public var status: JobStatus
    public var priority: Int
    public let createdAt: Date
    public var updatedAt: Date
    public let payload: Data
    public var result: Data?
    public var error: String?
    
    public init(
        id: UUID = UUID(),
        type: JobType,
        status: JobStatus = .pending,
        priority: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        payload: Data,
        result: Data? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.payload = payload
        self.result = result
        self.error = error
    }
    
    // GRDB Table Mapping
    public static var databaseTableName = "jobs"
}

// MARK: - Dependency Model

public struct JobDependency: Codable, FetchableRecord, PersistableRecord, Sendable {
    public let jobId: UUID
    public let dependsOnId: UUID
    
    public init(jobId: UUID, dependsOnId: UUID) {
        self.jobId = jobId
        self.dependsOnId = dependsOnId
    }
    
    public static var databaseTableName = "job_dependencies"
}
