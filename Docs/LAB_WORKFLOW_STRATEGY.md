# Lab Workflow Strategy: The "Gemini Loop"

> **Objective**: Validate `MetaVisKit2` by replicating a user journey: "Create, Generate, Analyze, Refine."

## 1. The Core Concept: "The Lab Project"
A **Lab Project** is a specific type of MetaVis project designed for scientific validation rather than creative storytelling.
*   **Goal**: Prove the pipeline (ACEScg linearity, Render integrity).
*   **Actors**:
    *   **User**: Sets up the constraints.
    *   **Virtual Device (LIGM)**: Generates the content.
    *   **Perception**: Analyzes the result.
    *   **Gemini 3**: Acts as the "Senior Colorist/Supervisor" providing feedback.
    *   **Agent (System)**: Executes corrections.

## 2. The Workflow Steps

### Step 1: Device Setup (The Generator)
Implementation of the first `VirtualDevice`: **`LIGMDevice`**.
*   **Type**: `.generator`.
*   **Capabilities**:
    *   `generate(prompt: "ACES Test Chart", type: .pattern)`
    *   `generate(prompt: "Skin Tone Reference", type: .human)`
*   **Output**: Returns a `MetaVisCore.Asset` dealing with `rgba16Float` data.

### Step 2: Ingestion & Timeline
1.  **Create Project**: Initialize `ProjectSession` (Lab Mode).
2.  **Generate**: Call `LIGMDevice` to create 5-10 test assets.
3.  **Construct**: Place assets on a `Timeline` track.
4.  **Render**: `MetaVisSimulation` processes the timeline to a "Audit Frame".

### Step 3: The Perception Pass (Local Analysis)
Before sending to the cloud, we run deterministic local checks using `MetaVisPerception`:
*   **Histogram**: Is there clipping?
*   **Waveform**: Are blacks lifted?
*   **Delta-E**: Does the output color match the specific input request?
*   **Metadata**: Generate a `AnalysisReport` JSON.

### Step 4: The Gemini Loop (Cloud Feedback)
1.  **Package**: Bundle the `Audit Frame` (low-res proxy) + `AnalysisReport`.
2.  **Send**: `MetaVisServices` sends to Gemini 3 Pro.
3.  **Prompt**: "Act as a Color Science Engineer. Review this render. Is the skin tone linear? Is the gamma correct?"
4.  **Receive**: Gemini returns structured feedback (e.g., "Exposure -0.5 EV needed").

### Step 5: Corrective Action
1.  **Interpret**: Agent translates "Exposure -0.5" into an `EditIntent`.
2.  **Apply**: Add `ColorCorrectionEffect(exposure: -0.5)` to the Clip.
3.  **Re-Render**: Iterate.

## 3. Expanding the Device Ecosystem
Once the loop is proven with `LIGMDevice`, we expand:
1.  **`CameraDevice`**: Connects to iPhone/Webcam. Capture real world, analyze against generated world.
2.  **`LightDevice`**: Connects to HomeKit/DMX. Adjust physical lighting based on render feedback.

## 4. Implementation Validation (The "Dogfood" Test)
We will build this flow **before** building the full UI.
*   **Harness**: A command-line tool `MetaVisLabCLI` that runs this loop.
*   **Success Metric**: The system can self-correct a bad render without human intervention.
