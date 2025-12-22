import Foundation
import MetaVisCore

/// Represents a request to the Local LLM.
public struct LLMRequest: Sendable, Codable {
    public let systemPrompt: String
    public let userQuery: String
    public let context: String // JSON representation of Visual/Timeline context

    public static let defaultSystemPrompt: String = {
        "You are Jarvis, a helpful video editing assistant.\n\n" + UserIntent.jsonSchemaDescription
    }()
    
    public init(systemPrompt: String = Self.defaultSystemPrompt, userQuery: String, context: String) {
        self.systemPrompt = systemPrompt
        self.userQuery = userQuery
        self.context = context
    }
}

/// Represents a response from the Local LLM.
public struct LLMResponse: Sendable, Codable {
    public let text: String
    public let intentJSON: String? // Extracted JSON block if present
    public let latency: TimeInterval

    public init(text: String, intentJSON: String?, latency: TimeInterval) {
        self.text = text
        self.intentJSON = intentJSON
        self.latency = latency
    }
}

/// The Service responsible for Text Generation.
/// Wraps a local CoreML Transformer (e.g. Llama-3-8B).
public actor LocalLLMService: LLMProvider {
    
    public init() {}
    
    public func warmUp() async throws {
        // Load model...
    }
    
    /// Generates a response for the given request.
    public func generate(request: LLMRequest) async throws -> LLMResponse {
        let start = Date()
        
        // Mock Implementation for now.
        // In real life, we'd feed:
        // System: <request.systemPrompt>
        // Context: <request.context>
        // User: <request.userQuery>
        
        // NOTE: This is a deterministic heuristic implementation (used as a fallback when
        // a real on-device model isn't available). We do not add artificial latency here.
        
        // Mock Logic: keyword-based intent emission.
        let responseText: String
        let json: String?
        
        let q = request.userQuery.lowercased()

        func firstNumber(in text: String) -> Double? {
            // Extract the first floating point number from free-form text.
            // Examples: "1", "1.25", "to 3s".
            let pattern = "([-+]?[0-9]*\\.?[0-9]+)"
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = re.firstMatch(in: text, range: range) else { return nil }
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            return Double(text[r])
        }

        // Optional deterministic targeting based on the encoded editing context.
        // This keeps the mock useful for end-to-end tests without a real model.
        let selectedVideo: LLMEditingContext.ClipSummary? = {
            guard let data = request.context.data(using: .utf8) else { return nil }
            guard let ctx = try? JSONDecoder().decode(LLMEditingContext.self, from: data) else { return nil }

            let videos = ctx.clips.filter { $0.trackKind == .video }
            guard !videos.isEmpty else { return nil }

            // Ordinal targeting (explicit) wins.
            if q.contains("second") || q.contains("clip 2") || q.contains("clip two") {
                return videos.count >= 2 ? videos[1] : videos[0]
            }

            // Name targeting: match any clip name substring mentioned in the query.
            // Prefer longer names to avoid accidental matches.
            let byName = videos
                .sorted(by: { $0.name.count > $1.name.count })
                .first(where: { !($0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && q.contains($0.name.lowercased()) })
            if let byName {
                return byName
            }

            // Heuristic token targeting: match common generator keywords in sourceFn.
            let bySourceToken = videos.first(where: {
                let src = $0.assetSourceFn.lowercased()
                return (q.contains("macbeth") && src.contains("macbeth")) ||
                       (q.contains("smpte") && src.contains("smpte")) ||
                       (q.contains("zone") && src.contains("zone"))
            })
            if let bySourceToken {
                return bySourceToken
            }

            return nil
        }()

        let clipId = selectedVideo?.id

        func renderJSON(action: String, target: String, params: [String: Double]) -> String {
            func fmt(_ d: Double) -> String {
                if d.isFinite { return String(d) }
                return "0"
            }
            let paramsJSON = params
                .sorted(by: { $0.key < $1.key })
                .map { "\"\($0.key)\": \(fmt($0.value))" }
                .joined(separator: ", ")

            if let clipId {
                return """
                {
                    \"action\": \"\(action)\",
                    \"target\": \"\(target)\",
                    \"params\": { \(paramsJSON) },
                    \"clipId\": \"\(clipId.uuidString)\"
                }
                """
            }

            return """
            {
                \"action\": \"\(action)\",
                \"target\": \"\(target)\",
                \"params\": { \(paramsJSON) }
            }
            """
        }
        if q.contains("ripple") && (q.contains("delete") || q.contains("remove")) {
            responseText = "Here is the command to ripple delete the clip."
            json = renderJSON(action: "ripple_delete", target: "clip", params: [:])
        } else if q.contains("move") {
            responseText = "Here is the command to move the clip."
            let n = firstNumber(in: q) ?? 1.0
            if q.contains(" by "), let base = selectedVideo?.startSeconds {
                // Delta semantics.
                // Support explicit direction words for positive numbers.
                let earlier = q.contains("earlier") || q.contains("before") || q.contains("left")
                let later = q.contains("later") || q.contains("after") || q.contains("right")
                let delta: Double
                if n < 0 {
                    delta = n
                } else if earlier && !later {
                    delta = -n
                } else {
                    delta = n
                }
                json = renderJSON(action: "move", target: "clip", params: ["start_seconds": max(0, base + delta)])
            } else {
                // Absolute semantics.
                json = renderJSON(action: "move", target: "clip", params: ["start_seconds": n])
            }
        } else if (q.contains("trim in") || q.contains("trim-in") || q.contains("slip")) && q.contains("ripple") {
            responseText = "Here is the command to ripple trim in."
            let n = firstNumber(in: q) ?? 0.5
            if q.contains(" by "), let base = selectedVideo?.offsetSeconds {
                json = renderJSON(action: "ripple_trim_in", target: "clip", params: ["offset_seconds": max(0, base + n)])
            } else {
                json = renderJSON(action: "ripple_trim_in", target: "clip", params: ["offset_seconds": n])
            }
        } else if q.contains("trim in") || q.contains("trim-in") || q.contains("slip") {
            responseText = "Here is the command to trim in (slip)."
            let n = firstNumber(in: q) ?? 0.5
            if q.contains(" by "), let base = selectedVideo?.offsetSeconds {
                let decrease = q.contains("back") || q.contains("decrease") || q.contains("less")
                let delta = decrease && n > 0 ? -n : n
                json = renderJSON(action: "trim_in", target: "clip", params: ["offset_seconds": max(0, base + delta)])
            } else {
                json = renderJSON(action: "trim_in", target: "clip", params: ["offset_seconds": n])
            }
        } else if q.contains("ripple") {
            responseText = "Here is the command to ripple trim out."
            let n = firstNumber(in: q) ?? 3.0
            if q.contains(" by "), let sel = selectedVideo {
                let oldEnd = sel.startSeconds + sel.durationSeconds
                let extend = q.contains("extend") || q.contains("longer") || q.contains("add")
                let newEnd = extend ? (oldEnd + n) : (oldEnd - n)
                json = renderJSON(action: "ripple_trim_out", target: "clip", params: ["end_seconds": max(0, newEnd)])
            } else {
                json = renderJSON(action: "ripple_trim_out", target: "clip", params: ["end_seconds": n])
            }
        } else if q.contains("trim") {
            responseText = "Here is the command to trim the clip end."
            let end = firstNumber(in: q) ?? 3.0
            json = renderJSON(action: "trim_end", target: "clip", params: ["end_seconds": end])
        } else if q.contains("cut") || q.contains("blade") {
            responseText = "Here is the command to cut the clip."
            let t = firstNumber(in: q) ?? 1.0
            json = renderJSON(action: "cut", target: "clip", params: ["time": t])
        } else if q.contains("speed") || q.contains("faster") || q.contains("slower") {
            responseText = "Here is the command to change speed."
            let f = firstNumber(in: q) ?? 1.25
            json = renderJSON(action: "speed", target: "clip", params: ["factor": f])
        } else if q.contains("blue") {
            responseText = "Here is the command to make it blue."
            json = """
            {
                "action": "color_grade",
                "target": "shirt",
                "params": { "hue": 0.6 }
            }
            """
        } else {
            responseText = "I'm not sure what you want to do."
            json = nil
        }
        
        let latency = Date().timeIntervalSince(start)
        return LLMResponse(text: responseText, intentJSON: json, latency: latency)
    }
}
