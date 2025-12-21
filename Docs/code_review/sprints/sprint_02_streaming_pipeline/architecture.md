# Architecture: Streaming I/O Pipeline

## Current State (MetaVisAudio)
`AudioTimelineRenderer` renders via `AVAudioEngine` manual offline rendering.

For file-backed clips, `AudioGraphBuilder` currently uses a streaming `FileClipStream`:
- Background `AVAssetReader` decode into a bounded ring buffer.
- `AVAudioSourceNode` render callback pulls from the ring buffer and applies gain/ramps.

## Proposed State (MetaVisAudio)
Treat audio as a **verification/hardening** target for this sprint:
- Keep `FileClipStream` + ring buffer model.
- Add deterministic unit-test evidence that short renders do not trigger eager full-track decoding.

Why not just `AVAudioPlayerNode.scheduleSegment`?
- `scheduleFile` / `scheduleSegment` are great for realtime playback and do stream decode.
- This repo currently needs deterministic offline rendering and per-sample automation in a pull-based callback. We should only pivot to player nodes if they are proven compatible with manual offline rendering and our gain/transition semantics.

## Current State (MetaVisIngest / FITS)
`FITSReader.read(url:)` performs:
`FITSReader.read(url:)` streams header blocks and reads payload via `FileHandle`.

## Proposed State (MetaVisIngest / FITS)
`FITSReader` becomes an incremental reader over an open handle:

`FITSReader` -> `FITSStreamingReader` (header blocks + data offset) -> scanline/batch reads -> conversion + statistics

Key properties:
- Read header in 2880-byte blocks until the `END` card.
- Compute `dataOffset`, `BITPIX`, and geometry (`NAXIS*`).
- Read payload incrementally (scanline or scanline batches).
- Convert big-endian to little-endian while streaming.
- Compute `FITSStatistics` without requiring a whole-file `Data`.

Compatibility:
- Keep `FITSReader.read(url:) -> FITSAsset` as the primary entrypoint.
- Internally, build `FITSAsset.rawData` as the final payload buffer (still allocates the final pixel payload, but avoids whole-file reads and avoids extra full-payload copies).

Incremental access:
- Provide an internal scanline read path (offset read + endianness conversion) for bounded-memory pipelines and deterministic tests.

## Dependencies
*   **Apple Core Audio**: Heavy reliance on `AVAudioFile` scheduling APIs.
*   **DispatchIO**: Candidate for high-performance non-blocking FITS reads.
