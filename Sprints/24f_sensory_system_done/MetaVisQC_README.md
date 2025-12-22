# MetaVisQC

**MetaVisQC** guarantees that your renders are correct. It is the sophisticated "Quality Control" layer that sits between the renderer and the final delivery.

## Why?
Rendering complexity means things can go wrong:
- Encoder dropouts (missing frames).
- Black screens (compositor failure).
- Muted audio (accidental track mute).
- Bad lighting / focus (creative issues).

MetaVisQC allows you to catch these issues **automatically** before a human reviewer ever sees the file.

## Features

### 🛡️ Local Gates
Fast, offline checks that run on every export.
- **Spec Validation:** Checks resolution, FPS, and bitrate.
- **Audio Presence:** Ensures the file isn't silent.
- **Entropy Checks:** Detects "black frame" failures or "stuck frame" encoder glitches using luma histograms and perceptual hashing.

### 🤖 AI Review
Integrates with Google Gemini to "watch" your video.
- **Prompt Engineering:** The module constructs a detailed context for the LLM, explaining what the video *should* be.
- **Privacy:** A strict "Local Gate" runs *before* upload. If the video is black/broken, we never send it to the cloud.

## Privacy & Safety
This module depends on `AIGovernance` from `MetaVisCore`. It will refusal to enact any network requests unless the runtime environment and user configuration explicitly allow media uploads.
