import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('metrics', Path(__file__).resolve().parents[1] / 'tools/ci-metrics.py')
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class MetricsTests(unittest.TestCase):
    def test_preview_excludes_parallel_regression(self):
        run = dict(id=1, head_sha='abc', created_at='2026-10-20T00:00:00Z')
        def job(name, end, conclusion='success'):
            return dict(name=name, started_at='2026-10-20T00:00:10Z', completed_at=end, conclusion=conclusion)
        report = metrics.summarize(run, [job('deploy', '2026-10-20T00:01:00Z'), job('regression', '2026-10-20T00:03:00Z', 'failure')])
        self.assertEqual(report['preview_seconds'], 60)
        self.assertEqual(report['jobs'][1]['conclusion'], 'failure')

    def test_failed_deployment_has_no_usable_preview(self):
        report = metrics.summarize(dict(id=1, head_sha='abc', created_at='2026-10-20T00:00:00Z'), [])
        self.assertIsNone(report['preview_seconds'])
