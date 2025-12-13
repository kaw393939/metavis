# Sprint 08 — TDD Plan (Intent/Tools/Observability)

## Tests (write first)

### 0) `TraceE2ETests.test_ingest_import_emits_trace_events()`

- Uses a deterministic “folder drop” ingest contract (no UI).
- Asserts trace contains import events + resulting timeline edit events.

### 1) `IntentE2ETests.test_intent_drives_session_and_exports_with_trace()`

- Parse a deterministic intent string with `IntentParser`.
- Resolve to typed commands via `IntentCommandRegistry`.
- Execute commands on a real `ProjectSession` using `CommandExecutor`.
- Export a short deterministic clip.
- Run `VideoQC`.
- Assert trace contains ordered events for: parse → command(s) → session actions → render compile/dispatch → export → QC.

### 2) `TraceTests.test_trace_is_deterministic_for_same_inputs()`

- Create two runs with same intent + seed.
- Assert trace event sequence (types + key fields) matches.

### 3) `RenderTracingTests.test_trace_includes_compile_and_pipeline_resolution()`

- Build a minimal `RenderGraph` with a known logical kernel name (e.g. `jwst_composite`).
- Execute a render with tracing enabled.
- Assert trace includes events/spans for:
  - graph compilation (logical kernel list)
  - pipeline resolution (logical name → concrete Metal function name)
  - dispatch start/stop (kernel name, threads/grid size if available)

### 4) `ExportTracingTests.test_trace_flags_cpu_readback_when_guardrail_enabled()`

- Configure export in a mode where guardrails are enabled (or a test-only flag).
- Execute a single-frame export.
- If a CPU readback path is taken, assert trace includes a `cpu_readback_used=true` event/span (or similar).
- If the intended zero-copy path is used, assert trace includes a `zero_copy_used=true` event/span.

## Production steps

1. Add `IntentCommand` + registry.
2. Add executor.
3. Add trace event model and `InMemoryTraceSink`.
4. Thread trace sink through session/export/QC entrypoints (opt-in, default no-op).

## Definition of done

- E2E intent-driven export + QC passes without mocks.
- Trace is produced and stable.
