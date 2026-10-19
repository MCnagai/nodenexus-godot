# NodeNexus – Godot browser-first starter

A fresh Godot 4.7.2 / GDScript project for Codex-driven development and Android Chrome playtesting. No Unity code has been transferred.

## Current state
- Camera prototype with repeating procedural grass, a 100-unit grid, and temporary node markers.
- Minimap shows the whole 6000 × 6000 map, node markers, and the current viewport.
- Desktop: right-button drag to pan; wheel to zoom around the pointer (30–250%).
- Touch: two-finger drag to pan, pinch to zoom; hold still for 0.5 seconds to invoke the same context signal as right-click, then drag to pan. Moving more than 12 logical pixels cancels the hold.
- Single-finger movement is reserved for future node interactions. Minimap is display-only.
- Camera stays inside the map; focus loss clears held inputs.
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

Run `bash tools/verify.sh` to activate the prepared environment, verify the engine version, and run all checks including Web export. It stops on the first failure.
In the prepared managed workspace, run `source /workspace/.environment/activate.sh` first to select Godot 4.7.2 and its installed Web templates. Elsewhere, install matching Godot 4.7.2 Web export templates, then:

```sh
godot --headless --path . --import
godot --headless --path . --script res://tests/test_smoke.gd
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
```

Serve `build/web` over HTTP(S). The mobile browser must be tested separately from CI.

The project and workflow are starter code; deployment and Android Chrome play have not yet been verified.

Camera changes were validated with the prepared Godot 4.7.2 environment: headless import, smoke test, and Web export. Android Chrome gesture behavior still needs device testing.
