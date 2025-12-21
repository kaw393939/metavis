# Search Results: Foundation Models framework availability iOS 18 iPhone 16 Pro Max

**Date:** 2025-12-20 17:14:56

## Answer

Short answer: Yes — the Foundation Models framework is part of the iOS 18 SDK and can be used on iPhone 16 Pro Max. It gives apps on-device access to the Apple Intelligence foundation model; however, you must still check runtime availability because the model can be unavailable if Apple Intelligence is turned off, the device isn’t eligible, or the model isn’t ready yet. ([developer.apple.com](https://developer.apple.com/wwdc25/guides/ios/?utm_source=openai))

What to do on device:
- Ensure Apple Intelligence is enabled in Settings and that the device’s language/region is supported. ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))
- Check availability before using the model:
  - Swift snippet:
    - let model = SystemLanguageModel.default
    - switch model.availability { case .available: … case .unavailable(.appleIntelligenceNotEnabled): … case .unavailable(.deviceNotEligible): … default: … } ([developer.apple.com](https://developer.apple.com/events/resources/code-along-205/?utm_source=openai))

Notes:
- The framework is designed for on-device use (works offline; no per-request cost). ([developer.apple.com](https://developer.apple.com/wwdc25/guides/ios/?utm_source=openai))
- If you’re submitting an app that uses it, build with Xcode 16+ against the iOS 18 SDK. ([developer.apple.com](https://developer.apple.com/news/upcoming-requirements/?id=02212025a&utm_source=openai))

If you need, I can help you add the availability check and a minimal generation call in your app target.
