# Search Results: Foundation Models entitlements adapter distribution App Store

**Date:** 2025-12-20 17:15:44

## Answer

If you want to ship a custom Foundation Models adapter in an App Store app, here’s what Apple requires and how to distribute it:

- Entitlement you need: com.apple.developer.foundation-model-adapter. Only the Apple Developer Program Account Holder can request it. You don’t need this entitlement to train or test adapters locally; it’s required for distributing adapters in your app. ([developer.apple.com](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.foundation-model-adapter))
- Packaging: Export your trained adapter as a .fmadapter package using Apple’s adapter training toolkit. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/))
- Distribution to users: Don’t bundle adapters in your app binary. Host them on your server and deliver them as large asset packs using the Background Assets framework. Each adapter is about 160 MB. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/))
- Versioning: Each adapter is tied to a specific system model version. You’ll need to train and serve separate adapters per model version and fetch the compatible one at runtime. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/))
- Policy/compliance: Your app’s use of the Foundation Models framework (including adapters) must comply with Apple’s Acceptable Use Requirements. ([developer.apple.com](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/?utm_source=openai))
- App Store submission: After you’ve added the entitlement and integrated Background Assets–based delivery, submit as usual through App Store Connect. ([developer.apple.com](https://developer.apple.com/app-store/?utm_source=openai))

Want a quick checklist (requesting the entitlement, exporting .fmadapter, integrating Background Assets, and selecting the correct adapter at runtime), or code snippets for loading an adapter?
