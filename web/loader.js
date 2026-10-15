/* Explicit gzip decoding keeps Pages' transport compression independent of WASM bytes. */
(() => {
  const boot = window.NODE_NEXUS;
  const nativeFetch = window.fetch.bind(window);
  const overlay = document.getElementById('status');
  const message = document.getElementById('status-message');
  const progress = document.getElementById('status-progress');
  const state = { phase: 'preparing', downloaded: 0, started: false, error: '', engineCacheHit: false };
  window.nodeNexusStatus = state;
  let failed = false;
  let deadline;
  let engineCache;
  let engineCacheKey;
  let cacheWrite = Promise.resolve();
  function phase(value, text) {
    if (failed && value !== 'error') return;
    state.phase = value; message.textContent = text;
  }
  function failure(error) {
    if (failed || state.started) return;
    failed = true;
    clearTimeout(deadline);
    const detail = error instanceof Error ? error.message : String(error);
    state.error = detail;
    phase('error', '読み込みを完了できませんでした。もう一度お試しください。');
    progress.hidden = true;
    document.getElementById('status-notice').textContent = detail;
    document.getElementById('error-details').hidden = false;
    document.getElementById('retry').hidden = false;
    console.error('NodeNexus load failed:', detail);
    cacheWrite.finally(() => engineCache?.delete(engineCacheKey)).catch(() => {});
  }
  window.nodeNexusFailure = failure;
  document.getElementById('retry').onclick = () => location.reload();
  window.addEventListener('unhandledrejection', event => { failure(event.reason); });
  window.addEventListener('error', event => { failure(event.error || event.message); });
  deadline = setTimeout(() => failure(new Error(`読み込みの時間制限に達しました (${state.phase})。`)), 180000);

  window.fetch = async (input, options) => {
    const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, location.href);
    if (url.origin !== location.origin || url.pathname !== '/index.wasm') return nativeFetch(input, options);
    let timeout;
    try {
      if (!('DecompressionStream' in window)) throw new Error('Chrome を最新のバージョンに更新してください。');
      phase('download', 'ゲームをダウンロードしています…');
      const controller = new AbortController();
      timeout = setTimeout(() => controller.abort(), 120000);
      // Fingerprinted assets use the browser cache; Access cookies stay same-origin.
      engineCacheKey = new URL(boot.wasm, location.href).href;
      try { engineCache = await caches.open('nodenexus-runtime-v1'); } catch { /* HTTP cache remains available when storage is restricted. */ }
      let response = engineCache ? await engineCache.match(engineCacheKey) : null;
      state.engineCacheHit = Boolean(response);
      if (!response) response = await nativeFetch(boot.wasm, { credentials: 'same-origin', redirect: 'error', cache: 'force-cache', signal: controller.signal });
      if (!response.ok || response.headers.get('content-type')?.includes('text/html')) throw new Error(`ゲームファイルを取得できませんでした (HTTP ${response.status})。`);
      if (engineCache && !state.engineCacheHit) cacheWrite = engineCache.put(engineCacheKey, response.clone()).catch(() => {});
      const reader = response.body.getReader();
      const stream = new ReadableStream({
        async pull(destination) {
          try {
            const { value, done } = await reader.read();
            if (failed) { destination.error(new Error(state.error)); return; }
            if (done) {
              await cacheWrite;
              clearTimeout(timeout);
              phase('starting', 'ゲームを起動しています…');
              progress.removeAttribute('value');
              destination.close();
              return;
            }
            state.downloaded += value.byteLength;
            progress.max = boot.wasmSize;
            progress.value = state.downloaded;
            message.textContent = `ダウンロード中 ${Math.min(100, Math.round(state.downloaded / boot.wasmSize * 100))}%`;
            destination.enqueue(value);
          } catch (error) {
            clearTimeout(timeout);
            failure(error);
            destination.error(error);
          }
        },
        cancel(reason) { clearTimeout(timeout); return reader.cancel(reason); },
      });
      const decoded = stream.pipeThrough(new DecompressionStream('gzip')).getReader();
      const checked = new ReadableStream({
        async pull(destination) {
          try {
            const { value, done } = await decoded.read();
            if (done) destination.close();
            else destination.enqueue(value);
          } catch (error) {
            failure(error);
            destination.error(error);
          }
        },
        cancel(reason) { return decoded.cancel(reason); },
      });
      return new Response(checked, { headers: { 'Content-Type': 'application/wasm' } });
    } catch (error) {
      clearTimeout(timeout);
      failure(error);
      throw error;
    }
  };
  window.startNodeNexus = async () => {
    try {
      if (failed) return;
      const missing = Engine.getMissingFeatures({ threads: false });
      if (missing.length) throw new Error(missing.join('\n'));
      const engine = new Engine({ ...boot.godot, onPrintError: (...args) => console.error(...args) });
      await engine.startGame();
      if (failed) return;
      clearTimeout(deadline);
      state.started = true;
      phase('running', '');
      overlay.remove();
    } catch (error) { failure(error); }
  };
})();
