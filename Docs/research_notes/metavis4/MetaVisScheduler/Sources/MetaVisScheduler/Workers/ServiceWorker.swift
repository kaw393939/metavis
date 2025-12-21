import Foundation
import MetaVisServices
// import MetaVisScheduler // Not needed if in the same module, but if separate target...
// Wait, ServiceWorker is inside MetaVisScheduler package.

public actor ServiceWorker: Worker {
    public let jobType: JobType
    private let orchestrator: ServiceOrchestrator
    
    public init(jobType: JobType = .generate, orchestrator: ServiceOrchestrator) {
        self.jobType = jobType
        self.orchestrator = orchestrator
    }
    
    public func execute(job: Job, progress: @escaping @Sendable (JobProgress) -> Void) async throws -> Data? {
        // 1. Decode payload
        let request = try JSONDecoder().decode(GenerationRequest.self, from: job.payload)
        
        // 2. Call Service and consume stream
        var finalResponse: GenerationResponse?
        
        let stream = await orchestrator.generate(request: request)
        for try await event in stream {
            switch event {
            case .progress(let p):
                progress(JobProgress(jobId: job.id, progress: p, message: "Processing...", step: "Service"))
                print("Job \(job.id) progress: \(p)")
            case .message(let msg):
                progress(JobProgress(jobId: job.id, progress: 0.0, message: msg, step: "Service"))
                print("Job \(job.id) message: \(msg)")
            case .completion(let response):
                finalResponse = response
            }
        }
        
        guard let response = finalResponse else {
            throw NSError(domain: "ServiceWorker", code: 1, userInfo: [NSLocalizedDescriptionKey: "No response received"])
        }
        
        // 3. Encode result
        return try JSONEncoder().encode(response)
    }
}
