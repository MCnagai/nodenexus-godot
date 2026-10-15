# NodeNexus – Codex working agreement

- This repository is a new Godot 4.7.2 GDScript project. Do not import or copy the old Unity game.
- Keep Web compatible with Android Chrome: Compatibility renderer and single-thread Web export.
- Work in focused branches and pull requests, not directly on the default branch.
- Do not invent gameplay mechanics or redesign features without the user's request.
- Run headless import and the smoke test, and Web export when templates are available.
- Use `tools/check-web.sh` for these checks and `tools/godot.sh` for individual commands; the wrapper activates the managed runtime and verifies Godot 4.7.2.
- In the managed sandbox, request `network.enabled: true` for editor imports, exports, local HTTP previews, and browser checks. Without socket access, Godot's editor reports TCP listener errors and the HTTP proxy is unreachable. Keep the configured proxy and TLS verification enabled.
- Never commit credentials or generated builds.
- Explain tests performed and limitations in each PR.
