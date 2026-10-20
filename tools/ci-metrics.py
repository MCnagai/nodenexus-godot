#!/usr/bin/env python3
"""Publish CI phase timings; token stays in the request header."""
import datetime as dt
import json
import os
from pathlib import Path
import urllib.request


def stamp(value):
    return dt.datetime.fromisoformat(value.replace('Z', '+00:00'))


def summarize(run, jobs):
    phases = []
    for job in jobs:
        if job['name'] == 'metrics':
            continue
        phases.append({'name': job['name'], 'conclusion': job['conclusion'],
                       'seconds': (stamp(job['completed_at']) - stamp(job['started_at'])).total_seconds(),
                       'steps': [{'name': step['name'], 'conclusion': step['conclusion'],
                                  'seconds': (stamp(step['completed_at']) - stamp(step['started_at'])).total_seconds()}
                                 for step in job.get('steps', []) if step.get('completed_at') and step.get('started_at')]})
    deploy = next((j for j in jobs if j['name'] == 'deploy' and j['conclusion'] == 'success'), None)
    return {'run_id': run['id'], 'commit': run['head_sha'], 'jobs': phases,
            'preview_seconds': (stamp(deploy['completed_at']) - stamp(run['created_at'])).total_seconds() if deploy else None}


def main():
    endpoint = f"{os.environ['GITHUB_API_URL']}/repos/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    def get(url):
        request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + os.environ['GITHUB_TOKEN'], 'Accept': 'application/vnd.github+json'})
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    report = summarize(get(endpoint), get(endpoint + '/jobs?per_page=100')['jobs'])
    Path('build').mkdir(exist_ok=True)
    Path('build/ci-metrics.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['### Process monitoring', f"Preview ready: {report['preview_seconds']} seconds from workflow creation (includes queueing).", '', '| Job | Seconds | Result |', '| --- | ---: | --- |']
    lines.extend(f"| {j['name']} | {j['seconds']} | {j['conclusion']} |" for j in report['jobs'])
    lines += ['', 'Full regression runs alongside deployment. Successful publication alone does not mean regression passed.', 'Detailed step durations: ci-metrics artifact. Local omissions: build/process/<session>/summary.json.']
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
        output.write('\n'.join(lines) + '\n')
    if report['preview_seconds'] is not None and report['preview_seconds'] > 120:
        print('::warning::Preview exceeded 120 seconds; review ci-metrics step durations before adding checks.')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
