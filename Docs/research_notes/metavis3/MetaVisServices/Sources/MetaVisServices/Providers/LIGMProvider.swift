import Foundation
import MetaVisImageGen
import Metal

public final class LIGMProvider: ServiceProvider {
    
    public let id = "ligm.local"
    public let capabilities: Set<ServiceCapability> = [
        .imageGeneration
    ]
    
    private var ligm: LIGM?
    private let device: MTLDevice
    
    public init(device: MTLDevice? = nil) {
        self.device = device ?? MTLCreateSystemDefaultDevice()!
    }
    
    public func initialize(loader: ConfigurationLoader) async throws {
        // LIGM doesn't need API keys, but we initialize the engine here
        self.ligm = LIGM(device: device)
    }
    
    public func generate(request: GenerationRequest) -> AsyncThrowingStream<ServiceEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let ligm = ligm else {
                        throw ServiceError.providerUnavailable("LIGM not initialized")
                    }
                    
                    continuation.yield(.progress(0.1))
                    
                    // Map GenerationRequest to LIGMRequest
                    let width = (request.parameters["width"]?.value as? Int) ?? 1024
                    let height = (request.parameters["height"]?.value as? Int) ?? 1024
                    
                    let ligmRequest = LIGMRequest(
                        mode: .noise,
                        width: width,
                        height: height,
                        seed: 12345
                    )
                    
                    continuation.yield(.progress(0.5))
                    
                    // Execute LIGM
                    let response = try await ligm.generate(request: ligmRequest)
                    
                    continuation.yield(.progress(1.0))
                    
                    // Mock saving to disk (in reality, we'd save the texture data)
                    let mockURL = URL(fileURLWithPath: "/tmp/ligm_texture.asset")
                    
                    let genResponse = GenerationResponse(
                        requestId: request.id,
                        status: .success,
                        artifacts: [
                            ServiceArtifact(type: .image, uri: mockURL, metadata: response.metadata)
                        ],
                        metrics: ServiceMetrics(latency: 0.1)
                    )
                    
                    continuation.yield(.completion(genResponse))
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
