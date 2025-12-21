# Workflow spec: science data → VFX trailer (JWST Carina template)

## Goal
Use “science rasters” (starting with FITS) as raw material for cinematic motion graphics and VFX composites, without making FITS itself a product focus.

JWST Carina (MIRI bands) is the first concrete template: it forces a real ingest → transform → composite → export workflow that generalizes to other datasets.

## Non-goals
- Not building a general astronomy/FITS product.
- Not supporting every FITS variant; FITS is one decoder feeding a generalized internal representation.

## Core abstraction: `ScientificRaster`
Represent any scientific image stack as:
- **Raster**: width/height, scalar or vector channels.
- **Channels**: named planes with per-channel metadata (units, wavelength/band, suggested palette).
- **Transforms** (non-destructive): black/white points, stretch operator (asinh/log/linear), denoise, detail enhancement.
- **Composites**: recipes that map channels → display-referred or scene-linear color.

FITS is simply a decoder that yields one or more channels plus metadata.

## Input formats to prioritize (minimal set)
- **FITS** (already present in metavis3): science-first scalar planes.
- **OpenEXR**: VFX-native HDR/half-float multi-channel.
- **TIFF**: scientific and DCC interchange (16-bit integer and float variants).

(Everything else can be treated as “image/video” sources already handled by existing ingest.)

## Canonical color + tone path
- Internal working space for compositing: **scene-linear** (ACEScg-style intermediates are already used in metavis3).
- A scientific stretch/tone-map stage should be explicit and parameterized (black/white/stretch), producing either:
  - **Scalar density** (for volumetrics), and/or
  - **RGB color** (for direct compositing).

## JWST Carina template (v46-style)
### Inputs
Two source rasters:
- `Density` (scalar): drives volumetric density.
- `Color` (RGB): drives emissive color.

### Graph contract
- Graph node: `jwstComposite` with ports:
  - `density`
  - `color`
- Output: scene-linear RGBA (e.g., `.rgba16Float`).

### Naming convention
If the ingest layer can’t carry semantic tags yet, use asset naming as a bridge:
- Files/assets containing `Density` bind to the `density` port.
- Files/assets containing `Color` bind to the `color` port.

(When metadata plumbing lands, replace string heuristics with explicit channel mapping.)

## Determinism + governance
- Deterministic rendering stages: capture strict golden hashes for frame outputs.
- Scientific/ML stages (if any): use tolerant QC metrics and always capture:
  - model identifier/version
  - preprocessing parameters
  - device + OS + Metal feature set

## Deliverables for the first trailer iteration
- A reproducible Carina ingest bundle (the 2 or 4 source files + mapping).
- A timeline graph preset that:
  - loads sources
  - applies stretch/tone
  - runs `jwstComposite`
  - runs final post (`final_composite`)
  - exports 10-bit HEVC via the zero-copy converter path

## Backlog items (actionable)
- Unify the JWST composite contract:
  - Either standardize on v46 (`density`, `color`) everywhere, or implement a true 4-band composite path.
- Make “color” truly RGB for v46:
  - Introduce/enable a FITS→RGB mapping stage (IDT/false-color) instead of relying on single-channel tone-map output.
- Add a `ScientificRaster` internal type:
  - decoders (FITS now, EXR/TIFF later)
  - channel metadata plumbing into graph builder
- Export validation:
  - ensure the render→pixelbuffer→mux path avoids CPU readbacks.
