# Research Note: AI, ML & Image Generation Architecture

**Source Documents:**
- `LIGM_ARCHITECTURE.md` (Local Image Generation Module)
- `AI_ML_PIPELINE_DEEP_DIVE.md` (Vision Framework)
- `20_agent_integration/ARCHITECTURE.md` (Agent/MCP)
- `AI_AUDIT_REPORT.md` (Optimization Audit)

## 1. Executive Summary
The AI ecosystem is divided into three distinct pillars:
1.  **LIGM (Local Image Generation Module):** A deterministic, offline system for generating high-quality assets (procedural & ML) in ACEScg linear space. It serves as the "Ground Truth" generator for testing.
2.  **Vision & CoreML Pipeline:** Real-time analysis (Segmentation, Depth, Saliency) for video effects. Currently functional but unoptimized (needs persistent sessions).
3.  **Agent System (MCP):** A conversational interface that translates natural language into CLI commands via a Model Context Protocol (MCP) server.

## 2. LIGM: The "Ground Truth" Generator
-   **Philosophy:** Determinism > Speed. Every pixel must be reproducible bit-exact given a seed.
-   **Color Space:** Fundamental adherence to **ACEScg Linear**. All ML/Procedural outputs are converted to this space before storage (OpenEXR).
-   **Backends:**
    -   *Procedural:* Noise (Perlin, FBM), Gradients, SDFs. Runs on CPU+AMX.
    -   *CoreML:* ANE-accelerated inference (e.g., Stable Diffusion, but local/small).
-   **Hardware Acceleration:**
    -   **AMX:** Used for heavy matrix math (Color Space Conversion `ACEScg <-> LAB`).
    -   **ANE:** Used for Neural Network inference.

## 3. Real-Time Vision Pipeline (`VisionProvider`)
-   **Capabilities:**
    -   Person Segmentation (Masking)
    -   Depth Estimation (Depth Anything V2)
    -   Saliency (Attention heatmaps)
    -   Optical Flow
-   **Critique (from Audit):**
    -   *Current:* "Photo Mode" architecture. Creates new `VNImageRequestHandler` per frame. Allocates new buffers per frame.
    -   *Target:* "Video Mode". Persistent `VNSequenceRequestHandler` for temporal stability. `CVPixelBufferPool` for zero-allocation loops. `IOSurface` for zero-copy.
-   **Depth Strategy:**
    -   Uses "Depth Anything V2 Small" (FP16, ~47MB).
    -   Heavy reliance on ANE.
    -   *Fallback:* Sobel edge detection (poor quality) if ANE/CoreML fails.

## 4. Agent Architecture (MCP)
-   **Role:** The "Brain" ensuring the user can simply ask for things ("Make a 60s highlight reel").
-   **Structure:**
    -   **Context Provider:** Aggregates Project, Timeline, and Analysis state into JSON Context.
    -   **Intent Parser:** NL -> `EditIntent` (Action: `trim`, Target: `clip_001`).
    -   **Executor:** `EditIntent` -> CLI Command (`metavis clip trim ...`).
-   **Safety:**
    -   **Validation Layer:** Checks if the command is safe/valid before execution.
    -   **Undo Stack:** Multi-turn conversation state with full rollback capability.

## 5. Critical Technical Constraints
-   **Memory:** Vision models compete with Video Decoding for Unified Memory.
    -   *Strict Limit:* AI models should not exceed 10-15% of RAM during playback.
-   **Concurrency:**
    -   LIGM is *Offline* (can saturate CPU/ANE).
    -   Vision is *Real-time* (must interact nicely with Render Loop).
    -   *Solution:* Vision runs on `.userInteractive` QoS, but must yield to Audio priority.
-   **File Formats:**
    -   LIGM Golden References: **OpenEXR** (16-bit Float).
    -   Previews: **PNG** (sRGB Gamma).

## 6. Synthesis for MetaVisKit2
-   **Unification:** The new system should unify the "VisionProvider" (Analysis) and "LIGM" (Generation) under a shared `IntelligenceEngine` actor to manage ANE resource contention.
-   **Zero-Copy:** The `CVPixelBuffer` -> `MTLTexture` dance is currently expensive. The new architecture must enforce `IOSurface` backed textures everywhere.
-   **Determinism:** Port the LIGM "Seed" philosophy to the video pipeline effects where possible (e.g. noise grains).
