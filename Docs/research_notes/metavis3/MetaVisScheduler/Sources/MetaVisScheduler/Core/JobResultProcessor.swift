import Foundation
import MetaVisCore

public protocol JobResultDelegate: AnyObject, Sendable {
    func jobDidComplete(jobId: UUID, result: Data, type: JobType)
    func jobDidFail(jobId: UUID, error: String)
}

public actor JobResultProcessor {
    private let queue: JobQueue
    public weak var delegate: JobResultDelegate?
    
    public init(queue: JobQueue) {
        self.queue = queue
    }
    
    public func processCompletion(job: Job) {
        guard let result = job.result else { return }
        delegate?.jobDidComplete(jobId: job.id, result: result, type: job.type)
    }
    
    public func processFailure(job: Job) {
        guard let error = job.error else { return }
        delegate?.jobDidFail(jobId: job.id, error: error)
    }
}
