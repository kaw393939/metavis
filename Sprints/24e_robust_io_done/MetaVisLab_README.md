# MetaVisLab

**MetaVisLab** is the "skunkworks" CLI for the MetaVis system. It houses experimental features, integration tests, and debugging tools that verify the core engine capabilities without the overhead of a full GUI application.

## Purpose

- **Verification:** Confirm that subsystems (Graphics, Audio, AI) work correctly in isolation.
- **Experiments:** Prototype new features (like Nebula raymarching or FITS compositing) before stabilizing them in `MetaVisCore` or `MetaVisGraphics`.
- **Debugging:** Generate visual diagnostics (histograms, edge overlays) to tune rendering logic.

## Key Experiments

### 🌌 Volumetric Nebula
A standalone renderer for the `fx_volumetric_nebula` shader. It produces beauty renders and technical debug passes (density, blue-ratio) to verify the shader's behavior.

### 🔭 JWST FITS Imaging
A pipeline for ingesting, normalizing, and compositing raw FITS scientific data from the James Webb Space Telescope.

### 🤖 Gemini QC
A prototype workflow that uses Google Gemini to "watch" a video clip and provide specific Quality Control feedback (framing, audio clarity, glitch detection).

## Running
See `MetaVisLab_API_Doc.md` for command-line usage.
