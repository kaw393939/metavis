# Implemented

## Summary
- Added `MetaVisLab transcript generate` CLI that shells out to `whisper.cpp` (`whisper-cli`) via `Process`.
- Enforced the external dependency contract via `WHISPERCPP_BIN` + `WHISPERCPP_MODEL` (clear error messages when missing/misconfigured).
- Uses Core ML encoder offload (`WHISPER_COREML=1`) and expects the corresponding Core ML encoder bundle to exist (`ggml-<model>-encoder.mlmodelc`).
- Emits Sprint 22-style word JSONL + summary JSON + WebVTT captions, with optional adjacent caption writing for export auto-discovery.

## How to run (local)
- Install/build whisper.cpp + download model + generate Core ML encoder:
	- `bash scripts/install_whispercpp_coreml_macos.sh`
- Run the real E2E test:
	- `scripts/run_whisper_e2e_tests.sh`

## Artifacts
- `transcript.words.v1.jsonl`
- `transcript.summary.v1.json`
- `captions.vtt`
- Optional: `<input_stem>.captions.vtt` (when `--write-adjacent-captions=true`)
- Debug logs: `whispercpp.stdout.txt`, `whispercpp.stderr.txt`

## Tests
- `TranscriptGenerateEnvGatingTests.test_transcript_generate_missingEnv_throwsClearError`
- `TranscriptGenerateEnvGatingTests.test_transcript_generate_nonexistentWhisperBin_throwsBeforeRunning`
- `TranscriptGenerateIntegrationTests.test_transcript_generate_runsWhisperAndEmitsArtifacts_whenEnabled` (gated by `METAVIS_RUN_WHISPERCPP_TESTS=1`)

## Code pointers
- Command router: `Sources/MetaVisLab/MetaVisLabMain.swift`
- Implementation: `Sources/MetaVisLab/TranscriptCommand.swift`

## Scripts
- whisper.cpp + Core ML installer: `scripts/install_whispercpp_coreml_macos.sh`
- Whisper E2E runner: `scripts/run_whisper_e2e_tests.sh`
