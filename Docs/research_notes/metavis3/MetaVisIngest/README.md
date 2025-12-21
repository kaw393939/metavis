# MetaVisIngest - Agent Mission Control

## 1. Mission
**"The Mouth"**
MetaVisIngest handles the intake of raw media. It wraps `AVFoundation` to import video files, image sequences, and audio. It is responsible for probing metadata (codec, color space) and generating lightweight proxies.

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [ ] Media Probe Ported
- [ ] Proxy Generator Ported
- [ ] Tests Passing

## 3. Legacy Intelligence
- **Sources**: `./legacy_sources/`
    - `Ingestion/`: `FootageIngestService`, `MediaProbe`.
    - `Video/`: Low-level decoding logic.
- **Tests**: `./legacy_tests/`
    - `FootageIngestServiceTests.swift`: Import verification.

## 4. Documentation
- **[Spec](./docs/sprints/future/spec.md)**: Requirements for format support and proxy generation.

## 5. Task List
### Phase 1: Import
1. [ ] **Probe**: Port `MediaProbe` to extract technical metadata.
2. [ ] **Decode**: Implement a robust `VideoDecoder` using `AVAssetReader`.

### Phase 2: Proxies
1. [ ] **Transcode**: Implement `ProxyGenerator` to create 720p ProRes Proxy files.
