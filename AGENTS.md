# NodeNexus – Codex working agreement

- This repository is a new Godot 4.7.2 GDScript project. Do not import or copy the old Unity game.
- Keep Web compatible with Android Chrome: Compatibility renderer and single-thread Web export.
- Work in focused branches and pull requests, not directly on the default branch.
- Do not invent gameplay mechanics or redesign features without the user's request.
- In the managed workspace, source `/workspace/.environment/activate.sh` before running Godot when that file exists. It selects the prepared Godot 4.7.2 binary and Web templates via PATH and XDG_DATA_HOME; verify `godot --version`.
- Use `bash tools/verify.sh` for local verification: it activates the prepared environment, checks Godot 4.7.2, imports, runs the smoke test, and exports Web. If an engine or template appears missing, inspect the existing activation/setup paths before reporting it as uninstalled.
- Never commit credentials or generated builds.
- Explain tests performed and limitations in each PR.
