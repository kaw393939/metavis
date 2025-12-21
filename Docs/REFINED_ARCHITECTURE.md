# Refined Architecture: The "ACES Bus" & Modular Features

**Status:** DRAFT (For Discussion)
**Date:** 2025-12-11
**Objective:** Modularize MetaVisKit2 into simple, composable units.

## 1. The Core Principle: "The ACES Bus"
We move from a "Renderer" mindset to a "Bus" mindset.
*   **The Bus**: A 100% `rgba16Float` ACEScg linear pipeline.
*   **The Rule**: Nothing touches the bus unless it is ACEScg.
*   **The Guard**: Input Devices (Cameras, File Readers) are responsible for **Normalization** before data hits the bus.

```mermaid
graph LR
    FITS[FITS Device] --"Normalizes to ACES"--> BUS
    Cam[Camera Device] --"Normalizes to ACES"--> BUS
    Video[ProRes Device] --"Normalizes to ACES"--> BUS
    
    BUS ==="ACES 16f Stream"===> FX[Feature Pipeline]
    FX ==="ACES 16f Stream"===> DISP[Display/Export]
```

## 1.5 A Parallel Bus: Evidence & Device Streams
In addition to the ACES image bus, the system carries time-indexed "evidence" that enables precision editing and compositing.

*   **Device Streams**: mask, tracks, flow, and depth (GPU-friendly buffers).
*   **Evidence Pack**: deterministic ingest outputs (sensors, transcript words, diarization, warnings).
*   **Scene State**: derived summaries (identities, intervals, edit-safety ratings) consumed by planning + compilation.

See `Docs/specs/SCENE_STATE_DATA_DICTIONARY.md`.

## 2. Ingestion: "Everything is a Device"
We stop thinking about "File Loaders" and start thinking about **Virtual Devices**.

### Case Study: FITS (Astronomy)
Instead of a `FITSReader`, we implement a `FITSInputDevice`.
*   **Capability**: Reads `.fits` / `.fit` files.
*   **Intelligence**: Checks Header (BUNIT, TELESCOP).
*   **Normalization**:
    *   If raw generic data: Auto-stretches using Median/99th% stats (reused from Legacy).
    *   If JWST: Maps filters (`f770w`) to Spectral Colors.
*   **Output**: A clean ACEScg image buffer.

### Case Study: Camera (Live)
*   **Capability**: Connects to AVFoundation.
*   **Normalization**: Applies IDT (Input Device Transform) from `Rec.709` -> `ACEScg`.

### Case Study: iOS Sensor Capture (Proxy + LiDAR)
*   **Proxy video**: 1080p preview used for fast ingest and early editing.
*   **Depth sidecar**: LiDAR depth stream aligned to the proxy time domain.
*   **Relink**: full-res media replaces the proxy later; the sidecar timeline remains stable via a time mapping.

This makes depth-driven "superpower" shaders (occlusion, depth-aware DOF, volumetrics) possible without requiring frame-by-frame segmentation everywhere.

## 3. Features: "The Capability Registry"
To avoid a monolithic "Renderer" with 100 hardcoded effects, we build a **Feature Registry**.

*   **Structure**:
    *   **Manifest**: Each feature (Bloom, Grain, Text) has a JSON/Swift manifest describing its inputs, outputs, and UI parameters.
    *   **Unit**: A `composable function`.
        ```swift
        struct FeatureManifest {
            let id: "com.metavis.fx.bloom"
            let name: "Cinematic Bloom"
            let inputs: [.image]
            let parameters: [
                .float("threshold", default: 1.0),
                .float("intensity", default: 0.5)
            ]
        }
        ```
*   **Loading**: The core engine scans for registered Features at startup. This makes adding new shaders easy (just drop in a Metal file + Manifest).

## 4. Project Types: "Recipes"
A "Project Type" is just a **Pre-configured Topology** of Devices and Features.

*   **Type: "Cinema"**
    *   **Topology**: `[VideoDevice] -> [ColorGrade] -> [FilmGrain] -> [Output]`
    *   **UI**: Timeline focused.
*   **Type: "Astronomy"**
    *   **Topology**: `[FITSDevice] -> [ToneMap] -> [SpectralComposite] -> [Output]`
    *   **UI**: Graph/Scientific focused.
*   **Type: "Director"** (Script)
    *   **Topology**: `[ScriptDevice] -> [AI_Generator] -> [Output]`
    *   **UI**: Text Editor focused.

## 5. Summary of Changes
1.  **Legacy Core Upgrade**: The `FITSReader` logic moves into `MetaVisIngest/Devices/FITSDevice`.
2.  **Legacy IO Upgrade**: `VideoToolboxEncoder` becomes the backend for `MetaVisExport`.
3.  **Legacy Timeline Adaptation**: The `TimelineGraphBuilder` logic becomes the "Compiler" for the "Cinema" Project Type default topology.
