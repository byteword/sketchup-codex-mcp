import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
RUNNER = ROOT / 'skills/sketchup-self-test/scripts/run_native_tests.py'
SESSION = '11111111-1111-4111-8111-111111111111'
MODEL = '22222222-2222-4222-8222-222222222222'


class NativeRunnerTest(unittest.TestCase):
    def run_case(self, mode, model=MODEL):
        with tempfile.TemporaryDirectory(dir=ROOT / 'dist') as directory:
            folder = pathlib.Path(directory)
            self.assertTrue(folder.resolve().is_relative_to((ROOT / 'dist').resolve()))
            output, log = folder / 'report.json', folder / 'calls.txt'
            command = [sys.executable, str(RUNNER), '--mcp-exe', sys.executable,
                       '--mcp-arg', str(ROOT / 'tests/smoke_adapter_fixture.py'),
                       '--mcp-arg', mode, '--mcp-arg', str(log), '--session-id', SESSION,
                       '--model-id', model, '--confirm-test-model', '--timeout', '1', '--output', str(output)]
            result = subprocess.run(command, capture_output=True, timeout=15)
            self.assertTrue(output.is_file(), (result.stdout,result.stderr))
            report = json.loads(output.read_text(encoding='utf-8'))
            calls = log.read_text(encoding='utf-8').splitlines()
            return result, report, calls

    def test_one_batch_command_writes_a_structured_report(self):
        process, report, calls = self.run_case('ok')
        self.assertEqual(0, process.returncode, process.stderr)
        self.assertEqual('passed', report['status'])
        self.assertEqual(56, report['report']['passed_count'])
        self.assertEqual(1, calls.count('sketchup_run_self_test'))

    def test_missing_permission_stops_before_mutation(self):
        process, report, calls = self.run_case('permission')
        self.assertEqual(1, process.returncode)
        self.assertEqual('blocked', report['status'])
        self.assertNotIn('sketchup_run_self_test', calls)

    def test_version_mismatch_stops_before_mutation(self):
        _, report, calls = self.run_case('version')
        self.assertEqual('blocked', report['status'])
        self.assertNotIn('sketchup_run_self_test', calls)

    def test_stale_model_never_runs_a_test(self):
        _, report, calls = self.run_case('ok', '33333333-3333-4333-8333-333333333333')
        self.assertEqual('blocked', report['status'])
        self.assertNotIn('sketchup_run_self_test', calls)

    def test_old_schema_is_blocked_before_submitting_extended_test(self):
        _, report, calls = self.run_case('old_schema')
        self.assertEqual('blocked', report['status'])
        self.assertNotIn('sketchup_run_self_test', calls)

    def test_lost_response_uses_result_lookup_without_rerunning(self):
        process, report, calls = self.run_case('lost')
        self.assertEqual(0, process.returncode, process.stderr)
        self.assertTrue(report['recovered_by_result_lookup'])
        self.assertEqual(1, calls.count('sketchup_run_self_test'))
        self.assertEqual(1, calls.count('sketchup_get_command_result'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
