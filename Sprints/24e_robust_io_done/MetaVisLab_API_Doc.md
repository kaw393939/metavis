# MetaVisLab API / CLI Documentation

`MetaVisLab` is a command-line interface (CLI) tool. It is not intended to be imported as a library by other modules.

## Usage

Run the `MetaVisLab` executable from the command line.

`swift run MetaVisLab <subcommand> [flags]`

## Subcommands

### `sensors`
Run machine perception algorithms on input media.
```bash
MetaVisLab sensors ingest --input movie.mov --out ./results
```

### `gemini-analyze`
Perform AI Quality Control on a clip using Google Gemini.
*Requires `RUN_GEMINI_QC=1` environment variable.*
```bash
MetaVisLab gemini-analyze --input movie.mov --out ./results
```

### `nebula-debug`
Render diagnostic frames for the Volumetric Nebula shader.
```bash
MetaVisLab nebula-debug --out ./debug_frames --width 1920 --height 1080
```

### `fits-timeline` / `fits-composite-png`
Render scientific FITS data.
```bash
MetaVisLab fits-composite-png --input-dir ./jwst_data --out ./renders
```
