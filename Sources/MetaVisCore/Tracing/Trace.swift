import Foundation

public struct TraceEvent: Codable, Sendable, Equatable {
    public var index: Int
    public var name: String
    public var fields: [String: String]

    public init(index: Int, name: String, fields: [String: String] = [:]) {
        self.index = index
        self.name = name
        self.fields = fields
    }
}

public protocol TraceSink: Sendable {
    func record(_ name: String, fields: [String: String]) async
}

public struct NoOpTraceSink: TraceSink {
    public init() {}

    public func record(_ name: String, fields: [String: String]) async {
        // no-op
    }
}

public actor InMemoryTraceSink: TraceSink {
    private var events: [TraceEvent] = []

    public init() {}

    public func record(_ name: String, fields: [String: String]) async {
        events.append(TraceEvent(index: events.count, name: name, fields: fields))
    }

    public func snapshot() async -> [TraceEvent] {
        events
    }

    public func reset() async {
        events.removeAll(keepingCapacity: true)
    }
}
