# MetaVisIngest Assessment

## Initial Assessment
MetaVisIngest handles the importation and analysis of media assets. It focuses on specialized formats (FITS) and technical analysis (Video Timing/VFR detection) rather than generic decoding (which is handled by AVFoundation/MetaVisAudio).

## Capabilities

### 1. Scientific Image Support (FITS)
- **`FITSReader.swift`**: Native Swift reader for the Flexible Image Transport System.
- **Support**:
    - Parsing Header Units (HDUs).
    - Handling Big-Endian to Little-Endian conversion.
    - Supports BITPIX -32 (Float) and 16 (Int16).
    - Computes statistical analysis (Mean, Median, P90, P99) during ingest.
- **Use Case**: Likely for importing astronomical data (JWST images) into the renderer.

### 2. Video Timing Analysis
- **`VideoTimingProbe.swift`**: A lightweight, efficient VFR (Variable Frame Rate) detector.
- **Method**: Reads packet-level timestamps (PTS) using `AVAssetReaderTrackOutput` without fully decoding frames (fast).
- **Profile**: determines `isVFRLikely` based on frame delta variance (Standard Deviation and Range).
- **Why**: Essential for conforming VFR footage to a constant editing timebase.

### 3. Local Mock Device (LIGM)
- **`LIGMDevice.swift`**: A mock implementation of a "Local Image Generation Module".
- **Function**: Returns `ligm://` URIs simulating a Stable Diffusion generation.
- **Role**: Allows testing the "Ingest" flow for generative assets without a 4GB model loaded.

## Technical Gaps & Debt

### 1. Limited FITS Support
- **Gap**: Only handles 2D images and specific bit depths. Complex FITS files (tables, 3D cubes) will fail or throw errors.
- **Structure**: The reader is synchronous and loads the entire data into memory (`Data(contentsOf: url)`).
- **Risk**: Large FITS files (>2GB) could crash the app.

### 2. Hardcoded Heuristics
- **Debt**: `VideoTimingProbe` uses hardcoded magic numbers for VFR detection logic (e.g., `vfrStdDevThreshold = 0.01`). These might need tuning across a wider corpus of footage.

## Improvements

1.  **Streaming FITS**: Rewrite `FITSReader` to use `FileHandle` or a streaming reader to support large files without full memory loading.
2.  **Generalized Probe**: Extract `VideoTimingProbe` into a more generic `MediaProbe` service that returns codec info, color profiles, etc., alongside timing.
