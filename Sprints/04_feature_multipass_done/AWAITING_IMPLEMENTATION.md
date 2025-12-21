# Awaiting Implementation

## Status
- ✅ Sprint is complete (multi-pass + multi-input + texture pooling).

## Gaps & Missing Features
- (Resolved) **Input Arity**: `MultiPassFeatureCompiler` supports passes with multiple inputs.
- (Resolved) **Texture Pooling**: `TexturePool` exists and is used by `MetalSimulationEngine`.

## Technical Debt
- **Generic Multi-Input Binding Semantics**: Engine binds extra inputs in a stable order starting at texture index 2. If a shader requires specific indices beyond this convention, it should declare/implement an explicit binding path.

## Recommendations
- If/when we add more multi-input shaders: document expected port → texture index mapping and add a focused render test per shader family.
