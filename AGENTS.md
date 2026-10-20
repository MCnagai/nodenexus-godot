# NodeNexus – Codex working agreement

## Continuity and delivery

- This is the author's Godot 4.7.2 GDScript rebuild of NodeNexus. Do not copy the old Unity game or invent unrequested mechanics.
- Preserve Compatibility rendering, single-thread Web export, Android Chrome support, and owner-only Cloudflare Access (including pre-upload verification).
- Before editing, inspect status, branch, and open prerequisite PRs. The working runtime/game/deployment baseline is PR #2, `feat/map-camera-controls`; default master may still be the starter. Preserve dirty work and prerequisite setup rather than rebuilding it. Do not merge without a request.
- For an interactive change, completion includes updating the protected phone preview, checking the deployed commit, and returning its URL. Distinguish automated emulation from real-device acceptance.
- Use the prepared environment through `tools/godot.sh`; never reinstall templates before checking the wrapper/runtime. Keep proxy and TLS verification. Never commit credentials or generated builds.

## Fast checks and explicit omissions (user-authorized ongoing policy)

- Start each task with `python3 tools/process.py SESSION start` using a unique session ID. Record meaningful commands with `... SESSION run PHASE COMMAND...`; record milestones `pushed`, `preview_verified`, `report_ready`. Record skipped checks with `... SESSION skip PHASE 'concrete reason'`. Finish with `... SESSION summary`. Logs are ignored under `build/process/SESSION/`.
- Use `NN_SESSION=SESSION tools/dev-check.sh SCOPE`. Choose the smallest relevant local scope: `combat`, `items` or `smoke` for isolated GDScript; `code` for import, Godot tests, and packaged Web export; `preview` for one mobile engine startup against existing output; `blocks` for packaged equip/combat/progress/drop interactions (mobile by default, override WEB_TEST_PROFILE for another profile); `full` only for broad interaction/runtime changes needing local reproduction; `docs` for documentation-only edits.
- CI always performs Godot checks/export and one mobile startup before publication. Full desktop/portrait/landscape interaction, loader, reload, and failure regressions run alongside deployment in the `regression` job. Do not repeat the entire browser suite locally merely because it exists. Do not claim regression passed while pending; fix failures and never merge with failed checks.
- Keep full regression, access tests, and pre/post-publication Access gates. Speed comes from avoiding duplicate work, selecting targeted local checks, caching, and overlapping regression with preview deployment. Do not silently remove coverage.
- On test failure, inspect the failure screenshot/log and changed fixture/coordinates before guessing. Reproduce the failing scenario first; avoid rerunning unrelated browser contexts.
- Batch independent reads. Avoid redundant repository discovery, repeated PR attachment when already attached, unnecessary screenshots, and polling unchanged CI state. Give progress at least once a minute during long work.
- CI `metrics` records job/step durations, queue-inclusive time to preview, and regression results in its summary and `ci-metrics` artifact on every code run. Inspect these for each delivery; compare with previous runs and identify the largest remaining delay. A preview over 120 seconds produces a warning, not a skipped check.
- Report elapsed time from task start to usable preview separately from final reporting. Never add overlapping waits or parallel CI jobs to wall time. Explain material omissions and pending checks. Keep monitoring and justified omissions on subsequent tasks without asking again.
- Documentation-only changes skip game CI; changes to CI, scripts, dependencies, loader, or game files do not. For workflow changes validate one complete CI run, including regression and metrics.

See [workflow policy](docs/development-workflow.md) and [phone setup](docs/mobile-setup.md).
