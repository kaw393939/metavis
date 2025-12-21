import Foundation
import MetaVisCore
import MetaVisPerception
import MetaVisServices

enum AutoSpeakerAudioQA {

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
        mode: AutoSpeakerAudioCommand.QAMode,
        sensors: MasterSensors,
        proposal: AutoSpeakerAudioProposalV1.AudioProposal,
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
        proposal: AutoSpeakerAudioProposalV1.AudioProposal,
        evidence: EvidencePack
    ) -> AcceptanceReport {
        let gainPath = "chain[0].params.globalGainDB"
        let gain = proposal.chain.first?.params?["globalGainDB"] ?? 0.0

        var violations: [String] = []
        var reasons: [String] = []
        var suggestedEdits: [AcceptanceReport.SuggestedEdit] = []

        // Minimal deterministic rubric (v1): clipRisk implies we should be conservative with gain.
        if proposal.flags.contains("clipRisk"), gain > 3.0 {
            violations.append("CLIPPING_PRESENT")
            reasons.append("clipRisk flag present and gain is high")
            suggestedEdits.append(.init(path: gainPath, value: 3.0))
        }

        // If noiseRisk is present but we applied no chain, call it out.
        if proposal.flags.contains("noiseRisk"), proposal.chain.isEmpty {
            violations.append("INTELLIGIBILITY_LOW")
            reasons.append("noiseRisk flag present but no cleanup chain applied")
        }

        let accepted = violations.isEmpty
        return AcceptanceReport(
            accepted: accepted,
            qualityAccepted: accepted,
            qaPerformed: true,
            summary: accepted ? "Local text QA accepted" : "Local text QA found issues",
            score: accepted ? 0.9 : 0.4,
            reasons: reasons,
            violations: violations,
            suggestedEdits: suggestedEdits
        )
    }

    private static func geminiEvaluate(
        sensors: MasterSensors,
        proposal: AutoSpeakerAudioProposalV1.AudioProposal,
        evidence: EvidencePack,
        evidenceAssetRootURL: URL?
    ) async throws -> Result {
        let config = try GeminiConfig.fromEnvironment()
        let client = GeminiClient(config: config)

        let gainPath = "chain[0].params.globalGainDB"
        let gain = proposal.chain.first?.params?["globalGainDB"] ?? 0.0
        let whitelist = proposal.whitelist.numeric[gainPath]
        let approxPeakDB = proposal.metricsSnapshot?.approxPeakDB ?? Double(sensors.summary.audio.approxPeakDB)
        let approxPeakStr = String(format: "%.2f", approxPeakDB)
        let predictedPeakStr = String(format: "%.2f", approxPeakDB + gain)

        let proposalJSON = String(data: (try? JSONWriting.encode(proposal)) ?? Data(), encoding: .utf8) ?? "{}"

        let prompt = """
You are a strict, conservative QC assistant for spoken-word audio enhancement.

You will be given:
- A deterministic EvidencePack summary (text only)
- A proposed AudioProposal JSON
- A ParameterWhitelist limiting what you are allowed to change

Task:
- Decide whether the proposal is acceptable.
- If not acceptable, suggest bounded edits ONLY within the whitelist.
- Prefer the smallest change that resolves the issue.

Critical calibration (dBFS math):
- `approxPeakDB` is in dBFS (0 dBFS is full-scale; values closer to 0 are louder).
- Applying `globalGainDB` shifts peak approximately by addition:
    predictedPeakDBFS ≈ approxPeakDB + globalGainDB
- Hard constraint: predictedPeakDBFS MUST stay <= 0.0 (avoid clipping).
- Conservative target headroom: predictedPeakDBFS <= -0.5 dBFS when `clipRisk` is present.
- If `approxPeakDB` is missing, be extra conservative and request evidence escalation instead of guessing.

Allowed edit space:
- Only numeric params in the whitelist are editable.
- For this run, only this path is expected to be editable: \(gainPath)

Whitelist for \(gainPath):
- min=\(whitelist?.min ?? -6.0)
- max=\(whitelist?.max ?? 6.0)
- maxDeltaPerCycle=\(whitelist?.maxDeltaPerCycle ?? 2.0)

Current value:
- \(gainPath)=\(gain)

Peak estimate:
- approxPeakDB=\(approxPeakStr)
- predictedPeakDBFS≈\(predictedPeakStr)

EvidencePack.textSummary:
\(evidence.textSummary)

AudioProposal JSON:
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
- INTELLIGIBILITY_LOW
- NOISE_ARTIFACTS_PRESENT
- CLIPPING_PRESENT
- LOUDNESS_INCONSISTENT
"""

        var parts: [GeminiGenerateContentRequest.Part] = [.text(prompt)]
        if let root = evidenceAssetRootURL {
            // Attach evidence assets when available (small, bounded uploads).
            for clip in evidence.assets.audioClips {
                let url = root.appendingPathComponent(clip.path)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let data = try Data(contentsOf: url)
                // Guardrail: avoid oversized uploads.
                if data.count > 1_500_000 { continue }
                parts.append(.text("AUDIO_CLIP path=\(clip.path) start=\(String(format: "%.3f", clip.startSeconds)) end=\(String(format: "%.3f", clip.endSeconds)) tags=\(clip.rationaleTags.joined(separator: ","))"))
                parts.append(.inlineData(mimeType: "audio/wav", dataBase64: data.base64EncodedString()))
            }

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
