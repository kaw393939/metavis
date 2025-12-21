import Foundation

public class WorkflowBuilder {
    private var jobs: [Job] = []
    private var dependencies: [UUID: [UUID]] = [:]
    
    public init() {}
    
    @discardableResult
    public func add(job: Job, dependsOn: [Job] = []) -> WorkflowBuilder {
        jobs.append(job)
        dependencies[job.id] = dependsOn.map { $0.id }
        return self
    }
    
    public func submit(to scheduler: Scheduler) async throws {
        // Submit in order of dependency (topological sort would be better, but simple iteration works if we just add them)
        // Actually, since we can add jobs in any order and the DB handles dependencies, we just need to make sure we submit them.
        // However, if we submit a job that depends on another job that hasn't been submitted yet, the DB constraint might fail if we enforced foreign keys strictly and the parent didn't exist.
        // But our JobQueue adds the job first, then dependencies.
        // If the dependency ID doesn't exist in the jobs table, the foreign key constraint will fail.
        // So we MUST submit the dependencies first.
        
        let sortedJobs = try topologicalSort(jobs: jobs, dependencies: dependencies)
        
        for job in sortedJobs {
            let deps = dependencies[job.id] ?? []
            try await scheduler.submit(job: job, dependencies: deps)
        }
    }
    
    private func topologicalSort(jobs: [Job], dependencies: [UUID: [UUID]]) throws -> [Job] {
        var sorted: [Job] = []
        var visited: Set<UUID> = []
        var tempVisited: Set<UUID> = []
        
        let jobMap = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
        
        func visit(_ jobId: UUID) throws {
            if tempVisited.contains(jobId) {
                throw NSError(domain: "WorkflowBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Circular dependency detected"])
            }
            if visited.contains(jobId) {
                return
            }
            
            tempVisited.insert(jobId)
            
            let deps = dependencies[jobId] ?? []
            for depId in deps {
                try visit(depId)
            }
            
            tempVisited.remove(jobId)
            visited.insert(jobId)
            if let job = jobMap[jobId] {
                sorted.append(job)
            }
        }
        
        for job in jobs {
            try visit(job.id)
        }
        
        return sorted
    }
}
