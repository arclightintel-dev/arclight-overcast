// Frame capture for the Arclight singularity shader.
// Virtualizes the clock so the TSL `time` uniform advances deterministically,
// steps frame-by-frame, and screenshots the canvas element.
import { chromium } from 'playwright';
import http from 'http';
import { promises as fs } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const SCRATCH = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(SCRATCH, '../..');
const OUT = path.join(SCRATCH, 'frames');

const FPS = Number(process.env.FPS || 24);
const FRAMES = Number(process.env.FRAMES || 1);
const OFFSET_FRAMES = Number(process.env.OFFSET_FRAMES || 0);
const WIDTH = Number(process.env.WIDTH || 1280);
const HEIGHT = Number(process.env.HEIGHT || 720);
const PORT = Number(process.env.PORT || 8931);

// tiny static server: serves repo files, but capture.html from scratchpad
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.jpg': 'image/jpeg' };
const server = http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  let fp = u.pathname === '/' || u.pathname === '/capture.html'
    ? path.join(SCRATCH, 'capture.html')
    : u.pathname.startsWith('/vendor/')
      ? path.join(SCRATCH, 'node_modules/three/build', u.pathname.slice('/vendor/'.length))
      : path.join(REPO, u.pathname.slice(1));
  try {
    let data = await fs.readFile(fp);
    if (u.pathname === '/singularity-gpu.js') {
      data = data.toString()
        .replace(/'https:\/\/esm\.sh\/three@[^']*\/webgpu'/, "'three/webgpu'")
        .replace(/'https:\/\/esm\.sh\/three@[^']*\/tsl'/, "'three/tsl'");
    }
    res.writeHead(200, { 'content-type': MIME[path.extname(fp)] || 'application/octet-stream' });
    res.end(data);
  } catch {
    res.writeHead(404); res.end('nf');
  }
});
await new Promise(r => server.listen(PORT, r));

const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.CHROMIUM_PATH || undefined,
  proxy: process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1' } : undefined,
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--disable-gpu-sandbox'],
});
const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT }, ignoreHTTPSErrors: true });
page.on('console', m => console.log('[page]', m.type(), m.text().slice(0, 300)));
page.on('pageerror', e => console.log('[pageerror]', String(e).slice(0, 500)));

// Virtual clock: performance.now/Date.now return __vt; rAF callbacks queue and
// only fire when __stepFrame pumps them with an advanced timestamp.
await page.addInitScript(() => {
  window.__vt = 0;
  window.__renders = 0;
  performance.now = () => window.__vt;
  Date.now = () => 1700000000000 + window.__vt;
  // native rAF keeps firing (Playwright needs it), but app callbacks see the
  // virtual timestamp — the app's 30fps throttle means it only renders when
  // __vt has advanced past its next frame deadline.
  const nativeRAF = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (cb) => nativeRAF(() => cb(window.__vt));
});

const t0 = Date.now();
await page.goto(`http://localhost:${PORT}/capture.html`, { waitUntil: 'load', timeout: 120000 });

// wait for first render at vt=0 — vt is NOT advanced here, so every worker's
// shader clock starts at exactly 0 (determinism across parallel workers)
let ready = false;
for (let i = 0; i < 3000 && !ready; i++) {
  await page.waitForTimeout(100);
  ready = await page.evaluate(() => !!window.__ready);
}
if (!ready) { console.error('never became ready'); await browser.close(); server.close(); process.exit(1); }
console.log('ready after', ((Date.now() - t0) / 1000).toFixed(1), 's; vt=', await page.evaluate(() => window.__vt));

// wrap renderAsync so we can tell when a frame for the current __vt completed
await page.evaluate(() => {
  const r = window.__inst.renderer;
  const orig = r.renderAsync.bind(r);
  r.renderAsync = async (...a) => { const v = await orig(...a); window.__renders++; return v; };
});

const cdp = await page.context().newCDPSession(page);
const shot = async (fp) => {
  const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' });
  await fs.writeFile(fp, Buffer.from(data, 'base64'));
};

const step = async (ms) => {
  const before = await page.evaluate(() => window.__renders);
  await page.evaluate((m) => { window.__vt += m; }, ms);
  await page.waitForFunction((b) => window.__renders > b, before, { timeout: 120000, polling: 50 });
};

await fs.mkdir(OUT, { recursive: true });
const stepMs = 1000 / FPS;
// jump so the first captured frame lands at (OFFSET_FRAMES+1)*stepMs
if (OFFSET_FRAMES > 0) await step(OFFSET_FRAMES * stepMs);
for (let f = 0; f < FRAMES; f++) {
  const ft = Date.now();
  await step(stepMs);
  const idx = OFFSET_FRAMES + f;
  await shot(path.join(OUT, `f${String(idx).padStart(4, '0')}.png`));
  console.log(`frame ${idx} (${f + 1}/${FRAMES}) in ${((Date.now() - ft) / 1000).toFixed(1)}s`);
}

await browser.close();
server.close();
console.log('done, total', ((Date.now() - t0) / 1000).toFixed(1), 's');
