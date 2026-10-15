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

function redRectangle(png) {
  let left = png.width, right = -1, top = png.height, bottom = -1, count = 0;
  for (let y = 0; y < png.height; y++) for (let x = 0; x < png.width; x++) {
    if (near(png.data, (y * png.width + x) * 4, [255, 0, 0])) {
      left = Math.min(left, x); right = Math.max(right, x);
      top = Math.min(top, y); bottom = Math.max(bottom, y); count++;
    }
  }
  return count > 500 ? { x: (left + right) / 2, y: (top + bottom) / 2, top, width: right - left + 1 } : null;
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
      let rectangle, initial;
      for (let attempt = 0; attempt < 20; attempt++) {
        initial = await page.screenshot();
        rectangle = redRectangle(image(initial));
        if (rectangle) break;
        await page.waitForTimeout(250);
      }
      assert.ok(rectangle, `${name}: red acceptance rectangle did not render`);
      await fs.writeFile(path.join(evidence, `${name}-red.png`), initial);
      const tap = async () => {
        const x = rectangle.x, y = rectangle.top - 80 * rectangle.width / 420;
        if (options.hasTouch) await page.touchscreen.tap(x, y);
        else await page.mouse.click(x, y);
      };
      await tap();
      await page.waitForTimeout(400);
      const green = await page.screenshot();
      const greenImage = image(green);
      const pixel = (Math.round(rectangle.y) * greenImage.width + Math.round(rectangle.x)) * 4;
      assert.ok(near(greenImage.data, pixel, [51, 191, 122]), `${name}: tap did not change red to green`);
      await fs.writeFile(path.join(evidence, `${name}-tap.png`), green);
      await tap();
      await page.waitForTimeout(400);
      assert.ok(near(image(await page.screenshot()).data, pixel, [255, 0, 0]), `${name}: second tap did not restore red`);
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
      console.log(`WEB_BROWSER_PASSED: ${name}, red -> green -> red, repeat load uses cached engine`);
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
