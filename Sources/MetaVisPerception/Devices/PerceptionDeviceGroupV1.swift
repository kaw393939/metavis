import Foundation

public enum PerceptionDeviceGroupError: Error, Sendable, Equatable {
    case warmUpFailed(device: String, message: String)
}

/// Type-erased lifecycle wrapper so callers can warm/cool a heterogenous set of devices.
public struct AnyPerceptionDeviceLifecycle: @unchecked Sendable {
    public var name: String
    private let _warmUp: @Sendable () async throws -> Void
    private let _coolDown: @Sendable () async -> Void

    public init(
        name: String,
        warmUp: @escaping @Sendable () async throws -> Void,
        coolDown: @escaping @Sendable () async -> Void
    ) {
        self.name = name
        self._warmUp = warmUp
        self._coolDown = coolDown
    }

    public init<D: PerceptionDevice>(_ device: D, name: String = String(describing: D.self)) {
        self.name = name
        self._warmUp = { try await device.warmUp() }
        self._coolDown = { await device.coolDown() }
    }

    public func warmUp() async throws {
        try await _warmUp()
    }

    public func coolDown() async {
        await _coolDown()
    }
}

/// Simple orchestration utilities for device groups.
///
/// Design goals:
/// - Deterministic order by default.
/// - Minimal surface area (warm/cool + a scoped helper).
public enum PerceptionDeviceGroupV1 {

    /// Warms up devices in array order.
    public static func warmUpAll(_ devices: [AnyPerceptionDeviceLifecycle]) async throws {
        for d in devices {
            do {
                try await d.warmUp()
            } catch {
                throw PerceptionDeviceGroupError.warmUpFailed(device: d.name, message: String(describing: error))
            }
        }
    }

    /// Cools down devices in reverse order.
    public static func coolDownAll(_ devices: [AnyPerceptionDeviceLifecycle]) async {
        for d in devices.reversed() {
            await d.coolDown()
        }
    }

    /// Warms up, runs operation, then cools down (even if operation throws).
    public static func withWarmedUp<T>(
        _ devices: [AnyPerceptionDeviceLifecycle],
        operation: () async throws -> T
    ) async throws -> T {
        try await warmUpAll(devices)
        do {
            let result = try await operation()
            await coolDownAll(devices)
            return result
        } catch {
            await coolDownAll(devices)
            throw error
        }
    }
}
