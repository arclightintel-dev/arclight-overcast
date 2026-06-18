// Arclight Labs — "Singularity" black hole, REAL TSL shader on three/webgpu.
// Lifts MisterPrada/singularity BlackHole.js colorNode + TSL-utils helpers verbatim,
// stripped of the Experience framework. Driven by the user's captured config.
// Exposes window.ArclightBH.start(opts) (drop-in compatible with the GLSL fallback).
//
// Requires an import map mapping "three/webgpu" and "three/tsl" to a single CDN build.

import * as THREE from 'https://esm.sh/three@0.180.0/webgpu';
import {
  Fn, If, Loop, uniform, color, float, vec2, vec3, vec4, mat3,
  sin, cos, floor, fract, dot, pow, add, sub, mul, mix, step, clamp, max, abs,
  texture, time, positionGeometry, positionWorld, cameraPosition, modelWorldMatrix,
  faceDirection, normalize, remapClamp
} from 'https://esm.sh/three@0.180.0/tsl';

/* ---------- TSL-utils helpers (verbatim from the repo) ---------- */
const lengthSqrt = Fn(([v]) => v.x.mul(v.x).add(v.y.mul(v.y)).add(v.z.mul(v.z)).sqrt());

const whiteNoise2D = (coord) => fract(sin(dot(coord, vec2(12.9898, 78.233))).mul(43758.5453));

const vecToFac = Fn(([vector]) =>
  vector.r.mul(0.2126).add(vector.g.mul(0.7152)).add(vector.b.mul(0.0722)).toVar());

const smoothRange = Fn(([value, inMin, inMax, outMin, outMax]) => {
  const t = clamp(value.sub(inMin).div(inMax.sub(inMin)), 0.0, 1.0);
  const smoothT = t.mul(t).mul(float(3.0).sub(t.mul(2.0)));
  return mix(outMin, outMax, smoothT);
}, { value: 'float', inMin: 'float', inMax: 'float', outMin: 'float', outMax: 'float', return: 'float' });

const rotateAxis = Fn(([axis_immutable, angle_immutable]) => {
  const angle = float(angle_immutable).toVar();
  const axis = vec3(axis_immutable).toVar();
  const s = float(sin(angle)).toVar();
  const c = float(cos(angle)).toVar();
  const oc = float(sub(1.0, c)).toVar();
  return mat3(
    oc.mul(axis.x).mul(axis.x).add(c),
    oc.mul(axis.x).mul(axis.y).sub(axis.z.mul(s)),
    oc.mul(axis.z).mul(axis.x).add(axis.y.mul(s)),
    oc.mul(axis.x).mul(axis.y).add(axis.z.mul(s)),
    oc.mul(axis.y).mul(axis.y).add(c),
    oc.mul(axis.y).mul(axis.z).sub(axis.x.mul(s)),
    oc.mul(axis.z).mul(axis.x).sub(axis.y.mul(s)),
    oc.mul(axis.y).mul(axis.z).add(axis.x.mul(s)),
    oc.mul(axis.z).mul(axis.z).add(c)
  );
}).setLayout({ name: 'rotateAxis', type: 'mat3', inputs: [{ name: 'axis', type: 'vec3' }, { name: 'angle', type: 'float' }] });

const srgbToLinear = Fn(([rgb]) =>
  mix(rgb.div(12.92), pow(add(rgb, 0.055).div(1.055), vec3(2.4)), step(0.04045, rgb)));

const linearToSrgb = Fn(([lin]) => {
  const low = lin.mul(12.92);
  const high = pow(lin, vec3(1.0 / 2.4)).mul(1.055).sub(0.055);
  return mix(low, high, step(0.0031308, lin));
});

const CatmulRom = Fn(([T, D, C, B, A]) =>
  mul(0.5, mul(2.0, B)
    .add(A.negate().add(C).mul(T))
    .add(mul(2.0, A).sub(mul(5.0, B)).add(mul(4.0, C)).sub(D).mul(T).mul(T))
    .add(A.negate().add(mul(3.0, B)).sub(mul(3.0, C)).add(D).mul(T).mul(T).mul(T))));

const ColorRamp3_BSpline = Fn(([T, A, B, C]) => {
  const AB = B.w.sub(A.w);
  const BC = C.w.sub(B.w);
  const iAB = T.sub(A.w).div(AB).saturate();
  const iBC = T.sub(B.w).div(BC).saturate();
  const p = vec3(sub(1.0, iAB), iAB.sub(iBC), iBC);
  const cA = CatmulRom(p.x, A.xyz, A.xyz, B.xyz, C.xyz);
  const cB = CatmulRom(p.y, A.xyz, B.xyz, C.xyz, C.xyz);
  const cC = C.xyz;
  If(T.lessThan(B.w), () => { return cA.xyz; });
  If(T.lessThan(C.w), () => { return cB.xyz; });
  return cC.xyz;
}, { T: 'float', A: 'vec4', B: 'vec4', C: 'vec4', return: 'vec3' });

/* ---------- defaults (user's captured config) ---------- */
const CFG = {
  iterations: 1230, stepSize: 0.0005, noiseFactor: 0.0022, power: 0.36,
  originRadius: 0.15, width: 0.027,
  rampCol1: [1, 1, 1], rampPos1: 0.076,
  rampCol2: [0.10390625, 0.10875211, 0.125], rampPos2: 0.359,
  rampCol3: [0, 0, 0], rampPos3: 0.598,
  rampEmission: 1.5, emissionColor: [0.2, 0.2, 0.2],
  topColor: [0, 0, 0], bottomColor: [0, 0, 0], bgIntensity: 2.8,
  exposure: 1.2, pixelRatio: 1.0, fov: 50,
  camDefault: [0.16, 0.037, 0.546], targetDefault: [-0.1432, 0.2553, 0.0383],
  camFinal: [-0.3696, 0.037, 0.4326], targetFinal: [-0.1104, 0.2553, -0.0989],
  cam2: [0.44, 0.16, -0.34], target2: [-0.02, 0.14, 0.06],
  orbitSpeed: 0.007
};

function cl(v, a, b) { return Math.max(a, Math.min(b, v)); }

// Procedural value-noise fallback (used only if the noise PNG fails to load),
// so the shader always has a valid, non-null texture to sample.
function makeNoiseTexture(THREEns, size) {
  const data = new Uint8Array(size * size * 4);
  for (let i = 0; i < size * size; i++) {
    const v = Math.floor(Math.random() * 256);
    data[i * 4] = v; data[i * 4 + 1] = Math.floor(Math.random() * 256);
    data[i * 4 + 2] = Math.floor(Math.random() * 256); data[i * 4 + 3] = 255;
  }
  const tex = new THREEns.DataTexture(data, size, size, THREEns.RGBAFormat);
  tex.needsUpdate = true;
  return tex;
}
function lerp(a, b, t) { return a + (b - a) * t; }
function lerp3(a, b, t) { return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)]; }
function eIO(p) { return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2; }
function eOut(p) { return 1 - Math.pow(1 - p, 3); }

class Singularity {
  constructor(opts) {
    this.canvas = opts.canvas;
    this.logo = opts.logo || null;
    this.revealEls = opts.revealEls || [];
    this.zEl = opts.zEl || null;
    this.getScroll = opts.getScroll || (() => 0);
    this.onReady = opts.onReady || null;
    const p = opts.props || {};
    this.opt = {
      exposure: p.exposure != null ? p.exposure : CFG.exposure,
      iterations: p.iterations != null ? p.iterations : CFG.iterations,
      discBright: p.discBrightness != null ? p.discBrightness : 1,
      morph: p.morphSpeed != null ? p.morphSpeed : 1
    };
    this.reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.startT = 0; this.last = 0; this.scrollY = 0; this.orbit = 0;
    this.hold = 0.25;
    this.morph = 3.6 / (this.opt.morph || 1);
    this.revealAt = this.hold + this.morph * 0.62;
    this._init();
  }

  async _init() {
    const THREEns = THREE;
    window.__singInst = this;
    // Force the WebGL2 backend: same TSL shader (compiles to GLSL), but WebGL2
    // compositing presents reliably in every preview/embedding context, whereas
    // the WebGPU swapchain silently fails to present in some panes.
    const renderer = this.renderer = new THREEns.WebGPURenderer({ canvas: this.canvas, antialias: true, alpha: false, forceWebGL: true, powerPreference: 'high-performance' });
    renderer.setPixelRatio(this._calcPixelRatio());
    renderer.setSize(window.innerWidth, window.innerHeight, false);
    renderer.toneMapping = THREEns.ACESFilmicToneMapping;
    renderer.toneMappingExposure = this.opt.exposure;
    renderer.setClearColor(0x000000, 1);
    try { await renderer.init(); } catch (e) { console.warn('[Singularity/GPU] init failed', e); this._failed = true; throw e; }

    const scene = this.scene = new THREEns.Scene();
    const cam = this.camera = new THREEns.PerspectiveCamera(CFG.fov, window.innerWidth / window.innerHeight, 0.1, 2000);
    cam.position.set.apply(cam.position, CFG.camDefault);
    cam.lookAt(new THREEns.Vector3().fromArray(CFG.targetDefault));

    // noise texture — MUST be fully loaded before first render: the WebGL2
    // backend throws ("texture.image is null") if asked to upload a not-yet-
    // loaded image, which silently blacks out the whole canvas. We await it,
    // and fall back to procedurally generated noise if the PNG fails.
    let noiseTex;
    try {
      noiseTex = await new THREEns.TextureLoader().loadAsync('./static/textures/noise_deep.png');
    } catch (e) {
      console.warn('[Singularity/GPU] noise PNG failed, using generated noise', e);
      noiseTex = makeNoiseTexture(THREEns, 256);
    }
    noiseTex.wrapS = noiseTex.wrapT = THREEns.RepeatWrapping;
    noiseTex.colorSpace = THREEns.NoColorSpace;
    noiseTex.needsUpdate = true;

    // uniforms
    const U = this.U = {
      stepSize: uniform(float(CFG.stepSize)),
      noiseFactor: uniform(float(CFG.noiseFactor)),
      power: uniform(float(CFG.power)),
      originRadius: uniform(float(CFG.originRadius)),
      width: uniform(float(CFG.width)),
      iterations: uniform(float(this.opt.iterations)),
      rampCol1: uniform(color(...CFG.rampCol1)), rampPos1: uniform(float(CFG.rampPos1)),
      rampCol2: uniform(color(...CFG.rampCol2)), rampPos2: uniform(float(CFG.rampPos2)),
      rampCol3: uniform(color(...CFG.rampCol3)), rampPos3: uniform(float(CFG.rampPos3)),
      rampEmission: uniform(float(CFG.rampEmission)),
      emissionColor: uniform(color(...CFG.emissionColor)),
      topColor: uniform(color(...CFG.topColor)),
      bottomColor: uniform(color(...CFG.bottomColor)),
      bgIntensity: uniform(float(CFG.bgIntensity)),
      discB: uniform(float(0))
    };

    const envGrad = (dir) => {
      const f = clamp(dir.y.mul(0.5).add(0.5), 0.0, 1.0);
      return mix(U.bottomColor, U.topColor, f).mul(U.bgIntensity);
    };

    const geometry = new THREEns.SphereGeometry(1, 16, 16);
    const material = new THREEns.MeshStandardNodeMaterial({ side: THREEns.DoubleSide });

    material.colorNode = Fn(() => {
      const _step = U.stepSize;
      const noiseAmp = U.noiseFactor;
      const power = U.power;
      const originRadius = U.originRadius;
      const bandWidth = U.width;
      const iterCount = U.iterations;

      const objCoords = positionGeometry.mul(vec3(1, 1, -1)).xzy;
      const isBackface = step(0.0, faceDirection.negate());
      const camPointObj = cameraPosition.mul(modelWorldMatrix).mul(vec3(1, 1, -1)).xzy;
      const startCoords = mix(objCoords, camPointObj.xyz, isBackface);
      const viewInWorld = normalize(sub(cameraPosition, positionWorld)).mul(vec3(1, 1, -1)).xzy;
      const rayDir = viewInWorld.negate().toVar();
      const noiseWhite = whiteNoise2D(objCoords.xy).mul(noiseAmp);
      const jitter = rayDir.mul(noiseWhite);
      const rayPos = startCoords.sub(jitter).toVar();
      const colorAcc = vec3(0).toVar();
      const alphaAcc = float(0.0).toVar();

      Loop(iterCount, () => {
        const rNorm = normalize(rayPos);
        const rLen = lengthSqrt(rayPos);
        const steerMag = _step.mul(power).div(rLen.mul(rLen));
        const range = remapClamp(rLen, 1.0, 0.5, 0.0, 1.0);
        const steer = rNorm.mul(steerMag.mul(range));
        const steeredDir = rayDir.sub(steer).normalize();
        const advance = rayDir.mul(_step);
        rayPos.addAssign(advance);

        const xyLen = lengthSqrt(rayPos.mul(vec3(1, 1, 0)));
        const rotPhase = xyLen.mul(4.270).sub(time.mul(0.1));
        const uvRot = rayPos.mul(rotateAxis(vec3(0, 0, 1), rotPhase));
        const uv = uvRot.mul(2);
        const noiseDeep = texture(noiseTex, uv);

        const bandEnds = vec3(bandWidth.negate(), 0.0, bandWidth);
        const dz = sub(bandEnds, vec3(rayPos.z));
        const zQuad = dz.mul(dz).div(bandWidth);
        const zBand = max(bandWidth.sub(zQuad).div(bandWidth), 0.0);
        const noiseAmp3 = noiseDeep.mul(zBand);
        const noiseAmpLen = lengthSqrt(noiseAmp3);
        const noiseNormal = texture(noiseTex, uv.mul(1.002)).mul(zBand);
        const noiseNormalLen = lengthSqrt(noiseNormal);

        const rampInput = xyLen.add(noiseAmpLen.sub(0.780).mul(1.5)).add(noiseAmpLen.sub(noiseNormalLen).mul(19.750));
        const rampA = vec4(U.rampCol1, U.rampPos1);
        const rampB = vec4(U.rampCol2, U.rampPos2);
        const rampC = vec4(U.rampCol3, U.rampPos3);
        const baseCol = ColorRamp3_BSpline(rampInput, rampA, rampB, rampC);
        const emissiveCol = baseCol.mul(U.rampEmission).add(U.emissionColor);

        const insideCore = lengthSqrt(rayPos).lessThan(originRadius);
        const shadedCol = mix(emissiveCol, vec3(0), insideCore);

        const zAbs = abs(rayPos.z);
        const aNoise = noiseAmpLen.sub(0.750).mul(-0.60);
        const aPre = zAbs.add(aNoise);
        const aRadial = smoothRange(xyLen, 1.0, 0.0, 0.0, 1.0);
        const aBand = smoothRange(aPre, bandWidth, 0.0, 0.0, aRadial);
        const alphaLocal = mix(aBand, 1.0, insideCore);

        const weight = alphaAcc.oneMinus().mul(vecToFac(alphaLocal));
        const newColor = mix(colorAcc, shadedCol, weight);
        const newAlpha = mix(alphaAcc, 1.0, vecToFac(alphaLocal));

        rayPos.addAssign(advance);
        rayDir.assign(steeredDir);
        colorAcc.assign(newColor);
        alphaAcc.assign(newAlpha);
      });

      const dirForEnv = rayDir.mul(vec3(1, -1, 1)).xzy;
      const env = linearToSrgb(envGrad(dirForEnv));
      const trans = float(1.0).sub(alphaAcc);
      const finalRGB = mix(colorAcc, env, trans).mul(U.discB);
      return srgbToLinear(finalRGB);
    })();
    material.emissiveNode = material.colorNode;

    const mesh = new THREEns.Mesh(geometry, material);
    scene.add(mesh);

    if (this.reduced) this.revealEls.forEach(e => e.style.opacity = 1);
    if (this.logo) this.logo.style.display = 'none';

    this._resize = () => {
      renderer.setPixelRatio(this._calcPixelRatio());
      renderer.setSize(window.innerWidth, window.innerHeight, false);
      cam.aspect = window.innerWidth / window.innerHeight;
      cam.updateProjectionMatrix();
    };
    this._scroll = () => { this.scrollY = this.getScroll(); };
    window.addEventListener('resize', this._resize);
    window.addEventListener('scroll', this._scroll, { passive: true });
    this._resize();

    // Render loop: capped at 30fps (the disc flows slowly — 30fps is visually
    // identical to 60 and halves GPU cost) and gated to "visible" — it only
    // renders while the canvas is on-screen AND the tab is foregrounded. When
    // paused, the WebGL canvas retains its last presented frame (a free freeze),
    // so the GPU goes fully idle while the disc stays on screen.
    this._minDelta = 1000 / 30 - 3;
    this._lastRender = -1e9;
    this._inView = true;
    this._tabVisible = !document.hidden;
    this._firstFrameDone = false;
    this._running = false;

    const loop = async (t) => {
      if (!this._running) return;
      if (t - this._lastRender >= this._minDelta) {
        this._lastRender = t;
        try {
          this._update(t);
          await this.renderer.renderAsync(this.scene, this.camera);
          if (!this._firstFrameDone) {
            this._firstFrameDone = true;
            if (this.onReady) { try { this.onReady(); } catch (e) {} }
          }
        } catch (e) { console.error('[Singularity/GPU] render error', e); }
      }
      this._raf = requestAnimationFrame(loop);
    };
    this._startLoop = () => { if (this._running) return; this._running = true; this._raf = requestAnimationFrame(loop); };
    this._stopLoop = () => { this._running = false; if (this._raf) cancelAnimationFrame(this._raf); };
    this._sync = () => {
      const shouldRun = this._inView && this._tabVisible;
      if (shouldRun) this._startLoop();
      else this._stopLoop();
    };

    // Hero copy reveal — driven on its OWN rAF, fully independent of the GPU
    // render loop, so the headline/subcopy/CTAs always appear even if the loop
    // is gated off (off-screen / background tab).
    if (this.revealEls && this.revealEls.length) {
      if (this.reduced) {
        this.revealEls.forEach((el) => { el.style.opacity = '1'; el.style.filter = 'none'; });
      } else {
        const rStart = performance.now();
        const tick = (t) => {
          const elapsed = (t - rStart) / 1000;
          let allDone = true;
          for (let i = 0; i < this.revealEls.length; i++) {
            const pr = cl((elapsed - 0.15 - i * 0.12) / 0.9, 0, 1);
            const e = eOut(pr);
            this.revealEls[i].style.opacity = e.toFixed(3);
            this.revealEls[i].style.filter = e < 0.999 ? 'blur(' + ((1 - e) * 4).toFixed(2) + 'px)' : 'none';
            if (pr < 1) allDone = false;
          }
          if (!allDone) this._revealRaf = requestAnimationFrame(tick);
        };
        this._revealRaf = requestAnimationFrame(tick);
      }
    }

    // Visibility gate (deterministic — no IntersectionObserver, which is flaky
    // for a fixed-position canvas inside a transformed/scaled container). The
    // hero canvas is full-screen fixed, so it's visible until scrolled roughly
    // one viewport past, and whenever the tab is foregrounded.
    this._computeInView = () => { this._inView = this.getScroll() < window.innerHeight * 3.0; };
    this._vis = () => { this._tabVisible = !document.hidden; this._sync(); };
    this._gateScroll = () => { this._computeInView(); this._sync(); };
    document.addEventListener('visibilitychange', this._vis);
    window.addEventListener('scroll', this._gateScroll, { passive: true });
    this._computeInView();
    this._startLoop();
  }

  _calcPixelRatio() {
    // Render at native resolution (supersampled vs the old 0.75×) so the disc's
    // fine filaments stay crisp instead of aliasing into harsh grain on large
    // screens. Clamp backing width to bound GPU cost.
    return Math.min(window.devicePixelRatio || 1, 1.5) * CFG.pixelRatio;
  }

  stop() {
    this._stopLoop();
    if (this._revealRaf) cancelAnimationFrame(this._revealRaf);
    if (this._vis) document.removeEventListener('visibilitychange', this._vis);
    if (this._gateScroll) window.removeEventListener('scroll', this._gateScroll);
    window.removeEventListener('resize', this._resize);
    window.removeEventListener('scroll', this._scroll);
  }

  setProps(p) {
    if (!p || !this.U) return;
    if (p.exposure != null && this.renderer) { this.opt.exposure = p.exposure; this.renderer.toneMappingExposure = p.exposure; }
    if (p.iterations != null) { this.opt.iterations = p.iterations; this.U.iterations.value = p.iterations; }
    if (p.discBrightness != null) this.opt.discBright = p.discBrightness;
    if (p.morphSpeed != null) this.morph = 3.6 / (p.morphSpeed || 1);
  }

  _update(now) {
    if (!this.U) return;
    if (!this.startT) this.startT = now;
    if (!this.last) this.last = now;
    let dt = (now - this.last) / 1000; this.last = now;
    if (dt > 0.05) dt = 0.05;
    const elapsed = (now - this.startT) / 1000;

    const maxScroll = document.documentElement.scrollHeight - window.innerHeight;
    const t = maxScroll > 0 ? cl(this.scrollY / maxScroll, 0, 1) : 0;
    const camT = cl((t - 0.25) / 0.4, 0, 1);
    const blend = camT * camT * (3 - 2 * camT);

    const cam = lerp3(CFG.camFinal, CFG.cam2, blend);
    const tgt = lerp3(CFG.targetFinal, CFG.target2, blend);
    this.camera.position.set(cam[0], cam[1], cam[2]);
    this.camera.lookAt(tgt[0], tgt[1], tgt[2]);

    this.U.discB.value = this.opt.discBright;

    if (this.logo && this.logo.style.display !== 'none') this.logo.style.display = 'none';

    if (this.zEl) this.zEl.textContent = 'Z  ' + (0.0341 + 0.0009 * Math.sin(elapsed * 0.6)).toFixed(4);
  }
}

window.ArclightBH = {
  start(opts) { return new Singularity(opts); }
};
