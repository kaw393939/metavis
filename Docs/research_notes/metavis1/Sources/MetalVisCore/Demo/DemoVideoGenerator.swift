import Foundation
import Metal

// Legacy class stubbed out for architectural migration
public class DemoVideoGenerator {
    public init(device: MTLDevice, scriptPath: String) {}
    public func generate(outputUrl: URL) async throws {}
}

public enum DemoError: Error {
    case textureCreationFailed
}
