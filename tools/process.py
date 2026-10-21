#!/usr/bin/env python3
"""Record task wall time, command durations and explicit omissions, without argv/secrets."""
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def record(path, event, **fields):
    row = {"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "event": event, **fields}
    with path.open("a") as output:
        output.write(json.dumps(row, ensure_ascii=False) + "\n")
    return row


def main():
    session, action, *args = sys.argv[1:]
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", session):
        raise ValueError("Use a unique, short task session ID")
    directory = ROOT / "build" / "process" / session
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "events.jsonl"
    if not path.exists():
        record(path, "task_started", session=session)
    if action == "run":
        phase, *command = args
        if not command or not re.fullmatch(r"[A-Za-z0-9_.-]+", phase):
            raise ValueError("run requires a phase name and a command")
        record(path, "phase_started", phase=phase)
        started = time.monotonic()
        with (directory / f"{phase}-{time.time_ns()}.log").open("w") as log:
            proc = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in proc.stdout:
                log.write(line)
                log.flush()
                print(line, end="", flush=True)
            code = proc.wait()
        seconds = round(time.monotonic() - started, 3)
        record(path, "phase_finished", phase=phase, seconds=seconds, exit_code=code)
        print(f"PROCESS_PHASE: {phase} {seconds:.3f}s exit={code}")
        return code
    if action == "skip":
        phase, reason = args
        if not reason.strip():
            raise ValueError("A skip reason is required")
        record(path, "skipped", phase=phase, reason=reason)
    elif action == "mark":
        record(path, "milestone", name=args[0])
    elif action == "summary":
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        start = datetime.datetime.fromisoformat(rows[0]["utc"])
        milestones = {r["name"]: r["utc"] for r in rows if r["event"] == "milestone"}
        total = (datetime.datetime.now(datetime.timezone.utc) - start).total_seconds()
        report = {"session": session, "started_at": rows[0]["utc"], "elapsed_seconds": round(total, 3),
                  "phases": [r for r in rows if r["event"] == "phase_finished"],
                  "omissions": [r for r in rows if r["event"] == "skipped"], "milestones": milestones,
                  "note": "Command durations may overlap other work; do not add overlapping CI/tool waits to task wall time."}
        if "preview_verified" in milestones:
            report["to_preview_verified_seconds"] = (datetime.datetime.fromisoformat(milestones["preview_verified"]) - start).total_seconds()
        (directory / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps(report, ensure_ascii=False, indent=2))
    elif action != "start":
        raise ValueError("Use start, run, skip, mark, or summary")
    return 0


if __name__ == "__main__":
    sys.exit(main())
