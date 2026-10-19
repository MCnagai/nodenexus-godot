#!/usr/bin/env python3
"""Build a cached, explicitly decoded Web package within Pages' asset limit."""
import gzip
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def prepare(root: Path) -> None:
    source = Path(__file__).resolve().parents[1] / 'web'
    original_html = (root / 'index.html').read_text()
    match = re.search(r'const GODOT_CONFIG = (\{[^\n]+\});', original_html)
    if not match:
        raise ValueError('Godot export configuration was not found; re-export before packaging')
    godot = json.loads(match.group(1))
    data = (root / 'index.wasm').read_bytes()
    if data.startswith(b'\x1f\x8b'):
        data = gzip.decompress(data)
    if not data.startswith(b'\0asm'):
        raise ValueError('index.wasm is not valid WebAssembly')
    assets = root / 'assets'
    assets.mkdir(exist_ok=True)
    compressed = gzip.compress(data, compresslevel=9, mtime=0)
    wasm_name = f'assets/engine.{hashlib.sha256(data).hexdigest()[:16]}.wasm.gz'
    (root / wasm_name).write_bytes(compressed)
    (root / 'index.wasm').unlink()
    engine_data = (root / 'index.js').read_bytes()
    engine_name = f'assets/engine.{hashlib.sha256(engine_data).hexdigest()[:16]}.js'
    (root / engine_name).write_bytes(engine_data)
    (root / 'index.js').unlink()
    loader_data = (source / 'loader.js').read_bytes()
    loader_name = f'assets/loader.{hashlib.sha256(loader_data).hexdigest()[:16]}.js'
    (root / loader_name).write_bytes(loader_data)
    boot = {'godot': godot, 'wasm': wasm_name, 'wasmSize': len(compressed)}
    html = (source / 'shell.html').read_text().replace('__BOOT_CONFIG__', json.dumps(boot)).replace('__ENGINE_SCRIPT__', engine_name).replace('__LOADER_SCRIPT__', loader_name)
    (root / 'index.html').write_text(html)
    # Cache only fingerprinted engine files in the signed-in browser. HTML/pack stay fresh.
    # No Content-Encoding override: gzip payload decoding is explicit in the loader.
    (root / '_headers').write_text(
        '/\n  Cache-Control: no-store\n/index.html\n  Cache-Control: no-store\n'
        '/index.pck\n  Cache-Control: no-store\n/build-info.json\n  Cache-Control: no-store\n'
        '/assets/*\n  Cache-Control: private, max-age=31536000, immutable\n'
        '/*\n  X-Content-Type-Options: nosniff\n  X-Robots-Tag: noindex, nofollow\n'
    )
    (root / '404.html').write_text('<!doctype html><title>Not found</title>Not found\n')
    sha = os.environ.get('BUILD_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    metadata = {'commit': sha, 'godot': '4.7.2', 'indicator': 'red', 'wasm': wasm_name, 'engine': engine_name, 'loader': loader_name}
    (root / 'build-info.json').write_text(json.dumps(metadata) + '\n')
    for file in root.rglob('*'):
        if file.is_file() and file.stat().st_size > 25 * 1024 * 1024:
            raise ValueError(f'Pages asset exceeds 25 MiB: {file.name}')
    print(f'PAGES_PACKAGE_PASSED: wasm={len(compressed)} bytes; explicit gzip; commit={sha}')


if __name__ == '__main__':
    prepare(Path(sys.argv[1]))
