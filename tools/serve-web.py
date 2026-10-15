#!/usr/bin/env python3
"""Serve the Pages package locally with the same compression headers."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class PagesHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def end_headers(self):
        cache = "private, max-age=31536000, immutable" if self.path.startswith("/assets/") else "no-store"
        self.send_header("Cache-Control", cache)
        super().end_headers()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--bind", default="127.0.0.1")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent / "build" / "web"
    with ThreadingHTTPServer((args.bind, args.port), partial(PagesHandler, directory=str(root))) as server:
        print(f"Preview: http://{args.bind}:{server.server_port}", flush=True)
        server.serve_forever()
