# MetaVisAudio Assessment

## Initial Assessment
MetaVisAudio is a powerful, deterministic audio engine built on top of `AVAudioEngine`. It emphasizes sample accuracy and procedural generation over standard playback, featuring a custom "LIGM" protocol and an AI agent for automated mastering.

## Capabilities

### 1. Deterministic Audio Graph
- **`AudioGraphBuilder`**: Manually constructs the node graph.
- **Topology**: Mixer per track -> Main Mixer.
- **Source Nodes**: Uses `AVAudioSourceNode` (pull-based) callback for *everything*, including files and procedural audio.
- **Why**: Allows frame-perfect control and mixing of generated vs recorded content without fighting `AVAudioPlayerNode` scheduling latency.

### 2. Procedural Audio Protocol ("LIGM")
- **Scheme**: `ligm://host/path?params`
- **Generators**: `sine`, `white/pink_noise`, `sweep`, `impulse`, `marker`.
- **Determinism**: Seeded by clip name and source path, ensuring the "random" noise is identical across renders.
- **Pink Noise**: Implements a custom 7-pole filter for deterministic pink noise generation.

### 3. AI Engineer Agent
- **`EngineerAgent`**: Automates the mastering process.
- **Workflow**: Renders a "diagnosis pass" (first 10s) -> Analyzes Loudness (LUFS) -> Configures Mastering Chain to meet target (e.g., -14 LUFS for Spotify).
- **Benefit**: Ensures reliable output levels without user intervention.

### 4. Custom File Decoding
- **Logic**: Manually decodes audio files into PCM buffers (`DecodedFileAudio`) using `AVAssetReader`.
- **Handling**: Performs sample rate conversion and channel mapping (mono->stereo, stereo->mono) in the render callback.

## Technical Gaps & Debt

### 1. Memory Usage (High Risk)
- **Problem**: `decodedFileCache` loads the *entire* decoded audio file into memory buffers (`[Float]`).
- **Impact**: Loading a long podcast or movie file will likely OOM the app.
- **Fix**: Implement a streaming reader or chunked caching for `AVAudioSourceNode`.

### 2. "LIGM" Protocol Fragility
- **Problem**: `createProceduralNode` parses URIs with string lookups (`hasPrefix`).
- **Improvement**: Formalize the protocol into a strongly-typed `ProceduralAudioSpec` enum/struct to avoid runtime typos.

### 3. Shallow Analysis
- **Problem**: `EngineerAgent` only listens to the first 10 seconds.
- **Impact**: If the loud part of the song is at 0:30, the agent might boost the quiet intro and clip the drop.
- **Improvement**: Implement a multi-point sampling strategy or a fast-scan algorithm.

## Improvements

1.  **Streaming Audio**: Replace `DecodedFileAudio` with a disk-backed ring buffer to support long files.
2.  **Loudness Scanning**: Use `Accelerate` to scan the decoded buffers directly (since they are in memory anyway right now!) instead of re-rendering.
3.  **Unit Tests**: The deterministic nature makes this module perfect for snapshot testing (render 1s of pink noise, compare checksum).
