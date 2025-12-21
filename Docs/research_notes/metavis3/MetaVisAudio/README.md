# MetaVisAudio - Agent Mission Control

## 1. Mission
**"The Ears & Voice"**
MetaVisAudio handles all sound processing. It mixes multiple tracks, applies DSP effects (EQ, Compression), and ensures sample-accurate synchronization with the video timeline.

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [ ] Mixer Ported
- [ ] DSP Effects Ported
- [ ] Tests Passing

## 3. Legacy Intelligence
- **Sources**: `./legacy_sources/`
    - `Audio/`: The entire legacy audio engine.
- **Tests**: `./legacy_tests/`
    - `Audio/`: Unit tests.

## 4. Documentation
- **[Spec](./docs/sprints/future/spec.md)**: Requirements for 32-bit float mixing.

## 5. Task List
### Phase 1: The Engine
1. [ ] **Graph**: Implement an `AVAudioEngine` graph.
2. [ ] **Mixer**: Create a multi-channel mixer node.

### Phase 2: Effects
1. [ ] **DSP**: Port legacy effects to `AVAudioUnit` subclasses.
