import Foundation
import MetaVisCore
import MetaVisPerception
import MetaVisServices

enum AutoColorCorrectQA {

    struct Result: Sendable {
        var report: AcceptanceReport
        var prompt: String?
        var rawResponse: String?

        init(report: AcceptanceReport, prompt: String? = nil, rawResponse: String? = nil) {
            self.report = report
            self.prompt = prompt
            self.rawResponse = rawResponse
        }
    }

    static func run(
        mode: AutoColorCorrectCommand.QAMode,
        sensors: MasterSensors,
        proposal: AutoColorGradeProposalV1.GradeProposal,
        evidence: EvidencePack,
        evidenceAssetRootURL: URL? = nil
    ) async throws -> Result {
        switch mode {
        case .off:
            return Result(
                report: AcceptanceReport(
                    accepted: true,
                    qualityAccepted: true,
                    qaPerformed: false,
                    summary: "QA disabled"
                )
            )

        case .localText:
            return Result(report: localTextEvaluate(sensors: sensors, proposal: proposal, evidence: evidence))

        case .gemini:
            return try await geminiEvaluate(sensors: sensors, proposal: proposal, evidence: evidence, evidenceAssetRootURL: evidenceAssetRootURL)
        }
    }

    private static func localTextEvaluate(
        sensors: MasterSensors,
        proposal: AutoColorGradeProposalV1.GradeProposal,
        evidence: EvidencePack
    ) -> AcceptanceReport {
        let p = proposal.grade.params

        let exposure = p["exposure"] ?? 0.0
        let contrast = p["contrast"] ?? 1.0
        let saturation = p["saturation"] ?? 1.0
        let temperature = p["temperature"] ?? 0.0
        let tint = p["tint"] ?? 0.0

        let descriptors = sensors.descriptors ?? []
        let avoidHeavy = descriptors.contains(where: { ($0.label == .avoidHeavyGrade || $0.label == .gradeConfidenceLow) && ($0.veto ?? false) })

        var violations: [String] = []
        var reasons: [String] = []
        var edits: [AcceptanceReport.SuggestedEdit] = []

        if avoidHeavy {
            // Tight rubric when confidence is low.
            if abs(exposure) > 0.15 {
                violations.append("HEAVY_GRADE_NOT_ALLOWED")
                reasons.append("avoidHeavyGrade veto present but exposure is large")
                edits.append(.init(path: "grade.params.exposure", value: max(-0.15, min(0.15, exposure))))
            }
            if contrast < 0.98 || contrast > 1.08 {
                violations.append("HEAVY_GRADE_NOT_ALLOWED")
                reasons.append("avoidHeavyGrade veto present but contrast is outside conservative band")
                edits.append(.init(path: "grade.params.contrast", value: max(0.98, min(1.08, contrast))))
            }
            if saturation < 0.98 || saturation > 1.08 {
                violations.append("HEAVY_GRADE_NOT_ALLOWED")
                reasons.append("avoidHeavyGrade veto present but saturation is outside conservative band")
                edits.append(.init(path: "grade.params.saturation", value: max(0.98, min(1.08, saturation))))
            }
            if abs(temperature) > 0.001 {
                violations.append("HEAVY_GRADE_NOT_ALLOWED")
                reasons.append("avoidHeavyGrade veto present but temperature is non-zero")
                edits.append(.init(path: "grade.params.temperature", value: 0.0))
            }
            if abs(tint) > 0.001 {
                violations.append("HEAVY_GRADE_NOT_ALLOWED")
                reasons.append("avoidHeavyGrade veto present but tint is non-zero")
                edits.append(.init(path: "grade.params.tint", value: 0.0))
            }
        }

        let accepted = violations.isEmpty
        return AcceptanceReport(
            accepted: accepted,
            qualityAccepted: accepted,
            qaPerformed: true,
            summary: accepted ? "Local text QA accepted" : "Local text QA found issues",
            score: accepted ? 0.85 : 0.45,
            reasons: reasons,
            violations: violations,
            suggestedEdits: edits
        )
    }

    private static func geminiEvaluate(
        sensors: MasterSensors,
        proposal: AutoColorGradeProposalV1.GradeProposal,
        evidence: EvidencePack,
        evidenceAssetRootURL: URL?
    ) async throws -> Result {
        let config = try GeminiConfig.fromEnvironment()
        let client = GeminiClient(config: config)

        let proposalJSON = String(data: (try? JSONWriting.encode(proposal)) ?? Data(), encoding: .utf8) ?? "{}"

        let prompt = """
You are a strict, conservative QC assistant for auto color correction.

You will be given:
- A deterministic EvidencePack summary (text, plus optional JPEG frames)
- A proposed GradeProposal JSON applying com.metavis.fx.grade.simple
- A ParameterWhitelist limiting what you are allowed to change

Task:
- Decide whether the proposal is acceptable.
- If not acceptable, suggest bounded edits ONLY within the whitelist.
- Prefer the smallest change that resolves the issue.

Critical calibration:
- Luma values are normalized in [0,1] where 0 = black and 1 = white.
- Target mean luma is ~0.45.
- If meanLuma > 0.45, exposure generally should move NEGATIVE (reduce brightness).
- If meanLuma < 0.45, exposure generally should move POSITIVE (increase brightness).
- Do not invert this relationship.

Decision rule for exposure (unless JPEG evidence clearly contradicts):
- Let expectedExposure ≈ (0.45 - meanLuma).
- If GradeProposal.grade.params.exposure is within ±0.02 of expectedExposure, do NOT suggest an exposure edit.
- If it is outside that band, suggest moving exposure toward expectedExposure, bounded by the whitelist.
- If you believe the meanLuma statistic is misleading, request additional frames instead of suggesting a contradictory edit.

Guardrails:
- Do NOT suggest changes to color management transforms (no IDT/ODT changes, no tonemap changes).
- Only numeric params in the whitelist are editable.

EvidencePack.textSummary:
\(evidence.textSummary)

GradeProposal JSON:
\(proposalJSON)

Return JSON only (no markdown, no backticks, no code fences).
The response MUST start with '{' and end with '}'.
Use this exact shape (include every field; no extra top-level keys):
{
  "accepted": true|false,
  "qualityAccepted": true|false,
  "qaPerformed": true,
  "score": number|null,
  "reasons": [string],
  "violations": [string],
  "suggestedEdits": [{"path": string, "value": number}],
  "requestedEvidenceEscalation": {"addFramesAtSeconds": [number], "extendOneAudioClipToSeconds": number|null, "notes": [string]}|null,
  "summary": string
}

Machine-readable violations MUST use stable codes when possible:
- HEAVY_GRADE_NOT_ALLOWED
- COLOR_CAST_PRESENT
- EXPOSURE_OFF
- QA_PARSE_ERROR
"""

        var parts: [GeminiGenerateContentRequest.Part] = [.text(prompt)]
        if let root = evidenceAssetRootURL {
            for frame in evidence.assets.frames {
                let url = root.appendingPathComponent(frame.path)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let data = try Data(contentsOf: url)
                if data.count > 1_500_000 { continue }
                parts.append(.text("FRAME path=\(frame.path) time=\(String(format: "%.3f", frame.timeSeconds)) tags=\(frame.rationaleTags.joined(separator: ","))"))
                parts.append(.inlineData(mimeType: "image/jpeg", dataBase64: data.base64EncodedString()))
            }
        }

        let requestBody = GeminiGenerateContentRequest(contents: [
            .init(role: "user", parts: parts)
        ])

        let response = try await client.generateContent(requestBody)
        let raw = response.primaryText ?? ""
        let json = extractJSONObject(from: raw) ?? raw

        let decoded: AcceptanceReport
        do {
            decoded = try JSONDecoder().decode(AcceptanceReport.self, from: Data(json.utf8))
        } catch {
            let fallback = AcceptanceReport(
                accepted: false,
                qualityAccepted: false,
                qaPerformed: true,
                summary: "Gemini QA response parse failed",
                score: 0.0,
                reasons: ["Failed to decode Gemini JSON response"],
                violations: ["QA_PARSE_ERROR"]
            )
            return Result(report: fallback, prompt: prompt, rawResponse: raw)
        }

        return Result(report: decoded, prompt: prompt, rawResponse: raw)
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        guard let end = text.lastIndex(of: "}") else { return nil }
        guard end >= start else { return nil }
        return String(text[start...end])
    }
}
