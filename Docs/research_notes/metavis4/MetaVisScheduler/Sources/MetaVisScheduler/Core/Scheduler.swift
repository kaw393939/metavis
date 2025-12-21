import Foundation

public protocol Worker: Sendable {
    var jobType: JobType { get }
    func execute(job: Job, progress: @escaping @Sendable (JobProgress) -> Void) async throws -> Data?
}

public actor Scheduler {
    
    private let queue: JobQueue
    private var workers: [JobType: Worker] = [:]
    private var isRunning = false
    private var activeJobs: Set<UUID> = []
    
    public var resultProcessor: JobResultProcessor?
    
    public init(queuePath: String? = nil) throws {
        self.queue = try JobQueue(path: queuePath)
        self.resultProcessor = JobResultProcessor(queue: self.queue)
    }
    
    public func register(worker: Worker) {
        workers[worker.jobType] = worker
    }
    
    public func submit(job: Job, dependencies: [UUID] = []) throws {
        try queue.add(job: job, dependencies: dependencies)
        Task { await tick() }
    }
    
    public func start() {
        isRunning = true
        Task { await tick() }
    }
    
    public func stop() {
        isRunning = false
    }
    
    private func tick() async {
        guard isRunning else { return }
        
        // 1. Get next job
        do {
            guard var job = try queue.getNextPendingJob() else { return }
            
            // 2. Check concurrency limits (Simple: 1 job per type for now, or global limit)
            // For now, let's just run it if we have a worker
            guard let worker = workers[job.type] else {
                print("Scheduler: No worker for type \(job.type)")
                return
            }
            
            // 3. Mark as running
            job.status = .running
            try queue.update(job: job)
            activeJobs.insert(job.id)
            
            // 4. Execute
            Task {
                await execute(job: job, worker: worker)
            }
            
            // 5. Try to pick up another job immediately (concurrency)
            await tick()
            
        } catch {
            print("Scheduler Error: \(error)")
        }
    }
    
    private func execute(job: Job, worker: Worker) async {
        var currentJob = job
        do {
            let result = try await worker.execute(job: currentJob) { [weak self] progress in
                Task {
                    await JobLogger.shared.report(progress: progress)
                }
            }
            currentJob.status = .completed
            currentJob.result = result
            await resultProcessor?.processCompletion(job: currentJob)
        } catch {
            currentJob.status = .failed
            currentJob.error = String(describing: error)
            await resultProcessor?.processFailure(job: currentJob)
        }
        
        // Update DB
        try? queue.update(job: currentJob)
        activeJobs.remove(currentJob.id)
        
        // Trigger next tick
        await tick()
    }
}
