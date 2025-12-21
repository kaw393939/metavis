import Foundation
import GRDB

/// Manages the persistence of Jobs and their dependencies.
public final class JobQueue: Sendable {
    
    private let dbQueue: DatabaseQueue
    
    public init(path: String? = nil) throws {
        if let path = path {
            self.dbQueue = try DatabaseQueue(path: path)
        } else {
            // In-memory for testing or ephemeral sessions
            self.dbQueue = try DatabaseQueue()
        }
        try migrator.migrate(dbQueue)
    }
    
    // MARK: - Migration
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: "jobs") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("status", .text).notNull()
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("payload", .blob).notNull()
                t.column("result", .blob)
                t.column("error", .text)
            }
            
            try db.create(table: "job_dependencies") { t in
                t.column("jobId", .text).notNull().references("jobs", onDelete: .cascade)
                t.column("dependsOnId", .text).notNull().references("jobs", onDelete: .cascade)
                t.primaryKey(["jobId", "dependsOnId"])
            }
        }
        
        return migrator
    }
    
    // MARK: - Operations
    
    public func add(job: Job, dependencies: [UUID] = []) throws {
        try dbQueue.write { db in
            try job.save(db)
            for depId in dependencies {
                let dep = JobDependency(jobId: job.id, dependsOnId: depId)
                try dep.save(db)
            }
            
            // If dependencies exist, mark as blocked
            if !dependencies.isEmpty {
                var updatedJob = job
                updatedJob.status = .blocked
                try updatedJob.save(db)
            }
        }
    }
    
    public func update(job: Job) throws {
        try dbQueue.write { db in
            var updated = job
            updated.updatedAt = Date()
            try updated.save(db)
            
            // If job completed, check dependents
            if job.status == .completed {
                try self.unblockDependents(of: job.id, in: db)
            }
        }
    }
    
    public func getNextPendingJob() throws -> Job? {
        try dbQueue.read { db in
            try Job
                .filter(Column("status") == JobStatus.pending)
                .order(Column("priority").desc, Column("createdAt").asc)
                .fetchOne(db)
        }
    }
    
    public func getJob(id: UUID) throws -> Job? {
        try dbQueue.read { db in
            try Job.fetchOne(db, key: id)
        }
    }
    
    // MARK: - Internal Logic
    
    private func unblockDependents(of jobId: UUID, in db: Database) throws {
        // Find all jobs that depend on this one
        let dependents = try JobDependency
            .filter(Column("dependsOnId") == jobId)
            .fetchAll(db)
        
        for dep in dependents {
            // Check if this dependent has ANY other pending dependencies
            let remainingDeps = try JobDependency
                .filter(Column("jobId") == dep.jobId)
                .filter(Column("dependsOnId") != jobId) // Exclude the one just finished
                .fetchAll(db)
            
            // We also need to check if those remaining dependencies are actually completed
            // This is a simplified check: if no other dependency rows exist, unblock.
            // A more robust check would join the jobs table.
            
            let areAllDepsMet = try areAllDependenciesMet(for: dep.jobId, in: db)
            
            if areAllDepsMet {
                if var job = try Job.fetchOne(db, key: dep.jobId) {
                    job.status = .pending
                    job.updatedAt = Date()
                    try job.save(db)
                }
            }
        }
    }
    
    private func areAllDependenciesMet(for jobId: UUID, in db: Database) throws -> Bool {
        // Get all dependency IDs
        let depIds = try JobDependency
            .filter(Column("jobId") == jobId)
            .fetchAll(db)
            .map { $0.dependsOnId }
        
        if depIds.isEmpty { return true }
        
        // Check if any of them are NOT completed
        let incompleteCount = try Job
            .filter(depIds.contains(Column("id")))
            .filter(Column("status") != JobStatus.completed)
            .fetchCount(db)
        
        return incompleteCount == 0
    }
}
