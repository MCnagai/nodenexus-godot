const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');
const { PNG } = require('pngjs');

const root = path.resolve(__dirname, '..');
const evidence = path.join(root, 'build', 'evidence');
const near = (data, offset, rgb) => rgb.every((value, i) => Math.abs(data[offset + i] - value) <= 2);
const image = buffer => PNG.sync.read(buffer);

function changedPixels(before, after) {
  const a = image(before), b = image(after);
  assert.equal(a.width, b.width);
  let changed = 0;
  for (let i = 0; i < a.data.length; i += 4) {
    if (Math.abs(a.data[i] - b.data[i]) + Math.abs(a.data[i + 1] - b.data[i + 1]) + Math.abs(a.data[i + 2] - b.data[i + 2]) > 15) changed++;
  }
  return changed;
}

async function run() {
  await fs.mkdir(evidence, { recursive: true });
  const server = spawn('python3', [path.join(root, 'tools/serve-web.py'), '--port', '0'], { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] });
  let browser;
  try {
    const url = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Preview server did not start')), 10000);
      server.stdout.on('data', data => {
        const match = data.toString().match(/http:\/\/127\.0\.0\.1:\d+/);
        if (match) { clearTimeout(timer); resolve(match[0]); }
      });
      server.once('error', error => { clearTimeout(timer); reject(error); });
      server.once('exit', code => { clearTimeout(timer); reject(new Error(`Preview server exited ${code}`)); });
    });
    browser = await chromium.launch({
      headless: true,
      ...(process.env.BROWSER_EXECUTABLE ? { executablePath: process.env.BROWSER_EXECUTABLE } : {}),
      args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
    });
    for (const [name, options] of [
      ['desktop', { viewport: { width: 1280, height: 720 } }],
      ['mobile', { viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true, deviceScaleFactor: 1 }],
    ]) {
      const page = await browser.newPage(options);
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => { if (/SCRIPT ERROR:|^ERROR:/.test(message.text())) errors.push(message.text()); });
      page.on('response', response => { if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) errors.push(`HTTP ${response.status()}: ${response.url()}`); });
      await page.goto(url, { waitUntil: 'networkidle', timeout: 25000 });
      await page.waitForFunction(() => !document.querySelector('#status'), null, { timeout: 20000 });
      await page.waitForTimeout(500);
      const initial = await page.screenshot();
      const rendered = image(initial);
      let grassPixels = 0;
      for (let i = 0; i < rendered.data.length; i += 4) {
        if (rendered.data[i + 1] > rendered.data[i] + 15 && rendered.data[i + 1] > rendered.data[i + 2] + 20) grassPixels++;
      }
      await fs.writeFile(path.join(evidence, `${name}-map.png`), initial);
      assert.ok(grassPixels > rendered.width * rendered.height * 0.3, `${name}: grass map did not render`);
      await fs.writeFile(path.join(evidence, `${name}-map.png`), initial);
      if (options.hasTouch) {
        const session = await page.context().newCDPSession(page);
        const send = (type, points) => session.send('Input.dispatchTouchEvent', { type, touchPoints: points });
        const point = (x, y, id) => ({ x, y, id });
        await send('touchStart', [point(100, 400, 0), point(250, 400, 1)]);
        for (let i = 1; i <= 8; i++) {
          await send('touchMove', [point(100 + i * 5, 400 + i * 3, 0), point(250 + i * 5, 400 + i * 3, 1)]);
        }
        await send('touchEnd', []);
        await page.waitForTimeout(300);
        const panned = await page.screenshot();
        assert.ok(changedPixels(initial, panned) > 1000, 'mobile: two-finger pan did not move map');
        await send('touchStart', [point(110, 400, 0), point(240, 400, 1)]);
        for (let i = 1; i <= 8; i++) {
          await send('touchMove', [point(110 - i * 5, 400, 0), point(240 + i * 5, 400, 1)]);
        }
        await send('touchEnd', []);
        await page.waitForTimeout(300);
        assert.ok(changedPixels(panned, await page.screenshot()) > 1000, 'mobile: pinch did not zoom map');
        await send('touchStart', [point(180, 400, 0)]);
        await page.waitForTimeout(650);
        const held = await page.screenshot();
        for (let i = 1; i <= 8; i++) await send('touchMove', [point(180 + i * 6, 400, 0)]);
        await send('touchEnd', []);
        await page.waitForTimeout(300);
        assert.ok(changedPixels(held, await page.screenshot()) > 1000, 'mobile: long-press drag did not pan map');
        await session.detach();
      } else {
        await page.mouse.move(500, 350);
        await page.mouse.down({ button: 'right' });
        await page.mouse.move(650, 400, { steps: 8 });
        await page.mouse.up({ button: 'right' });
        await page.waitForTimeout(300);
        const panned = await page.screenshot();
        assert.ok(changedPixels(initial, panned) > 1000, 'desktop: right drag did not move map');
        await page.mouse.wheel(0, -400);
        await page.waitForTimeout(300);
        assert.ok(changedPixels(panned, await page.screenshot()) > 1000, 'desktop: wheel did not zoom map');
      }
      await fs.writeFile(path.join(evidence, `${name}-camera.png`), await page.screenshot());
      const metadata = await page.request.get(`${url}/build-info.json`);
      assert.equal(metadata.status(), 200);
      const build = await metadata.json();
      assert.match(build.commit, /^[0-9a-f]{40}$/);
      const gzipResponse = await page.request.get(`${url}/${build.wasm}`);
      assert.equal(gzipResponse.headers()['content-encoding'], undefined, 'gzip must be decoded explicitly, not by an origin-specific header');
      assert.match(gzipResponse.headers()['cache-control'], /private.*immutable/);
      await page.reload({ waitUntil: 'networkidle' });
      await page.waitForFunction(() => window.nodeNexusStatus?.started, null, { timeout: 20000 });
      const warm = await page.evaluate(wasm => {
        const entry = performance.getEntriesByType('resource').find(item => item.name.endsWith(wasm));
        return entry ? { transfer: entry.transferSize, size: entry.decodedBodySize } : null;
      }, build.wasm);
      assert.equal(await page.evaluate(() => window.nodeNexusStatus.engineCacheHit), true, `${name}: runtime cache was not reused`);
      assert.ok(!warm || warm.transfer === 0, `${name}: engine was downloaded again instead of using browser cache`);
      assert.deepEqual(errors, [], `${name}: browser errors`);
      console.log(`WEB_BROWSER_PASSED: ${name}, map pan and zoom, repeat load uses cached engine`);
      await page.close();
    }
    for (const [name, response] of [
      ['corrupt-gzip', { status: 200, contentType: 'application/gzip', body: 'invalid compressed bytes' }],
      ['expired-session', { status: 200, contentType: 'text/html', body: '<html>Sign in</html>' }],
    ]) {
      const page = await browser.newPage();
      await page.route('**/*.wasm.gz', route => route.fulfill(response));
      await page.goto(url, { waitUntil: 'networkidle' });
      await page.waitForFunction(() => window.nodeNexusStatus?.phase === 'error', null, { timeout: 10000 });
      assert.equal(await page.locator('#retry').isVisible(), true);
      assert.ok(await page.locator('#status-notice').textContent());
      console.log(`WEB_FAILURE_HANDLED: ${name}, actionable error shown instead of stalled loading`);
      await page.close();
    }
  } finally {
    if (browser) await browser.close();
    server.kill();
  }
}
run().catch(error => { console.error(error); process.exitCode = 1; });
