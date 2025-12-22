# Sprint 24e: Robust IO

**Focus:** Consolidation and Hygiene.

This sprint is about cleaning up the "Glue Code". We are removing the `ffmpeg` dependency from the **Gemini proxy generation** path in the Lab CLI and connecting it to the proper `MetaVisExport` pipeline.

**Status (2025-12-22):** Completed. `GeminiAnalyzeCommand` now generates its inline proxy via `MetaVisExport.VideoExporter` (no shell-out), `LIGMDevice` is plugin-routed, IO paths are centralized via `IOContext`, and debug file logging to hardcoded `/tmp/...` paths has been removed from exporter and engine.

## Contents
*   [Specification](spec.md)
*   [Architecture](architecture.md)
*   [TDD Plan](tdd_plan.md)
*   **Artifacts:** `MetaVisIngest`, `MetaVisExport`, `MetaVisLab` reviews.

## Primary Deliverables
1.  **Unified Export** (Removal of `ffmpeg` usage in `GeminiAnalyzeCommand`).
2.  **Generative Plugin Architecture** (Protocol-based `LIGMDevice`).
3.  **Path Hygiene** (Safe, explicit path handling in CLI).
4.  **Configurable Output Paths** for all CLI commands.

## Verification
- `swift test` passes (305 tests, 0 failures).

## Cross-cutting hardening learnings (from recent codebase work)
1. **Avoid optional tool assumptions in docs/scripts**
	- Prefer ubiquitous tools (`grep`, `python3`) or document dependencies explicitly.

2. **Acceptance/fixture iteration should not require code changes**
	- When a CLI or pipeline depends on heavy models or external state, prefer pre-generated fixtures + an env override for the fixture dir.

3. **Prefer structured logging over ad-hoc file logging**
	- Use `TraceSink`/`OSLog` rather than writing to hardcoded paths like `/tmp/...`.
