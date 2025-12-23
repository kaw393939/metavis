# Search Results: coremltools 2025 stateful models LLM KV cache mlprogram

**Date:** 2025-12-20 16:59:33

## Answer

Here’s the 2025 snapshot for Core ML Tools + Core ML when you want stateful LLMs (KV cache) with MLProgram:

What’s supported
- Stateful models (“State” type) are now first‑class in Core ML (introduced for iOS 18 / macOS 15). coremltools 8.x can convert models that use state so the KV cache can be updated in place instead of being passed in/out as tensors each step. This specifically targets transformer KV caches. ([developer.apple.com](https://developer.apple.com/videos/play/wwdc2024/10161/))
- MLProgram remains the recommended representation for modern models. coremltools 8.x also added multi‑function MLPrograms so you can package multiple entry points (for example, base model + adapters) that share weights. ([developer.apple.com](https://developer.apple.com/videos/play/wwdc2024/10161/))
- On‑device API: you create a model‑managed state object once and pass it to each prediction; Core ML preallocates and updates the KV buffers in place. Apple’s WWDC24 demo (Mistral‑7B on M3 Max) showed ~1.6× speedup when using state vs manual I/O of the cache. ([developer.apple.com](https://developer.apple.com/videos/play/wwdc2024/10161/))

Converter status (PyTorch)
- torch.export path is supported for LLMs and is the route that enables stateful conversion, dynamic shapes, and 4‑bit weight compression in MLProgram. Set minimum_deployment_target to at least iOS 18/macOS 15 to emit State. ([github.com](https://github.com/apple/coremltools/releases?utm_source=openai))
- Multi‑function export helpers: coremltools.utils.MultiFunctionDescriptor and utils.save_multifunction for building a single mlpackage with multiple functions sharing weights. ([github.com](https://github.com/apple/coremltools/releases?utm_source=openai))
- Releases: current stable is in the 8.x line; the repo also advertises a 9.0 beta. ([github.com](https://github.com/apple/coremltools?utm_source=openai))

Using stateful KV cache (high‑level)
- Convert with MLProgram + iOS 18/macOS 15 target so the KV tensors map to Core ML State. Example flow (Python): exported_program → ct.convert(…, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18). Then test with mlmodel.make_state() and predict(..., state=state) so KV updates in place. On device, create the model’s state once and reuse it across prefill/decoding steps. ([github.com](https://github.com/apple/coremltools/releases?utm_source=openai))

Caveats and gotchas seen in 2024–2025
- Shape flexibility + state: mixing enumerated (fixed set) and range shapes in a single stateful model can fail at runtime. Keep input shape flexibility consistent. ([github.com](https://github.com/apple/coremltools/issues/2548?utm_source=openai))
- MLProgram + FLOAT16: some models show accuracy issues with compute_precision=FLOAT16; FLOAT32 (or different compression) may be required. ([github.com](https://github.com/apple/coremltools/issues/2603?utm_source=openai))
- Some developers reported state/KV behavior differences during batched “prefill” vs single‑token decode; if you see non‑updating KV in prefill, inspect state usage and execution options. ([developer.apple.com](https://developer.apple.com/forums/tags/core-ml?utm_source=openai))
- If you can’t target iOS 18/macOS 15, you can still implement “manual state” (pass cache as inputs/outputs each step), but you won’t get the new in‑place state speedups. ([developer.apple.com](https://developer.apple.com/jp/documentation/coreml/core_ml_api/making_predictions_with_a_sequence_of_inputs/?utm_source=openai))

Where to watch/read first
- WWDC24 “Deploy machine learning and AI models on‑device with Core ML” (chapters: Models with state; Multifunction models) for the KV‑cache workflow and performance demo. ([developer.apple.com](https://developer.apple.com/videos/play/wwdc2024/10161/))
- coremltools 8.x release notes for State type support, torch.export guidance, and multi‑function utilities. ([github.com](https://github.com/apple/coremltools/releases?utm_source=openai))
- Core ML overview page (What’s new) for the 2024–2025 additions: stateful models, MLTensor, multi‑function. ([developer.apple.com](https://developer.apple.com/machine-learning/core-ml/?utm_source=openai))

Want a minimal working example for a specific model (e.g., Llama/Mistral) and target device? Tell me your base model, desired precision, and OS target, and I’ll sketch the exact ct.convert call and on‑device loop.
