# MetaVisPerception - Agent Mission Control

## 1. Mission
**"The Eyes & Brain"**
MetaVisPerception provides the "Scientific Method" for the renderer. It uses AI (Gemini) and Computer Vision to analyze video content for quality, accuracy, and semantic understanding. It has **no side effects**—it only observes and reports.

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [ ] Gemini Integration Ported
- [ ] CV Metrics Ported
- [ ] Tests Passing

## 3. Legacy Intelligence
- **Sources**: `./legacy_sources/`
    - `Analysis/GeminiAnalyzer.swift`: The AI bridge.
    - `Analysis/QualityAnalyzer.swift`: Deterministic metrics (Sharpness, Noise).
    - `Analysis/MotionAnalyzer.swift`: Optical flow.
- **Tests**: `./legacy_tests/`
    - `Analysis/`: Unit tests for the analyzers.

## 4. Documentation
- **[Spec](./docs/sprints/future/spec.md)**: Requirements for Gemini 2.0 and CV metrics.
- **[TDD Plan](./docs/tdd_plan.md)**: (To Be Created) Strategy for mocking AI responses.

## 5. Task List
### Phase 1: AI Analysis
1. [ ] **Gemini**: Port `GeminiAnalyzer`. Update to use the latest Google Generative AI SDK.
2. [ ] **Prompts**: Extract system prompts into a resource file or constant enum.

### Phase 2: CV Analysis
1. [ ] **Metrics**: Port `QualityAnalyzer` (Laplacian variance, SNR).
2. [ ] **Motion**: Port `MotionAnalyzer`.
