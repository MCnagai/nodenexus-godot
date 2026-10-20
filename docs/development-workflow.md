# Development feedback and measurement

The user's priority is quick iteration from a phone. These rules apply across tasks; the repository's AGENTS.md is the entry point for a new chat.

## Delivery path

1. Preserve the prepared runtime and current PR baseline.
2. Make the requested edit; run the smallest meaningful local check with `tools/dev-check.sh`.
3. Push. CI imports/tests/exports and runs a single mobile engine startup. Publication still requires owner-only Access verification before and after upload.
4. Deployment and full browser regression run in parallel. Return the usable protected preview promptly, stating if regression is pending. Check the regression result before calling the task fully verified.
5. Review the CI metrics and local summary. Record the largest delay and any justified omissions. Fix failed checks rather than treating earlier publication as success.

Local example:

```sh
python3 tools/process.py camera-20261020 start
NN_SESSION=camera-20261020 tools/dev-check.sh code
python3 tools/process.py camera-20261020 skip browser-full 'Full suite runs once in CI; local export/Godot tests passed.'
python3 tools/process.py camera-20261020 mark pushed
# After confirming deployment and its commit:
python3 tools/process.py camera-20261020 mark preview_verified
python3 tools/process.py camera-20261020 mark report_ready
python3 tools/process.py camera-20261020 summary
```

Scopes: `smoke`, `combat`, `code`, `preview`, `blocks`, `full`, `docs`. `blocks` reuses packaged output and defaults to the mobile profile; it skips unchanged camera/reload/error scenarios locally while CI retains the full suite. `preview` assumes a current packaged build; it does not export. Session logs contain command output: do not run commands that print credentials through the recorder. Arguments and environment variables are not automatically recorded.

CI stores step timings and job conclusions in `ci-metrics-<run-id>` for 30 days. Preview time includes queueing; job durations overlap, so their sum is not elapsed time. A warning above 120 seconds prompts investigation. Failure screenshots are retained for seven days. No scheduled service or external notification is required.

## Baseline and remaining work

The measured empty-start task took 10m50s to observed preview and 12m38s to report-ready. Local browser attempts consumed 165s, diagnosis 64s, CI 214s (including a second full browser run). Full regression occupied 109s of CI. The new path removes duplicate local full runs, publishes after the small startup gate, runs complete regression alongside publication, and caches only the Chromium headless shell. This is a change in ordering and duplication, not removal of full coverage.

Measure new runs before claiming a reduction. Remaining candidates include runner queueing, browser OS dependency installation, and Wrangler installation. Do not add caching complexity for these without evidence of a useful saving. This policy is available in other chats that use this workspace/repository; it is not a global setting for unrelated projects.
