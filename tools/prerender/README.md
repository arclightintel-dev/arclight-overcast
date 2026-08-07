# Black-hole loop pre-render pipeline

The landing page background (`bh-loop.mp4` + `bh-poster.jpg`) is a pre-rendered,
seamlessly looping capture of the TSL ray-march shader in `/singularity-gpu.js`.
The shader no longer runs in visitors' browsers — it is only executed here, at
build time, to regenerate the loop.

## How it works

- `capture.mjs` serves the repo over localhost, loads `capture.html` in headless
  Chromium (SwiftShader — no GPU needed), and virtualizes the clock:
  `performance.now()` returns a virtual time that only advances when the script
  steps it, so the shader's `time` uniform is exactly deterministic. Each step
  advances 1/24 s and screenshots the canvas.
- Determinism makes the capture parallelizable: N workers each render a segment
  (`OFFSET_FRAMES`/`FRAMES`) and the segments splice together exactly.
- Three.js is vendored from npm and mapped via an import map (`three/webgpu`,
  `three/tsl`) so no CDN access is needed.
- `encode.sh` (ffmpeg) takes the 288 captured frames (12 s @ 24 fps) and
  crossfades the last 2 s over the first 2 s, producing a 10 s loop whose
  wrap-around is invisible. The poster is extracted from the loop's first frame
  so the poster → video handoff on the page is seamless.

## Regenerating

```bash
npm install            # playwright, ffmpeg-static, three@0.180.0
# 4 parallel workers, 72 frames each:
for i in 0 1 2 3; do
  OFFSET_FRAMES=$((i*72)) FRAMES=72 PORT=$((8931+i)) node capture.mjs &
done; wait
./encode.sh ../../bh-loop.mp4   # also writes ../../bh-loop-poster.jpg
```

Capture is CPU-ray-marched: ~30 s per 720p frame per core. A full regeneration
takes 1–3 hours on a 4-core box.
