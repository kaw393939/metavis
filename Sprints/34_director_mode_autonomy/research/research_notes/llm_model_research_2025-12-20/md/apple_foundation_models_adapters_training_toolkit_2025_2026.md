# Search Results: Apple Foundation Models adapters training toolkit requirements 2025 2026

**Date:** 2025-12-20 17:13:53

## Answer

Here are the official requirements for training and shipping Apple Foundation Models (AFM) adapters, current as of December 20, 2025, plus what to expect going into 2026.

What you need in 2025
- Toolkit availability and OS compatibility
  - Latest adapter training toolkit version: 26.0.0. Compatible with macOS 26, iOS 26, iPadOS 26, and visionOS 26. Each toolkit version is tied to a specific system model version. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
- Apple Developer Program and entitlement
  - You must be a member of the Apple Developer Program to download the adapter training toolkit and agree to its terms. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
  - To ship adapters in an App Store app, the Account Holder must request the Foundation Models Framework Adapter Entitlement. You don’t need this entitlement to train or test locally. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
- Hardware and software prerequisites for training
  - A Mac with Apple silicon and at least 32 GB memory, or Linux GPU machines. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
  - Python 3.11 or later (pip/virtual env recommended). ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
- Versioning requirement
  - Each adapter works with only one specific system model version; if you support users on different OS/system model versions, you must train and distribute a separate adapter for each. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
- Packaging and distribution
  - Export adapters as .fmadapter packages; plan distribution as Background Assets rather than bundling in the app. Each adapter is about 160 MB. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
- Training approach
  - The toolkit performs parameter‑efficient fine‑tuning (LoRA). Apple’s research notes the provided Python toolkit trains rank‑32 adapters compatible with the Foundation Models framework. ([machinelearning.apple.com](https://machinelearning.apple.com/research/introducing-apple-foundation-models?utm_source=openai))

Planning for 2026
- Expect new toolkit releases whenever the system base model updates (often alongside platform OS updates). Adapters must be retrained for each new base model version. If your team has the Adapter Entitlement, the Account Holder will receive email notifications when new toolkit versions are available; otherwise, check the toolkit page when new betas ship. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))

If you want, tell me your machine specs and target OSes and I’ll map out a concrete setup and retraining plan for the 26.x cycle and beyond.
