# Concept: Autonomy Tiers (Selling the Virtual Crew)

> **Clarification**: The Agent is not just a helper; it is the **Product**.
> *   **Free**: You drive the ship.
> *   **Paid**: The crew drives the ship.

## 1. The Separation of Powers ("Manual vs. Auto")

We separate the **Engine Capabilities** from the **Agent Capabilities**.

### Block A: The Engine (The Tool)
*   **Status**: Free (mostly).
*   **Philosophy**: "If you want to do it yourself manually, go ahead."
*   **User Experience**: User manually adjusts curves, cuts clips, sets keyframes.
*   **Limit**: Caps on Resolution/Format (e.g., 1080p max for free).

### Block B: The Agent (The Crew)
*   **Status**: Paid (Unlock Codes / Subscription).
*   **Philosophy**: "You are paying for labor."
*   **User Experience**: User says "Color grade this like The Matrix." Agent does the work.

## 2. The Skill Tree Mechanism
We monetize by unlocking specific **Agent Skills`**.

### Skill 1: The Virtual Colorist (`AutoColor`)
*   **Manual**: User has full access to Lift/Gamma/Gain wheels.
*   **Autonomous**: "Fix skin tones", "Match shot A to shot B".
*   **License**: Requires `Unlock: COLOR_AI`.

### Skill 2: The Virtual Assistant Editor (`AutoLogger`)
*   **Manual**: User watches footage, types metadata.
*   **Autonomous**: Agent watches footage, tags "Exterior", "Day", "Happy", "Action".
*   **License**: Requires `Unlock: LOGGING_AI`.

### Skill 3: The Virtual Mograph Artist (`AutoMotion`)
*   **Manual**: User sets keyframes on Position/Scale.
*   **Autonomous**: "Make this title fly in with a bounce."
*   **License**: Requires `Unlock: MOGRAPH_AI`.

## 3. Architecture: The `AgentPermit`
The Agent checks for a permit before executing complex workflows.

```swift
struct AgentSkillRequest {
    let skill: AgentSkill // .autoGrade, .autoEdit
}

// In ProjectSession
func handle(request: AgentIntent) {
    if plan.hasSkill(request.skill) {
        agent.execute(request)
    } else {
        notifyUser("I know how to color grade this, but I'm not unlocked. Upgrade to Autonomy Plan?")
    }
}
```

## 4. The "100% Autonomous" End Game
For enterprise/studios, we sell the **"Showrunner License"**.
*   **Input**: "Make a 30-second ad for coffee."
*   **Process**:
    1.  Agent writes script.
    2.  Agent generates assets (`LIGMDevice`).
    3.  Agent edits timing.
    4.  Agent grades and mixes.
*   **Output**: Final Video.
*   **Value**: This is the highest tier because it replaces an entire production company.

## 5. Summary
We don't just sell "Resolution" (Pixel Power). We sell **"Time"** (Brain Power).
The Engine is the bait. The Agent is the catch.
