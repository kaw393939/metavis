# MetaVisPerception Assessment

## Initial Assessment
MetaVisPerception is the "Sense" layer of the AI, responsible for converting raw audio/video pixels into semantic understanding. It relies heavily on deterministic heuristics and custom DSP rather than opaque neural networks, aligning with the "auditable" philosophy of the system.

## Capabilities

### 1. Master Sensor Ingestor
- **`MasterSensorIngestor.swift`**: The main entry point. Orchestrates Video and Audio analysis passes.
- **Determinism**:
    - **Stable IDs**: Hashes file content (not paths) to generate stable UUIDs for assets.
    - **Face Tracking**: Sorts Vision results by geometry (x, y, area) to assign stable person IDs (`P0`, `P1`) across runs, avoiding Vision's non-deterministic UUIDs.
- **Video Analysis**: Samples frames at a stride (1s), running Face Detection and Person Segmentation.

### 2. Custom DSP Audio Analysis
- **`AudioVADHeuristics.swift`**: Implements a Voice Activity Detector (VAD) using `vDSP` (Accelerate).
- **Features**: RMS, Spectral Centroid/Flatness/Dominant Hz, Zero Crossing Rate.
- **Classification**: Rules-based classifier (`speechLike`, `musicLike`, `silence`) instead of a black-box ML model.
- **Beat Detection**: Identifies emphasis points for editing alignment.

### 3. Semantic Descriptors
- **`DescriptorBuilder.swift`**: Synthesizes sensor data into high-level editorial tags.
- ** Tags**: `safeForBeauty`, `singleSubject`, `continuousSpeech`, `punchInSuggestion`.
- **Logic**: complex "if-this-then-that" rules (e.g., "If single face stable for 2s AND speech continuous AND no red warnings -> Safe For Beauty").

## Technical Gaps & Debt

### 1. Heuristic Fragility
- **Issue**: The module is packed with "magic numbers" (thresholds for RMS, spectral centroids, confidence scores).
- **Risk**: Likely to fail on diverse content (e.g., background noise, different microphones) that doesn't match the test corpus.
- **Debt**: No machine learning usage for classification (SoundAnalysis), likely to maintain "auditability" but sacrificing accuracy.

### 2. Code Duplication
- **Issue**: Implements its own `AVAssetReader` loop for audio analysis, very similar to `MetaVisAudio`'s decoder but distinct.
- **Fix**: Shared "AudioReader" utility in `MetaVisCore` or `MetaVisIngest`.

### 3. Performance
- **Issue**: Sequential processing (Video pass then Audio pass).
- **Optimization**: Parallelize video and audio analysis if memory allows.

## Improvements

1.  **ML Integration**: Evaluate `SoundAnalysis` (SNClassifySoundRequest) for more robust VAD/Music detection, perhaps as a parallel signal to the heuristics.
2.  **Configurable Heuristics**: Move magic numbers into a JSON configuration file to allow tuning without recompilation.
3.  **Visualization**: The "Descriptors" are complex; a timeline visualizer for debugging these segments would be valuable.
