# MetaVisPerception

**MetaVisPerception** provides the "eyes and ears" for the MetaVis system. It uses Computer Vision and Digital Signal Processing (DSP) to analyze media files and extract semantic meaning.

## Features

### 👁️ Vision
- **Face Detection & Tracking:** Stable, deterministic face tracking.
- **Segmentation:** Foreground/Background separation (Masks).
- **Scene Analysis:** Indoor/Outdoor inference, lighting estimation.

### 👂 Audio
- **VAD (Voice Activity Detection):** Distinguishes Speech, Music, and Silence.
- **DSP Analysis:** Extracts RMS, Peak, Dominant Frequency, and Spectral Flatness.
- **Beat Detection:** Identifies emphasis points and rhythmic beats.

### 🧠 Intelligence
- **Bite Extraction:** logic to identify usable "A-Roll" clips.
- **Auto-Start:** Suggests the optimal trim point to remove pre-roll silence/throat-clearing.
- **Punch-In Suggestions:** Identifies moments where an editor *could* cut to a close-up based on audio beats and visual stability.

## Core Philosophy: Determinism
A non-negotiable requirement of this module is **Reference Determinism**. If you ingest the same video file twice, you **MUST** get the exact same JSON output down to the last decimal place. This allows the timeline engine to be purely functional and reproducible.

## Dependencies
- `Vision` (Apple)
- `Accelerate` (vDSP)
- `CoreVideo`
- `MetaVisCore`
