import Foundation
import MetaVisCore

public enum SemanticFrameV2Builder {
    public struct Options: Sendable {
        /// Time window used to decide whether a subject is speaking.
        public var speakingWindowSeconds: Double

        /// Minimum binding posterior required to assert `isSpeaking=true` for a subject.
        /// If the binding is weaker than this, we emit `speakerId` but keep `isSpeaking=false`
        /// with an explicit `speaker_binding_missing` reason.
        public var minPosteriorForSpeaking: Double

        /// Minimum binding posterior required to emit `speakerId` / `speakerLabel` onto a subject.
        /// Below this, we do not surface speaker identity on faces.
        public var minPosteriorForSpeakerId: Double

        public init(
            speakingWindowSeconds: Double = 0.25,
            minPosteriorForSpeaking: Double = 0.8,
            minPosteriorForSpeakerId: Double = 0.7
        ) {
            self.speakingWindowSeconds = speakingWindowSeconds
            self.minPosteriorForSpeaking = minPosteriorForSpeaking
            self.minPosteriorForSpeakerId = minPosteriorForSpeakerId
        }
    }

    /// Builds v2 semantic frames from sensors + diarization outputs.
    ///
    /// - `bindings` is optional; when present, we emit inferred `isSpeaking` and `speakerId` attributes.
    /// - Output is deterministic and stable (sorted attributes, stable ordering).
    public static func buildAll(
        sensors: MasterSensors,
        diarizedWords: [TranscriptWordV1] = [],
        bindings: IdentityBindingGraphV1? = nil,
        options: Options = Options()
    ) -> [SemanticFrameV2] {
        // Preindex: conservative one-to-one speakerId -> binding edge.
        // We avoid surfacing ambiguous speaker identities on faces.
        let assignedBindingBySpeaker: [String: IdentityBindingEdgeV1] = {
            guard let bindings else { return [:] }

            // Group edges per speaker and keep deterministic ordering.
            var bySpeaker: [String: [IdentityBindingEdgeV1]] = [:]
            for e in bindings.bindings {
                bySpeaker[e.speakerId, default: []].append(e)
            }
            for k in bySpeaker.keys {
                bySpeaker[k] = (bySpeaker[k] ?? []).sorted { a, b in
                    if a.posterior != b.posterior { return a.posterior > b.posterior }
                    return a.trackId.uuidString < b.trackId.uuidString
                }
            }

            // Determine speaker processing order by their best posterior, deterministic tiebreak.
            let speakerOrder = bySpeaker
                .map { (speakerId: $0.key, best: ($0.value.first?.posterior ?? 0.0)) }
                .sorted { a, b in
                    if a.best != b.best { return a.best > b.best }
                    return a.speakerId < b.speakerId
                }

            var usedTracks = Set<UUID>()
            var out: [String: IdentityBindingEdgeV1] = [:]

            for s in speakerOrder {
                guard let edges = bySpeaker[s.speakerId], !edges.isEmpty else { continue }
                // Pick the best non-conflicting track above the emit threshold.
                if let chosen = edges.first(where: { $0.posterior >= options.minPosteriorForSpeakerId && !usedTracks.contains($0.trackId) }) {
                    out[s.speakerId] = chosen
                    usedTracks.insert(chosen.trackId)
                }
            }

            return out
        }()

        // Preindex diarized words by midSeconds.
        let wordsByTime: [(t: Double, w: TranscriptWordV1)] = {
            if diarizedWords.isEmpty { return [] }
            func ticksForTiming(_ w: TranscriptWordV1) -> (start: Int64, end: Int64) {
                let start = w.timelineTimeTicks ?? w.sourceTimeTicks
                let end = w.timelineTimeEndTicks ?? w.sourceTimeEndTicks
                return (start: start, end: max(start, end))
            }
            func midSeconds(startTicks: Int64, endTicks: Int64) -> Double {
                let midTicks = startTicks + (max(Int64(0), endTicks - startTicks) / 2)
                return Double(midTicks) / 60000.0
            }
            return diarizedWords.map { w in
                let timing = ticksForTiming(w)
                return (t: midSeconds(startTicks: timing.start, endTicks: timing.end), w: w)
            }.sorted { a, b in
                if a.t != b.t { return a.t < b.t }
                return a.w.wordId < b.w.wordId
            }
        }()

        func nearestWord(at t: Double, within window: Double) -> TranscriptWordV1? {
            guard !wordsByTime.isEmpty else { return nil }
            var best: TranscriptWordV1?
            var bestDt = Double.greatestFiniteMagnitude
            for item in wordsByTime {
                let dt = abs(item.t - t)
                if dt < bestDt {
                    bestDt = dt
                    best = item.w
                }
            }
            guard bestDt <= window else { return nil }
            return best
        }

        let samples = sensors.videoSamples.sorted { $0.time < $1.time }
        return samples.map { sample in
            build(
                from: sample,
                nearestWord: nearestWord(at: sample.time, within: options.speakingWindowSeconds),
                assignedBindingBySpeaker: assignedBindingBySpeaker,
                options: options
            )
        }
    }

    private static func build(
        from sample: MasterSensors.VideoSample,
        nearestWord: TranscriptWordV1?,
        assignedBindingBySpeaker: [String: IdentityBindingEdgeV1],
        options: Options
    ) -> SemanticFrameV2 {
        // Frame-level deterministic metrics.
        let frameMetrics: [SemanticAttributeV1] = {
            let conf = ConfidenceRecordV1.evidence(score: 1.0, sources: [.vision], reasons: [], evidenceRefs: [])
            var attrs: [SemanticAttributeV1] = []
            attrs.reserveCapacity(6)

            attrs.append(.init(key: "video.meanLuma", value: .double(.init(
                value: sample.meanLuma,
                confidence: conf,
                confidenceLevel: .deterministic,
                provenance: [.metric("video.meanLuma", value: sample.meanLuma)]
            ))))

            attrs.append(.init(key: "video.skinLikelihood", value: .double(.init(
                value: sample.skinLikelihood,
                confidence: conf,
                confidenceLevel: .deterministic,
                provenance: [.metric("video.skinLikelihood", value: sample.skinLikelihood)]
            ))))

            attrs.append(.init(key: "video.faces.count", value: .double(.init(
                value: Double(sample.faces.count),
                confidence: conf,
                confidenceLevel: .deterministic,
                provenance: [.metric("video.faces.count", value: Double(sample.faces.count))]
            ))))

            if let pm = sample.personMaskPresence {
                attrs.append(.init(key: "video.personMaskPresence", value: .double(.init(
                    value: pm,
                    confidence: conf,
                    confidenceLevel: .deterministic,
                    provenance: [.metric("video.personMaskPresence", value: pm)]
                ))))
            }

            if let pc = sample.peopleCountEstimate {
                attrs.append(.init(key: "video.peopleCountEstimate", value: .double(.init(
                    value: Double(pc),
                    confidence: conf,
                    confidenceLevel: .heuristic,
                    provenance: [.metric("video.peopleCountEstimate", value: Double(pc))]
                ))))
            }

            return attrs.sorted { $0.key < $1.key }
        }()

        let subjects: [SemanticSubjectV2] = sample.faces
            .sorted { $0.trackId.uuidString < $1.trackId.uuidString }
            .map { face in
                var attrs: [SemanticAttributeV1] = []
                attrs.reserveCapacity(8)

                // Stable identity label derived by the sensors pipeline.
                if let personId = face.personId {
                    let conf = ConfidenceRecordV1.evidence(score: 1.0, sources: [.vision], reasons: [], evidenceRefs: [])
                    attrs.append(SemanticAttributeV1(
                        key: "personId",
                        value: .string(EvidencedValueV1(
                            value: personId,
                            confidence: conf,
                            confidenceLevel: .deterministic,
                            provenance: [.init(kind: .signal, id: "MasterSensors.videoSamples.faces.personId")]
                        ))
                    ))
                }

                // Inferred speaking attribution (requires diarized word stream + binding graph).
                     if let w = nearestWord,
                         let speakerId = w.speakerId,
                         let edge = assignedBindingBySpeaker[speakerId],
                         edge.trackId == face.trackId {
                    // Use binding posterior as an auditable score.
                    let isStrong = edge.posterior >= options.minPosteriorForSpeaking
                    let reasons: [ReasonCodeV1] = isStrong ? [] : [.speaker_binding_missing]
                    let conf = ConfidenceRecordV1.evidence(
                        score: Float(edge.posterior),
                        sources: [.fused],
                        reasons: reasons,
                        evidenceRefs: [.metric("binding.posterior", value: edge.posterior)]
                    )

                    // Always surface the candidate speakerId when we have a mapped edge.
                    attrs.append(.init(key: "speakerId", value: .string(.init(
                        value: speakerId,
                        confidence: conf,
                        confidenceLevel: .inferred,
                        provenance: [
                            .init(kind: .artifact, id: "identity.bindings.v1"),
                            .init(kind: .artifact, id: "transcript.words.v1.jsonl")
                        ]
                    ))))

                    if let label = w.speakerLabel {
                        attrs.append(.init(key: "speakerLabel", value: .string(.init(
                            value: label,
                            confidence: conf,
                            confidenceLevel: .inferred,
                            provenance: [
                                .init(kind: .artifact, id: "speaker_map.v1.json")
                            ]
                        ))))
                    }

                    attrs.append(.init(key: "isSpeaking", value: .bool(.init(
                        value: isStrong,
                        confidence: conf,
                        confidenceLevel: .inferred,
                        provenance: [
                            .metric("binding.posterior", value: edge.posterior),
                            .interval("frame", startSeconds: sample.time, endSeconds: sample.time)
                        ]
                    ))))
                } else {
                    // Explicit uncertainty surface: we do not know.
                    let conf = ConfidenceRecordV1.evidence(
                        score: 0.0,
                        sources: [.fused],
                        reasons: [.speaker_binding_missing],
                        evidenceRefs: []
                    )
                    attrs.append(.init(key: "isSpeaking", value: .bool(.init(
                        value: false,
                        confidence: conf,
                        confidenceLevel: .inferred,
                        provenance: [
                            .interval("frame", startSeconds: sample.time, endSeconds: sample.time)
                        ]
                    ))))
                }

                // Stable ordering.
                attrs.sort { $0.key < $1.key }

                return SemanticSubjectV2(
                    trackId: face.trackId,
                    personId: face.personId,
                    rect: face.rect,
                    label: .person,
                    attributes: attrs
                )
            }

        // We keep contextTags minimal and deterministic (frame-level metrics are emitted as attributes).
        return SemanticFrameV2(
            timestampSeconds: sample.time,
            subjects: subjects,
            contextTags: frameMetrics.map { $0.key }
        )
    }
}
