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

public struct StdoutTraceSink: TraceSink {
    public init() {}

    public func record(_ name: String, fields: [String: String]) async {
        switch name {
        case "export.begin", "export.end",
             "render.video.begin", "render.video.progress", "render.video.end":
            var parts: [String] = [name]
            if let frame = fields["frame"], let total = fields["totalFrames"] {
                parts.append("\(frame)/\(total)")
            }
            if let output = fields["output"] {
                parts.append(output)
            }
            print(parts.joined(separator: " "))
        default:
            break
        }
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
