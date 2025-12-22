# Research Notes: On-Device Diarization & Sensor Fusion
**Date:** 2025-12-20
**Source:** `eai` deep search (Apple Silicon 2024/2025 state of the art)

## 1. Diarization Strategy for Apple Silicon

The industry standard for server-side is `pyannote.audio`, but it is too heavy for real-time on-device usage without modification.

### Recommended Architecture: "Extract & Cluster"
1.  **Segmentation (VAD):** Cheap energy/model-based Voice Activity Detection to slice audio.
    *   *Current State:* We have `AudioVADHeuristics`.
2.  **Embedding Extraction (The ANE Workload):**
    *   Deep neural network that maps a ~3s audio window to a 192d/512d vector (d-vector/x-vector).
    *   **Model Choice:** `ECAPA-TDNN` or `ResNet34-SE`.
    *   **Optimization:** Must be converted to **CoreML** with **Static Input Shapes** (e.g., exactly 3.0s buffer). If segment is short, pad it.
    *   **Quantization:** Int8 or Float16 for ANE resident execution.
3.  **Clustering (The CPU Workload):**
    *   Group vectors by similarity.
    *   **Algo:** Online clustering or Spectral Clustering (if offline).
    *   **Lib:** `Accelerate.framework` (`BNNS` / `vDSP`) is 100x faster than Swift arrays.

## 2. Sensor Fusion ("Sticky" Fusion)

To improve pure audio diarization, we fused it with Vision data.

### Approach: Late Fusion
Do not feed raw audio pixels into one giant model. Process streams independently and fuse the *embeddings* or *labels*.

*   **Stream A (Audio):** Time range -> Speaker Embedding Vector.
*   **Stream B (Vision):** Time range -> Face Track ID (from `FaceDetectionService`).
*   **Fusion Logic:**
    *   Construct a bipartite graph or simple probability matrix.
    *   *Heuristic:* If `Face A` is consistently present when `Speaker Cluster 1` is active, and `Face A` is absent when `Speaker Cluster 1` is active (wait, that implies off-screen speech) — simpler:
    *   **Co-occurrence:** Calculate P(Face | Voice). If high (>0.8), sticky-link them.
    *   *Caveat:* "Active Speaker Detection" (Mouth moving) is the real gold standard. Without it (Perception Sprint Gap), we rely on statistical co-occurrence.

## 3. ANE Implementation Directives
*   **Fixed Batch Size:** Do not send one segment at a time. Send batch=1 or batch=fixed_N.
*   **Warmup:** Run a dummy inference on app launch.
*   **No Dynamic Control Flow:** The model graph must be static.

## 4. Proposed Stack for Sprint 24
1.  **VAD:** Existing `MetaVisPerception`.
2.  **Embedding:** Port `ECAPA-TDNN` to CoreML (Int8). Run on ANE.
3.  **Clustering:** Greedy algorithm using Cosine Similarity (Accelerate).
4.  **Labeling:** Fuse with `MasterSensors` face tracks.
