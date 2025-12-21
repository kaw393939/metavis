# The Masterpiece: A Deterministic Neuro-Symbolic Engine for LLMs

**Date:** 2025-12-20
**Vision:** "A Deterministic Communication Tool for LLMs"
**Status:** BLEEDING EDGE

## 1. The Core Philosophy
To build a "Communication Tool for LLMs" that works like a reliable machine, we must abandon "probabilistic pixels."
**The LLM should not generate pixels.** The LLM should generate **Code (Symbols)**, and a **Deterministic Engine** should generate the pixels.

**Architecture:** `User <-> LLM <-> [Neuro-Symbolic Bridge] <-> [Deterministic Render Graph] <-> Pixel Display`

## 2. Determinism Layer (The Bedrock)
**Challenge:** Apple Silicon GPUs use "fast-math" by default, making pixel-perfect consistency impossible across drivers/OS versions.
**Masterpiece Solution:**
*   **Symbolic Ground Truth:** The "Truth" is not the pixel buffer. The "Truth" is the **CRDT State** (JSON/Struct tree).
*   **Determinism Modes:**
    *   **Fast Mode (UI):** Native Metal Float32 (Fast-Math). Non-deterministic but smooth (120fps).
    *   **Simulation Mode (The Masterpiece):** A Compute Shader pipeline using **Software-Emulated Fixed Point (16.16)** or strict IEEE-754 enforced Float32 intrinsics. It runs slower but guarantees bit-perfect reproduction on any M-series chip.
*   **Result:** An LLM can "replay" a simulation 10 years from now and get the *exact* same hash.

## 3. The Neuro-Symbolic Bridge
**Challenge:** LLMs hallucinate. Asking an LLM to "make the video sadder" yields random results.
**Masterpiece Solution:**
*   **The "Source Code Agent" Pattern:** The LLM does not call APIs directly. It writes a robust **Domain Specific Language (DSL)** script (e.g., `MetaVisScript`).
*   **Grammar-Constrained Decoding:** We force the LLM to output *only* valid DSL syntax using a grammar definition (e.g., GBNF).
*   **Symbolic Validation:** The DSL script is parsed by a classic Compiler. If invalid, the Compiler gives precise error messages back to the LLM (Neuro-Symbolic loop).
*   **Semantic Lifting:** We use small neural networks (Neuro) to "lift" vague constraints (e.g., "sadder") into specific symbolic parameters (e.g., `ColorGrade.saturation = -0.2`, `Music.key = C_Minor`).

## 4. The "Infinite Canvas" & CRDTs
**Challenge:** Real-time collaboration between Human and AI on a non-linear timeline.
**Masterpiece Solution:**
*   **Hierarchical Tree CRDT:** Standard Text CRDTs (RGA/Yjs) fail on complex trees. We will implement a custom **Tree-CRDT** (based on LSEQ or Fugue) to manage the Timeline hierarchy.
*   **AI as a "Ghost User":** The API treats the AI exactly like a human collaborator. The AI submits CRDT operations. This unifies the Undo/Redo stack for both Human and AI.
*   **State-of-the-Art Sync:** We use **WebRTC Data Channels** to sync these small CRDT operations instantly, allowing the AI to "watch" the user edit and react in real-time.

## 5. Implementation Roadmap (The "Long Hard" Path)
1.  **Phase 1: The DSL (Sprint 04+):** Define the grammar of `MetaVisScript`.
2.  **Phase 2: The Grammar Engine:** Implement grammar-constrained LLM generation (using local models or specialized API calls).
3.  **Phase 3: The Fixed-Point Renderer:** Write a Metal Compute library for 16.16 Fixed Point math to prove determinism.
4.  **Phase 4: The Neuro-Symbolic Loop:** Build the feedback loop where the Compiler corrects the LLM.

**Conclusion:**
This architecture treats the LLM as a *programmer*, not a painter. By constraining the LLM to symbolic logic and executing it on a deterministic engine, we build a tool that feels less like a "chatbot" and more like a "mind-extension."
