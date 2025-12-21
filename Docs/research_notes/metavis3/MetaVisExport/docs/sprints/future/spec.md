# MetaVisExport - Specification

## Goals
1.  Encode final video and audio streams.
2.  Mux them into a container (MOV/MP4).

## Requirements
- **Zero-Copy**: Must consume `CVPixelBuffer` directly from Metal.
- **Formats**: HEVC (10-bit), ProRes (422/4444), H.264.
- **Metadata**: Write correct color tags (NCLC) and timecode tracks.
