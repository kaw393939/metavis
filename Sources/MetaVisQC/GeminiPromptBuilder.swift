import Foundation
import MetaVisCore
import MetaVisServices

public enum GeminiPromptBuilder {
    public struct Evidence: Sendable, Equatable {
        public struct LabeledInlineData: Sendable, Equatable {
            public var label: String
            public var mimeType: String
            public var data: Data

            public init(label: String, mimeType: String, data: Data) {
                self.label = label
                self.mimeType = mimeType
                self.data = data
            }
        }

        public struct LabeledFileUri: Sendable, Equatable {
            public var label: String
            public var mimeType: String
            public var fileUri: String

            public init(label: String, mimeType: String, fileUri: String) {
                self.label = label
                self.mimeType = mimeType
                self.fileUri = fileUri
            }
        }

        public var inline: [LabeledInlineData]
        public var fileUris: [LabeledFileUri]

        public init(inline: [LabeledInlineData] = [], fileUris: [LabeledFileUri] = []) {
            self.inline = inline
            self.fileUris = fileUris
        }
    }

    public struct PromptContext: Sendable, Equatable {
        public struct DeterministicMetrics: Sendable, Equatable {
            public var durationSeconds: Double?
            public var nominalFPS: Double?
            public var width: Int?
            public var height: Int?

            public init(durationSeconds: Double? = nil, nominalFPS: Double? = nil, width: Int? = nil, height: Int? = nil) {
                self.durationSeconds = durationSeconds
                self.nominalFPS = nominalFPS
                self.width = width
                self.height = height
            }
        }

        public var expectedNarrative: String
        public var keyFrameLabels: [String]
        public var policy: AIUsagePolicy
        public var privacy: PrivacyPolicy
        public var modelHint: String?
        public var metrics: DeterministicMetrics?

        public init(
            expectedNarrative: String,
            keyFrameLabels: [String],
            policy: AIUsagePolicy,
            privacy: PrivacyPolicy,
            modelHint: String? = nil,
            metrics: DeterministicMetrics? = nil
        ) {
            self.expectedNarrative = expectedNarrative
            self.keyFrameLabels = keyFrameLabels
            self.policy = policy
            self.privacy = privacy
            self.modelHint = modelHint
            self.metrics = metrics
        }
    }

    public static func buildPrompt(_ context: PromptContext, notes: [String] = []) -> String {
        let modelLine = context.modelHint.map { "MODEL_HINT: \($0)" } ?? "MODEL_HINT: (unknown)"

        let policyLine = "AI_POLICY: mode=\(context.policy.mode.rawValue), mediaSource=\(context.policy.mediaSource.rawValue), maxInlineBytes=\(context.policy.maxInlineBytes)"
        let privacyLine = "PRIVACY: allowRawMediaUpload=\(context.privacy.allowRawMediaUpload), allowDeliverablesUpload=\(context.privacy.allowDeliverablesUpload)"
        let redactionLine = "REDACTION: redactFilePaths=\(context.policy.redaction.redactFilePaths), redactIdentifiers=\(context.policy.redaction.redactIdentifiers)"

        let metricsLine: String
        if let m = context.metrics {
            func fmt(_ v: Double?) -> String {
                guard let v, v.isFinite else { return "(unknown)" }
                return String(format: "%.3f", v)
            }
            let res: String
            if let w = m.width, let h = m.height, w > 0, h > 0 {
                res = "\(w)x\(h)"
            } else {
                res = "(unknown)"
            }
            metricsLine = "METRICS: durationSeconds=\(fmt(m.durationSeconds)), nominalFPS=\(fmt(m.nominalFPS)), resolution=\(res)"
        } else {
            metricsLine = "METRICS: (none)"
        }

        let frames = context.keyFrameLabels.isEmpty ? "(none)" : context.keyFrameLabels.joined(separator: ", ")

        var lines: [String] = []
        lines.append("You are a strict QA system for a video export pipeline.")
        lines.append(modelLine)
        lines.append(policyLine)
        lines.append(privacyLine)
        lines.append(redactionLine)
        lines.append(metricsLine)
        lines.append("")
        lines.append("EXPECTED NARRATIVE:")
        lines.append(context.expectedNarrative)
        lines.append("")
        lines.append("KEYFRAMES PROVIDED (labels):")
        lines.append(frames)

        if !notes.isEmpty {
            lines.append("")
            lines.append("NOTES:")
            for n in notes { lines.append("- \(n)") }
        }

        lines.append("")
        lines.append("Return ONLY valid JSON with this schema:")
        lines.append("{\n  \"accepted\": true|false,\n  \"checks\": [ { \"label\": string, \"pass\": true|false, \"reason\": string } ],\n  \"summary\": string\n}")
        lines.append("")
        lines.append("Acceptance rules:")
        lines.append("- accepted=true ONLY if every check pass=true.")
        lines.append("- Be conservative: if uncertain, fail.")

        return lines.joined(separator: "\n")
    }

    public static func buildRequest(system: String? = nil, prompt: String, evidence: Evidence) -> GeminiGenerateContentRequest {
        var parts: [GeminiGenerateContentRequest.Part] = []
        if let system, !system.isEmpty {
            parts.append(.text("SYSTEM: \(system)"))
        }
        parts.append(.text(prompt))

        for item in evidence.inline {
            parts.append(.text("EVIDENCE: \(item.label)"))
            parts.append(.inlineData(mimeType: item.mimeType, dataBase64: item.data.base64EncodedString()))
        }

        for item in evidence.fileUris {
            parts.append(.text("EVIDENCE_URI: \(item.label)"))
            parts.append(.fileData(mimeType: item.mimeType, fileUri: item.fileUri))
        }

        return GeminiGenerateContentRequest(contents: [
            .init(parts: parts)
        ])
    }

    public static func redactedFileName(from url: URL, policy: AIUsagePolicy) -> String {
        if policy.redaction.redactFilePaths {
            return url.lastPathComponent
        }
        return url.path
    }
}
