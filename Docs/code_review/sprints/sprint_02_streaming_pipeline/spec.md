# Sprint 02: Streaming I/O Pipeline

## 1. Objective
Replace "load entire file into RAM" patterns in `MetaVisAudio` and `MetaVisIngest` with streaming implementations.

This sprint is specifically about eliminating *avoidable* memory spikes and "decode everything up front" behavior while preserving deterministic offline rendering.

## 2. Scope
- **Target modules**: `MetaVisAudio`, `MetaVisIngest`
- **Key code paths (current)**
	- `MetaVisAudio/AudioGraphBuilder`: already uses a streaming `FileClipStream` + ring buffer feeding an `AVAudioSourceNode` render callback (no `decodedFileCache` full-track pattern).
	- `MetaVisIngest/FITSReader`: streams header blocks via `FileHandle` and reads only the required payload bytes for the chosen image HDU (no `Data(contentsOf:)`).

Non-goals:
- Redesign the entire audio engine API surface.
- Add new UI affordances.
- Optimize unrelated ingest formats.

## 3. Acceptance Criteria
1. **Audio (verify existing streaming behavior)**
	 - Confirm file-backed audio remains ring-buffer / bounded-working-set based (streaming `FileClipStream`).
	 - Unit tests provide deterministic evidence that a short render does not trigger eager full-track decode.

	 Notes:
	 - Apple’s `AVAudioPlayerNode.scheduleFile` / `scheduleSegment` are valid streaming APIs for realtime playback. However, this repo’s offline renderer currently uses `AVAudioSourceNode` to supply audio samples and apply per-sample gain/ramps deterministically, so the streaming fix must fit that model unless we prove `AVAudioPlayerNode` is compatible with manual offline rendering *and* supports our gain automation.

2. **FITS (no full-file Data load)**
	 - `FITSReader` must no longer call `Data(contentsOf:)` for the full file.
	 - Header parsing must read 2880-byte blocks incrementally.
	 - Pixel data must be readable incrementally (e.g. scanline-at-a-time via `FileHandle` offset reads) for bounded-memory pipelines.
	 - Endianness conversion must not introduce an additional full-payload copy (convert in-place in the final payload buffer).

3. **Verification / evidence**
	 - Unit tests prove the structural contract (no eager full-file decode / no eager full-file read).
	 - Profiling evidence (Instruments) demonstrates bounded memory during:
		 - offline render of a timeline containing a long file-backed audio clip, and
		 - ingest/processing of a large FITS file.

## 4. Implementation Strategy
- **Audio**
	- Replace the `DecodedFileAudio` / `decodedFileCache` approach with a streaming provider used by the `AVAudioSourceNode` render callback.
	- A practical model for this codebase:
		- A per-clip (or per-asset) streaming decoder that reads `CMSampleBuffer`s from `AVAssetReaderTrackOutput` into a small ring buffer of interleaved float samples at the engine’s target format.
		- The `AVAudioSourceNode` render callback pulls from that ring buffer and applies `AudioMixing.clipGain(...)` the same way it does today.
		- Prebuffer 1–2 chunks ahead (conceptually similar to segment scheduling) to avoid underruns.
	- Keep the work inside the render callback minimal: no file I/O, no large allocations.

- **FITS**
	- Introduce a streaming reader that:
		- reads 2880-byte header blocks (80-byte cards) until `END`,
		- computes the image data offset, dimensions, and `BITPIX`,
		- reads payload in fixed chunks (e.g. scanlines or scanline batches) via `FileHandle` or POSIX `pread`,
		- converts byte order in-place while streaming, and
		- computes `FITSStatistics` in a streaming pass (histogram bins remain bounded).
	- Preserve the existing `FITSReader().read(url:) -> FITSAsset` public API unless a new streaming API is clearly required by downstream callers.

## 5. Artifacts
*   [Architecture](./architecture.md)
*   [TDD Plan](./tdd_plan.md)
