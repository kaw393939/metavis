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
            await trace.record("intent.command.begin", fields: ["index": String(idx), "command": command.traceDescription])
            await apply(command, to: &timeline)
            await trace.record("intent.command.end", fields: ["index": String(idx)])
        }
        await trace.record("intent.commands.execute.end", fields: ["count": String(commands.count)])
    }

    private func apply(_ command: IntentCommand, to timeline: inout Timeline) async {
        switch command {
        case let .applyColorGrade(target, gradeTarget, params):
            guard let loc = resolveTargetVideoClip(target, in: timeline) else { return }
            var track = timeline.tracks[loc.trackIndex]
            var clip = track.clips[loc.clipIndex]

            // Deterministic effect id; keep it stable for observability and testability.
            let effectID = "mv.colorGrade"
            var nodeParams: [String: NodeValue] = [:]
            for (k, v) in params.sorted(by: { $0.key < $1.key }) {
                nodeParams[k] = .float(v)
            }
            nodeParams["target"] = .string(gradeTarget)

            let app = FeatureApplication(id: effectID, parameters: nodeParams)
            clip.effects = (clip.effects.filter { $0.id != effectID }) + [app]

            track.clips[loc.clipIndex] = clip
            timeline.tracks[loc.trackIndex] = track
            timeline.recomputeDuration()

        case let .trimClipEnd(target, atSeconds):
            guard let loc = resolveTargetVideoClip(target, in: timeline) else { return }
            var track = timeline.tracks[loc.trackIndex]

            let targetId = track.clips[loc.clipIndex].id
            track.clips.sort(by: { $0.startTime < $1.startTime })
            guard let idx = track.clips.firstIndex(where: { $0.id == targetId }) else { return }
            var clip = track.clips[idx]

            let linkedAudio = linkedAudioClips(forVideoClip: clip, in: timeline)

            let start = clip.startTime
            let newEnd = Time(seconds: atSeconds)
            guard newEnd > start else { return }
            clip.duration = newEnd - start
            track.clips[idx] = clip

            // Keep time-aligned audio clips in sync with the trimmed video clip.
            if !linkedAudio.isEmpty {
                updateAudioClips(linkedAudio, in: &timeline) { audio in
                    audio.duration = clip.duration
                }
            }

            normalizePairedTransitions(in: &track)
            timeline.tracks[loc.trackIndex] = track
            timeline.recomputeDuration()

        case let .retimeClip(target, speedFactor):
            guard let loc = resolveTargetVideoClip(target, in: timeline) else { return }
            var track = timeline.tracks[loc.trackIndex]
            var clip = track.clips[loc.clipIndex]

            let effectID = "mv.retime"
            let params: [String: NodeValue] = ["factor": .float(speedFactor)]
            let app = FeatureApplication(id: effectID, parameters: params)
            clip.effects = (clip.effects.filter { $0.id != effectID }) + [app]

            track.clips[loc.clipIndex] = clip
            timeline.tracks[loc.trackIndex] = track
            timeline.recomputeDuration()

        case let .moveClip(target, toStartSeconds):
            guard let loc = resolveTargetVideoClip(target, in: timeline) else { return }
            var track = timeline.tracks[loc.trackIndex]

            let targetId = track.clips[loc.clipIndex].id
            track.clips.sort(by: { $0.startTime < $1.startTime })
            guard let idx = track.clips.firstIndex(where: { $0.id == targetId }) else { return }
            var clip = track.clips[idx]

            let oldStart = clip.startTime
            let linkedAudio = linkedAudioClips(forVideoClip: clip, in: timeline)

            clip.startTime = Time(seconds: max(0, toStartSeconds))
            track.clips[idx] = clip
            track.clips.sort(by: { $0.startTime < $1.startTime })
            normalizePairedTransitions(in: &track)
            timeline.tracks[loc.trackIndex] = track
            timeline.recomputeDuration()

            // Keep linked audio clips in sync with the moved video clip.
            if !linkedAudio.isEmpty {
                let delta = clip.startTime - oldStart
                updateAudioClips(linkedAudio, in: &timeline) { audio in
                    audio.startTime = audio.startTime + delta
                    if audio.startTime.seconds < 0 {
                        audio.startTime = .zero
                    }
                }
            }

            // Overlap policy: permissive (no auto-ripple), but warn deterministically when overlaps exist.
            if hasOverlap(in: track) {
                await trace.record(
                    "timeline.overlap.detected",
                    fields: [
                        "track": track.name,
                        "kind": String(describing: track.kind),
                        "command": "moveClip"
                    ]
                )
            }

        case let .trimClipIn(target, toOffsetSeconds):
            guard let loc = resolveTargetVideoClip(target, in: timeline) else { return }
            var track = timeline.tracks[loc.trackIndex]
            var clip = track.clips[loc.clipIndex]

            clip.offset = Time(seconds: max(0, toOffsetSeconds))
            track.clips[loc.clipIndex] = clip
            timeline.tracks[loc.trackIndex] = track

        case let .bladeClip(target, atSeconds):
            guard let loc = resolveTargetVideoClip(target, in: timeline) else { return }
            var track = timeline.tracks[loc.trackIndex]
            let clip = track.clips[loc.clipIndex]

            let split = Time(seconds: atSeconds)
            guard split > clip.startTime && split < clip.endTime else { return }

            let firstDuration = split - clip.startTime
            let secondDuration = clip.endTime - split
            let secondOffset = clip.offset + firstDuration

            var first = clip
            first.duration = firstDuration
            first.transitionOut = nil

            var second = clip
            second.startTime = split
            second.duration = secondDuration
            second.offset = secondOffset
            second.transitionIn = nil

            // Replace the original clip with two clips.
            track.clips.remove(at: loc.clipIndex)
            track.clips.insert(contentsOf: [first, second], at: loc.clipIndex)
            track.clips.sort(by: { $0.startTime < $1.startTime })
            timeline.tracks[loc.trackIndex] = track
            timeline.recomputeDuration()

        case let .rippleTrimOut(target, newEndSeconds):
            guard let loc = resolveTargetVideoClip(target, in: timeline) else { return }
            var track = timeline.tracks[loc.trackIndex]

            let targetId = track.clips[loc.clipIndex].id
            track.clips.sort(by: { $0.startTime < $1.startTime })
            guard let idx = track.clips.firstIndex(where: { $0.id == targetId }) else { return }
            var clip = track.clips[idx]

            let linkedAudio = linkedAudioClips(forVideoClip: clip, in: timeline)

            let oldEnd = clip.endTime
            let newEnd = Time(seconds: newEndSeconds)
            guard newEnd > clip.startTime else { return }

            clip.duration = newEnd - clip.startTime
            let delta = newEnd - oldEnd

            // Keep time-aligned audio clips in sync with the trimmed video clip.
            if !linkedAudio.isEmpty {
                updateAudioClips(linkedAudio, in: &timeline) { audio in
                    audio.duration = clip.duration
                }
            }

            track.clips[idx] = clip
            // Ripple within the edited track by clip order, not by timestamps.
            // This preserves intentional overlaps (e.g. crossfades) across trims.
            if delta.seconds != 0 {
                shiftDownstreamClipsOnTrackByIndex(
                    track: &track,
                    startIndex: idx + 1,
                    delta: delta
                )
            }
            track.clips.sort(by: { $0.startTime < $1.startTime })
            normalizePairedTransitions(in: &track)
            timeline.tracks[loc.trackIndex] = track
            timeline.recomputeDuration()

            if delta.seconds != 0 {
                shiftClipsOnOtherTracksAtOrAfter(
                    in: &timeline,
                    excludingTrackIndex: loc.trackIndex,
                    ripplePoint: oldEnd,
                    delta: delta
                )
            }

        case let .rippleTrimIn(target, newOffsetSeconds):
            guard let loc = resolveTargetVideoClip(target, in: timeline) else { return }
            var track = timeline.tracks[loc.trackIndex]

            let targetId = track.clips[loc.clipIndex].id
            track.clips.sort(by: { $0.startTime < $1.startTime })
            guard let idx = track.clips.firstIndex(where: { $0.id == targetId }) else { return }
            var clip = track.clips[idx]

            let linkedAudio = linkedAudioClips(forVideoClip: clip, in: timeline)

            let oldOffset = clip.offset
            let newOffset = Time(seconds: max(0, newOffsetSeconds))
            let deltaOffset = newOffset - oldOffset

            // Increasing offset trims in (shortens duration). Decreasing offset extends duration.
            let newDuration = clip.duration - deltaOffset
            guard newDuration.seconds > 0 else { return }

            let oldEnd = clip.endTime
            clip.offset = newOffset
            clip.duration = newDuration
            let newEnd = clip.endTime

            // Keep time-aligned audio clips in sync with the trimmed video clip.
            if !linkedAudio.isEmpty {
                updateAudioClips(linkedAudio, in: &timeline) { audio in
                    audio.offset = clip.offset
                    audio.duration = clip.duration
                }
            }

            let deltaEnd = newEnd - oldEnd
            track.clips[idx] = clip
            // Ripple within the edited track by clip order, not by timestamps.
            if deltaEnd.seconds != 0 {
                shiftDownstreamClipsOnTrackByIndex(
                    track: &track,
                    startIndex: idx + 1,
                    delta: deltaEnd
                )
            }
            track.clips.sort(by: { $0.startTime < $1.startTime })
            normalizePairedTransitions(in: &track)
            timeline.tracks[loc.trackIndex] = track
            timeline.recomputeDuration()

            if deltaEnd.seconds != 0 {
                shiftClipsOnOtherTracksAtOrAfter(
                    in: &timeline,
                    excludingTrackIndex: loc.trackIndex,
                    ripplePoint: oldEnd,
                    delta: deltaEnd
                )
            }

        case let .rippleDelete(target):
            guard let loc = resolveTargetVideoClip(target, in: timeline) else { return }
            var track = timeline.tracks[loc.trackIndex]

            let targetId = track.clips[loc.clipIndex].id
            track.clips.sort(by: { $0.startTime < $1.startTime })
            guard let idx = track.clips.firstIndex(where: { $0.id == targetId }) else { return }
            let clip = track.clips[idx]

            let linkedAudio = linkedAudioClips(forVideoClip: clip, in: timeline)
            let oldEnd = clip.endTime
            let delta = Time(seconds: -clip.duration.seconds)

            // Clear transitions that belonged to boundaries with the deleted clip.
            if idx > 0 {
                track.clips[idx - 1].transitionOut = nil
            }
            if idx + 1 < track.clips.count {
                track.clips[idx + 1].transitionIn = nil
            }

            track.clips.remove(at: idx)

            // Ripple within the edited track by clip order: shift the clips that were after the deleted clip.
            if delta.seconds != 0 {
                shiftDownstreamClipsOnTrackByIndex(
                    track: &track,
                    startIndex: idx,
                    delta: delta
                )
            }

            track.clips.sort(by: { $0.startTime < $1.startTime })
            normalizePairedTransitions(in: &track)
            timeline.tracks[loc.trackIndex] = track
            timeline.recomputeDuration()

            // Remove any linked audio clips that were time-aligned with the deleted video clip.
            if !linkedAudio.isEmpty {
                removeAudioClips(linkedAudio, in: &timeline)
            }

            if delta.seconds != 0 {
                shiftClipsOnOtherTracksAtOrAfter(
                    in: &timeline,
                    excludingTrackIndex: loc.trackIndex,
                    ripplePoint: oldEnd,
                    delta: delta
                )
            }
        }
    }

    private struct ClipIndexPath: Sendable, Equatable {
        var trackIndex: Int
        var clipIndex: Int
    }

    private func linkedAudioClips(forVideoClip clip: Clip, in timeline: Timeline) -> [ClipIndexPath] {
        var out: [ClipIndexPath] = []
        out.reserveCapacity(2)

        for (ti, track) in timeline.tracks.enumerated() where track.kind == .audio {
            for (ci, c) in track.clips.enumerated() {
                // Minimal, deterministic heuristic: consider clips "linked" when they share the same
                // timeline start and duration (i.e. fully time-aligned).
                if c.startTime == clip.startTime && c.duration == clip.duration {
                    out.append(ClipIndexPath(trackIndex: ti, clipIndex: ci))
                }
            }
        }

        return out
    }

    private func updateAudioClips(
        _ paths: [ClipIndexPath],
        in timeline: inout Timeline,
        mutate: (inout Clip) -> Void
    ) {
        guard !paths.isEmpty else { return }

        // Apply in descending index order to avoid invalidating indices if callers ever
        // expand this to include removals.
        for path in paths.sorted(by: { (a, b) in
            if a.trackIndex != b.trackIndex { return a.trackIndex > b.trackIndex }
            return a.clipIndex > b.clipIndex
        }) {
            guard timeline.tracks.indices.contains(path.trackIndex) else { continue }
            var track = timeline.tracks[path.trackIndex]
            guard track.clips.indices.contains(path.clipIndex) else { continue }
            var clip = track.clips[path.clipIndex]
            mutate(&clip)
            track.clips[path.clipIndex] = clip
            track.clips.sort(by: { $0.startTime < $1.startTime })
            normalizePairedTransitions(in: &track)
            timeline.tracks[path.trackIndex] = track
        }

        timeline.recomputeDuration()
    }

    private func removeAudioClips(_ paths: [ClipIndexPath], in timeline: inout Timeline) {
        guard !paths.isEmpty else { return }

        for path in paths.sorted(by: { (a, b) in
            if a.trackIndex != b.trackIndex { return a.trackIndex > b.trackIndex }
            return a.clipIndex > b.clipIndex
        }) {
            guard timeline.tracks.indices.contains(path.trackIndex) else { continue }
            var track = timeline.tracks[path.trackIndex]
            guard track.clips.indices.contains(path.clipIndex) else { continue }

            // Clear transitions at the deleted boundary (mirrors video rippleDelete behavior).
            if path.clipIndex > 0 {
                track.clips[path.clipIndex - 1].transitionOut = nil
            }
            if path.clipIndex + 1 < track.clips.count {
                track.clips[path.clipIndex + 1].transitionIn = nil
            }

            track.clips.remove(at: path.clipIndex)
            track.clips.sort(by: { $0.startTime < $1.startTime })
            normalizePairedTransitions(in: &track)
            timeline.tracks[path.trackIndex] = track
        }

        timeline.recomputeDuration()
    }

    private func shiftDownstreamClipsOnTrackByIndex(
        track: inout Track,
        startIndex: Int,
        delta: Time
    ) {
        guard delta.seconds != 0 else { return }

        track.clips.sort(by: { $0.startTime < $1.startTime })
        guard startIndex >= 0, startIndex < track.clips.count else { return }

        for ci in startIndex..<track.clips.count {
            track.clips[ci].startTime = track.clips[ci].startTime + delta
            if track.clips[ci].startTime.seconds < 0 {
                track.clips[ci].startTime = .zero
            }
        }
    }

    private func shiftClipsOnOtherTracksAtOrAfter(
        in timeline: inout Timeline,
        excludingTrackIndex: Int,
        ripplePoint: Time,
        delta: Time
    ) {
        guard delta.seconds != 0 else { return }

        for ti in timeline.tracks.indices {
            if ti == excludingTrackIndex { continue }
            var track = timeline.tracks[ti]

            for ci in track.clips.indices {
                // Time-based ripple for non-primary tracks.
                // This maintains cross-track alignment without assuming overlap intent.
                if track.clips[ci].startTime >= ripplePoint {
                    track.clips[ci].startTime = track.clips[ci].startTime + delta
                    if track.clips[ci].startTime.seconds < 0 {
                        track.clips[ci].startTime = .zero
                    }
                }
            }

            track.clips.sort(by: { $0.startTime < $1.startTime })
            normalizePairedTransitions(in: &track)
            timeline.tracks[ti] = track
        }

        timeline.recomputeDuration()
    }

    private func normalizePairedTransitions(in track: inout Track) {
        // Only normalize when both sides of a boundary have transitions set.
        // This keeps explicit fade-to/from-black behavior intact (single-sided transitions).
        track.clips.sort(by: { $0.startTime < $1.startTime })
        guard track.clips.count >= 2 else { return }

        for i in 0..<(track.clips.count - 1) {
            guard let out = track.clips[i].transitionOut,
                  let `in` = track.clips[i + 1].transitionIn
            else { continue }

            let overlap = track.clips[i].endTime - track.clips[i + 1].startTime
            if overlap.seconds <= 0 {
                track.clips[i].transitionOut = nil
                track.clips[i + 1].transitionIn = nil
                continue
            }

            if out.duration > overlap {
                track.clips[i].transitionOut = Transition(type: out.type, duration: overlap, easing: out.easing)
            }
            if `in`.duration > overlap {
                track.clips[i + 1].transitionIn = Transition(type: `in`.type, duration: overlap, easing: `in`.easing)
            }
        }
    }

    private func hasOverlap(in track: Track) -> Bool {
        // Assumes clips are sorted by start time.
        guard track.clips.count >= 2 else { return false }
        var prevEnd = track.clips[0].endTime
        for clip in track.clips.dropFirst() {
            if clip.startTime < prevEnd { return true }
            prevEnd = clip.endTime
        }
        return false
    }

    private struct ClipLocation: Sendable, Equatable {
        let trackIndex: Int
        let clipIndex: Int
    }

    private func resolveTargetVideoClip(_ target: ClipTarget, in timeline: Timeline) -> ClipLocation? {
        switch target {
        case .firstVideoClip:
            for (ti, track) in timeline.tracks.enumerated() where track.kind == .video {
                if !track.clips.isEmpty {
                    return ClipLocation(trackIndex: ti, clipIndex: 0)
                }
            }
            return nil

        case let .clipId(id):
            for (ti, track) in timeline.tracks.enumerated() where track.kind == .video {
                if let ci = track.clips.firstIndex(where: { $0.id == id }) {
                    return ClipLocation(trackIndex: ti, clipIndex: ci)
                }
            }
            return nil
        }
    }

}
