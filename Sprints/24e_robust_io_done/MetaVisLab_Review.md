# MetaVisLab Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisLab`

## 1. Executive Summary

`MetaVisLab` is the experimental proving ground and CLI entry point for the MetaVis system. It provides a suite of commands to test individual subsystems (Sensors, Gemini integration, FITS rendering, Nebula volumetric effects) in isolation.

**Strengths:**
- **Modular Testing:** Each `Command` struct (e.g., `NebulaDebugCommand`, `GeminiAnalyzeCommand`) isolates a specific subsystem, verifying it end-to-end without needing the full app UI.
- **Deep Diagnostics:** `NebulaDebugCommand` renders specific debug passes (density histograms, edge width visualizations) to PNGs, enabling graphical debugging of shaders.
- **Safety:** Explicit large-asset checks (`enforceLargeAssetPolicy`) prevent accidental ingest of massive files unless overridden.

**Critical Gaps:**
- **Hardcoded Paths:** Commands frequently default to local paths like `./test_outputs` or specific input files (`keith_talk.mov`), which hinders portability to other environments (CI/CD).
- **Process Invocation:** `GeminiAnalyzeCommand` invokes `ffmpeg` via `Process()`. This assumes `ffmpeg` is in the PATH, which is a fragile dependency.
- **Mock Logic:** As noted in `MetaVisIngest` review, `LIGMDevice` usage here relies on mock logic.

---

## 2. Detailed Findings

### 2.1 CLI Architecture (`MetaVisLabMain.swift`)
- **Structure:** Simple switch-statement dispatcher in `MetaVisLabProgram.run`.
- **User Experience:** Provides a decent help text (`MetaVisLabHelp`) but error handling varies per command.

### 2.2 LLM Integration (`GeminiAnalyzeCommand.swift`)
- **Workflow:** Generates a low-res proxy via `ffmpeg`, probes duration, selects keyframes, and sends to Gemini for "Quality Control" analysis.
- **Prompt Engineering:** Contains a sophisticated system prompt (`expectedNarrative`) that instructs the model to act as a "strict, conservative QC assistant" and return structured JSON.
- **Risk:** The reliance on `ffmpeg` CLI execution is a weak point. It should ideally use `MetaVisExport` to generate the proxy internally.

### 2.3 Sensor Integration (`SensorsCommand.swift`)
- **Scope:** Wraps `MasterSensorIngestor` from `MetaVisPerception`.
- **Output:** writes `sensors.json` and optional `bites.v1.json`. This is the primary way to verify the "Machine Perception" layer.

### 2.4 Graphics Debugging (`NebulaDebugCommand.swift`)
- **Visualization:** Manually constructs RGBA float buffers and writes them to PNG using `CoreGraphics`. This confirms that the Metal backend in `MetaVisGraphics` is producing valid pixels off-screen.
- **Complexity:** This command manually assembles a `RenderGraph`. This is good for verification but verbose.

---

## 3. Recommendations

1.  **Replace ffmpeg shell-out:** Refactor `GeminiAnalyzeCommand` to use `MetaVisExport` (or a dedicated proxy transcoder in `MetaVisCore`) to create the 360p proxy. This removes the external runtime dependency.
2.  **Configurable Paths:** Move default paths (like `./test_outputs`) to a configuration object or environment variable to support CI execution.
3.  **Unified Command Protocol:** Define a `LabCommand` protocol to standardize argument parsing (`parse(args:)`) and execution (`run(options:)`), reducing boilerplate in `MetaVisLabMain`.
