import Foundation
import MetaVisServices

public extension Job {
    /// Creates a job for generating content via MetaVisServices.
    static func generation(
        request: GenerationRequest,
        priority: Int = 0
    ) throws -> Job {
        let payload = try JSONEncoder().encode(request)
        return Job(
            type: .generate,
            status: .pending,
            priority: priority,
            payload: payload
        )
    }
    
    /// Decodes the result of a generation job.
    func generationResult() throws -> GenerationResponse? {
        guard let result = result else { return nil }
        return try JSONDecoder().decode(GenerationResponse.self, from: result)
    }
}
