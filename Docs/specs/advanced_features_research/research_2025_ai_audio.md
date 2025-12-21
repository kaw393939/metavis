# 2025 Companion Research: AI & Audio

**Date:** 2025-12-20
**Scope:** Apple Intelligence, CoreML, PHASE, Synchronization
**Status:** COMPLETE

## 1. Executive Summary
The "Apple Intelligence" era (2025) shifts AI from the cloud to on-device. Audio follows suit with "Apple Spatial Audio Format" (ASAF) and PHASE.

## 2. AI Source Separation
**Legacy:** Custom implementation (Demucs-like).
**2025 State of the Art:**
*   **Apple Intelligence Foundation Models:** Apple now exposes Foundation Models developers. While explicit "Source Separation" API isn't documented, the Neural Engine is 3x faster.
*   **CoreML + Neural Engine:** Running a quantized Demucs/Hybrid-Transformer model on the ANE (Apple Neural Engine) is the only viable path for real-time.
*   **Recommendation:** Continue optimizing the custom model for **ANE execution** (float16/int8 quantization).

## 3. Spatial Audio Ecosystem
**Legacy:** AVAudioEngine 3D Mixing.
**2025 State of the Art:**
*   **ASAF (Apple Spatial Audio Format):** New system-level format for immersive audio (visionOS focused, but cross-platform).
*   **PHASE (Physical Audio Spatialization Engine):** High-level game audio engine. Handles occlusion, geometry, and reverb automatically.
*   **AVAudioEngine:** Still the low-level workhorse.
*   **Recommendation:** Only use **PHASE** if building a 3D "Game-like" scene. For a timeline video editor, **AVAudioEngine** with `AVAudioEnvironmentNode` (spatial mixer) is sufficient and more flexible.

## 4. Multi-Camera Synchronization
**Legacy:** Audio Fingerprinting (Custom).
**2025 State of the Art:**
*   **AVCaptureMultiCamSession:** Built-in hardware sync on iOS.
*   **Final Cut Camera:** Apple's solution.
*   **Recommendation:** For our "Studio Mode" with iPhones, leverage `AVCaptureMultiCamSession` for hardware clock sync if possible. If mixing disparate files, stay with **Audio Fingerprinting** (Chromaprint/Spectrogram correlation).

## 5. Implementation Recommendations
1.  **Strict ANE Quantization:** Ensure AI models are compiled for Neural Engine (compute units = `.all` is not enough; model architecture must match ANE constraints).
2.  **Adopt PHASE for "Simulation Mode":** When the user switches to the 3D "Simulation Workbench", switch the audio engine to PHASE to get free occlusion/geometry support.
