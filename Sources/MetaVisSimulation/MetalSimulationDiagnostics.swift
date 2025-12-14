import Foundation

/// Lightweight diagnostics to support deterministic/export guardrail tests.
///
/// This intentionally avoids extra dependencies; it's best-effort and only used for assertions in tests.
public enum MetalSimulationDiagnostics {
    private static let lock = NSLock()
    private static var _cpuReadbackCount: Int = 0
    private static var _textureAllocationCount: Int = 0

    public static var cpuReadbackCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _cpuReadbackCount
    }

    public static var textureAllocationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _textureAllocationCount
    }

    public static func reset() {
        lock.lock(); defer { lock.unlock() }
        _cpuReadbackCount = 0
        _textureAllocationCount = 0
    }

    public static func incrementCPUReadback() {
        lock.lock(); defer { lock.unlock() }
        _cpuReadbackCount += 1
    }

    public static func incrementTextureAllocation() {
        lock.lock(); defer { lock.unlock() }
        _textureAllocationCount += 1
    }
}
