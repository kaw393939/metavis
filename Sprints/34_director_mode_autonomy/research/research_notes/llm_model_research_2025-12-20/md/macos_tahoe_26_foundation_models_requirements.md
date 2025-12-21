# Search Results: macOS Tahoe 26 Apple Intelligence Foundation Models framework requirements

**Date:** 2025-12-20 17:12:50

## Answer

Here are the practical requirements to use the Apple Intelligence Foundation Models framework on macOS “Tahoe” 26:

OS and device
- A physical Mac running macOS 26 (Tahoe) with Apple Intelligence available and enabled. Apple Intelligence features (and thus the on‑device model the framework uses) aren’t supported in virtual machines, and iOS/iPadOS simulators rely on the models installed on the host macOS. ([developer.apple.com](https://developer.apple.com/forums/thread/787445?utm_source=openai))
- Foundation Models is new in the macOS 26 SDK; plan a minimum deployment target of macOS 26 for features using this framework. ([developer.apple.com](https://developer.apple.com/macos/whats-new/?utm_source=openai))

Xcode and SDK
- Xcode 26 with the macOS 26 SDK to build against the Foundation Models APIs. (Xcode 26 is the toolchain Apple references for current platform SDKs and submissions.) ([developer.apple.com](https://developer.apple.com/macos/submit/?utm_source=openai))

Network and cost model
- The framework talks to the on‑device model, works offline, and has no per‑request cost. ([developer.apple.com](https://developer.apple.com/macos/whats-new/?utm_source=openai))

Testing notes
- If you test in the iOS/iPadOS Simulator, the simulator uses the host Mac’s on‑device models; running the simulator on a Mac without macOS 26 (or with Apple Intelligence disabled) will prevent Foundation Models features from working. Not supported in VMs. ([developer.apple.com](https://developer.apple.com/forums/thread/787445?utm_source=openai))

Policies and usage restrictions
- Your app must comply with Apple’s Acceptable Use Requirements for the Foundation Models framework (for example, no regulated healthcare/legal/financial uses, no attempts to circumvent guardrails or identify training data, etc.). Review these before shipping. ([developer.apple.com](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/?utm_source=openai))

Adapters (optional, only if you fine‑tune)
- Shipping a custom adapter requires the “Foundation Models Framework Adapter” entitlement (requestable by the Account Holder). You don’t need this to train or test locally. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
- Each adapter is tied to a specific “system model” version; you’ll need to train and deliver one per supported OS model version. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
- Training locally: Mac with Apple silicon and at least 32 GB RAM (or Linux GPU machines) and Python 3.11+. This is only for training adapters, not for using the base framework. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))

International availability
- Language and locale support for Apple Intelligence expands by OS release; plan feature availability checks and graceful fallbacks. ([developer.apple.com](https://developer.apple.com/wwdc25/guides/visionos/?utm_source=openai))

Tip: In your app, check model availability at runtime before presenting features (Apple’s code‑along materials call this out as best practice). ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))

If you’re targeting something more specific (e.g., App Store review, entitlements, or adapter delivery via Background Assets), tell me your scenario and I’ll tailor the checklist.
