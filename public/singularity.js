/* Arclight Labs — "Singularity" black hole.
   Faithful WebGL port of MisterPrada/singularity BlackHole.js (TSL/WebGPU) using
   config-3 (FINAL): danger-close equatorial, white ramp, black->deep-blue gradient env,
   ACES filmic, exposure 1.2. Volumetric ray-march of a noise-textured thin accretion
   disc with mild ray-bending and a dark core.
   API:  window.ArclightBH.start(opts) -> instance   (drop-in compatible).
*/
(function () {
  'use strict';

  // ---- config 3 (FINAL) ----
  var CFG = {
    stepSize: 0.0005,
    noiseFactor: 0.0022,
    power: 0.36,
    originRadius: 0.15,
    width: 0.027,
    rampCol1: [1.0, 1.0, 1.0],        rampPos1: 0.076,
    rampCol2: [0.10390625, 0.10875211, 0.125], rampPos2: 0.359,
    rampCol3: [0.0, 0.0, 0.0],        rampPos3: 0.598,
    rampEmission: 1.5,
    emissionColor: [0.2, 0.2, 0.2],
    topColor: [0.0, 0.0, 0.0],
    bottomColor: [0.0, 0.0, 0.0],
    bgIntensity: 2.8,
    exposure: 1.2,
    // shader-space (world Y -> shader Z): world camFinal (-0.3696,0.037,0.4326)
    camFinal: [-0.3696, -0.4326, 0.037],
    targetFinal: [-0.1104, 0.0989, 0.2553],
    fov: 50
  };

  function v3(a){ return [a[0],a[1],a[2]]; }
  function lerp3(a,b,t){ return [a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t]; }

  function BH(opts) {
    this.canvas = opts.canvas;
    this.logo = opts.logo || null;
    this.revealEls = opts.revealEls || [];
    this.zEl = opts.zEl || null;
    this.getScroll = opts.getScroll || function () { return 0; };
    var p = opts.props || {};
    this.opt = {
      exposure: p.exposure != null ? p.exposure : CFG.exposure,
      iterations: p.iterations != null ? p.iterations : 1100,
      discBright: p.discBrightness != null ? p.discBrightness : 1,
      morph: p.morphSpeed != null ? p.morphSpeed : 1,
      quality: p.quality != null ? p.quality : 1.0
    };
    this.reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.start = 0; this.last = 0; this.scrollY = 0; this.spin = 0;
    if (!this.initGL()) { this.canvas.style.background = '#000'; return; }

    var self = this;
    this._resize = function () { self.resize(); };
    this._scroll = function () { self.scrollY = self.getScroll(); };
    window.addEventListener('resize', this._resize);
    window.addEventListener('scroll', this._scroll, { passive: true });
    this.resize();

    this.hold = 0.25;
    this.morph = 3.4 / (this.opt.morph || 1);
    this.revealAt = this.hold + this.morph * 0.6;
    if (this.reduced) this.revealEls.forEach(function (e) { e.style.opacity = 1; });

    this.loop = function (t) { self.frame(t); self.raf = requestAnimationFrame(self.loop); };
    this.raf = requestAnimationFrame(this.loop);
  }

  BH.prototype.stop = function () {
    cancelAnimationFrame(this.raf);
    window.removeEventListener('resize', this._resize);
    window.removeEventListener('scroll', this._scroll);
  };
  BH.prototype.setProps = function (p) {
    if (!p) return;
    if (p.exposure != null) this.opt.exposure = p.exposure;
    if (p.iterations != null) this.opt.iterations = p.iterations;
    if (p.discBrightness != null) this.opt.discBright = p.discBrightness;
    if (p.morphSpeed != null) this.opt.morph = p.morphSpeed;
    if (p.quality != null) { this.opt.quality = p.quality; this.resize(); }
  };

  BH.prototype.initGL = function () {
    var gl = this.canvas.getContext('webgl', { antialias: false, alpha: false, premultipliedAlpha: false, powerPreference: 'high-performance' })
      || this.canvas.getContext('experimental-webgl');
    if (!gl) { console.warn('[Singularity] WebGL unavailable'); return false; }
    this.gl = gl;

    var vs = 'attribute vec2 aPos; void main(){ gl_Position = vec4(aPos,0.0,1.0); }';
    var fs = [
      'precision highp float;',
      'uniform vec2 uRes; uniform float uTime,uExposure,uDiscB,uReveal,uTanFov,uAspect,uSpin;',
      'uniform vec3 uCam,uFwd,uRight,uUp;',
      'uniform sampler2D uNoise;',
      'uniform float uStep,uNoiseF,uPower,uOrigin,uWidth,uEmis; uniform int uIter;',
      'uniform vec3 uR1,uR2,uR3,uEmisCol,uTop,uBot; uniform float uP1,uP2,uP3,uBg;',

      // --- helpers ---
      'vec3 catmull(float T, vec3 D, vec3 C, vec3 B, vec3 A){',
      '  return 0.5*( 2.0*B + (-A + C)*T + (2.0*A -5.0*B +4.0*C - D)*T*T + (-A +3.0*B -3.0*C + D)*T*T*T );',
      '}',
      'vec3 ramp3(float T){',
      '  float AB=uP2-uP1, BC=uP3-uP2;',
      '  float iAB=clamp((T-uP1)/AB,0.0,1.0);',
      '  float iBC=clamp((T-uP2)/BC,0.0,1.0);',
      '  vec3 pp=vec3(1.0-iAB, iAB-iBC, iBC);',
      '  vec3 cA=catmull(pp.x, uR1,uR1,uR2,uR3);',
      '  vec3 cB=catmull(pp.y, uR1,uR2,uR3,uR3);',
      '  if(T<uP2) return cA;',
      '  if(T<uP3) return cB;',
      '  return uR3;',
      '}',
      'float smoothRange(float v,float iMin,float iMax,float oMin,float oMax){',
      '  float t=clamp((v-iMin)/(iMax-iMin),0.0,1.0);',
      '  t=t*t*(3.0-2.0*t);',
      '  return mix(oMin,oMax,t);',
      '}',
      'float remapClamp(float v,float iMin,float iMax,float oMin,float oMax){',
      '  float t=clamp((v-iMin)/(iMax-iMin),0.0,1.0);',
      '  return mix(oMin,oMax,t);',
      '}',
      // ACES filmic
      'vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.0,1.0); }',
      'vec3 toSRGB(vec3 c){ return pow(clamp(c,0.0,1.0), vec3(1.0/2.2)); }',
      // environment gradient (world-up = shader +z)
      'vec3 envCol(vec3 d){',
      '  float t=clamp(d.z*0.5+0.5,0.0,1.0);',           // -z(down)->0 (bottom/blue), +z(up)->1 (top/black)
      '  return mix(uBot, uTop, t) * uBg;',
      '}',

      'void main(){',
      '  vec2 uv=(gl_FragCoord.xy - 0.5*uRes)/uRes.y;',
      '  vec3 dir=normalize(uFwd + uv.x*uTanFov*uAspect*uRight + uv.y*uTanFov*uUp);',
      '  vec3 ro=uCam;',
      // ray-sphere (bounding radius = 1, the geometry sphere)
      '  float b=dot(ro,dir); float c=dot(ro,ro)-1.0; float disc=b*b-c;',
      '  vec3 outCol=envCol(dir);',
      '  if(disc>0.0){',
      '    float sq=sqrt(disc);',
      '    float t0=-b-sq, t1=-b+sq;',
      '    float tEnter=max(t0,0.0);',
      '    vec3 pos=ro+dir*tEnter;',
      '    vec3 rdir=dir;',
      '    float ca=2.39996*0.0;',           // placeholder (kept simple)
      '    vec3 colAcc=vec3(0.0); float aAcc=0.0;',
      '    float st=uStep;',
      '    for(int i=0;i<1200;i++){',
      '      if(i>=uIter) break;',
      '      if(aAcc>0.992) break;',
      // steering toward center (lensing) — only near core (r<1)
      '      float rLen=length(pos);',
      '      vec3 rN=pos/max(rLen,1e-5);',
      '      float steerMag=st*uPower/(rLen*rLen);',
      '      float rng=remapClamp(rLen,1.0,0.5,0.0,1.0);',
      '      vec3 steered=normalize(rdir - rN*steerMag*rng);',
      '      vec3 adv=rdir*st;',
      '      pos+=adv;',
      // disc plane = xy, thickness along z
      '      float xyLen=length(pos.xy);',
      '      float rotPhase=xyLen*4.270 - uTime*0.1 + uSpin;',
      '      float cs=cos(rotPhase), sn=sin(rotPhase);',
      '      vec2 ruv=vec2(pos.x*cs - pos.y*sn, pos.x*sn + pos.y*cs)*2.0;',
      '      vec3 nDeep=texture2D(uNoise, ruv).rgb;',
      // z-band: three lobes at -w,0,+w
      '      vec3 bandEnds=vec3(-uWidth,0.0,uWidth);',
      '      vec3 dz=bandEnds - vec3(pos.z);',
      '      vec3 zQuad=dz*dz/uWidth;',
      '      vec3 zBand=max((vec3(uWidth)-zQuad)/uWidth, 0.0);',
      '      vec3 nAmp3=nDeep*zBand; float nAmpLen=length(nAmp3);',
      '      vec3 nNorm=texture2D(uNoise, ruv*1.002).rgb*zBand; float nNormLen=length(nNorm);',
      '      float rampIn=xyLen + (nAmpLen-0.780)*1.5 + (nAmpLen-nNormLen)*19.750;',
      '      vec3 baseCol=ramp3(rampIn);',
      '      vec3 emiss=baseCol*uEmis + uEmisCol;',
      '      bool inCore=rLen<uOrigin;',
      '      vec3 shaded = inCore ? vec3(0.0) : emiss;',
      // alpha shaping
      '      float zAbs=abs(pos.z);',
      '      float aNoise=(nAmpLen-0.750)*(-0.60);',
      '      float aPre=zAbs+aNoise;',
      '      float aRadial=smoothRange(xyLen,1.0,0.0,0.0,1.0);',
      '      float aBand=smoothRange(aPre,uWidth,0.0,0.0,aRadial);',
      '      float aLocal = inCore ? 1.0 : aBand;',
      // front-to-back composite
      '      float w=(1.0-aAcc)*aLocal;',
      '      colAcc=mix(colAcc, shaded, w);',
      '      aAcc=mix(aAcc, 1.0, aLocal);',
      '      pos+=adv; rdir=steered;',
      '      if(rLen>1.02 && dot(rdir,pos)>0.0) break;',
      '    }',
      '    vec3 env=envCol(rdir);',
      '    outCol=mix(env, colAcc, aAcc) + colAcc*0.0;',
      '    outCol=mix(outCol, colAcc, aAcc);',
      '  }',
      '  outCol*=uDiscB;',
      '  vec3 mapped=aces(outCol*uExposure);',
      '  gl_FragColor=vec4(toSRGB(mapped),1.0);',
      '}'
    ].join('\n');

    var prog = this.makeProgram(gl, vs, fs);
    if (!prog) return false;
    this.prog = prog;
    gl.useProgram(prog);
    var buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    var loc = gl.getAttribLocation(prog, 'aPos');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

    this.u = {};
    var names = ['uRes','uTime','uExposure','uDiscB','uReveal','uTanFov','uAspect','uSpin',
      'uCam','uFwd','uRight','uUp','uNoise','uStep','uNoiseF','uPower','uOrigin','uWidth','uEmis','uIter',
      'uR1','uR2','uR3','uEmisCol','uTop','uBot','uP1','uP2','uP3','uBg'];
    for (var k = 0; k < names.length; k++) this.u[names[k]] = gl.getUniformLocation(prog, names[k]);

    // static uniforms
    gl.uniform1f(this.u.uStep, CFG.stepSize);
    gl.uniform1f(this.u.uNoiseF, CFG.noiseFactor);
    gl.uniform1f(this.u.uPower, CFG.power);
    gl.uniform1f(this.u.uOrigin, CFG.originRadius);
    gl.uniform1f(this.u.uWidth, CFG.width);
    gl.uniform1f(this.u.uEmis, CFG.rampEmission);
    gl.uniform3fv(this.u.uR1, CFG.rampCol1); gl.uniform1f(this.u.uP1, CFG.rampPos1);
    gl.uniform3fv(this.u.uR2, CFG.rampCol2); gl.uniform1f(this.u.uP2, CFG.rampPos2);
    gl.uniform3fv(this.u.uR3, CFG.rampCol3); gl.uniform1f(this.u.uP3, CFG.rampPos3);
    gl.uniform3fv(this.u.uEmisCol, CFG.emissionColor);
    gl.uniform3fv(this.u.uTop, CFG.topColor);
    gl.uniform3fv(this.u.uBot, CFG.bottomColor);
    gl.uniform1f(this.u.uBg, CFG.bgIntensity);
    gl.uniform1f(this.u.uTanFov, Math.tan(CFG.fov * Math.PI / 360));

    this.loadNoise();
    return true;
  };

  BH.prototype.loadNoise = function () {
    var gl = this.gl, self = this;
    var tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([128,128,128,255]));
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    this.noiseTex = tex;
    var img = new Image();
    img.onload = function () {
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
      self.noiseReady = true;
    };
    img.onerror = function () { console.warn('[Singularity] noise texture failed to load'); };
    img.src = './static/textures/noise_deep.png';
  };

  BH.prototype.makeProgram = function (gl, vsrc, fsrc) {
    function sh(type, src) {
      var s = gl.createShader(type);
      gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) { console.error('[Singularity] shader:', gl.getShaderInfoLog(s)); return null; }
      return s;
    }
    var v = sh(gl.VERTEX_SHADER, vsrc), f = sh(gl.FRAGMENT_SHADER, fsrc);
    if (!v || !f) return null;
    var pr = gl.createProgram();
    gl.attachShader(pr, v); gl.attachShader(pr, f); gl.linkProgram(pr);
    if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) { console.error('[Singularity] link:', gl.getProgramInfoLog(pr)); return null; }
    return pr;
  };

  BH.prototype.resize = function () {
    var gl = this.gl;
    var scale = Math.min(window.devicePixelRatio || 1, 1.5) * (this.opt.quality || 0.62);
    var W = Math.max(2, Math.floor(window.innerWidth * scale));
    var H = Math.max(2, Math.floor(window.innerHeight * scale));
    this.canvas.width = W; this.canvas.height = H;
    gl.viewport(0, 0, W, H);
    this.bw = W; this.bh = H;
  };

  function cl(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function eIO(p) { return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2; }
  function eOut(p) { return 1 - Math.pow(1 - p, 3); }

  function norm(a){ var l=Math.hypot(a[0],a[1],a[2])||1; return [a[0]/l,a[1]/l,a[2]/l]; }
  function cross(a,b){ return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]; }

  BH.prototype.frame = function (now) {
    var gl = this.gl, u = this.u;
    if (!this.start) this.start = now;
    if (!this.last) this.last = now;
    var dt = (now - this.last) / 1000; this.last = now;
    if (dt > 0.05) dt = 0.05;
    var elapsed = (now - this.start) / 1000;

    var morph = this.morph;
    var p = cl((elapsed - this.hold) / morph, 0, 1);
    if (this.reduced) p = 1;
    var eio = eIO(p), eout = eOut(p);

    // intro: descend from a wider, higher establishing shot into config-3 framing
    var camEstablish = [0.34, -1.18, 0.66];
    var tgtEstablish = [0.0, 0.0, 0.0];
    var cam = lerp3(camEstablish, CFG.camFinal, eio);
    var tgt = lerp3(tgtEstablish, CFG.targetFinal, eout);

    // gentle perpetual drift after settle (azimuth around disc normal z)
    this.spin += dt * 0.02 * (this.reduced ? 0 : 1);
    var driftA = 0.05 * Math.sin(elapsed * 0.12) * eout;
    var cs = Math.cos(driftA), sn = Math.sin(driftA);
    cam = [cam[0]*cs - cam[1]*sn, cam[0]*sn + cam[1]*cs, cam[2]];

    var fwd = norm([tgt[0]-cam[0], tgt[1]-cam[1], tgt[2]-cam[2]]);
    var up0 = [0,0,1];
    var right = norm(cross(fwd, up0));
    var camUp = cross(right, fwd);

    // disc brightness ramps in; fades on scroll
    var sc = cl(this.scrollY / (window.innerHeight * 0.9), 0, 1);
    var discB = eOut(cl((p - 0.18) / 0.82, 0, 1)) * this.opt.discBright * (1 - sc * 0.92);
    var exposure = lerp(0.72, this.opt.exposure, eio);

    // logo morph (spin + scale + dissolve)
    if (this.logo) {
      if (this.reduced) { this.logo.style.opacity = '0'; }
      else {
        var rot = 1180 * Math.pow(p, 1.7);
        var scl = lerp(1, 3.0, Math.pow(p, 1.55));
        var op = 1 - cl((p - 0.46) / 0.42, 0, 1);
        var bl = lerp(0, 9, cl((p - 0.5) / 0.45, 0, 1));
        this.logo.style.transform = 'rotate(' + rot.toFixed(1) + 'deg) scale(' + scl.toFixed(3) + ')';
        this.logo.style.opacity = op.toFixed(3);
        this.logo.style.filter = 'blur(' + bl.toFixed(1) + 'px)';
      }
    }

    // hero reveal
    if (!this.reduced && this.revealEls) {
      for (var i = 0; i < this.revealEls.length; i++) {
        var pr = cl((elapsed - this.revealAt - i * 0.16) / 1.4, 0, 1);
        var e = eOut(pr);
        this.revealEls[i].style.opacity = e.toFixed(3);
        this.revealEls[i].style.filter = e < 0.999 ? 'blur(' + ((1 - e) * 5).toFixed(2) + 'px)' : 'none';
      }
    }

    if (this.zEl) this.zEl.textContent = 'Z  ' + (0.0341 + 0.0009 * Math.sin(elapsed * 0.6)).toFixed(4);

    var iter = this.opt.iterations | 0;
    if (sc > 0.5) iter = Math.max(220, Math.floor(iter * 0.6)); // cheaper when scrolled away

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.noiseTex);
    gl.uniform1i(u.uNoise, 0);
    gl.uniform2f(u.uRes, this.bw, this.bh);
    gl.uniform1f(u.uTime, elapsed);
    gl.uniform1f(u.uExposure, exposure);
    gl.uniform1f(u.uDiscB, discB);
    gl.uniform1f(u.uReveal, p);
    gl.uniform1f(u.uAspect, this.bw / this.bh);
    gl.uniform1f(u.uSpin, this.spin);
    gl.uniform1i(u.uIter, iter);
    gl.uniform3fv(u.uCam, cam);
    gl.uniform3fv(u.uFwd, fwd);
    gl.uniform3fv(u.uRight, right);
    gl.uniform3fv(u.uUp, camUp);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  };

  window.ArclightBH = { start: function (o) { return new BH(o); } };
})();
