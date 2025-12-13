import CoreVideo

// CoreVideo pixel buffers are reference types and not formally Sendable.
// In our pipeline we pass them across concurrency boundaries with
// single-owner discipline (no concurrent mutation), so this is safe.
extension CVBuffer: @retroactive @unchecked Sendable {}

