# Sprint 20 — ACEScg Contract + Deterministic SDR Preview

## Goal
Make the “ACEScg at the door” + deterministic SDR preview contract **explicit, testable, and enforced**.

This sprint is intentionally narrow:
- Inputs: Rec.709 (SDR) video + procedural generators + EXR
- Working space: ACEScg (scene-linear)
- Display preview: deterministic Rec.709 SDR transform (ODT)

## Acceptance criteria
- **Graph contract**: For any compiled video timeline frame:
  - an IDT node exists immediately after each source node (`idt_rec709_to_acescg` or `idt_linear_rec709_to_acescg` for EXR)
  - an ODT node exists at the graph root (`odt_acescg_to_rec709`)
- **EXR input rule**: EXR sources use the linear IDT (`idt_linear_rec709_to_acescg`).
- **Deterministic preview metadata** (deliverables): exported HEVC SDR preview is tagged consistently (color primaries / transfer / matrix), and passes deterministic QC.

## Existing code likely touched
- Sources/MetaVisSimulation/TimelineCompiler.swift
- Sources/MetaVisGraphics/Resources/*.metal (IDT/ODT kernels)
- Sources/MetaVisExport/* (container metadata defaults)
- Sources/MetaVisQC/* (metadata assertions)

## New code to add
- Tests/MetaVisSimulationTests/ACEScgWorkingSpaceContractTests.swift
- (Optional) Tests/MetaVisExportTests/SDRPreviewMetadataContractTests.swift

## Deterministic test-data strategy
- Prefer procedural generators (`ligm://fx_*`) for deterministic frames.
- Use local EXR fixtures under assets/exr for EXR path.

## Test strategy (no mocks)
- Compile timelines and assert render-graph invariants.
- Keep export tests low-res and short (<= 1s) to keep CI fast.
