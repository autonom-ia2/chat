"""Unit contracts for the fixed production operations runner; no external calls."""
import importlib.util
from pathlib import Path
import base64
import gzip
import json
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("operations", Path(__file__).with_name("relationships_operations.py"))
ops = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ops)


class OperationsContracts(unittest.TestCase):
    def test_accepts_only_reviewed_stacks_and_actions(self):
        for action in ops.ACTIONS:
            for tenant, account in ops.ACCOUNTS.items():
                ops.validate(action, tenant, account, "a" * 40)
        for values in [("shell", "hub2you", "354307071110", "a" * 40),
                       ("enable", "hub2you", "140023375763", "a" * 40),
                       ("verify", "third-party", "354307071110", "a" * 40)]:
            with self.assertRaises(ValueError):
                ops.validate(*values)

    def test_sha_is_never_interpreted_as_shell_or_branch(self):
        for value in ["main", "a" * 39, "a" * 41, "a" * 39 + ";", "A" * 40, "$(id)"]:
            with self.assertRaises(ValueError):
                ops.validate("enable", "hub2you", "354307071110", value)

    def test_mismatched_aws_identity_aborts_before_ssm(self):
        with patch.object(ops, "aws", return_value={"Account": "wrong"}) as call:
            with self.assertRaises(RuntimeError):
                ops.preflight("354307071110")
            self.assertEqual(call.call_count, 1)

    def test_fixed_command_requires_both_web_and_worker_sha_and_hides_raw_output(self):
        invocations = []
        def fake(*args):
            invocations.append(args)
            if args[1] == "send-command":
                return {"Command": {"CommandId": "synthetic-command"}}
            return {"Status": "Success", "StandardOutputContent": "not for reports\n" + ops.MARKER + json.dumps({'encoding': 'gzip-base64', 'payload': base64.b64encode(gzip.compress(b'{"checks":true}')).decode()})}
        with patch.object(ops, "aws", side_effect=fake), patch.object(ops.time, "sleep"):
            result = ops.invoke("i-synthetic", "verify", "a" * 40)
        self.assertEqual(result["application"], {"checks": True})
        arguments = invocations[0]
        parameters = ops.json.loads(arguments[arguments.index("--parameters") + 1])
        command = parameters["commands"][0]
        self.assertIn("chatwoot-web cat /app/.git_sha", command)
        self.assertIn("chatwoot-worker cat /app/.git_sha", command)
        self.assertIn("RELATIONSHIPS_OP_ACTION=verify", command)
        syntax = subprocess.run(["sh", "-n"], input=command, text=True, capture_output=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        self.assertEqual(parameters["executionTimeout"], ["240"])

    def test_large_reviewed_snapshot_fits_the_ssm_transport(self):
        rows = [{"id": number, "active": True, "eligible": {name: True for name in ["relationships_navigation", "relationships_attributes", "relationships_company_media"]}, "enabled": {name: True for name in ["relationships_navigation", "relationships_attributes", "relationships_company_media"]}} for number in range(500)]
        report = {"accounts_before": rows, "accounts_after": rows}
        text = json.dumps({"encoding": "gzip-base64", "payload": base64.b64encode(gzip.compress(json.dumps(report).encode())).decode()})
        self.assertLess(len(text), 20_000)
        self.assertEqual(ops.decode_report(text), report)

    def test_report_decompression_is_bounded(self):
        text = json.dumps({"encoding": "gzip-base64", "payload": base64.b64encode(gzip.compress(b'x' * 1_000_001)).decode()})
        with self.assertRaises(ValueError):
            ops.decode_report(text)

    def test_failed_runtime_cannot_be_reported_as_success(self):
        def fake(*args):
            if args[1] == "send-command":
                return {"Command": {"CommandId": "synthetic-command"}}
            return {"Status": "Failed", "StandardOutputContent": "private runtime output"}
        with patch.object(ops, "aws", side_effect=fake), patch.object(ops.time, "sleep"):
            with self.assertRaises(RuntimeError):
                ops.invoke("i-synthetic", "enable", "a" * 40)


if __name__ == "__main__":
    unittest.main()
