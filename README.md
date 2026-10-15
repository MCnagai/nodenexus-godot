# NodeNexus – Godot browser-first starter

A fresh Godot 4.7.2 / GDScript project for Codex-driven development and Android Chrome playtesting. No Unity code has been transferred.

## Current state
- Tap-responsive Godot 2D smoke-test scene.
- Headless smoke test at `tests/test_smoke.gd`.
- GitHub Actions Web export workflow.
- Cloudflare Pages direct-upload step **only runs after secrets/variable are configured**.

## Codex
Connect this repository in Codex Cloud and ask for changes on branches via pull requests. Consult `AGENTS.md`.

## Cloudflare setup
1. Create Cloudflare Pages project via **Direct Upload**.
2. In GitHub Settings → Secrets and variables → Actions:
   - secret `CLOUDFLARE_API_TOKEN` with Pages Edit permission;
   - secret `CLOUDFLARE_ACCOUNT_ID`;
   - variable `CLOUDFLARE_PAGES_PROJECT` set to the exact Pages project name.
3. Run the GitHub Actions workflow or push a branch. The deploy step is skipped until configured.
4. Restrict preview access with Cloudflare Access. A public GitHub repository and/or preview URL exposes the project.

## Local verification
In the configured cloud environment, run `./tools/check-web.sh` to import,
test, and export with the installed Godot 4.7.2 and matching templates.
The wrapper activates `/workspace/.environment/activate.sh` when available;
elsewhere install the matching engine/templates and optionally set `GODOT_BIN`.
For an individual command, use `./tools/godot.sh --headless --script res://tests/test_smoke.gd`.

Cloud sandbox commands that run the editor, serve HTTP, or launch a browser need
network permission (`network.enabled: true`). This permits local sockets and
access through the configured proxy; it does not change the outbound allowlist.
Without it, editor TCP listeners and proxy connections fail even though the
environment itself is running. User data, cache, and settings use the writable
XDG directories selected by the activation script.

Install matching Godot 4.7.2 Web export templates, then:

```sh
godot --headless --path . --import
godot --headless --path . --script res://tests/test_smoke.gd
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
```

Serve `build/web` over HTTP(S). The mobile browser must be tested separately from CI.
For a local preview, run `python3 -m http.server 8000 --bind 127.0.0.1 --directory build/web`
and open `http://127.0.0.1:8000` in the same environment.

Cloud verification on 2026-10-15 passed import, the GDScript smoke test, and Web
export on Godot 4.7.2. Headless Chromium loaded the single-thread WebGL build;
desktop clicks and touch input at a 412 × 915 mobile viewport changed the counter
and indicator color. Android hardware and deployment have not yet been verified.
