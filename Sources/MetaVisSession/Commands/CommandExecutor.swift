import Foundation
import MetaVisCore
import MetaVisTimeline

public struct CommandExecutor: Sendable {
    public var trace: any TraceSink

    public init(trace: any TraceSink = NoOpTraceSink()) {
        self.trace = trace
    }

    public func execute(_ commands: [IntentCommand], in timeline: inout Timeline) async {
        await trace.record("intent.commands.execute.begin", fields: ["count": String(commands.count)])
        for (idx, command) in commands.enumerated() {
            await trace.record("intent.command.begin", fields: ["index": String(idx), "command": String(describing: command)])
            apply(command, to: &timeline)
            await trace.record("intent.command.end", fields: ["index": String(idx)])
        }
        await trace.record("intent.commands.execute.end", fields: ["count": String(commands.count)])
    }

    private func apply(_ command: IntentCommand, to timeline: inout Timeline) {
        switch command {
        case let .applyColorGradeToFirstVideoClip(target, params):
            guard var first = timeline.tracks.first else { return }
            guard !first.clips.isEmpty else { return }
            var clip = first.clips[0]

            // Deterministic effect id; keep it stable for observability and testability.
            let effectID = "mv.colorGrade"
            var nodeParams: [String: NodeValue] = [:]
            for (k, v) in params.sorted(by: { $0.key < $1.key }) {
                nodeParams[k] = .float(v)
            }
            nodeParams["target"] = .string(target)

            let app = FeatureApplication(id: effectID, parameters: nodeParams)
            clip.effects = (clip.effects.filter { $0.id != effectID }) + [app]

            first.clips[0] = clip
            timeline.tracks[0] = first

        case let .trimEndOfFirstVideoClip(atSeconds):
            guard var first = timeline.tracks.first else { return }
            guard !first.clips.isEmpty else { return }
            var clip = first.clips[0]

            let start = clip.startTime
            let newEnd = Time(seconds: atSeconds)
            if newEnd > start {
                clip.duration = newEnd - start
                first.clips[0] = clip
                timeline.tracks[0] = first
            }

        case let .retimeFirstVideoClip(speedFactor):
            guard var first = timeline.tracks.first else { return }
            guard !first.clips.isEmpty else { return }
            var clip = first.clips[0]

            let effectID = "mv.retime"
            let params: [String: NodeValue] = ["factor": .float(speedFactor)]
            let app = FeatureApplication(id: effectID, parameters: params)
            clip.effects = (clip.effects.filter { $0.id != effectID }) + [app]

            first.clips[0] = clip
            timeline.tracks[0] = first
        }
    }
}
