# TDD Plan: Sprint 02

## Existing Tests
- `MetaVisAudioTests/FileAudioSourceTests.swift`: Validates file-backed audio renders non-silent.
- `MetaVisIngestTests/FITSReaderTests.swift`: Validates minimal Float32 FITS parsing and endianness conversion.

## New Tests
1. **Audio streaming contract test (structural, deterministic)**
    - Implemented via DEBUG-only diagnostics (`FileAudioStreamingDiagnostics`) and assertions in `FileAudioSourceTests`.

2. **FITS non-eager read contract test (structural)**
    - Implemented via DEBUG-only `FITSReader.Diagnostics.lastBytesRead` and a test that appends large trailing garbage.

3. **FITS scanline read + endianness conversion test (deterministic)**
    - Implemented using an internal scanline API (`readFloat32Scanline`) and a deterministic assertion on row values.

Avoid brittle assertions:
- Do not assert wall-clock timings in unit tests.
- Do not assert absolute RAM usage in XCTest (use Instruments + documented evidence instead).

## Test Command
```bash
swift test --filter MetaVisAudioTests
swift test --filter MetaVisIngestTests
```
