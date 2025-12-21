# Search Results: Apple Foundation Models framework on-device LLM Swift 2025

**Date:** 2025-12-20 16:57:45

## Answer

Here’s the short version for 2025: Apple’s Foundation Models framework lets your Swift app call the on‑device Apple Intelligence LLM directly — private, offline, with built‑in guided generation, streaming, and tool calling. It’s a first‑party framework with native Swift APIs. ([developer.apple.com](https://developer.apple.com/apple-intelligence/whats-new/?utm_source=openai))

How to get started (Swift)
- Add the Foundation Models framework to your target, and import it in Swift with: import FoundationModels. Create a session with high‑level “instructions” and send a prompt. For example: let session = LanguageModelSession(instructions: "..."); let text = try await session.respond(to: "Summarize…"). This is the minimal pattern shown in Apple’s code‑along and docs. ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))
- Generate structured data (guided generation): define Swift types with the @Generable macro, then ask the model to produce that type for predictable results. ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))
- Stream partial results to update UI as tokens arrive (for await over the streaming API). ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))
- Tool calling: register Swift “tools” so the model can call into your code to fetch data or take actions. ([developer.apple.com](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling?utm_source=openai))
- Check model availability and pre‑warm the model to reduce first‑token latency (recommended in Apple’s guidance). ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))

Adapters (optional, for domain skills)
- You can train and ship a custom adapter that specializes the system LLM for your app’s tasks, using Apple’s Adapter Training Toolkit, then load that adapter in your app via the framework. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))

Safety, policy, and UX
- Follow Apple’s acceptable‑use requirements for the Foundation Models framework, and use the provided guidance to improve output safety and design a good generative‑AI experience. ([developer.apple.com](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/?utm_source=openai))

Model details (what’s on device in 2025)
- Apple’s 2025 tech report describes the on‑device ~3B‑parameter foundation language model optimized for Apple silicon (e.g., KV‑cache sharing, 2‑bit QAT) that backs the framework access. ([machinelearning.apple.com](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025?utm_source=openai))

Want a copy‑paste Swift starter that does: 1) simple text gen, 2) a streamed response for SwiftUI, 3) a @Generable struct, and 4) one tool call? Tell me your target platform (iOS, macOS, visionOS) and I’ll tailor it.
