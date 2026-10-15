#!/usr/bin/env python3
"""Package Godot's Web output for Pages' 25 MiB asset limit."""
import gzip
import json
import os
import subprocess
import sys
from pathlib import Path


def prepare(root: Path) -> None:
    wasm = root / "index.wasm"
    data = wasm.read_bytes()
    if data.startswith(b"\0asm"):
        wasm.write_bytes(gzip.compress(data, compresslevel=9, mtime=0))
    elif not data.startswith(b"\x1f\x8b") or not gzip.decompress(data).startswith(b"\0asm"):
        raise ValueError("index.wasm is not valid WebAssembly")
    (root / "_headers").write_text(
        "/*\n  Cache-Control: no-store\n  X-Content-Type-Options: nosniff\n"
        "  X-Robots-Tag: noindex, nofollow\n"
        "/index.wasm\n  Content-Type: application/wasm\n  Content-Encoding: gzip\n"
    )
    # Avoid Pages' SPA fallback hiding a missing asset behind an HTML 200 response.
    (root / "404.html").write_text("<!doctype html><title>Not found</title>Not found\n")
    sha = os.environ.get("BUILD_SHA") or subprocess.check_output(
        ["git", "rev-parse", "HEAD"], text=True
    ).strip()
    (root / "build-info.json").write_text(json.dumps({"commit": sha, "godot": "4.7.2", "indicator": "red"}) + "\n")
    for file in root.rglob("*"):
        if file.is_file() and file.stat().st_size > 25 * 1024 * 1024:
            raise ValueError(f"Pages asset exceeds 25 MiB: {file.name}")
    print(f"PAGES_PACKAGE_PASSED: wasm={wasm.stat().st_size} bytes; commit={sha}")


if __name__ == "__main__":
    prepare(Path(sys.argv[1]))
