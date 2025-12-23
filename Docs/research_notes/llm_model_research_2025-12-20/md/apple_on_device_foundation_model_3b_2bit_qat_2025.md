# Search Results: on-device 3B foundation language model 2-bit QAT KV cache sharing 2025

**Date:** 2025-12-20 17:16:49

## Answer

If you’re asking about Apple’s 2025 on‑device foundation language model: yes—the ~3B on‑device model uses 2‑bit quantization‑aware training (QAT) and a KV‑cache sharing architecture.

Key points (2025):
- Model and timeline: Apple introduced an updated family of foundation models at WWDC on June 9, 2025, and published a detailed tech report on July 17, 2025. The on‑device model is approximately 3B parameters; a larger server model uses a novel PT‑MoE design. ([machinelearning.apple.com](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates))
- KV‑cache sharing: The on‑device model is split into two blocks (5:3 depth). KV caches from the end of block 1 are reused by block 2, cutting KV‑cache memory by 37.5% and improving time‑to‑first‑token. ([machinelearning.apple.com](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates))
- Quantization: Decoder weights are compressed to 2 bits per weight via QAT using learnable clipping/initialization; embeddings are 4‑bit (QAT), and the KV cache is 8‑bit. Apple uses low‑rank adapters to recover quality after compression. ([machinelearning.apple.com](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates))
- Quality impact: With the above compression, Apple reports small regressions on some benchmarks and slight improvements on others (e.g., minor MMLU gains for the on‑device model), indicating 2‑bit QAT is viable for production. ([machinelearning.apple.com](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates))
- Evolution from 2024: The earlier 2024 write‑up described mixed 2/4‑bit “palletization” averaging ~3.7 bpw; the 2025 update moves the on‑device decoder weights to full 2‑bit via QAT with additional optimizations. ([machinelearning.apple.com](https://machinelearning.apple.com/research/introducing-apple-foundation-models))
- Developer access: The Foundation Models framework now exposes the on‑device model to apps (guided generation, tool calling, streaming). Apple’s developer pages summarize what’s new and link to code‑along resources. ([developer.apple.com](https://developer.apple.com/apple-intelligence/whats-new/?utm_source=openai))

If you want, I can:
- Explain how KV‑cache sharing integrates into a typical Transformer stack and what to watch for during long‑context inference.
- Suggest adapter‑training and evaluation steps for an app‑specific skill using the Foundation Models framework. ([developer.apple.com](https://developer.apple.com/jp/apple-intelligence/foundation-models-adapter/?utm_source=openai))
