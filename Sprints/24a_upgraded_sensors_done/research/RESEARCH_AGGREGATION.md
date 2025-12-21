# Research Aggregation: MetaVis Sensor Package (2025)
**Date:** 2025-12-20
**Method:** `eai` Deep Search (Apple Silicon State of the Art 2025)

## 1. Vision Framework (Tier 0)
*   **iOS 18 Update:** Apple has introduced Swift-native overlays for the Vision framework. The core request `VNGenerateForegroundInstanceMaskRequest` remains the standard for "Subject Lift".
*   **Performance:** These run highly optimized on the ANE/GPU partition managed by the OS.
*   **Tracking:** `VNTrackObjectRequest` is essential to stabilize masks. Compute mask on keyframes -> Track -> Warp.

## 2. MobileSAM (Tier 1)
*   **Architecture:** The `TinyViT` encoder variant is strictly required for mobile performance. Standard ViT-H is too heavy.
*   **CoreML Export:**
    *   **Tool:** `coremltools 8+`
    *   **Optimization:** `palettize_weights` (LUT quantization) is critical for Transformers to reduce bandwidth.
    *   **Shape:** 1024x1024 Static Input.
*   **ANE Compatibility:** Requires careful split of Encoder (heavy, runs once) vs Decoder (light, runs interactively). Ideally Encoder runs on NPU, Decoder on CPU/GPU.

## 3. SAM 2 (Tier 2)
*   **Status:** There is **NO OFFICIAL** CoreML Video pipeline for SAM 2 as of Dec 2025.
*   **Implication:** A "Video Grade" offline pass must likely run on the **GPU** (via PyTorch/LibTorch or a custom Metal port) rather than a simple CoreML model. This is a high-risk item.
*   **Recommendation:** Prioritize Tier 1 (MobileSAM) for interactive use. Use Tier 2 only if a Metal port is available.

## 4. Face Parsing (Micro-Segmentation)
*   **Missing Native:** Apple `Vision` provides landmarks (points) but *not* semantic masks (teeth/lips pixels).
*   **Recommended Model:** `BiSeNetV2` (Bilateral Segmentation Network).
    *   *Why:* Real-time, lightweight, ANE-friendly.
*   **Dataset:**
    *   `CelebAMask-HQ` (19 classes including skin, nose, eyes, eyebrows, ears, mouth, lips, hair).
    *   `LaPa` (Landmark guided Face Parsing).
*   **Training:** Must train a custom `BiSeNetV2` on one of these datasets to get the "Teeth" class.

## 5. ANE Optimization (General)
*   **Static Shapes:** Inputs must not be dynamic (e.g. `1x3x1024x1024` strictly).
*   **Quantization:** `Int8` or `Float16`.
*   **Warmup:** Always run a dummy inference on launch to load weights into the Neural Engine SRAM.
