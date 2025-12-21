# MetaVisCalibration - Specification

## Goals
1.  Port the ACES color pipeline matrices and transforms.
2.  Implement the Color Validation logic (Lab Delta E).

## Requirements

### Color Science
- **Working Space**: ACEScg (AP1 primaries).
- **Storage**: 16-bit Float (Linear).
- **Transforms**:
    -   Must implement `M_ACEScg_to_XYZ` and `M_AP0_to_XYZ`.
    -   Must implement Bradford CAT (`M_CAT_D65_to_D60`).
    -   Must support PQ (ST.2084) and HLG transfer functions.

### Validation
- Must implement `LabColor` struct.
- Must implement Delta E 2000 (or 1976) calculation.
- Must provide a CLI tool or library function to validate a given frame against a reference chart.
