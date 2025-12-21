# Search Results: Core ML Tools weight compression 4-bit LLM 2025

**Date:** 2025-12-20 17:01:37

## Answer

Here’s the current (Dec 20, 2025) picture and practical recipes for doing 4‑bit weight compression for LLMs with Core ML Tools.

What Core ML Tools supports now
- coremltools 9.0 (released Nov 2025) adds official 4‑bit weight quantization support, blockwise quantization, grouped channel‑wise palettization, joint compression (e.g., palettization with 8‑bit LUTs, pruning+quantization), and experimental activation quantization. It also improves conversion of 4‑bit‑quantized Torch models, including ops like embedding_4bit and torchao’s _weight_int4pack_mm. These features target the iOS 18 / macOS 15 runtime with new compression ops. ([github.com](https://github.com/apple/coremltools/releases))

Two workable paths to W4 LLMs

A) Post‑training on the Core ML model (data‑free)
- Start from a float16 Core ML model (mlprogram).
- Palettize weights to 4 bits: use ct.optimize.coreml.palettize_weights with an OpPalettizerConfig set for 4 bits; optionally enable grouped channel‑wise or blockwise modes, vector palettization (cluster_dim > 1), and per‑channel scale. ([github.com](https://github.com/apple/coremltools/releases))
- Optional: “Joint compression” so the palette/LUT itself is int8 (smaller memory traffic): follow with ct.optimize.coreml.linear_quantize_weights(joint_compression=True). ([github.com](https://github.com/apple/coremltools/releases))
- Optional: Quantize activations to 8‑bit (A8) using the activation‑quantization API to yield A8W4 for better ANE residency. ([github.com](https://github.com/apple/coremltools/releases))
- Tip for LLMs: 4‑bit palettization can work well, but many models benefit from fine‑tuning or more advanced mixed‑bit palettization if you push bits that low; Apple’s Stable Diffusion reference recommends ≈4‑bit palettization as a good sweet spot when aiming below 6‑bit. ([github.com](https://github.com/apple/ml-stable-diffusion?utm_source=openai))

B) Quantize in PyTorch, then convert
- Quantize the PyTorch LLM to 4‑bit (e.g., GPTQ/AWQ/torchao). coremltools 9.0 supports converting several 4‑bit quantized/decomposed patterns and torchao’s packed int4 matmul. ([github.com](https://github.com/apple/coremltools/releases))
- Export with torch.export and convert with ct.convert; the release notes include an example of exporting a model with 4‑bit weight ranges and converting it (set minimum_deployment_target appropriately; for 4‑bit compression ops, iOS 18+ is the safe target). ([github.com](https://github.com/apple/coremltools/releases))
- If you’re using ct.optimize.torch’s PostTrainingQuantizer for 4‑bit, note that you still pass torch.int8/torch.uint8 for weight_dtype (PyTorch lacks a 4‑bit dtype); the range is set to 4‑bit under the hood. ([github.com](https://github.com/apple/coremltools/issues/2266?utm_source=openai))

ANE‑friendly A8W4 sequence (commonly used)
- Make a float16 Core ML model.
- Quantize activations to 8‑bit.
- Palettize weights to 4‑bit (fp16 LUT).
- Joint‑compress LUT to int8 (so weights are W4 with an int8 LUT). This A8W4 approach is frequently recommended for ANE utilization. ([github.com](https://github.com/apple/coremltools/issues/2410?utm_source=openai))

Minimum OS / targets to keep in mind
- The compression/decompression kernels needed for low‑bit weight formats and related ops are part of the iOS 18 / macOS 15 runtime set; target those (or newer) to run 4‑bit compressed weights efficiently on device. ([github.com](https://github.com/apple/coremltools/releases))

Quick checklist for a 4‑bit LLM mlpackage
- Use coremltools 9.0. ([github.com](https://github.com/apple/coremltools/releases))
- Target iOS 18+ / macOS 15+ in ct.convert.
- Prefer A8W4 for ANE; verify accuracy/perplexity layer‑wise.
- For PyTorch first: apply GPTQ/AWQ or ct.optimize.torch, export, then ct.convert. ([github.com](https://github.com/apple/coremltools/releases))
- For Core ML post‑training: palettize_weights nbits=4; consider blockwise/grouped channel‑wise/vector palettization; optionally joint‑compress LUT and quantize activations. ([github.com](https://github.com/apple/coremltools/releases))

If you share:
- Which LLM (e.g., Llama‑family size), 
- Target device/OS (iPhone vs Mac; iOS/macOS version),
- Latency/memory targets and accuracy tolerance,

…I can sketch an exact command‑by‑command pipeline (Torch quantization config or Core ML post‑training configs), and a small script to batch‑validate perplexity vs fp16.
