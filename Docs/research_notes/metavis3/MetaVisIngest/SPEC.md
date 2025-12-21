# MetaVisIngest Specification

## Overview
MetaVisIngest is the "Hardware Bridge" and "IO Layer." It handles importing media, connecting to physical hardware (Cameras, Lights), and managing external services (Generators).

## 1. Hardware Drivers (MCP Servers)
**Goal:** Connect physical hardware to the `VirtualDevice` abstraction.

### Components
*   **`PhysicalCameraDevice`:**
    *   Implements `VirtualDevice`.
    *   Connects to RED/ARRI/iPhone via network/USB.
    *   Syncs properties (ISO, FPS) bi-directionally.
*   **`DisplayDevice`:**
    *   Implements `VirtualDevice`.
    *   Controls the Mac/Pro Display XDR (Brightness, Color Profile, View Mode).

### Implementation Plan
*   [ ] Create `PhysicalCameraDevice` class.
*   [ ] Create `DisplayDevice` class.
*   [ ] Implement "Driver Discovery" (scanning for connected devices).

## 2. Generator Services
**Goal:** Connect Generative AI services as "Generator Devices."

### Components
*   **`GeneratorDevice`:**
    *   Implements `VirtualDevice`.
    *   Type: `.generator`.
    *   Properties: Prompt, Seed, Model Parameters.
    *   Action: `generate()` -> Returns Media Asset.

### Implementation Plan
*   [ ] Create `GeneratorDevice` base class.
*   [ ] Implement `ElevenLabsDevice` (Audio).
*   [ ] Implement `VeoDevice` (Video).

## 3. Media Ingest
**Goal:** Efficiently import and proxy media.

### Components
*   **`MediaImporter`:**
    *   Handles file copying/transcoding.
    *   Generates proxies for smooth playback.
    *   Extracts metadata (Timecode, Camera Model, Lens Data).

### Implementation Plan
*   [ ] Update `MediaImporter` to extract Lens/Camera metadata into `Clip` properties.
