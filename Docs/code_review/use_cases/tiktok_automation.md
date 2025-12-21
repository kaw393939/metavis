# Feasibility Breakdown: Automated Social Video Creation

## The Short Answer
**Yes, absolutely.** MetaVisKit2 is uniquely capable for this because it is built as a **Simulation Engine** rather than a human UI tool. You can define a "Recipe" (template) in Swift, feed it data, and output thousands of videos largely without human intervention.

However, it currently lacks the **ingest** capabilities (e.g. downloading stock footage, TTS) required for a fully autonomous "Text-to-Video" pipeline.

## 1. Capabilities (What Works Now)

### Programmatic Editing (`MetaVisSession / Recipes`)
You can write Swift code to generate timelines dynamically.
*   **Example**: `DemoRecipes.BrollMontageDemo` automatically assembles clips, adds transitions, and syncs audio tones.
*   **Potential**: You could write a `TikTokRecipe` that takes a folder of images + audio, crops them to 9:16, applies a "Ken Burns" effect, and syncs cuts to the beat.

### Headless & Cloud Ready
*   **CLI**: The system runs via `metavis-cli`, meaning you can deploy it on a headless Mac Mini server farm to render videos 24/7.
*   **JSON State**: Projects are just JSON files. A web server could generate a `project.json` and send it to MetaVis to render.

### "Smart" Formatting (`MetaVisPerception`)
*   **Face Detection**: The engine can "see" faces. You could write a script: "Find the face in this 16:9 video and auto-crop to 9:16 vertical video, keeping the face centered."
*   **Silence Removal**: The engine can identify silence in spoken word (e.g. podcasts) and automatically "Jump Cut" to remove dead air.

## 2. The Missing Pieces (The Gaps)

To build a fully automated "Text-to-Video" bot (e.g. "Make me a video about Roman History"), you are missing:

### A. Asset Sourcing (The "Hands")
*   **Status**: ❌ Not Implemented.
*   **Gap**: `MetaVisIngest` only reads local files.
*   **Need**: A module to download images/videos from Pexels, Unsplash, or YouTube.

### B. Voice Synthesis (The "Mouth")
*   **Status**: ❌ Not Implemented.
*   **Gap**: `MetaVisAudio` generates noise/tones (`LIGM`) but cannot do Text-to-Speech (TTS).
*   **Need**: Integration with ElevenLabs API or Apple's generic speech synthesizer.

### C. The Script Writer (The "Brain")
*   **Status**: ⚠️ Partial (Mock Only).
*   **Gap**: `MetaVisServices` is currently a skeleton.
*   **Need**: **Sprint 05 (Local Intelligence)** to integrate Llama-3 so it can write scripts, choose keywords, and decide *what* to show.

## 3. The Blueprint: How to Build "TikTokBot"

If you wanted to build this *today*, you would need to:

1.  **Write a Script** (External Python/Node):
    *   Ask ChatGPT for a script about "Roman History".
    *   Use ElevenLabs to generate MP3 voiceover.
    *   Download 5 stock clips of "Rome".
2.  **MetaVis Assembly** (Swift Recipe):
    *   Create a `SocialMediaRecipe` struct.
    *   Load the MP3 voiceover.
    *   Load the 5 clips.
    *   Use `AudioAnalysis` to find sentence breaks.
    *   Place clips on the timeline matching the voiceover.
    *   Add "Pop-Text" subtitles (using `MetaVisGraphics` CoreText overlay).
    *   Export as 9:16 HEVC.

## Verdict
MetaVisKit2 is the **Engine** for this car, but it doesn't have the **Fuel** (Assets) or **Driver** (Scripting) yet.

**You can build the automation pipeline *around* it immediately**, using MetaVis as the high-quality renderer that ensures the final video is glitch-free, professionally governed (watermarked, safe), and visually consistent.
