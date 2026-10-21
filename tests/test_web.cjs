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
const hasWireAt = (png, x, y) => [-2, -1, 0, 1, 2].some(dy => near(png.data, ((Math.round(y) + dy) * png.width + Math.round(x)) * 4, [224, 242, 178]));

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
      ['mobile', { viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true, deviceScaleFactor: 3 }],
      ['mobile-landscape', { viewport: { width: 915, height: 412 }, isMobile: true, hasTouch: true, deviceScaleFactor: 3 }],
    ]) {
      if (process.env.WEB_TEST_PROFILE && process.env.WEB_TEST_PROFILE !== name) continue;
      const page = await browser.newPage(options);
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => { if (/SCRIPT ERROR:|^ERROR:/.test(message.text())) errors.push(message.text()); });
      page.on('response', response => { if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) errors.push(`HTTP ${response.status()}: ${response.url()}`); });
      await page.goto(url, { waitUntil: 'networkidle', timeout: 25000 });
      await page.waitForFunction(() => !document.querySelector('#status'), null, { timeout: 20000 });
      await page.waitForTimeout(500);
      const backing = await page.locator('#canvas').evaluate(canvas => ({ width: canvas.width, height: canvas.height }));
      assert.ok(backing.width <= options.viewport.width && backing.height <= options.viewport.height,
        `${name}: high-DPI multiplied the render target (${backing.width}x${backing.height})`);
      const initial = await page.screenshot({ scale: 'css' });
      const rendered = image(initial);
      let grassPixels = 0;
      for (let i = 0; i < rendered.data.length; i += 4) {
        if (rendered.data[i + 1] > rendered.data[i] + 15 && rendered.data[i + 1] > rendered.data[i + 2] + 20) grassPixels++;
      }
      await fs.writeFile(path.join(evidence, `${name}-map.png`), initial);
      assert.ok(grassPixels > rendered.width * rendered.height * 0.3, `${name}: grass map did not render`);
      await fs.writeFile(path.join(evidence, `${name}-map.png`), initial);
      if (process.env.WEB_TEST_SCENARIO !== "blocks") {
      // The board starts empty; create a real debug unit for movement checks.
      const fixtureReferenceHeight = options.viewport.height < 500 && options.viewport.width > options.viewport.height ? 320 : 720;
      const fixtureScale = Math.min(options.viewport.width / 480, options.viewport.height / fixtureReferenceHeight);
      const fixtureUiScale = Math.max(1, Math.min(3, 1 / fixtureScale));
      const fixtureX = options.viewport.width - 114 * fixtureUiScale * fixtureScale;
      const fixtureY = 72 * fixtureUiScale * fixtureScale;
      if (options.hasTouch) await page.touchscreen.tap(fixtureX, fixtureY);
      else await page.mouse.click(fixtureX, fixtureY);
      await page.waitForTimeout(300);
      const fixtureHorizontal = Math.min(170, Math.max(0, options.viewport.width / fixtureScale / 2 - 80 - 24) * 0.8);
      const fixtureVertical = Math.min(140, Math.max(0, options.viewport.height / fixtureScale / 2 - 38 - 160 * fixtureUiScale));
      const source = { x: options.viewport.width / 2 - fixtureHorizontal * fixtureScale, y: options.viewport.height / 2 + fixtureVertical * fixtureScale };
      const target = { x: options.viewport.width / 2, y: options.viewport.height / 2 };
      if (options.hasTouch) {
        const session = await page.context().newCDPSession(page);
        await session.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ ...source, id: 0 }] });
        for (let i = 1; i <= 8; i++) {
          await session.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: source.x + (target.x - source.x) * i / 8, y: source.y + (target.y - source.y) * i / 8, id: 0 }] });
        }
        await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        await session.detach();
      } else {
        await page.mouse.move(source.x, source.y);
        await page.mouse.down();
        await page.mouse.move(target.x, target.y, { steps: 8 });
        await page.mouse.up();
      }
      await page.waitForTimeout(300);
      const movedNode = image(await page.screenshot({ scale: 'css' }));
      const offset = (Math.round(target.y - 25 * fixtureScale) * movedNode.width + Math.round(target.x + 64 * fixtureScale)) * 4;
      await fs.writeFile(path.join(evidence, `${name}-moved-node.png`), await page.screenshot({ scale: 'css' }));
      assert.ok(near(movedNode.data, offset, [35, 59, 55]), `${name}: node body did not arrive at drag destination`);
      const released = await page.screenshot({ scale: 'css' });
      if (!options.hasTouch) {
        await page.mouse.move(target.x + 100, target.y + 50);
        await page.waitForTimeout(150);
        assert.ok(near(image(await page.screenshot({ scale: 'css' })).data, offset, [35, 59, 55]), 'desktop: node followed mouse after release');
      }
      await fs.writeFile(path.join(evidence, `${name}-node-drag.png`), released);
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
        const panned = await page.screenshot({ scale: 'css' });
        assert.ok(changedPixels(initial, panned) > 1000, 'mobile: two-finger pan did not move map');
        await send('touchStart', [point(110, 400, 0), point(240, 400, 1)]);
        for (let i = 1; i <= 8; i++) {
          await send('touchMove', [point(110 - i * 5, 400, 0), point(240 + i * 5, 400, 1)]);
        }
        await send('touchEnd', []);
        await page.waitForTimeout(300);
        assert.ok(changedPixels(panned, await page.screenshot({ scale: 'css' })) > 1000, 'mobile: pinch did not zoom map');
        await send('touchStart', [point(180, 400, 0)]);
        await page.waitForTimeout(650);
        const held = await page.screenshot({ scale: 'css' });
        for (let i = 1; i <= 8; i++) await send('touchMove', [point(180 + i * 6, 400, 0)]);
        await send('touchEnd', []);
        await page.waitForTimeout(300);
        assert.ok(changedPixels(held, await page.screenshot({ scale: 'css' })) > 1000, 'mobile: long-press drag did not pan map');
        await session.detach();
      } else {
        await page.mouse.move(500, 350);
        await page.mouse.down({ button: 'right' });
        await page.mouse.move(650, 400, { steps: 8 });
        await page.mouse.up({ button: 'right' });
        await page.waitForTimeout(300);
        const panned = await page.screenshot({ scale: 'css' });
        assert.ok(changedPixels(initial, panned) > 1000, 'desktop: right drag did not move map');
        await page.mouse.wheel(0, -400);
        await page.waitForTimeout(300);
        assert.ok(changedPixels(panned, await page.screenshot({ scale: 'css' })) > 1000, 'desktop: wheel did not zoom map');
      }
      await fs.writeFile(path.join(evidence, `${name}-camera.png`), await page.screenshot({ scale: 'css' }));
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
      await page.waitForTimeout(400);
      }
      // Fresh camera: generate a pair through the visible debug menu.
      const referenceHeight = options.viewport.height < 500 && options.viewport.width > options.viewport.height ? 320 : 720;
      const worldScale = Math.min(options.viewport.width / 480, options.viewport.height / referenceHeight);
      const uiScale = Math.max(1, Math.min(3, 1 / worldScale));
      const uiX = options.viewport.width - 114 * uiScale * worldScale;
      const activate = async (x, y) => options.hasTouch ? page.touchscreen.tap(x, y) : page.mouse.click(x, y);
      await activate(uiX, 72 * uiScale * worldScale);
      await activate(uiX, 130 * uiScale * worldScale);
      await page.waitForTimeout(300);
      const vertical = Math.min(140, Math.max(0, options.viewport.height / worldScale / 2 - 38 - 160 * uiScale));
      const portY = options.viewport.height / 2 + vertical * worldScale;
      const initialHorizontal = Math.min(170, Math.max(0, options.viewport.width / worldScale / 2 - 80 - 24) * 0.8);
      const allyBodyX = options.viewport.width / 2 - initialHorizontal * worldScale;
      const pointerDrag = async (from, to, via = []) => {
        if (options.hasTouch) {
          const session = await page.context().newCDPSession(page);
          await session.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ ...from, id: 0 }] });
          let previous = from;
          for (const end of [...via, to]) {
            for (let step = 1; step <= 8; step++) await session.send('Input.dispatchTouchEvent', {
              type: 'touchMove', touchPoints: [{ x: previous.x + (end.x - previous.x) * step / 8, y: previous.y + (end.y - previous.y) * step / 8, id: 0 }] });
            previous = end;
          }
          await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
          await session.detach();
        } else {
          await page.mouse.move(from.x, from.y);
          await page.mouse.down();
          for (const end of [...via, to]) await page.mouse.move(end.x, end.y, { steps: 8 });
          await page.mouse.up();
        }
      };
      const itemCell = slot => ({ x: (48 + slot % 4 * 48) * uiScale * worldScale,
        y: options.viewport.height + (-248 + Math.floor(slot / 4) * 48) * uiScale * worldScale });
      const boxButton = { x: 80 * uiScale * worldScale, y: options.viewport.height - 36 * uiScale * worldScale };
      const rowPoint = slot => ({ x: allyBodyX, y: portY + (38 + 27 + slot * 46) * worldScale });
      const countColor = (png, center, rgb, radius = 14) => {
        let count = 0;
        for (let dy = -radius; dy <= radius; dy++) for (let dx = -radius; dx <= radius; dx++) {
          const x = Math.round(center.x + dx), y = Math.round(center.y + dy);
          if (x >= 0 && y >= 0 && x < png.width && y < png.height && near(png.data, (y * png.width + x) * 4, rgb)) count++;
        }
        return count;
      };
      await activate(boxButton.x, boxButton.y);
      await pointerDrag(itemCell(1), itemCell(5));
      await pointerDrag(itemCell(5), itemCell(2));
      const movedItems = image(await page.screenshot({ scale: 'css' }));
      assert.ok(countColor(movedItems, itemCell(2), [227, 238, 245]) > 3, `${name}: sword stack did not swap cells`);
      assert.ok(countColor(movedItems, itemCell(5), [118, 202, 112]) > 3, `${name}: herb stack did not swap cells`);
      const equip = async (slot, open = true) => {
        if (open) await activate(boxButton.x, boxButton.y);
        // Pull outside the panel first, revealing any node that was behind it.
        await pointerDrag(itemCell(slot), { x: allyBodyX, y: portY }, [{ x: 244 * uiScale * worldScale, y: portY }]);
      };
      await equip(2, false);
      await equip(5);
      await pointerDrag(rowPoint(1), rowPoint(0));
      const iconX = allyBodyX - 80 * worldScale + 18 * worldScale;
      const reordered = image(await page.screenshot({ scale: 'css' }));
      assert.ok(countColor(reordered, { x: iconX, y: rowPoint(0).y }, [118, 202, 112]) > 3, `${name}: herb did not move to first row`);
      await pointerDrag(rowPoint(0), rowPoint(1));
      await pointerDrag(rowPoint(1), itemCell(5), [boxButton]);
      const returned = image(await page.screenshot({ scale: 'css' }));
      assert.ok(countColor(returned, itemCell(5), [118, 202, 112]) > 3, `${name}: block did not return to chosen cell`);
      await equip(5, false);
      await fs.writeFile(path.join(evidence, `${name}-blocks.png`), await page.screenshot({ scale: 'css' }));
      const horizontal = Math.min(170, Math.max(0, options.viewport.width / worldScale / 2 - 80 - 24) * 0.8);
      let outX = options.viewport.width / 2 - (horizontal - 80) * worldScale;
      let inX = options.viewport.width / 2 + (horizontal - 80) * worldScale;
      // Locate the actual colored ports: responsive spawning avoids minimap overlap.
      const spawned = image(await page.screenshot({ scale: 'css' }));
      const portCenter = rgb => {
        const row = Math.round(portY);
        const xs = [];
        for (let x = 0; x < spawned.width; x++) if (near(spawned.data, (row * spawned.width + x) * 4, rgb)) xs.push(x);
        assert.ok(xs.length, `${name}: generated port is not visible`);
        // Hover outlines share the ally port color. Pick the widest contiguous
        // run (the port circle), not the midpoint of unrelated colored pixels.
        const runs = [];
        for (const x of xs) {
          if (!runs.length || x > runs[runs.length - 1][1] + 1) runs.push([x, x]);
          else runs[runs.length - 1][1] = x;
        }
        const run = runs.reduce((best, next) => next[1] - next[0] > best[1] - best[0] ? next : best);
        return (run[0] + run[1]) / 2;
      };
      outX = portCenter([142, 229, 207]);
      inX = portCenter([242, 155, 148]);
      const wireX = (outX + inX) / 2;
      const connectDebugPorts = async () => {
      if (options.hasTouch) {
        const session = await page.context().newCDPSession(page);
        await session.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: outX, y: portY, id: 0 }] });
        for (let i = 1; i <= 8; i++) await session.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: outX + (inX - outX) * i / 8, y: portY, id: 0 }] });
        await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        await session.detach();
      } else {
        await page.mouse.move(outX, portY);
        await page.mouse.down();
        await page.mouse.move(inX, portY, { steps: 8 });
        await page.mouse.up();
      }
      };
      await connectDebugPorts();
      await page.waitForTimeout(300);
      const connected = image(await page.screenshot({ scale: 'css' }));
      await fs.writeFile(path.join(evidence, `${name}-wire.png`), await page.screenshot({ scale: 'css' }));
      assert.ok(hasWireAt(connected, wireX, portY), `${name}: debug ports did not create a visible connection`);
      const hpArea = { x: Math.floor(options.viewport.width / 2 - (horizontal + 68) * worldScale), y: Math.floor(portY - 30 * worldScale), width: Math.ceil(136 * worldScale), height: Math.ceil(64 * worldScale) };
      const blockArea = { x: Math.floor(allyBodyX - 80 * worldScale - 4),
        y: Math.floor(portY + 41 * worldScale),
        width: Math.ceil(160 * worldScale + 8),
        height: Math.ceil(92 * worldScale) };
      const progressBefore = await page.screenshot({ clip: blockArea, scale: 'css' });
      await page.waitForTimeout(300);
      const progressAfter = await page.screenshot({ clip: blockArea, scale: 'css' });
      assert.ok(changedPixels(progressBefore, progressAfter) > 10, `${name}: block countdown border did not animate`);
      await fs.writeFile(path.join(evidence, `${name}-block-progress.png`), progressAfter);
      const hpBefore = await page.screenshot({ clip: hpArea, scale: 'css' });
      await page.waitForTimeout(1300);
      const hpAfter = await page.screenshot({ clip: hpArea, scale: 'css' });
      assert.ok(changedPixels(hpBefore, hpAfter) > 3, `${name}: connected unit HP display did not change`);
      await fs.writeFile(path.join(evidence, `${name}-combat.png`), await page.screenshot({ scale: 'css' }));
      await activate(outX, portY);
      await page.waitForTimeout(200);
      const disconnected = image(await page.screenshot({ scale: 'css' }));
      assert.ok(!hasWireAt(disconnected, wireX, portY), `${name}: output tap did not disconnect`);
      const stopped = await page.screenshot({ clip: hpArea, scale: 'css' });
      const stoppedBlocks = await page.screenshot({ clip: blockArea, scale: 'css' });
      await page.waitForTimeout(1100);
      assert.ok(changedPixels(stopped, await page.screenshot({ clip: hpArea, scale: 'css' })) < 5, `${name}: disconnected HP kept decreasing`);
      assert.ok(changedPixels(stoppedBlocks, await page.screenshot({ clip: blockArea, scale: 'css' })) < 5, `${name}: disconnected block progress kept animating`);
      await connectDebugPorts();
      await page.waitForTimeout(200);
      await activate(inX, portY);
      await page.waitForTimeout(200);
      assert.ok(!hasWireAt(image(await page.screenshot({ scale: 'css' })), wireX, portY), `${name}: input tap did not disconnect`);
      await fs.writeFile(path.join(evidence, `${name}-disconnected.png`), await page.screenshot({ scale: 'css' }));
      // Real defeat -> visible money -> pointer pickup -> occupied inventory cell.
      await connectDebugPorts();
      await page.waitForTimeout(7000);
      const dropped = image(await page.screenshot({ scale: 'css' }));
      const gold = [];
      for (let y = 0; y < dropped.height - 60; y++) {
        for (let x = 0; x < dropped.width; x++) {
          if (near(dropped.data, (y * dropped.width + x) * 4, [244, 204, 82])) gold.push({ x, y });
        }
      }
      assert.ok(gold.length > 20, `${name}: enemy defeat did not render money`);
      const coinX = gold.reduce((sum, p) => sum + p.x, 0) / gold.length;
      const coinY = gold.reduce((sum, p) => sum + p.y, 0) / gold.length;
      await activate(coinX, coinY);
      await activate(80 * uiScale * worldScale, options.viewport.height - 36 * uiScale * worldScale);
      await page.waitForTimeout(150);
      const inventory = image(await page.screenshot({ scale: 'css' }));
      const cellX = 43 * uiScale * worldScale;
      const cellY = options.viewport.height - 254 * uiScale * worldScale;
      let inventoryGold = 0;
      for (let dy = -12; dy <= 12; dy++) for (let dx = -12; dx <= 12; dx++) {
        const x = Math.round(cellX + dx), y = Math.round(cellY + dy);
        if (near(inventory.data, (y * inventory.width + x) * 4, [244, 204, 82])) inventoryGold++;
      }
      await fs.writeFile(path.join(evidence, `${name}-inventory.png`), await page.screenshot({ scale: 'css' }));
      assert.ok(inventoryGold > 10, `${name}: pickup did not put money icon into first cell`);
      assert.deepEqual(errors, [], `${name}: browser errors`);
      console.log(`WEB_BROWSER_PASSED: ${name}, equip/wiring/HP/progress/disconnect/pickup${process.env.WEB_TEST_SCENARIO === "blocks" ? " (targeted blocks)" : ", node drag, camera, cached reload"}`);
      await page.close();
    }
    if (process.env.WEB_TEST_SCENARIO !== "blocks") for (const [name, response] of [
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
