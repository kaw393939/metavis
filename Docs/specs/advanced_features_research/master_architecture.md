# The Constitution: Master Architecture for MetaVisKit2

**Vision:** A Deterministic Communication Tool for Human + AI Co-Creation.
**Goal:** Enable AI to create complex movies by "using the tool" rather than "generating the pixels."

---

## 1. Core Philosophy: The "Ghost User"
In this system, the AI is not a separate automated process. It is a first-class citizen—a **"Ghost User"**—that interacts with the application exactly like a human user.
*   **Unified Action Stack:** Both Human and Ghost User submit **CRDT Operations** (e.g., `AddClip`, `Trimmer`, `ColorGrade`).
*   **Shared Truth:** The "Movie" is not the video file; it is the **Symbolic State** (the CRDT Tree).
*   **Progression:**
    *   **Copilot Mode:** Human acts, Ghost User assists (e.g., "Make this sadder").
    *   **Solo Mode:** Ghost User acts alone, building a movie from scratch using the same tools.

## 2. The "Brain": Neuro-Symbolic Engine
We bridge the gap between "Fuzzy AI" and "Rigid Code" with a Neuro-Symbolic Loop.
1.  **Intent (Neuro):** The LLM receives a prompt ("Make a sci-fi intro").
2.  **Symbolic Generation (DSL):** The LLM generates a script in **`MetaVisScript`**, a rigorous Domain Specific Language (DSL).
3.  **Grammar Enforcement:** We use GBNF logic to force the LLM to output *only* valid DSL syntax.
4.  **Semantic Lifting:** Small neural networks map vague concepts (e.g., "Gloomy") to precise parameters (e.g., `Grade.saturation = -0.4`, `Cloud.density = 0.8`).
5.  **Execution (Deterministic):** The DSL is compiled into the Render Graph.

## 3. The "Eyes": Dual-Mode Deterministic Renderer
To guarantee that the "Solo Mode" AI creates consistent results forever, we solve the GPU non-determinism problem.
*   **UI Mode (Fast):** Uses standard Metal (Float32 "Fast Math") for 120fps interactive editing.
*   **Simulation Mode (The Masterpiece):** Uses **Software-Emulated Fixed-Point Math (16.16)** in Compute Shaders.
    *   **Guarantee:** A simulation run on M1, M5, or Cloud will yield the **exact bit-for-bit same result**.
    *   **Why?** This allows the AI to "replay" scenarios, branch timelines, and learn from perfect feedback loops without "butterfly effect" chaos from floating-point drift.

## 4. The "Hands": Collaborative CRDT Timeline
The Timeline is modeled as a **Hierarchical Tree CRDT**.
*   **Structure:** `Timeline -> Tracks -> Clips -> Effects`.
*   **Conflict Resolution:**
    *   If Human moves Clip A to `00:10` and AI moves Clip A to `00:20`, the CRDT deterministically resolves (e.g., Last Write Wins based on logical clock).
*   **Real-Time Sync:** WebRTC Data Channels synchronize state instantly, allowing the Human to watch the AI work in real-time.

## 5. Technology Stack (2025 Standard)
*   **Language:** Swift 6 (Strict Concurrency).
*   **Graphics:** Metal 3 (Mesh Shaders, Bindless Heaps).
*   **Simulation:** Metal Compute (Fixed Point), Curl Noise (Backgrounds).
*   **Text:** Multi-Channel SDF (MSDF).
*   **AI:** CoreML (Neural Engine) + Local LLM (Grammar Constrained).
*   **Video:** VideoToolbox (Zero-Copy 10-bit HDR).

## 6. Legacy Implementation Plan (The Port)
We carry forward the "Crown Jewels" from the legacy codebase:
1.  **PBR/SDF:** Port the `Disney_BRDF` and `SDFText` shaders, upgrading Text to MSDF.
2.  **Graph Layout:** Port the Barnes-Hut GPU layout for visualizing the AI's "thought process" (Task Graphs).
3.  **Color Space:** Strict ACEScg pipeline for all rendering.

---

This document represents the final architectural decision. We build a tool for the AI, not just a tool that uses AI.
