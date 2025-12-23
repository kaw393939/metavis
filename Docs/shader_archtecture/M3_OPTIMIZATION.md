# Apple M3+ shader optimization checklist

This is a practical guide for making the existing shader stack faster on Apple Silicon (M3+), without changing the UX.

## 1) The big levers (highest ROI)

1. **Reduce bandwidth**
   - Avoid extra full-resolution passes.
   - Prefer separable kernels (already used for Gaussian blur).
   - Keep intermediate format consistent (`rgba16Float`) to avoid conversion.

2. **Prefer half precision where safe**
   - Many postFX computations can use `half` intermediates.
   - Keep accumulation/critical math (e.g., PQ, volumetric integration) in `float` where needed.

3. **Use coherent access patterns**
   - Favor `texture.sample` with linear sampling for filtered reads.
   - For pure point reads, `texture.read` is fine.

4. **Threadgroup sizing via PSO limits**
   - Use `pso.threadExecutionWidth` and `pso.maxTotalThreadsPerThreadgroup` as defaults.
   - Avoid hard-coding threadgroup sizes unless profiling proves it wins.

## 2) Hot kernels to watch

- Large-radius blurs: sample counts scale with radius.
- Volumetric raymarch: heavy ALU + branches; step count dominates.
- Any kernel using atomics (`scope_waveform_*`, QC fingerprint/stats): contention can dominate.

## 3) Atomics guidance (waveform/QC)

- Use relaxed atomics (already done) and keep the working set small.
- Prefer 2-pass reduction (tile-local then global) if contention becomes a problem.

## 4) Library/PSO health

- Keep kernel names stable.
- Pre-warm only the kernels required for the current request path.
- Consider splitting “core always” vs “feature-on-demand” caches.
