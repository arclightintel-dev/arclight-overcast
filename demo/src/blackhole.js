/* Arclight Labs — relativistic ray-marched black hole (Schwarzschild geodesics).
   Self-contained WebGL engine. window.ArclightBH.start(opts) -> instance. */
(function () {
  'use strict';

  function BH(opts) {
    this.canvas = opts.canvas;
    this.logo = opts.logo || null;
    this.revealEls = opts.revealEls || [];
    this.zEl = opts.zEl || null;
    this.getScroll = opts.getScroll || function () { return 0; };
    var p = opts.props || {};
    this.opt = {
      exposure: p.exposure != null ? p.exposure : 1,
      incl: p.inclination != null ? p.inclination : 0.15,
      offsetX: p.offsetX != null ? p.offsetX : 0.22,
      star: p.starBrightness != null ? p.starBrightness : 1,
      mspeed: p.morphSpeed != null ? p.morphSpeed : 1
    };
    this.reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.start = 0; this.last = 0; this.az = 0; this.scrollY = 0;
    if (!this.initGL()) { this.canvas.style.background = '#000'; return; }

    var self = this;
    this._resize = function () { self.resize(); };
    this._scroll = function () { self.scrollY = self.getScroll(); };
    window.addEventListener('resize', this._resize);
    window.addEventListener('scroll', this._scroll, { passive: true });
    this.resize();

    this.hold = 0.3; this.morph = 2.9 / (this.opt.mspeed || 1);
    this.revealAt = this.hold + this.morph * 0.56;
    if (this.reduced) { this.revealEls.forEach(function (e) { e.style.opacity = 1; }); }

    this.loop = function (t) { self.frame(t); self.raf = requestAnimationFrame(self.loop); };
    this.raf = requestAnimationFrame(this.loop);

    if (opts.onReady) setTimeout(opts.onReady, 200);
  }

  BH.prototype.stop = function () {
    cancelAnimationFrame(this.raf);
    window.removeEventListener('resize', this._resize);
    window.removeEventListener('scroll', this._scroll);
  };
  BH.prototype.setProps = function (p) {
    if (!p) return;
    if (p.exposure != null) this.opt.exposure = p.exposure;
    if (p.inclination != null) this.opt.incl = p.inclination;
    if (p.offsetX != null) this.opt.offsetX = p.offsetX;
    if (p.starBrightness != null) this.opt.star = p.starBrightness;
    if (p.morphSpeed != null) this.opt.mspeed = p.morphSpeed;
  };

  BH.prototype.initGL = function () {
    var gl = this.canvas.getContext('webgl', { antialias: true, alpha: false, premultipliedAlpha: false, powerPreference: 'high-performance' })
      || this.canvas.getContext('experimental-webgl');
    if (!gl) { console.warn('[Arclight] WebGL unavailable'); return false; }
    this.gl = gl;

    var vs = 'attribute vec2 aPos; void main(){ gl_Position = vec4(aPos,0.0,1.0); }';
    var fs = [
      'precision highp float;',
      'uniform vec2 uRes; uniform float uTime,uCamR,uDiscB,uExposure,uAz,uIncl,uStar,uIn,uOut,uFov,uCx,uCy,uThick;',
      'float hash(vec3 p){ p=fract(p*0.3183099+0.1); p*=17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }',
      'float h2d(vec2 p){ return fract(sin(dot(p,vec2(41.3,289.1)))*43758.5453); }',
      'float vnoise(vec2 p){ vec2 i=floor(p),f=fract(p); vec2 u=f*f*(3.0-2.0*f);',
      '  float a=h2d(i),b=h2d(i+vec2(1.0,0.0)),c=h2d(i+vec2(0.0,1.0)),d=h2d(i+vec2(1.0,1.0));',
      '  return mix(mix(a,b,u.x),mix(c,d,u.x),u.y); }',
      'float fbm(vec2 p){ float s=0.0,a=0.55; for(int i=0;i<4;i++){ s+=a*vnoise(p); p*=2.03; a*=0.5; } return s; }',
      'float starfield(vec3 d){ float c=0.0; for(int i=0;i<3;i++){ float sc=130.0+float(i)*150.0;',
      '  vec3 p=d*sc; vec3 id=floor(p); vec3 f=fract(p)-0.5; float h=hash(id);',
      '  float st=smoothstep(0.975,1.0,h); c+=st*exp(-dot(f,f)*46.0)*(1.0-float(i)*0.28); } return c; }',
      'void main(){',
      '  vec2 uv=(gl_FragCoord.xy - 0.5*uRes)/uRes.y - vec2(uCx,uCy);',
      '  vec3 cam=uCamR*vec3(cos(uIncl)*sin(uAz),sin(uIncl),cos(uIncl)*cos(uAz));',
      '  vec3 fwd=normalize(-cam);',
      '  vec3 rgt=normalize(cross(vec3(0.0,1.0,0.0),fwd));',
      '  vec3 up=cross(fwd,rgt);',
      '  vec3 dir=normalize(fwd*uFov + uv.x*rgt + uv.y*up);',
      '  vec3 pos=cam; vec3 vel=dir;',
      '  vec3 Lm=cross(pos,vel); float h2=dot(Lm,Lm);',
      '  vec3 col=vec3(0.0);',
      '  bool captured=false;',
      '  for(int i=0;i<240;i++){',
      '    float r=length(pos);',
      '    if(r<1.0){captured=true;break;}',
      '    if(r>52.0 && dot(vel,pos)>0.0){break;}',
      '    float dt=clamp(0.13*(r-1.0),0.02,0.45);',
      '    if(r>uIn && r<uOut && abs(pos.y)<uThick){',
      '      float tt=(r-uIn)/(uOut-uIn);',
      '      float fall=pow(1.0-tt,1.45)*smoothstep(0.0,0.04,tt);',
      '      float sig=uThick*0.55;',
      '      float vert=exp(-(pos.y*pos.y)/(2.0*sig*sig));',
      '      float ang=atan(pos.z,pos.x);',
      '      float adv=ang*1.5 + uTime*0.22 - 7.0/r;',
      '      vec2 q=vec2(adv*1.1, log(r)*9.0 - uTime*0.1);',
      '      float n=fbm(q);',
      '      float n2=fbm(q*2.6+17.0);',
      '      float streak=pow(clamp(n*0.75+n2*0.45,0.0,1.0),1.8);',
      '      streak=0.08+1.5*streak;',
      '      vec3 tang=normalize(cross(vec3(0.0,1.0,0.0),pos));',
      '      float beam=1.0+0.95*dot(tang,normalize(cam-pos));',
      '      beam=clamp(beam,0.16,2.6);',
      '      float inner=1.0+2.6*smoothstep(0.32,0.0,tt);',
      '      col+=vec3(0.95,0.965,1.0)*fall*vert*streak*pow(beam,2.2)*inner*uDiscB*0.5*dt;',
      '    }',
      '    vec3 acc=-1.5*h2*pos/pow(dot(pos,pos),2.5);',
      '    vel+=acc*dt; pos+=vel*dt;',
      '  }',
      '  if(!captured){ col+=vec3(starfield(normalize(vel)))*uStar; }',
      '  col=vec3(1.0)-exp(-col*uExposure);',
      '  col=pow(col,vec3(0.9));',
      '  gl_FragColor=vec4(col,1.0);',
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
    var names = ['uRes', 'uTime', 'uCamR', 'uDiscB', 'uExposure', 'uAz', 'uIncl', 'uStar', 'uIn', 'uOut', 'uFov', 'uCx', 'uCy', 'uThick'];
    for (var k = 0; k < names.length; k++) this.u[names[k]] = gl.getUniformLocation(prog, names[k]);
    return true;
  };

  BH.prototype.makeProgram = function (gl, vsrc, fsrc) {
    function sh(type, src) {
      var s = gl.createShader(type);
      gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) { console.error('[Arclight] shader:', gl.getShaderInfoLog(s)); return null; }
      return s;
    }
    var v = sh(gl.VERTEX_SHADER, vsrc), f = sh(gl.FRAGMENT_SHADER, fsrc);
    if (!v || !f) return null;
    var pr = gl.createProgram();
    gl.attachShader(pr, v); gl.attachShader(pr, f); gl.linkProgram(pr);
    if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) { console.error('[Arclight] link:', gl.getProgramInfoLog(pr)); return null; }
    return pr;
  };

  BH.prototype.resize = function () {
    var gl = this.gl;
    var scale = Math.min(window.devicePixelRatio || 1, 1.4);
    var W = Math.floor(window.innerWidth * scale), H = Math.floor(window.innerHeight * scale);
    this.canvas.width = W; this.canvas.height = H;
    gl.viewport(0, 0, W, H);
    this.bw = W; this.bh = H;
  };

  function cl(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function eIO(p) { return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2; }
  function eOut(p) { return 1 - Math.pow(1 - p, 3); }
  function eSine(p) { return -(Math.cos(Math.PI * p) - 1) / 2; }

  BH.prototype.frame = function (now) {
    var gl = this.gl, u = this.u;
    if (!this.start) this.start = now;
    if (!this.last) this.last = now;
    var dt = (now - this.last) / 1000; this.last = now;
    if (dt > 0.05) dt = 0.05;
    var elapsed = (now - this.start) / 1000;

    var morph = 2.9 / (this.opt.mspeed || 1);
    var p = cl((elapsed - this.hold) / morph, 0, 1);
    if (this.reduced) p = 1;

    var eio = eIO(p), eout = eOut(p);
    var camR = lerp(23.0, 9.0, eio);
    var incl = lerp(0.5, this.opt.incl, eout);
    var discB = eSine(cl((p - 0.34) / 0.66, 0, 1));
    var exposure = lerp(0.7, 1.12, eio) * this.opt.exposure;
    var baseSlow = 0.05, peak = this.reduced ? 0.05 : 1.5 * (this.opt.mspeed || 1);
    var omega = baseSlow + (peak - baseSlow) * Math.sin(Math.PI * p);
    this.az += omega * dt;

    if (this.logo) {
      if (this.reduced) { this.logo.style.opacity = '0'; }
      else {
        var rot = 1240 * Math.pow(p, 1.7);
        var scl = lerp(1, 3.1, Math.pow(p, 1.6));
        var op = 1 - cl((p - 0.5) / 0.42, 0, 1);
        var bl = lerp(0, 9, cl((p - 0.55) / 0.45, 0, 1));
        this.logo.style.transform = 'rotate(' + rot.toFixed(1) + 'deg) scale(' + scl.toFixed(3) + ')';
        this.logo.style.opacity = op.toFixed(3);
        this.logo.style.filter = 'blur(' + bl.toFixed(1) + 'px)';
      }
    }

    if (!this.reduced && this.revealEls) {
      for (var i = 0; i < this.revealEls.length; i++) {
        var pr = cl((elapsed - this.revealAt - i * 0.18) / 1.4, 0, 1);
        var e = eOut(pr);
        this.revealEls[i].style.opacity = e.toFixed(3);
        this.revealEls[i].style.filter = e < 0.999 ? 'blur(' + ((1 - e) * 5).toFixed(2) + 'px)' : 'none';
      }
    }

    var sc = cl(this.scrollY / (window.innerHeight * 0.85), 0, 1);
    discB *= (1 - sc);
    var starB = this.opt.star * (0.5 + 0.5 * cl(elapsed / 1.8, 0, 1));

    if (this.zEl) this.zEl.textContent = 'Z  ' + (0.0341 + 0.0009 * Math.sin(elapsed * 0.6)).toFixed(4);

    gl.uniform2f(u.uRes, this.bw, this.bh);
    gl.uniform1f(u.uTime, elapsed);
    gl.uniform1f(u.uCamR, camR);
    gl.uniform1f(u.uDiscB, discB);
    gl.uniform1f(u.uExposure, exposure);
    gl.uniform1f(u.uAz, this.az);
    gl.uniform1f(u.uIncl, incl);
    gl.uniform1f(u.uStar, starB);
    gl.uniform1f(u.uIn, 2.2);
    gl.uniform1f(u.uOut, 16.0);
    gl.uniform1f(u.uFov, 1.3);
    gl.uniform1f(u.uCx, this.opt.offsetX);
    gl.uniform1f(u.uCy, 0.0);
    gl.uniform1f(u.uThick, 0.55);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  };

  window.ArclightBH = { start: function (o) { return new BH(o); } };
})();
