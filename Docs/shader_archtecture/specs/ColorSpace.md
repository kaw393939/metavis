# ColorSpace.metal

## Purpose
Core pipeline transforms:
- IDT into ACEScg
- ODT back to Rec.709
- Utility transforms (exposure, contrast, CDL)
- Scopes (waveform accumulate/render)

## Kernels (highlights)
- IDT/ODT
  - `idt_rec709_to_acescg`
  - `idt_linear_rec709_to_acescg`
  - `odt_acescg_to_rec709`

- Utility
  - `exposure_adjust`
  - `contrast_adjust`
  - `cdl_correct`
  - `lut_apply_3d`
  - `aces_tonemap`
  - `source_texture`
  - `source_linear_ramp`
  - `source_test_color`

- Scopes
  - `scope_waveform_accumulate` (uses atomics)
  - `scope_waveform_render` (uses atomics)

## Binding conventions
Most kernels follow:
- input `texture(0)` → output `texture(1)`
Special cases:
- `scope_waveform_accumulate`: `source` `texture(0)`, `grid` `buffer(0)`
- `scope_waveform_render`: `grid` `buffer(0)`, `dest` `texture(1)`

## Engine callsites
- Golden-thread enforcement: `Sources/MetaVisSimulation/TimelineCompiler.swift` inserts IDT/ODT nodes.
- Scope path special-cased in `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.
