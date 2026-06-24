# Blackhole Hero -- Governing Production Spec

**Status:** GOVERNING -- all implementation derives from this document.
**Version:** 3.0 (reconciled from claude-main v1, hotpants v1, hotpants v2)
**Date:** 2026-06-17

---

## 1. Governing Principle

Precompute the optical transport field. Render everything else live. Never precompute full-screen displacement sequences or full frames unless shipping video fallback.

The renderer is a texture-lookup compositor, not a ray marcher. Every per-pixel ray traced offline produces a transport record. The runtime shader reads that record and composites layers. The complexity budget lives in the offline precompute; the runtime budget is one full-screen pass plus post-processing.

---

## 2. Coordinate System

All precomputed maps use a **black-hole-local polar coordinate system**, not screen coordinates. The camera's relationship to the black hole is baked into the transport atlas at precompute time for a locked viewpoint.

- **Origin:** black hole singularity
- **Radial axis:** Schwarzschild radial coordinate r (units of M, gravitational radii)
- **Angular axis:** azimuthal angle in the camera's deflection plane
- **Texture UV mapping:** nonlinear, following Bruneton's approach -- remap (e, u) to texture space via `GetRayDeflectionTextureUFromEsquare` / `GetRayDeflectionTextureVFromEsquareAndU` to eliminate divergences near the photon sphere (u = 2/3) and critical impact parameter (e^2 = mu = 4/27)

The locked camera composition is **Config 3** (`eval/benchmark-config-3.json`):
- Position: (0.16, 0.037, 0.546) -- danger-close equatorial
- FOV: 50 degrees
- Target: (-0.1432, 0.2553, 0.0383)
- Tone mapping: ACES Filmic, exposure 1.2

---

## 3. Architecture Overview

```
precompute/          Offline Python/C++ pipeline
  geodesic_tracer    Binet equation geodesic integration (Bruneton method)
  transport_baker    Packs per-ray results into atlas textures
  disk_renderer      Pre-renders polar disk atlas frames
  starfield_gen      Generates layered starfield cubemap/equirect
  manifest_gen       Produces versioned asset manifest

assets/              Built artifacts (gitignored, reproduced from precompute/)
  transport/         Transport atlas maps (4x RGBA16F)
  disk/              Polar disk atlas frames (KTX2)
  starfield/         Layered starfield textures (KTX2)
  poster/            Static fallback images (AVIF/WebP)
  manifest.json      Version + integrity hashes

src/                 Runtime TypeScript + GLSL
  renderer/          WebGL2 compositor shader
  loader/            Manifest-driven async asset loader
  tiers/             Quality tier detection and switching
  post/              Bloom, grading, TAA
  safety/            Headline safe-zone logic
```

---

## 4. Transport Atlas (Offline Precompute)

### 4.1 Per-Ray Fields

For every pixel in the transport atlas, the geodesic tracer computes:

| Field | Type | Description |
|-------|------|-------------|
| bgSourceUV | vec2 | Where this ray lands on the background sky sphere after gravitational deflection |
| capture | float | 0.0 = escapes to infinity, 1.0 = captured by event horizon |
| magnification | float | Gravitational lensing solid-angle ratio (omega_pixel / omega_deflected). Clamped to 1e6 per Bruneton |
| caustic | float | Einstein ring / caustic intensity. High at photon ring, zero elsewhere |
| diskPrimaryUV | vec2 | First disk intersection point in disk-local polar coords (r, phi) |
| diskPrimaryWeight | float | Anti-aliased opacity at first intersection (Bruneton's FilteredPulse) |
| diskPrimaryDoppler | float | Relativistic Doppler factor delta at first intersection |
| diskSecondaryUV | vec2 | Second disk intersection (underside / ghost image through lensing) |
| diskSecondaryWeight | float | Anti-aliased opacity at second intersection |
| diskSecondaryDoppler | float | Doppler factor at second intersection |
| timeDelay | float | Coordinate time offset between ray emission and reception (for disk animation sync) |
| mipBias | float | Suggested MIP level offset based on local magnification gradient |
| motionVector | vec2 | Screen-space velocity for TAA reprojection (post-MVP) |

### 4.2 Map Packing

Four RGBA16F textures at base resolution 1024x1024:

| Map | R | G | B | A |
|-----|---|---|---|---|
| **transport_bg** | bgSourceUV.x | bgSourceUV.y | magnification | capture |
| **transport_disk0** | diskPrimaryUV.x | diskPrimaryUV.y | diskPrimaryWeight | diskPrimaryDoppler |
| **transport_disk1** | diskSecondaryUV.x | diskSecondaryUV.y | diskSecondaryWeight | diskSecondaryDoppler |
| **transport_aux** | caustic | timeDelay | mipBias | motionVector (packed) |

**Format:** Raw binary with Brotli compression for network delivery. Filename pattern: `transport_bg.rgba16f.1024.bin.br`

### 4.3 Geodesic Method

Schwarzschild metric (spin a=0). Binet equation integration following Bruneton:
1. For each pixel direction from locked camera, compute impact parameter e and initial inverse radius u
2. Look up precomputed deflection table D(e, u) -- 512x512 RG32F with nonlinear UV mapping
3. Classify ray: captured (e^2 > mu and u > 2/3), escapes (deflection >= 0), or hits disk (intersection test against equatorial plane)
4. Record all fields above

**Why not Kerr?** Config 3's visual target is achievable with Schwarzschild lensing + art-directed Doppler on the disk material. Kerr adds frame-dragging geodesic complexity for minimal visual payoff at our locked camera angle. The disk's apparent rotation and asymmetry come from the Doppler field baked into the transport atlas, which encodes the *visual effect* of relativistic beaming without requiring Kerr geodesics.

**DECISION NEEDED:** Confirm Schwarzschild-only for MVP. Kerr upgrade path exists (swap geodesic tracer, same atlas format) but doubles precompute complexity.

---

## 5. Disk Material

### 5.1 Strategy: Pre-Rendered Polar Atlas (Primary)

The accretion disk is NOT rendered procedurally at runtime. Instead:

1. **Offline:** Render a polar atlas of the disk in disk-local (r, phi) space. 64 frames, looped, at 512x512 per frame.
2. **Content:** Each frame contains RGB emission + alpha opacity, computed from:
   - Novikov-Thorne radial temperature profile: `T(r) = T_max * (r_isco/r)^0.75 * max(0, 1 - sqrt(r_isco/r))^0.25`
   - Tanner-Helland blackbody approximation for temperature-to-color (validated in steeltroops `blackbody.ts`)
   - 2-octave FBM turbulence with Keplerian rotation: `Omega = sqrt(M) / (r*sqrt(r) + a*sqrt(M))`
   - Height falloff: `exp(-|y| / (r * scaleHeight))`
3. **Runtime:** The shader reads `diskPrimaryUV` from the transport atlas, samples the polar disk atlas at that UV + time-offset from `timeDelay`, applies `diskPrimaryDoppler` for beaming, and composites.

**Beaming model:** `I_observed = I_emitted * delta^3.5` where delta is the Doppler factor from the transport atlas. The 3.5 exponent (not 4.0) follows steeltroops' choice for visual dynamic range stability over strict Liouville compliance.

### 5.2 Fallback: Runtime Procedural (Degraded)

If disk atlas loading fails or for quality tier 2 (video), fall back to a simple runtime procedural:
- Single noise octave, Keplerian rotation, no temperature profile
- Color from brand palette ramp, not blackbody
- No secondary disk intersection

### 5.3 Disk Atlas Asset Spec

| Property | Value |
|----------|-------|
| Resolution | 512x512 per frame |
| Frames | 64 (seamless loop) |
| Format | KTX2/Basis (ETC1S for mobile, UASTC for desktop) |
| Color space | Linear HDR (pre-tonemapped emission) |
| Content | RGB emission, A opacity |
| Loop period | Normalized to orbital period at r=6M (ISCO for a=0) |

---

## 6. Background Starfield

Layered, not monolithic. Each layer has independent parallax depth and MIP treatment.

| Layer | Content | Resolution | MIP | Parallax |
|-------|---------|------------|-----|----------|
| Deep dust | Faint galactic dust, warm nebula glow | 2048x1024 equirect | Trilinear | 0.0 (static) |
| Bright stars | Individual bright stars, point-like | 2048x1024 equirect | Nearest (preserve points) | 0.02 |
| Navigational | Sparse landmark stars, slightly larger | 1024x512 equirect | Nearest | 0.05 |
| Galactic cloud | Large-scale Milky Way structure | 1024x512 equirect | Trilinear | 0.01 |

**Runtime:** The transport atlas `bgSourceUV` tells the shader where each pixel's deflected ray lands on the sky sphere. The shader samples each starfield layer at that UV (with per-layer parallax offset for scroll-driven camera drift) and composites back-to-front.

**Format:** KTX2/Basis. Total budget: ~4MB compressed for all 4 layers.

---

## 7. Brand Palette

All disk emission, bloom, and grading are filtered through this authored palette. No raw blackbody colors reach the screen.

| Name | Hex | Linear RGB | Role |
|------|-----|-----------|------|
| Void Black | #000000 | (0, 0, 0) | Event horizon, deep background |
| Graphite | #2D2A28 | (0.175, 0.162, 0.160) | Disk outer edge, cool emission |
| Authority Gold | #C49A3C | (0.769, 0.604, 0.235) | Disk peak emission, photon ring bloom |
| Arclight White | #FFFFFF | (1, 1, 1) | Photon ring core, brightest caustic |
| Soft Silver | #B8B4B0 | (0.722, 0.706, 0.690) | Star highlights, headline text |
| Ion Blue | #0A69CE | (0.039, 0.412, 0.808) | Environment bottom tint (from Config 3 bottomColor) |

**Application:** A 1D color ramp LUT (256 texels, RGBA8) maps normalized emission intensity to palette color. This is sampled *after* Doppler beaming, *before* tonemapping.

**Source of truth:** Config 3's ramp positions -- rampCol1 at 0.05, rampCol2 at 0.425, rampCol3 at 0.9. Config 3 used pure white ramp (post-eval decision); the palette above restores brand warmth while keeping the white core.

---

## 8. Headline Safety

Text legibility is a **renderer feature**, not a CSS overlay concern.

### 8.1 Safe Zone Definition

```
DOM provides:
  - safeZoneRect: { x, y, width, height } in normalized viewport coords
  - safeZonePadding: float (blur transition width, default 0.08)
```

### 8.2 Renderer Behavior in Safe Zone

1. **Exposure suppression:** Inside the safe zone, multiply final HDR color by `exposureMask = smoothstep(0, padding, distToEdge)`. The center of the headline gets near-zero emission behind it.
2. **Bloom exclusion:** The bloom source texture masks out the safe zone entirely. No bloom bleeds *into* the headline area. Bloom *from* the headline area still contributes outside it.
3. **Caustic suppression:** Caustic/photon-ring intensity is attenuated within the safe zone.

This produces a natural darkened region behind the headline without a visible rectangle or vignette artifact.

---

## 9. Runtime Renderer

### 9.1 Architecture

One full-screen quad, one WebGL2 fragment shader per frame. No scene graph. No mesh.

```
Inputs:
  uniform sampler2D transport_bg;      // RGBA16F
  uniform sampler2D transport_disk0;   // RGBA16F
  uniform sampler2D transport_disk1;   // RGBA16F
  uniform sampler2D transport_aux;     // RGBA16F
  uniform sampler2D diskAtlas;         // KTX2, current + next frame for lerp
  uniform sampler2D starfield[4];      // Layered starfield
  uniform sampler2D paletteLUT;        // Brand color ramp
  uniform sampler2D bloomHalo;         // Precomputed static bloom halo
  uniform vec4 safeZone;              // (x, y, w, h) from DOM
  uniform float safeZonePadding;
  uniform float time;
  uniform float scrollProgress;       // 0-1 scroll position for camera drift

Output: HDR RGBA to framebuffer (tonemapped in post)
```

### 9.2 Shader Pseudocode

```glsl
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;

    // 1. Read transport atlas
    vec4 bg = texture(transport_bg, uv);
    vec4 d0 = texture(transport_disk0, uv);
    vec4 d1 = texture(transport_disk1, uv);
    vec4 aux = texture(transport_aux, uv);

    float captured = bg.a;
    vec2 skyUV = bg.rg;
    float magnification = bg.b;
    float caustic = aux.r;
    float timeDelay = aux.g;
    float mipBias = aux.b;

    // 2. Background: composite starfield layers at deflected UV
    vec3 sky = vec3(0.0);
    if (captured < 0.5) {
        for (int i = 0; i < 4; i++) {
            vec2 layerUV = skyUV + parallaxOffset[i] * scrollProgress;
            sky += texture(starfield[i], layerUV, mipBias + mipOverride[i]).rgb;
        }
        sky *= magnification;
    }

    // 3. Disk: sample polar atlas at transport-mapped UVs
    vec3 color = sky;

    // Secondary disk (behind, composited first)
    if (d1.b > 0.001) { // diskSecondaryWeight
        vec2 diskUV = d1.rg;
        float diskTime = time - timeDelay;
        vec3 diskEmission = sampleDiskAtlas(diskUV, diskTime);
        diskEmission *= pow(d1.a, 3.5); // Doppler beaming
        diskEmission = texture(paletteLUT, vec2(luminance(diskEmission), 0.5)).rgb;
        color = mix(color, diskEmission, d1.b);
    }

    // Primary disk (in front)
    if (d0.b > 0.001) { // diskPrimaryWeight
        vec2 diskUV = d0.rg;
        float diskTime = time - timeDelay;
        vec3 diskEmission = sampleDiskAtlas(diskUV, diskTime);
        diskEmission *= pow(d0.a, 3.5); // Doppler beaming
        diskEmission = texture(paletteLUT, vec2(luminance(diskEmission), 0.5)).rgb;
        color = mix(color, diskEmission, d0.b);
    }

    // 4. Caustic/photon ring additive glow
    color += caustic * PHOTON_RING_COLOR * PHOTON_RING_INTENSITY;

    // 5. Headline safety: suppress exposure in safe zone
    float distToSafe = safeZoneDistance(uv, safeZone);
    float exposureMask = smoothstep(0.0, safeZonePadding, distToSafe);
    color *= exposureMask;

    // 6. Output to HDR framebuffer for post-processing
    fragColor = vec4(color, 1.0);
}
```

### 9.3 Post-Processing Pipeline

Applied after the main composite, before presentation:

1. **Bloom (split strategy):**
   - **Static halo:** Precomputed bloom texture around the photon ring. Added as a screen-space overlay. Zero runtime cost.
   - **Selective runtime bloom:** Small separable Gaussian on pixels exceeding bloom threshold. Masked by headline safe zone.
2. **Tonemapping:** ACES Filmic (matches Config 3), exposure 1.2.
3. **Vignette:** Radial falloff, subtle.
4. **Film grain:** Per-frame noise, very low amplitude (0.02).
5. **Chromatic aberration:** Subtle channel offset near frame edges only.

**TAA (post-MVP):** Temporal anti-aliasing using `motionVector` from `transport_aux`. History clamping with selective weight reduction near disk edges and caustics to prevent ghosting. Requires double-buffering the composite output.

---

## 10. Quality Tiers

| Tier | Name | Trigger | What Renders | GPU Memory |
|------|------|---------|-------------|------------|
| 0 | Poster | `prefers-reduced-motion`, no WebGL2, `Save-Data` header, initial paint | Static AVIF/WebP image. No JS. | 0 |
| 1 | Video | Low-power mobile, WebGL2 present but GPU tier < 2 | Looping MP4/WebM background. CSS-only. | 0 |
| 2 | Live Transport | Mid-range GPU, WebGL2 | Transport atlas + disk atlas + starfield. Primary disk only. No secondary. No TAA. Bloom: static halo only. 512x512 transport maps. | ~8MB |
| 3 | High Cinematic | Desktop GPU, tier >= 3 | Full transport atlas at 1024x1024. Primary + secondary disk. Full starfield layers. Split bloom. TAA with motion vectors. Film grain + chromatic aberration. | ~40MB |

### Tier Detection

```
if (no WebGL2 || prefersReducedMotion || saveData) -> Tier 0
else if (gpuTier < 2 || isMobileLowEnd) -> Tier 1
else if (gpuTier < 3) -> Tier 2
else -> Tier 3
```

GPU tier detection via `detect-gpu` library or equivalent UA + renderer string heuristic.

### Asset Budget per Tier

| Tier | Network Transfer | GPU Memory | Frame Budget |
|------|-----------------|------------|-------------|
| 0 | 50-150KB (poster image) | 0 | N/A |
| 1 | 2-5MB (video) | 0 | N/A |
| 2 | ~4MB (512 transport + disk atlas + starfield) | ~8MB | 8ms (120fps target, allow 16ms) |
| 3 | ~12MB (1024 transport + full disk + full starfield) | ~40MB | 8ms |

---

## 11. View Slices (Post-MVP)

For scroll-driven camera variation, precompute 4-16 view slices of the transport atlas at different camera angles along a predetermined scroll path. At runtime, interpolate between adjacent slices based on scroll position.

**MVP:** 1 view slice (Config 3 camera, fixed). Scroll drives only parallax offsets on starfield layers.

**Post-MVP:** 4 slices minimum for smooth scroll-driven camera orbit. Each slice is a full set of 4 transport maps. Network budget: 4x the transport atlas size.

**DECISION NEEDED:** How aggressive should scroll-driven camera motion be? Subtle parallax (current plan) vs. significant orbital camera change?

---

## 12. Asset Model

### 12.1 Manifest

`assets/manifest.json`:
```json
{
  "version": "1.0.0",
  "generated": "2026-06-17T00:00:00Z",
  "assets": {
    "transport_bg": {
      "path": "transport/transport_bg.rgba16f.1024.bin.br",
      "format": "RGBA16F",
      "resolution": [1024, 1024],
      "hash": "sha256:...",
      "sizeBytes": 0
    },
    ...
  },
  "tiers": {
    "2": ["transport_bg_512", "transport_disk0_512", "disk_atlas_32", "starfield_deep", "starfield_bright"],
    "3": ["transport_bg", "transport_disk0", "transport_disk1", "transport_aux", "disk_atlas_64", "starfield_deep", "starfield_bright", "starfield_nav", "starfield_cloud"]
  }
}
```

### 12.2 Format Summary

| Asset Class | Format | Compression |
|-------------|--------|-------------|
| Transport maps | Raw RGBA16F binary | Brotli (.bin.br) |
| Disk atlas frames | KTX2/Basis | ETC1S (mobile) / UASTC (desktop) |
| Starfield layers | KTX2/Basis | ETC1S / UASTC |
| Brand palette LUT | Raw RGBA8 binary | Brotli |
| Static bloom halo | KTX2/Basis | UASTC |
| Poster fallback | AVIF (primary), WebP (fallback) | Native |
| Video fallback | MP4 (H.265), WebM (VP9) | Native |

### 12.3 Build Pipeline

```bash
# Full rebuild
python precompute/build.py --config eval/benchmark-config-3.json --resolution 1024

# Outputs to assets/ with manifest
# Artifacts are gitignored; CI rebuilds from precompute/ source
```

---

## 13. Implementation Tracks

### Track 1: Geodesic Tracer + Transport Atlas Baker

**Deliverable:** Python/C++ tool that reads Config 3 camera params, traces geodesics via Bruneton's method, and outputs the 4 packed RGBA16F transport maps.

**Acceptance Criteria:**
- [ ] Reads camera config from benchmark-config-3.json
- [ ] Produces transport_bg, transport_disk0, transport_disk1, transport_aux at 1024x1024
- [ ] bgSourceUV is invertible: sampling a known-grid background through the atlas reproduces Bruneton's reference lensing pattern
- [ ] capture field produces a clean event horizon silhouette with feathered edge
- [ ] magnification field shows amplification peak at the photon ring (r = 1.5 * rs)
- [ ] caustic field peaks at Einstein ring location
- [ ] diskPrimaryUV/Weight correctly identifies equatorial plane intersections within [r_isco, r_outer]
- [ ] Doppler factors are physically plausible: approaching limb > 1.0, receding limb < 1.0
- [ ] Output matches Bruneton reference within 1% for bgSourceUV on a known test case

### Track 2: Disk Material Atlas

**Deliverable:** Pre-rendered 64-frame polar disk atlas in KTX2 format.

**Acceptance Criteria:**
- [ ] Novikov-Thorne temperature profile matches steeltroops' implementation
- [ ] Tanner-Helland blackbody matches steeltroops' `blackbody()` function output
- [ ] Keplerian rotation at correct angular velocity per radius
- [ ] FBM turbulence produces plausible filamentary structure
- [ ] 64 frames loop seamlessly (frame 0 == frame 64)
- [ ] Palette LUT applied: output emission maps through brand color ramp
- [ ] ISCO inner edge is clean (no rendering inside ISCO)

### Track 3: Runtime Compositor Shader

**Deliverable:** WebGL2 full-screen shader that reads transport atlas + disk atlas + starfield and composites the final image.

**Acceptance Criteria:**
- [ ] Correctly samples all 4 transport maps
- [ ] Disk compositing respects front-to-back order (secondary behind primary)
- [ ] Doppler beaming applied with delta^3.5
- [ ] Brand palette LUT colors disk emission
- [ ] Headline safe zone suppresses exposure correctly
- [ ] Static bloom halo composited
- [ ] Tonemapping matches Config 3 (ACES Filmic, 1.2 exposure)
- [ ] Frame time < 8ms on reference GPU (RTX 3060 or equivalent)
- [ ] No visible banding in dark regions (test with calibrated monitor)

### Track 4: Quality Tiers + Asset Loader

**Deliverable:** Tier detection, manifest-driven loading, and graceful degradation.

**Acceptance Criteria:**
- [ ] Tier 0: poster image displays within 200ms of first paint, no JS required
- [ ] Tier 1: video background plays, no WebGL initialized
- [ ] Tier 2: 512x512 transport loads and renders correctly
- [ ] Tier 3: full 1024x1024 transport + all features
- [ ] Tier upgrade: if device exceeds tier 2 threshold mid-session (unlikely but handle), do NOT hot-swap -- stay at detected tier
- [ ] Asset loading is non-blocking: poster shows first, WebGL takes over when ready
- [ ] Manifest integrity: loader verifies SHA-256 hash before GPU upload

### Track 5: Starfield + Post-Processing

**Deliverable:** Layered starfield asset pipeline + runtime post-processing.

**Acceptance Criteria:**
- [ ] 4 starfield layers render at correct parallax depths
- [ ] Point stars remain sharp (nearest-neighbor MIP on bright star layer)
- [ ] Nebula dust is soft (trilinear on dust layer)
- [ ] Split bloom: static halo + selective runtime bloom
- [ ] Vignette, grain, chromatic aberration all toggleable
- [ ] Total post-processing < 2ms additional frame time

---

## 14. MVP Scope

### MVP Includes

- 1 view slice (Config 3 camera, fixed)
- 1024x1024 transport atlas (all 4 maps)
- Primary disk only (transport_disk0). No secondary disk.
- 64-frame disk polar atlas
- 2 starfield layers (deep dust + bright stars)
- Basic TAA: OFF for MVP (no motion vectors needed)
- Static bloom halo, no runtime selective bloom
- Headline safe zone
- Brand palette LUT
- Tier 0 (poster) + Tier 2 (live transport) only
- Tonemapping + vignette in post. No grain, no chromatic aberration.

### MVP Excludes (Post-MVP, Tracked)

| Feature | Rationale | Dependency |
|---------|-----------|------------|
| Secondary disk (transport_disk1) | Visual refinement, not hero impact | Track 1 already produces the data |
| TAA with motion vectors | Requires double-buffering, complexity | motionVector field in transport_aux |
| Selective runtime bloom | Static halo sufficient for MVP | Post pipeline extension |
| View slices (scroll camera) | Scroll parallax on starfield is sufficient | Transport atlas x4-16 |
| Tier 1 (video fallback) | Tier 0 poster covers non-WebGL; video is polish | Video encode pipeline |
| Tier 3 (high cinematic) | Tier 2 at 1024 is the full experience for MVP | All tracks |
| Navigational + galactic cloud starfield layers | 2 layers sufficient for depth | Asset pipeline |
| Film grain + chromatic aberration | Post-processing polish | Trivial to add |
| Dust particles (foreground) | Nice-to-have, not load-bearing | Particle system or texture |
| Kerr metric geodesics | Schwarzschild sufficient for locked camera | Tracer rewrite |

---

## 15. Decisions (Resolved 2026-06-17)

1. **Schwarzschild (a=0).** MisterPrada's original used approximate 1/r^2, not real geodesics. Schwarzschild gives real photon sphere, Einstein ring, and correct disk lensing at half the complexity of Kerr. Kerr upgrade path preserved — same atlas format, swap geodesic tracer.

2. **4 view slices, default to subtle parallax.** Scroll intensity is a runtime parameter. Preset 1 = subtle starfield shift. Full range available up to moderate orbital camera change.

3. **Pre-rendered polar atlas for disk material.** 64-frame looped disk texture rendered offline. No runtime procedural noise. Cinematic quality, no boiling.

4. **Secondary disk included in MVP.** One extra texture read. High visual value — the lensed underside is what makes it look real.

5. **Poster is a screenshot of the Tier 2 renderer** once built.

---

## 16. Reference Implementations

| Source | What We Use | License |
|--------|------------|---------|
| Bruneton `black_hole_shader` | Geodesic method: deflection table D(e,u), nonlinear UV mapping, constant-time ray classification, anti-aliased disk intersection via FilteredPulse. Specifically: `definitions.glsl` texture dimensions (512x512 deflection, 64x32 inverse radius), `functions.glsl` lookup functions, `model.glsl` scene compositor structure. | BSD-3 |
| Steeltroops | Disk physics: Kerr Keplerian omega, Novikov-Thorne temperature, Tanner-Helland blackbody, delta^3.5 beaming, 2-octave FBM noise. We adapt the disk rendering approach but precompute it into a polar atlas instead of runtime ray-marching. | Eval reference only |
| MisterPrada (Config 3) | Camera composition and visual tuning parameters. The runtime shader approach (TSL ray-march on sphere geometry) is explicitly NOT what we're building -- we replace that with transport-atlas lookup. | Eval reference only |

---

## 17. Invariants

These are preserved throughout implementation. Violating any of these requires spec amendment:

1. **No runtime ray marching.** The transport atlas eliminates per-pixel geodesic computation. If a feature requires runtime ray tracing, it belongs in precompute.
2. **No full-screen displacement sequences.** The lensing field is local and static per view slice. It does not vary per frame.
3. **Camera is locked per view slice.** Precomputed transport is only valid for the camera it was computed from.
4. **Disk emission goes through brand palette.** Raw blackbody / raw physics colors never reach the screen.
5. **Headline safety is a renderer feature.** It is not achievable via CSS alone because bloom and caustics bleed.
6. **WebGL2 baseline.** No WebGPU requirement. No Three.js dependency. Vanilla WebGL2 + custom shaders.
7. **Asset manifest governs loading.** The loader never hardcodes paths or assumes asset existence.
8. **Tier detection is one-shot.** No mid-session tier switching.
