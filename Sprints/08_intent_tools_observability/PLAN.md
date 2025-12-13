# Sprint 08 — Intent/Tools/Observability (No-mocks)

## Goal
Make the agent loop real and inspectable:
- intent → typed commands
- commands → session actions
- structured tool protocol
- structured traces/logging for reproducibility

Also ensure the same tracing model can cover creator workflows (ingest/transfer, dialog cleanup, captions) without building UI.

## Acceptance criteria
- An `IntentCommandRegistry` exists mapping parsed intents to typed commands.
- Commands execute against `ProjectSession` deterministically.
- A structured event log/trace exists for:
  - ingest/generate
  - transfer/import (iPhone → Mac pipeline later; folder-drop contract first)
  - timeline edits
  - analysis jobs (dialog cleanup, captions/diarization)
  - export
  - QC
  - (optional) AI gate
  - render graph compile/dispatch (include logical kernel name → concrete Metal function mapping where applicable)
  - performance counters/guardrails (e.g. per-frame allocations, export CPU readback usage)
- E2E test validates that:
  - given a deterministic intent string, commands execute
  - a complete trace is emitted
  - output export passes deterministic QC

## Existing code likely touched
- `Sources/MetaVisServices/IntentParser.swift`
- `Sources/MetaVisSession/ProjectSession.swift` (command execution entry)
- `Sources/MetaVisServices/LocalLLMService.swift` (kept optional; not required for tests)
- `Sources/MetaVisCore/VirtualDevice.swift` (tool/device pattern reference)
- `Sources/MetaVisExport/VideoExporter.swift`, `Sources/MetaVisQC/VideoQC.swift` (E2E)

## New code to add
- `Sources/MetaVisSession/Commands/IntentCommand.swift`
- `Sources/MetaVisSession/Commands/IntentCommandRegistry.swift`
- `Sources/MetaVisSession/Commands/CommandExecutor.swift`
- `Sources/MetaVisCore/Tracing/TraceEvent.swift`
- `Sources/MetaVisCore/Tracing/TraceSink.swift` (in-memory sink for tests; file sink optional)

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
