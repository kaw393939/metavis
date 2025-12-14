# Sprint 08 — Intent/Tools/Observability (No-mocks)

## Goal
Make the agent loop real and inspectable:
- intent → typed commands
- commands → session actions
- structured tool protocol
- structured traces/logging for reproducibility

Also ensure the same tracing model can cover creator workflows (ingest/transfer, dialog cleanup, captions) without building UI.

## Acceptance criteria
### Must-have
- A typed command layer exists (separate from free-form intents) that can be executed deterministically.
- A registry exists mapping *parsed intents* (currently `UserIntent`) to typed commands.
- Commands execute against `ProjectSession` deterministically (no network; no model calls).
- A structured event log/trace exists with a testable in-memory sink.

### Trace coverage
- Trace includes events/spans for:
  - intent parsing
  - command resolution
  - session actions (timeline edits, config mutations)
  - analysis jobs (e.g. perception analysis) and throttling/skips
  - export
  - QC (structural + content/metadata)
  - optional AI gate (skip reasons must be deterministic)
  - render graph compile/dispatch (logical kernel name → concrete Metal function name when available)
  - performance guardrails (at minimum: export CPU readback usage)

### Verification
- E2E test validates that:
  - given a deterministic intent payload, commands execute
  - a complete trace is emitted
  - output export passes deterministic QC

## Existing code likely touched
- `Sources/MetaVisServices/IntentParser.swift`
- `Sources/MetaVisSession/ProjectSession.swift` (command execution entry)
- `Sources/MetaVisServices/LocalLLMService.swift` (kept optional; not required for tests)
- `Sources/MetaVisCore/VirtualDevice.swift` (tool/device pattern reference)
- `Sources/MetaVisExport/VideoExporter.swift`, `Sources/MetaVisQC/VideoQC.swift` (E2E)

Additional relevant (now present) building blocks:
- `Sources/MetaVisExport/Deliverables/*` (deliverable bundles + manifest)
- `Sources/MetaVisQC/VideoContentQC.swift` (content QC sampling)
- `Sources/MetaVisQC/VideoMetadataQC.swift` (metadata QC)
- `Sources/MetaVisSimulation/MetalSimulationDiagnostics.swift` (export CPU readback guardrail)
- `Sources/MetaVisCore/AIGovernance.swift` + `Sources/MetaVisCore/QualityPolicyBundle.swift` (AI/Privacy policy defaults)

## New code to add
- `Sources/MetaVisSession/Commands/IntentCommand.swift`
- `Sources/MetaVisSession/Commands/IntentCommandRegistry.swift`
- `Sources/MetaVisSession/Commands/CommandExecutor.swift`
- `Sources/MetaVisCore/Tracing/TraceEvent.swift`
- `Sources/MetaVisCore/Tracing/TraceSink.swift` (in-memory sink for tests; file sink optional)

## Current state (as of 2025-12-13)
- Intent parsing exists (`IntentParser`) and is tested via `Tests/MetaVisServicesTests/LocalLLMTests.swift`.
- Session mutation is already typed and deterministic via `EditAction` + `ProjectSession.dispatch(_:)`.
- Deliverable export is real and deterministic end-to-end (export → QC → manifest persistence), with E2E coverage:
  - `Tests/MetaVisExportTests/DeliverableE2ETests.swift`
  - `Tests/MetaVisExportTests/QCExpansionE2ETests.swift`
- Content QC and metadata QC are already implemented and produce measured metrics in `deliverable.json`:
  - content: fingerprints + adjacent distances + luma histogram-derived stats
  - metadata: codec FourCC + available color metadata
- Performance guardrail exists for export CPU readback (`MetalSimulationDiagnostics.cpuReadbackCount`) and is asserted in tests.
- AI governance types exist and defaults are privacy-first; Gemini integration is env-gated.

## Remaining gaps Sprint 08 closes
- No structured trace/event sink exists yet (current logs are ad-hoc `print`/`logDebug`).
- No `IntentCommandRegistry`/`CommandExecutor` exists yet to map `UserIntent` → deterministic session actions.
- No trace coverage for render graph compile/dispatch/pipeline resolution beyond debug logs.

## Deterministic generated-data strategy
- Do not call external models in tests.
- Use deterministic intent samples (static strings) that parse consistently.
- Use procedural generator timelines for exported media.

## Test strategy (no mocks)
- Use real `IntentParser`.
- Use real `ProjectSession`.
- Use real exporter + metal engine + QC.
- Trace sink is a real implementation (not a mock): `InMemoryTraceSink`.

## Work breakdown
1. Add typed command model.
2. Map existing intent parser outputs → commands.
3. Execute commands against session.
4. Add tracing events + sink.
5. Add E2E tests.
