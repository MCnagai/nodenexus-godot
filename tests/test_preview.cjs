// Fast publication gate: one real mobile engine startup, no repeated gameplay suite.
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const { chromium } = require('playwright');
(async () => {
  const server = spawn('python3', ['tools/serve-web.py', '--port', '0'], { stdio: ['ignore', 'pipe', 'pipe'] });
  let browser;
  try {
    const url = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Preview server startup timeout')), 10000);
      server.once('error', reject);
      server.once('exit', code => reject(new Error(`Preview server exited: ${code}`)));
      server.stdout.on('data', data => {
        const match = data.toString().match(/http:\/\/127\.0\.0\.1:\d+/);
        if (match) { clearTimeout(timer); resolve(match[0]); }
      });
    });
    browser = await chromium.launch({ headless: true,
      ...(process.env.BROWSER_EXECUTABLE ? { executablePath: process.env.BROWSER_EXECUTABLE } : {}),
      args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
    const page = await browser.newPage({ viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true, deviceScaleFactor: 3 });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (/SCRIPT ERROR:|^ERROR:/.test(message.text())) errors.push(message.text()); });
    page.on('response', response => { if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) errors.push(`HTTP ${response.status()}`); });
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => window.nodeNexusStatus?.started, null, { timeout: 30000 });
    await page.waitForFunction(() => {
      const c = document.querySelector('#canvas');
      return c?.width === 412 && c.height === 915 && !document.querySelector('#status');
    }, null, { timeout: 10000 });
    await fs.mkdir('build/evidence', { recursive: true });
    await page.screenshot({ path: 'build/evidence/preview-mobile.png', scale: 'css' });
    assert.deepEqual(errors, []);
    console.log('PREVIEW_SMOKE_PASSED: mobile engine startup; full regression is separate');
  } finally {
    if (browser) await browser.close();
    server.kill();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
