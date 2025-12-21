import Foundation

public actor IngestWorker: Worker {
    public let jobType: JobType = .ingest
    
    public init() {}
    
    public func execute(job: Job, progress: @escaping @Sendable (JobProgress) -> Void) async throws -> Data? {
        // Placeholder for Ingest logic
        // 1. Decode payload (e.g. file path)
        // 2. Perform ingest (copy, analyze metadata, generate proxy)
        // 3. Return result (metadata)
        
        progress(JobProgress(jobId: job.id, progress: 0.0, message: "Starting Ingest...", step: "Ingest"))
        
        // Simulating work
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        progress(JobProgress(jobId: job.id, progress: 1.0, message: "Ingest Complete", step: "Ingest"))
        
        let resultString = "Ingest complete for job \(job.id)"
        return resultString.data(using: .utf8)
    }
}
