"""Exercise only the deployment's AWK validator with synthetic env input."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = [ROOT / '.github/workflows' / f'deploy-{stack}-blue-green.yml'
             for stack in ('hub2you', 'autonomia')]
OPERATOR_KEYS = ('INSTAGRAM_TESTER_RUNTIME_STACK', 'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL',
                 'INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY')


def validator(path):
    source = path.read_text()
    beginning = "if ! awk '"
    ending = "' \"$value_file\"; then"
    if source.count(beginning) != 1 or source.count(ending) != 1:
        raise ValueError('validator boundary changed')
    return source.split(beginning, 1)[1].split(ending, 1)[0]


class OperatorEnvAllowlistTests(unittest.TestCase):
    def test_operator_configuration_is_accepted_for_both_stacks(self):
        for path in WORKFLOWS:
            stack = 'hub2you' if 'hub2you' in path.name else 'autonomia'
            values = (stack, f'https://runtime.example/{stack}/', 'a' * 64)
            body = 'INSTAGRAM_TESTER_AUTOMATION_ENABLED=false\n'
            body += ''.join(f'{key}={value}\n' for key, value in zip(OPERATOR_KEYS, values))
            with self.subTest(workflow=path.name):
                result = subprocess.run(['awk', validator(path)], input=body, text=True,
                                        capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, '')

    def test_existing_keys_comments_and_blank_lines_still_work(self):
        body = '# synthetic\n\nINSTAGRAM_TESTER_AUTOMATION_ENABLED=false\nINSTAGRAM_TESTER_PROXY_HOST=192.0.2.10\n'
        for path in WORKFLOWS:
            with self.subTest(workflow=path.name):
                result = subprocess.run(['awk', validator(path)], input=body, text=True,
                                        capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_unlisted_keys_and_malformed_lines_remain_rejected(self):
        invalid = ('DATABASE_URL=synthetic\n', 'INSTAGRAM_TESTER_OPERATOR_BROWSER_PRIVATE_KEY=synthetic\n',
                   'INSTAGRAM_TESTER_OPERATOR_BROWSER_EXTRA=synthetic\n', 'MALFORMED\n')
        for path in WORKFLOWS:
            for body in invalid:
                with self.subTest(workflow=path.name, field=body.partition('=')[0].strip()):
                    result = subprocess.run(['awk', validator(path)], input=body, text=True,
                                            capture_output=True, timeout=5)
                    self.assertNotEqual(result.returncode, 0)

    def test_duplicate_operator_key_remains_rejected(self):
        for path in WORKFLOWS:
            for key in OPERATOR_KEYS:
                body = f'{key}=first\n{key}=second\n'
                with self.subTest(workflow=path.name, key=key):
                    result = subprocess.run(['awk', validator(path)], input=body, text=True,
                                            capture_output=True, timeout=5)
                    self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
