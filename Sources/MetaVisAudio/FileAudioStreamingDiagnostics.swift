import Foundation

/// Test/debug-only counters for file-backed audio streaming.
///
/// These exist to support deterministic unit tests that prove we do not decode
/// an entire file-backed asset up-front when rendering only a short time range.
public enum FileAudioStreamingDiagnostics {
#if DEBUG
    private static let lock = NSLock()

    public static var isEnabled: Bool = false

    public private(set) static var lastConfiguredDurationFrames: Int = 0
    public private(set) static var lastDecodedFrames: Int = 0

    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        lastConfiguredDurationFrames = 0
        lastDecodedFrames = 0
    }

    static func recordConfigured(durationFrames: Int) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        lastConfiguredDurationFrames = durationFrames
    }

    static func addDecoded(frames: Int) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        lastDecodedFrames += max(0, frames)
    }
#else
    public static var isEnabled: Bool {
        get { false }
        set { _ = newValue }
    }

    public static var lastConfiguredDurationFrames: Int { 0 }
    public static var lastDecodedFrames: Int { 0 }

    public static func reset() {}
    static func recordConfigured(durationFrames: Int) { _ = durationFrames }
    static func addDecoded(frames: Int) { _ = frames }
#endif
}
