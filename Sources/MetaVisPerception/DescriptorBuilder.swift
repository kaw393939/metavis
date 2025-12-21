import Foundation

enum DescriptorBuilder {

    struct Options: Sendable {
        var minConfidence: Double
        var silenceGapSeconds: Double

        init(minConfidence: Double = 0.55, silenceGapSeconds: Double = 0.4) {
            self.minConfidence = minConfidence
            self.silenceGapSeconds = silenceGapSeconds
        }
    }

    static func build(
        videoSamples: [MasterSensors.VideoSample],
        audioSegments: [MasterSensors.AudioSegment],
        audioBeats: [MasterSensors.AudioBeat] = [],
        warnings: [MasterSensors.WarningSegment],
        suggestedStart: MasterSensors.SuggestedStart?,
        scene: MasterSensors.SceneContext,
        analyzedSeconds: Double,
        options: Options = Options()
    ) -> [MasterSensors.DescriptorSegment] {
        guard analyzedSeconds > 0.0001 else { return [] }

        let stats = Stats(videoSamples: videoSamples, audioSegments: audioSegments, warnings: warnings, analyzedSeconds: analyzedSeconds)

        var out: [MasterSensors.DescriptorSegment] = []

        // Segment-level audio descriptors (minimal): mark silence regions.
        // NOTE: We intentionally do NOT emit segment-level continuous_speech; it duplicates the global descriptor.
        for seg in audioSegments {
            let start = clamp(seg.start, 0.0, analyzedSeconds)
            let end = clamp(seg.end, 0.0, analyzedSeconds)
            if end <= start + 0.0001 { continue }
            switch seg.kind {
            case .silence:
                out.append(
                    MasterSensors.DescriptorSegment(
                        start: start,
                        end: end,
                        label: .silenceGap,
                        confidence: clamp(seg.confidence, 0.0, 1.0),
                        veto: nil,
                        evidence: [
                            .init(field: "audioSegment.kind", value: 0.0),
                            .init(field: "audioSegment.confidence", value: seg.confidence)
                        ],
                        reasons: ["silence_detected"]
                    )
                )
            default:
                break
            }
        }

        if let suggestedStart {
            let start = 0.0
            let end = clamp(suggestedStart.time, 0.0, analyzedSeconds)
            if end > start + 0.0001 {
                out.append(
                    MasterSensors.DescriptorSegment(
                        start: start,
                        end: end,
                        label: .suggestedStart,
                        confidence: clamp(suggestedStart.confidence, 0.0, 1.0),
                        veto: nil,
                        evidence: [
                            .init(field: "suggestedStart.time", value: end),
                            .init(field: "speechCoverage", value: stats.speechCoverage),
                            .init(field: "facePresenceRate", value: stats.facePresenceRate)
                        ],
                        reasons: suggestedStart.reasons
                    )
                )
            }
        }

        if scene.indoorOutdoor.confidence < options.minConfidence || scene.lightSource.confidence < options.minConfidence {
            out.append(
                MasterSensors.DescriptorSegment(
                    start: 0.0,
                    end: analyzedSeconds,
                    label: .gradeConfidenceLow,
                    confidence: clamp(1.0 - min(scene.indoorOutdoor.confidence, scene.lightSource.confidence), 0.0, 1.0),
                    veto: nil,
                    evidence: [
                        .init(field: "scene.indoorOutdoor.confidence", value: scene.indoorOutdoor.confidence),
                        .init(field: "scene.lightSource.confidence", value: scene.lightSource.confidence)
                    ],
                    reasons: ["scene_confidence_low"]
                )
            )
            out.append(
                MasterSensors.DescriptorSegment(
                    start: 0.0,
                    end: analyzedSeconds,
                    label: .avoidHeavyGrade,
                    confidence: clamp(1.0 - min(scene.indoorOutdoor.confidence, scene.lightSource.confidence), 0.0, 1.0),
                    veto: nil,
                    evidence: [
                        .init(field: "scene.indoorOutdoor.confidence", value: scene.indoorOutdoor.confidence),
                        .init(field: "scene.lightSource.confidence", value: scene.lightSource.confidence)
                    ],
                    reasons: ["grade_confidence_low"]
                )
            )
        }

        if stats.facePresenceRate <= 0.10 {
            out.append(
                MasterSensors.DescriptorSegment(
                    start: 0.0,
                    end: analyzedSeconds,
                    label: .noFaceDetected,
                    confidence: clamp(1.0 - stats.facePresenceRate, 0.0, 1.0),
                    veto: nil,
                    evidence: [
                        .init(field: "facePresenceRate", value: stats.facePresenceRate)
                    ],
                    reasons: ["face_presence_low"]
                )
            )
        }

        if stats.people2pRate >= 0.30 {
            out.append(
                MasterSensors.DescriptorSegment(
                    start: 0.0,
                    end: analyzedSeconds,
                    label: .multiPerson,
                    confidence: clamp((stats.people2pRate - 0.30) / 0.70, 0.0, 1.0),
                    veto: true,
                    evidence: [
                        .init(field: "people2pRate", value: stats.people2pRate),
                        .init(field: "singleFaceRate", value: stats.singleFaceRate)
                    ],
                    reasons: ["multiple_people_detected"]
                )
            )
        }

        // Conservative single-subject: we only emit this when the data strongly supports it.
        if stats.singleFaceRate >= 0.60 && stats.people2pRate <= 0.20 && stats.facePresenceRate >= 0.40 {
            let conf = clamp(min(1.0, (stats.singleFaceRate - 0.60) / 0.40), 0.0, 1.0)
            out.append(
                MasterSensors.DescriptorSegment(
                    start: 0.0,
                    end: analyzedSeconds,
                    label: .singleSubject,
                    confidence: max(0.55, conf),
                    veto: nil,
                    evidence: [
                        .init(field: "singleFaceRate", value: stats.singleFaceRate),
                        .init(field: "people2pRate", value: stats.people2pRate),
                        .init(field: "facePresenceRate", value: stats.facePresenceRate),
                        .init(field: "faceAreaMean", value: stats.faceAreaMean)
                    ],
                    reasons: ["single_face_rate_high"]
                )
            )
        }

        if stats.speechCoverage >= 0.70 && stats.speechSeconds >= 1.0 {
            let conf = clamp((stats.speechCoverage - 0.70) / 0.30, 0.0, 1.0)
            out.append(
                MasterSensors.DescriptorSegment(
                    start: 0.0,
                    end: analyzedSeconds,
                    label: .continuousSpeech,
                    confidence: max(0.55, conf),
                    veto: nil,
                    evidence: [
                        .init(field: "speechCoverage", value: stats.speechCoverage),
                        .init(field: "speechSeconds", value: stats.speechSeconds),
                        .init(field: "silenceCoverage", value: stats.silenceCoverage)
                    ],
                    reasons: ["speech_coverage_high"]
                )
            )
        }

        if stats.maxSilenceGapSeconds >= options.silenceGapSeconds {
            let conf = clamp((stats.maxSilenceGapSeconds - options.silenceGapSeconds) / 1.2, 0.0, 1.0)
            out.append(
                MasterSensors.DescriptorSegment(
                    start: 0.0,
                    end: analyzedSeconds,
                    label: .silenceGap,
                    confidence: max(0.55, conf),
                    veto: nil,
                    evidence: [
                        .init(field: "maxSilenceGapSeconds", value: stats.maxSilenceGapSeconds)
                    ],
                    reasons: ["silence_gap_detected"]
                )
            )
        }

        // Punch-in suggestions: centered on audio emphasis beats when the single face is stable.
        // This is intentionally conservative; it should only emit when the evidence is strong.
        do {
            let beatsSorted = audioBeats.sorted {
                if $0.time != $1.time { return $0.time < $1.time }
                if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return $0.reasons.joined(separator: ",") < $1.reasons.joined(separator: ",")
            }

            // Video samples are typically 1s stride, so use a wider window to reliably include >=2 samples.
            let faceWindowSeconds: Double = 2.2
            let markerHalfSeconds: Double = 0.15
            // If confidence is low, do not suggest A-roll punch-in cuts.
            let minBeatConfidence: Double = 0.70
            let minSpacingSeconds: Double = 0.75
            let minFacePresentRate: Double = 0.60
            let minSingleFaceRate: Double = 0.60
            let maxCenterRMS: Double = 0.012
            let maxAreaRelStd: Double = 0.12
            let maxFaceAreaMean: Double = 0.22

            var lastAcceptedTime: Double = -1_000_000.0

            for beat in beatsSorted {
                guard beat.kind == .emphasis else { continue }
                guard beat.confidence >= minBeatConfidence else { continue }
                let anchorTime = beat.timeImpact ?? beat.time
                if anchorTime - lastAcceptedTime < minSpacingSeconds { continue }

                let wStart = clamp(anchorTime - faceWindowSeconds * 0.5, 0.0, analyzedSeconds)
                let wEnd = clamp(anchorTime + faceWindowSeconds * 0.5, 0.0, analyzedSeconds)
                if wEnd <= wStart + 0.0001 { continue }

                guard let faceStats = FaceWindowStats(videoSamples: videoSamples, start: wStart, end: wEnd) else { continue }
                guard faceStats.facePresentRate >= minFacePresentRate else { continue }
                guard faceStats.singleFaceRate >= minSingleFaceRate else { continue }
                guard faceStats.centerRMS <= maxCenterRMS else { continue }
                guard faceStats.areaRelStd <= maxAreaRelStd else { continue }
                guard faceStats.areaMean <= maxFaceAreaMean else { continue }

                let segStart = clamp(anchorTime - markerHalfSeconds, 0.0, analyzedSeconds)
                let segEnd = clamp(anchorTime + markerHalfSeconds, 0.0, analyzedSeconds)
                if segEnd <= segStart + 0.0001 { continue }

                let stability = clamp(1.0 - (faceStats.centerRMS / maxCenterRMS), 0.0, 1.0)
                let conf = clamp(min(beat.confidence, stability), 0.0, 1.0)
                if conf < options.minConfidence { continue }

                out.append(
                    MasterSensors.DescriptorSegment(
                        start: segStart,
                        end: segEnd,
                        label: .punchInSuggestion,
                        confidence: conf,
                        veto: nil,
                        evidence: [
                            .init(field: "audioBeat.confidence", value: beat.confidence),
                            .init(field: "audioBeat.timeOnset", value: beat.time),
                            .init(field: "audioBeat.timeImpact", value: anchorTime),
                            .init(field: "faceWindow.centerRMS", value: faceStats.centerRMS),
                            .init(field: "faceWindow.areaMean", value: faceStats.areaMean),
                            .init(field: "faceWindow.areaRelStd", value: faceStats.areaRelStd),
                            .init(field: "faceWindow.facePresentRate", value: faceStats.facePresentRate),
                            .init(field: "faceWindow.singleFaceRate", value: faceStats.singleFaceRate)
                        ],
                        reasons: [
                            "audio_beat_emphasis",
                            "face_stable"
                        ]
                    )
                )

                lastAcceptedTime = anchorTime
            }
        }

        // Safe-for-beauty is a high-level “go” signal: single subject + continuous speech + not dominated by red warnings.
        if out.contains(where: { $0.label == .singleSubject }) && out.contains(where: { $0.label == .continuousSpeech }) {
            if stats.warningRedCoverage <= 0.20 {
                let conf = clamp((0.20 - stats.warningRedCoverage) / 0.20, 0.0, 1.0)
                let reasons = ([
                    "single_subject",
                    "continuous_speech",
                    "low_red_warning_coverage"
                ] + stats.redWarningReasons)
                out.append(
                    MasterSensors.DescriptorSegment(
                        start: 0.0,
                        end: analyzedSeconds,
                        label: .safeForBeauty,
                        confidence: max(0.55, conf),
                        veto: nil,
                        evidence: [
                            .init(field: "warningRedCoverage", value: stats.warningRedCoverage),
                            .init(field: "singleFaceRate", value: stats.singleFaceRate),
                            .init(field: "speechCoverage", value: stats.speechCoverage)
                        ],
                        reasons: reasons
                    )
                )
            }
        }

        // Stable ordering: start, end, label.
        out.sort {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.label.rawValue < $1.label.rawValue
        }

        return out
    }

    private struct Stats {
        let facePresenceRate: Double
        let singleFaceRate: Double
        let people2pRate: Double
        let faceAreaMean: Double

        let speechCoverage: Double
        let silenceCoverage: Double
        let speechSeconds: Double
        let maxSilenceGapSeconds: Double

        let warningRedCoverage: Double
        let redWarningReasons: [String]

        init(
            videoSamples: [MasterSensors.VideoSample],
            audioSegments: [MasterSensors.AudioSegment],
            warnings: [MasterSensors.WarningSegment],
            analyzedSeconds: Double
        ) {
            let totalSamples = max(1, videoSamples.count)
            let facePresentCount = videoSamples.filter { !$0.faces.isEmpty }.count
            let singleFaceCount = videoSamples.filter { $0.faces.count == 1 }.count
            let people2pCount = videoSamples.filter {
                let estimate = $0.peopleCountEstimate ?? $0.faces.count
                return estimate >= 2
            }.count

            self.facePresenceRate = Double(facePresentCount) / Double(totalSamples)
            self.singleFaceRate = Double(singleFaceCount) / Double(totalSamples)
            self.people2pRate = Double(people2pCount) / Double(totalSamples)

            var faceAreas: [Double] = []
            faceAreas.reserveCapacity(videoSamples.count)
            for s in videoSamples {
                guard !s.faces.isEmpty else { continue }
                let maxArea = s.faces
                    .map { Double($0.rect.width * $0.rect.height) }
                    .max() ?? 0.0
                faceAreas.append(maxArea)
            }
            if faceAreas.isEmpty {
                self.faceAreaMean = 0.0
            } else {
                self.faceAreaMean = faceAreas.reduce(0.0, +) / Double(faceAreas.count)
            }

            func clampToAnalyzed(_ start: Double, _ end: Double) -> (Double, Double)? {
                let s = max(0.0, min(analyzedSeconds, start))
                let e = max(0.0, min(analyzedSeconds, end))
                if e <= s + 0.0001 { return nil }
                return (s, e)
            }

            var speechSeconds: Double = 0.0
            var silenceSeconds: Double = 0.0
            var maxSilenceGap: Double = 0.0

            let segmentsSorted = audioSegments.sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.end < $1.end
            }

            for seg in segmentsSorted {
                guard let (s, e) = clampToAnalyzed(seg.start, seg.end) else { continue }
                let dur = e - s
                switch seg.kind {
                case .speechLike:
                    speechSeconds += dur
                case .silence:
                    silenceSeconds += dur
                    maxSilenceGap = max(maxSilenceGap, dur)
                default:
                    break
                }
            }

            self.speechSeconds = speechSeconds
            self.speechCoverage = analyzedSeconds > 0 ? clamp(speechSeconds / analyzedSeconds, 0.0, 1.0) : 0.0
            self.silenceCoverage = analyzedSeconds > 0 ? clamp(silenceSeconds / analyzedSeconds, 0.0, 1.0) : 0.0
            self.maxSilenceGapSeconds = maxSilenceGap

            var redSeconds: Double = 0.0
            var redReasons: [String] = []
            for w in warnings where w.severity == .red {
                guard let (s, e) = clampToAnalyzed(w.start, w.end) else { continue }
                redSeconds += (e - s)
                redReasons.append(contentsOf: w.governedReasonCodes.map { $0.rawValue })
            }
            self.warningRedCoverage = analyzedSeconds > 0 ? clamp(redSeconds / analyzedSeconds, 0.0, 1.0) : 0.0
            self.redWarningReasons = Array(Set(redReasons)).sorted()
        }
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    private struct FaceWindowStats {
        let facePresentRate: Double
        let singleFaceRate: Double
        let centerRMS: Double
        let areaMean: Double
        let areaRelStd: Double

        init?(videoSamples: [MasterSensors.VideoSample], start: Double, end: Double) {
            let inWindow = videoSamples.filter { $0.time >= start - 0.000001 && $0.time <= end + 0.000001 }
            guard !inWindow.isEmpty else { return nil }

            let total = Double(inWindow.count)
            let facePresentCount = Double(inWindow.filter { !$0.faces.isEmpty }.count)
            let singleFaceCount = Double(inWindow.filter { $0.faces.count == 1 }.count)

            self.facePresentRate = facePresentCount / total
            self.singleFaceRate = singleFaceCount / total

            var centersX: [Double] = []
            var centersY: [Double] = []
            var areas: [Double] = []
            centersX.reserveCapacity(inWindow.count)
            centersY.reserveCapacity(inWindow.count)
            areas.reserveCapacity(inWindow.count)

            for s in inWindow {
                guard !s.faces.isEmpty else { continue }
                let maxFace = s.faces.max { (a, b) in
                    (a.rect.width * a.rect.height) < (b.rect.width * b.rect.height)
                }
                guard let maxFace else { continue }
                let r = maxFace.rect
                let cx = Double(r.midX)
                let cy = Double(r.midY)
                let area = Double(r.width * r.height)
                if !cx.isFinite || !cy.isFinite || !area.isFinite { continue }
                centersX.append(cx)
                centersY.append(cy)
                areas.append(area)
            }

            guard centersX.count >= 2, centersY.count == centersX.count, areas.count == centersX.count else { return nil }

            let n = Double(centersX.count)
            let meanX = centersX.reduce(0.0, +) / n
            let meanY = centersY.reduce(0.0, +) / n
            let meanA = areas.reduce(0.0, +) / n
            self.areaMean = meanA

            var sumSq: Double = 0.0
            for i in 0..<centersX.count {
                let dx = centersX[i] - meanX
                let dy = centersY[i] - meanY
                sumSq += (dx * dx + dy * dy)
            }
            self.centerRMS = (sumSq / n).squareRoot()

            if meanA <= 0.0000001 {
                self.areaRelStd = 1.0
            } else {
                var varA: Double = 0.0
                for a in areas {
                    let da = a - meanA
                    varA += da * da
                }
                let stdA = (varA / n).squareRoot()
                self.areaRelStd = stdA / meanA
            }
        }
    }
}
