# Search Results: Foundation Models framework on-device LLM API

**Date:** 2025-12-15 23:55:03

## Answer

Do you want a quick start, an overview, or details on specific capabilities like streaming, tool calling, or adapters?

Quick overview
- What it is: A native Swift framework that gives your app direct access to Apple’s on‑device foundation model (the same one behind Apple Intelligence). It’s private (runs on device), works offline, and there’s no per‑request cost. It supports features like guided generation, tool calling, streaming, and structured outputs. ([developer.apple.com](https://developer.apple.com/apple-intelligence/whats-new/?utm_source=openai))

Fast start (minimal flow)
Swift (example):
- import FoundationModels
- let session = LanguageModelSession(instructions: "You write short, helpful replies.")
- let text = try await session.respond(to: "Summarize this article…")
That pattern (session with instructions → respond to a prompt) is the basic API you’ll use in Xcode; you can then enable streaming, tool calling, or structured output as needed. ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))

Key capabilities you can add
- Structured output: Define Swift types the model can fill using the @Generable macro for predictable typed results. ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))
- Streaming: Show partial tokens as they arrive to keep the UI responsive. ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))
- Tool calling: Let the model call into your Swift code (for lookups, actions, etc.). ([developer.apple.com](https://developer.apple.com/apple-intelligence/whats-new/?utm_source=openai))
- Prompt design and safety: Apple provides guidance and APIs to improve safety of outputs. ([developer.apple.com](https://developer.apple.com/apple-intelligence/whats-new/?utm_source=openai))

Adapters (optional fine‑tuning)
- You can specialize the system LLM with a custom adapter trained using Apple’s Adapter Training Toolkit, then load that adapter in your app with the Foundation Models framework. Adapters are tied to specific system model versions, and deploying them requires the Foundation Models Framework Adapter Entitlement. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))

Policies and requirements
- Review Apple’s acceptable‑use requirements for what you can and can’t do with the Foundation Models framework (for example, restrictions around sensitive domains and attempting to bypass guardrails). ([developer.apple.com](https://developer.apple.com/kr/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/?utm_source=openai))

Where to find docs and samples
- Foundation Models resources hub (docs, HIG, samples, videos). ([developer.apple.com](https://developer.apple.com/apple-intelligence/resources/?utm_source=openai))
- How‑to guides like “Prompting an on‑device foundation model” and “Loading and using a custom adapter” are in the documentation set. ([developer.apple.com](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model?utm_source=openai))

Tell me:
- Which platform (iOS, iPadOS, macOS, visionOS)?
- Do you need streaming UI, tool calling, structured outputs, or adapters?
- A tiny spec of the feature you’re building (e.g., summarizer, Q&A, text extraction), and I’ll sketch the exact API calls you need.
