# Search Results: Whisper Core ML Apple Neural Engine ANE transcription

**Date:** 2025-12-20 18:39:20

## Answer

Are you looking to run Whisper on Apple’s Neural Engine (ANE) via Core ML for on‑device transcription? Here are the cleanest paths, depending on your stack:

Fastest path (C/C++ app or CLI)
- Use whisper.cpp with Core ML: it runs the Whisper encoder on ANE for big speedups; build with Core ML enabled and generate the Core ML encoder model, then run as usual. The repo’s README includes steps to pip‑install ane_transformers/coremltools, generate the mlmodelc encoder, and build with WHISPER_COREML enabled. ([github.com](https://github.com/ggml-org/whisper.cpp?utm_source=openai))
- You can force which hardware Core ML uses (ANE vs GPU) by editing the Core ML configuration in whisper.cpp’s encoder bridge as noted by the maintainer. ([github.com](https://github.com/ggml-org/whisper.cpp/discussions/1722?utm_source=openai))

Native Swift/macOS/iOS app
- A Core ML port of Whisper for Apple Silicon (with ANE optimizations) exists if you prefer a Swift‑first API for file and real‑time transcription. It builds on Apple’s ANE Transformer techniques. ([github.com](https://github.com/vade/OpenAI-Whisper-CoreML?utm_source=openai))
- To target ANE in your own Core ML code, set MLModelConfiguration.computeUnits = .cpuAndNeuralEngine when loading the model; see Apple’s docs for computeUnits and async loading. Use Xcode’s Core ML/Neural Engine Instruments to verify ANE usage. ([developer.apple.com](https://developer.apple.com/documentation/coreml/mlmodelconfiguration/computeunits?utm_source=openai))

Python + on‑device streaming
- Hybrid approach: Core ML encoder on ANE + MLX decoder (good for streaming/latency). See Lightning‑SimulWhisper for a ready implementation and instructions to generate the Core ML encoder from whisper.cpp. ([github.com](https://github.com/altalt-org/Lightning-SimulWhisper?utm_source=openai))

ANE‑friendly conversion tips
- Apple’s reference “ml‑ane‑transformers” shows how to restructure Transformer ops for ANE and convert with coremltools (ct.ComputeUnit.ALL/.CPU_AND_NEURAL_ENGINE). These patterns help Whisper‑style models map to ANE. ([github.com](https://github.com/apple/ml-ane-transformers?utm_source=openai))

React Native (optional)
- If you’re building a cross‑platform UI, whisper.rn (binding for whisper.cpp) supports Core ML models on iOS; you ship the encoder .mlmodelc alongside the ggml model. ([github.com](https://github.com/mybigday/whisper.rn?utm_source=openai))

Clarify your target so I can give exact steps:
- Platform: macOS app, iOS app, or CLI?
- Realtime vs batch?
- Model size (tiny/base/small/medium/large) and languages?
- Do you want pure on‑device (no GPU), or ANE+GPU is fine?

I can then provide the concrete commands (model conversion, build flags, and Swift/Python snippets) tailored to your setup.
