# MetaVisLab Assessment

## Initial Assessment
MetaVisLab acts as the command-line "Workbench" and verification harness for the entire system. It orchestrates high-level automated workflows (like "Auto Enhance") and provides developer tools for testing specific subsystems (FITS, EXR, Sensors). It is the integration point where core modules come together into executable pipelines.

## Capabilities

### 1. Automated Enhancement Pipelines
- **`AutoEnhanceCommand`**: A turnkey command that ingests a video, runs it through `AutoColorCorrect` and `AutoSpeakerAudio`, and exports a mastered result.
- **Orchestration**: Manages the flow of data between `MetaVisPerception` (sensors), `MetaVisSimulation` (proposal generation), and `MetaVisExport` (rendering).
- **Face-Aware Rendering**: Demonstrates advanced coupling by injecting face-tracking data from sensors into the render pipeline to drive mask-based beauty effects.

### 2. Feedback Loops
- **`AutoColorCorrectCommand`**: Implements a sophisticated "Agentic Loop". It doesn't just apply a filter; it proposes a grade, generates evidence (frames), asks an expert (LLM or Local Rule), and iteratively refines parameters based on feedback.

### 3. Developer Tooling
- **Verification Commands**: Includes targeted commands for deep-system testing:
    -   `export-demos`: Validates recipe export.
    -   `exr-timeline` / `fits-timeline`: Validates high-bit-depth scientific workflows.
    -   `sensors`: Validates raw perception output.

## Technical Gaps & Debt

### 1. External Dependencies (`ffmpeg`)
- **Issue**: `AutoColorCorrectCommand` shells out to `ffmpeg` CLI to extract JPEG evidence frames.
- **Debt**: Introduces a hidden runtime dependency. If `ffmpeg` isn't in `$PATH`, the lab fails.
- **Fix**: Use `AVAssetImageGenerator` or the internal `VideoExporter` to generate evidence frames natively.

### 2. Redundant Argument Parsing
- **Issue**: Each command re-implements massive `Option` structs and argument parsing logic.
- **Fix**: Shared configuration objects or a more hierarchical command structure.

### 3. Hardcoded "Lab" Paths
- **Issue**: Defaults to writing `test_outputs` in the current working directory.
- **Debt**: Can clutter user directories or fail in restricted environments (sandboxes).

## Improvements

1.  **Native Evidence Generation**: Replace `ffmpeg` calls with Swifty AVFoundation code to make the specific commands self-contained.
2.  **Pipeline Abstraction**: Abstract the "Analyze -> Propose -> Verify" loop into a generic `OptimizationPipeline<T>` to reduce code duplication betwen Audio and Color commands.
3.  **Strict Environment Checks**: Verify all dependencies (including API keys) at startup (`MetaVisLabMain`) rather than failing deep inside a command.
