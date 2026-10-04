"""Synthetic subprocess-only tests: no AWS or n8n access."""
import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import patch

PATH = Path(__file__).resolve().parents[2] / 'scripts/instagram_testers/runtime/publish-coordination-parameters.py'
SPEC = importlib.util.spec_from_file_location('publisher', PATH)
p = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(p)


class PublisherTest(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(p.os.environ, {'PATH': '/synthetic/bin'}, clear=True)
        environment.start()
        self.addCleanup(environment.stop)
        self.calls = []
        self.environments = []
        self.existing = {}
        self.data = {'ca': '-----BEGIN CERTIFICATE-----\nYWJj\n-----END CERTIFICATE-----\n',
                     'host': 'ssh-ed25519 ' + base64.b64encode(b'\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x20' + b'x' * 32).decode()}
        for _, _, user in p.STACKS:
            self.data[user + '.key'] = '-----BEGIN OPENSSH PRIVATE KEY-----\nYWJj\n-----END OPENSSH PRIVATE KEY-----\n'
            self.data[user + '.env'] = (f'INSTAGRAM_TESTER_COORDINATION_REDIS_URL=rediss://{user}:' + 'a' * 64
                                       + '@ig-coord.internal:16381/0\nINSTAGRAM_TESTER_COORDINATION_EPOCH='
                                       + 'b' * 64 + '\nINSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE=/run/igcoord/ca.crt\n')
        self.account_wrong = False
        self.host_wrong = False
        self.command_fails = False
        self.fail_operation = None
        self.fail_profile = None
        self.fail_identity_at = None
        self.identities = 0
        self.readback_mode = None

    def fake(self, args, **kwargs):
        self.calls.append((args, kwargs.get('input')))
        self.environments.append(kwargs.get('env'))
        if self.command_fails:
            return subprocess.CompletedProcess(args, 1, 'SECRET', 'SECRET')
        if args[0] == 'ssh':
            if '-G' in args:
                output = 'hostname ' + ('evil.example' if self.host_wrong else p.HOST) + '\nport 22\n'
            else:
                output = json.dumps(self.data if args[-1].endswith('read') else dict.fromkeys(self.data, 'metadata-ok'))
        else:
            if '--cli-input-json' in args:
                return subprocess.CompletedProcess(args, 1, '', 'Invalid JSON received')
            profile = args[args.index('--profile') + 1]
            operation = next(arg for arg in args if arg in (
                'get-caller-identity', 'describe-parameters', 'get-parameter', 'put-parameter'))
            self.assertIn('--no-cli-auto-prompt', args)
            self.assertEqual(kwargs['env']['AWS_CLI_AUTO_PROMPT'], 'off')
            self.assertEqual(kwargs['env']['AWS_PAGER'], '')
            if operation != 'put-parameter':
                self.assertIsNone(kwargs.get('input'))
            if operation == 'get-caller-identity':
                self.identities += 1
            if ((operation == self.fail_operation and profile == self.fail_profile)
                    or (operation == 'get-caller-identity' and self.identities == self.fail_identity_at)):
                return subprocess.CompletedProcess(args, 1, 'SECRET', 'SECRET Invalid JSON')
            if operation == 'get-caller-identity':
                output = json.dumps({'Account': 'wrong' if self.account_wrong else dict((a, b) for a, b, _ in p.STACKS)[profile]})
            elif operation == 'describe-parameters':
                parameter_filter = args[args.index('--parameter-filters') + 1]
                self.assertTrue(parameter_filter.startswith('Key=Name,Option=Equals,Values='))
                name = parameter_filter.split('Values=', 1)[1]
                old = self.existing.get((profile, name))
                output = json.dumps({'Parameters': [] if old is None else [{'Name': name, 'Type': old['Type']}]})
            elif operation == 'get-parameter':
                self.assertIn('--with-decryption', args)
                parameter = self.existing[profile, args[args.index('--name') + 1]].copy()
                if self.readback_mode == 'unknown':
                    raise ValueError('SECRET readback payload')
                if self.readback_mode == 'failure':
                    return subprocess.CompletedProcess(args, 1, 'SECRET', 'SECRET')
                if self.readback_mode in ('Name', 'Type', 'Value'):
                    parameter[self.readback_mode] = 'divergent'
                output = json.dumps({'Parameter': parameter})
            elif operation == 'put-parameter':
                self.assertIn('--no-overwrite', args)
                self.assertNotIn('--overwrite', args)
                self.assertEqual(args[args.index('--value') + 1], 'file:///dev/stdin')
                name = args[args.index('--name') + 1]
                self.existing[profile, name] = {'Name': name, 'Type': args[args.index('--type') + 1],
                                                'Value': kwargs['input']}
                output = '{}'
            else:
                self.fail(operation)
        return subprocess.CompletedProcess(args, 0, output, '')

    def execute(self, apply=False, tty=True, confirmation=None, entrypoint=False):
        stdin = io.StringIO((p.CONFIRM if confirmation is None else confirmation) + '\n')
        stdout = io.StringIO()
        self.stdout = stdout
        self.stderr = io.StringIO()
        with patch.object(p.subprocess, 'run', side_effect=self.fake), patch.object(p.sys, 'argv', ['publisher'] + (['--apply'] if apply else [])), patch.object(p.sys, 'stdin', stdin), patch.object(stdin, 'isatty', return_value=tty), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(self.stderr):
            if entrypoint:
                self.assertEqual(p.entrypoint(), 1)
            else:
                p.main()
        return stdout.getvalue()

    def test_default_reads_metadata_only(self):
        self.assertEqual(len(self.execute().splitlines()), 8)
        self.assertTrue(self.calls[-1][0][-1].endswith('check'))
        self.assertFalse(any('get-parameter' in c or 'put-parameter' in c for c, _ in self.calls))

    def test_apply_creates_with_stdin_payload_and_account_check(self):
        output = self.execute(True)
        puts = [(i, c, body) for i, (c, body) in enumerate(self.calls) if 'put-parameter' in c]
        self.assertEqual(len(puts), 8)
        for i, args, body in puts:
            self.assertIn('get-caller-identity', self.calls[i - 1][0])
            self.assertIn('get-parameter', self.calls[i + 1][0])
            read_args, read_body = self.calls[i + 1]
            self.assertEqual(read_args[read_args.index('--name') + 1], args[args.index('--name') + 1])
            self.assertIn('--with-decryption', read_args)
            self.assertIsNone(read_body)
            self.assertIn('file:///dev/stdin', args)
            self.assertNotIn(body, args)
            profile = args[args.index('--profile') + 1]
            name = args[args.index('--name') + 1]
            self.assertEqual(self.existing[profile, name]['Value'], body)
            user = next(user for stack, _, user in p.STACKS if stack == profile)
            suffix = name.removeprefix(p.PREFIX)
            expected = (self.data[user + '.key'] if suffix == 'ssh-key' else
                        self.data[user + '.env'] if suffix == 'redis-env' else
                        self.data['ca'] if suffix == 'ca' else p.HOST + ' ' + self.data['host'] + '\n')
            self.assertEqual(body, expected)
        self.assertNotIn('rediss://', output)
        self.assertNotIn('YWJj', output)

    def test_consent_and_tty_before_any_subprocess(self):
        for tty, answer in ((False, p.CONFIRM), (True, 'no')):
            with self.assertRaises(ValueError):
                self.execute(True, tty, answer)
            self.assertEqual(self.calls, [])

    def test_aws_operations_avoid_invalid_json_stdin(self):
        self.execute(True)
        for args, body in self.calls:
            if args[0] == 'aws':
                self.assertNotIn('--cli-input-json', args)
                if 'put-parameter' not in args:
                    self.assertIsNone(body)

    def test_put_stdin_preserves_raw_multiline_without_serialization(self):
        for value in ('  synthetic-key\nline "two"\\tail\n\n', 'synthetic-without-final-newline'):
            with self.subTest(value=value), patch.object(p.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '{}', '')) as command:
                p.aws('hub2you', 'ssm', 'put-parameter', {'Name': p.PREFIX + 'ssh-key',
                      'Type': 'SecureString', 'Value': value, 'Overwrite': False})
                self.assertEqual(command.call_args.kwargs['input'], value)
                self.assertIn('--no-overwrite', command.call_args.args[0])
                self.assertNotIn(value, command.call_args.args[0])

    def test_synthetic_credentials_only_reach_put_stdin(self):
        values = (self.data['ig_hub.key'], self.data['ig_auto.env'], 'a' * 64, 'b' * 64)
        with patch.dict(p.os.environ, {'PATH': '/synthetic/bin'}, clear=True):
            self.execute(True)
            for (args, _), env in zip(self.calls, self.environments):
                for value in values:
                    self.assertNotIn(value, ' '.join(args))
                    self.assertNotIn(value, json.dumps(env))
            self.assertEqual(dict(p.os.environ), {'PATH': '/synthetic/bin'})
        for value in values:
            self.assertNotIn(value, self.stdout.getvalue() + self.stderr.getvalue())

    def test_unknown_aws_operation_and_profile_fail_without_subprocess(self):
        for profile, service, operation in (('hub2you', 'ssm', 'delete-parameter'),
                                             ('hub2you', 'sts', 'put-parameter'),
                                             ('SECRET', 'ssm', 'get-parameter')):
            with patch.object(p.subprocess, 'run') as command:
                with self.assertRaises(p.Failure):
                    p.aws(profile, service, operation, {'Value': 'SECRET'})
                command.assert_not_called()

    def test_failure_before_first_put_never_reports_partial_publication(self):
        for profile, operation, identity_at in (('hub2you', 'get-caller-identity', None),
                                                 ('financial', 'describe-parameters', None),
                                                 (None, None, 3)):
            self.calls.clear()
            self.identities = 0
            self.fail_profile, self.fail_operation, self.fail_identity_at = profile, operation, identity_at
            self.execute(True, entrypoint=True)
            diagnostic = self.stderr.getvalue()
            self.assertIn('Nenhuma publicação iniciada nesta execução.', diagnostic)
            self.assertNotIn('parcial', diagnostic)
            self.assertIn('aborted ' + ('publish' if identity_at else 'inventory') + ' command-failed', diagnostic)
            self.assertIn((profile or 'hub2you') + ' ' + ('sts get-caller-identity' if identity_at or operation == 'get-caller-identity' else 'ssm describe-parameters'), diagnostic)
            self.assertFalse(any('put-parameter' in args for args, _ in self.calls))
            self.assertNotIn('SECRET', diagnostic)

    def test_first_put_failure_reports_possible_partial_and_safe_context(self):
        self.fail_profile, self.fail_operation = 'hub2you', 'put-parameter'
        self.execute(True, entrypoint=True)
        diagnostic = self.stderr.getvalue()
        self.assertIn('aborted publish command-failed', diagnostic)
        self.assertIn('hub2you ssm put-parameter', diagnostic)
        self.assertIn('publicação parcial', diagnostic)
        self.assertNotIn('Nenhuma publicação iniciada', diagnostic)
        self.assertNotIn('SECRET', diagnostic)
        self.assertNotIn('created', self.stdout.getvalue())
        self.assertEqual(sum('put-parameter' in args for args, _ in self.calls), 1)

    def test_last_existing_mismatch_prevents_all_planned_writes(self):
        name = p.PREFIX + 'known-hosts'
        self.existing['financial', name] = {'Name': name, 'Type': 'String', 'Value': 'divergent'}
        self.execute(True, entrypoint=True)
        self.assertIn('aborted compare existing-mismatch', self.stderr.getvalue())
        self.assertIn('Nenhuma publicação iniciada nesta execução.', self.stderr.getvalue())
        self.assertFalse(any('put-parameter' in args for args, _ in self.calls))

    def test_later_identity_failure_reports_partial_and_resets_next_execution(self):
        self.fail_identity_at = 4
        self.execute(True, entrypoint=True)
        self.assertIn('publicação parcial', self.stderr.getvalue())
        self.assertIn('hub2you sts get-caller-identity', self.stderr.getvalue())
        self.assertEqual(sum('put-parameter' in args for args, _ in self.calls), 1)
        self.command_fails = True
        self.execute(entrypoint=True)
        self.assertIn('Nenhuma publicação iniciada nesta execução.', self.stderr.getvalue())
        self.assertNotIn('parcial', self.stderr.getvalue())

    def test_put_subprocess_exception_uses_static_diagnostic(self):
        original_fake = self.fake
        def failing_put(args, **kwargs):
            if 'put-parameter' in args:
                raise subprocess.TimeoutExpired(args, 60, output='SECRET', stderr='SECRET')
            return original_fake(args, **kwargs)
        with patch.object(self, 'fake', side_effect=failing_put):
            self.execute(True, entrypoint=True)
        self.assertIn('aborted publish unexpected-error hub2you ssm put-parameter', self.stderr.getvalue())
        self.assertIn('publicação parcial', self.stderr.getvalue())
        self.assertNotIn('SECRET', self.stderr.getvalue() + self.stdout.getvalue())

    def test_account_and_hostname_abort_without_put(self):
        for flag in ('account_wrong', 'host_wrong'):
            setattr(self, flag, True)
            with self.assertRaises(ValueError):
                self.execute(True)
            self.assertFalse(any('put-parameter' in c for c, _ in self.calls))
            setattr(self, flag, False)

    def test_existing_match_preserved_mismatch_aborts_all_writes(self):
        profile = p.STACKS[0][0]
        name = p.PREFIX + 'ssh-key'
        self.existing[profile, name] = {'Name': name, 'Type': 'SecureString', 'Value': self.data['ig_hub.key']}
        self.assertIn('preserved', self.execute(True))
        self.calls.clear()
        self.existing[profile, name]['Value'] = 'divergent'
        with self.assertRaises(ValueError):
            self.execute(True)
        self.assertFalse(any('put-parameter' in c for c, _ in self.calls))

    def test_invalid_json_allowlist_endpoint_and_key(self):
        for key, value in (('admin', 'forbidden'), ('ig_hub.env', 'BAD=secret\n'), ('host', 'ssh-rsa AAAA'), ('ca', 'invalid')):
            original = self.data.copy()
            self.data[key] = value
            with self.assertRaises((ValueError, KeyError)):
                self.execute(True)
            self.assertFalse(any('put-parameter' in c for c, _ in self.calls))
            self.data = original
            self.calls.clear()
        self.data['ig_hub.env'] = self.data['ig_hub.env'].replace('ig_hub:', 'ig_auto:')
        with self.assertRaises(ValueError):
            self.execute(True)

    def test_subprocess_error_never_exposes_payload(self):
        self.command_fails = True
        with self.assertRaises(ValueError) as raised:
            self.execute(True)
        self.assertEqual(str(raised.exception), 'command-failed')

    def test_remote_checks_never_read_secrets_and_reject_bad_files(self):
        good = SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=0, st_size=100)
        directory = SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0)
        for mode, record, parent, rejected in (
                ('check', good, directory, False),
                ('read', SimpleNamespace(st_mode=good.st_mode, st_uid=1, st_size=100), directory, True),
                ('read', SimpleNamespace(st_mode=stat.S_IFLNK | 0o600, st_uid=0, st_size=100), directory, True),
                ('read', SimpleNamespace(st_mode=stat.S_IFREG | 0o644, st_uid=0, st_size=100), directory, True),
                ('read', good, SimpleNamespace(st_mode=stat.S_IFLNK | 0o755, st_uid=0), True)):
            with patch.object(p.subprocess, 'run', return_value=SimpleNamespace(stdout='999:999\n')) as docker, patch.object(p.os, 'lstat', return_value=parent), patch.object(p.os, 'open', return_value=7), patch.object(p.os, 'fstat', return_value=record), patch.object(p.os, 'fdopen') as opened, patch.object(p.sys, 'argv', ['-', mode]), contextlib.redirect_stdout(io.StringIO()):
                if rejected:
                    with self.assertRaises(SystemExit):
                        exec(p.REMOTE, {})
                else:
                    exec(p.REMOTE, {})
                    opened.return_value.__enter__.return_value.read.assert_not_called()

    def test_existing_type_mismatch_aborts_before_source(self):
        name = p.PREFIX + 'ca'
        self.existing['financial', name] = {'Name': name, 'Type': 'SecureString', 'Value': 'synthetic'}
        with self.assertRaises(ValueError):
            self.execute(True)
        self.assertFalse(any(c[0] == 'ssh' or 'put-parameter' in c for c, _ in self.calls))

    def test_parsers_without_regex_reject_invalid_pem_and_hex(self):
        self.assertNotIn('import re', PATH.read_text())
        self.assertNotIn('re.fullmatch', PATH.read_text())
        p.validate_pem(self.data['ca'], 'CERTIFICATE')
        for value in ('', '-----BEGIN CERTIFICATE-----\n!bad!\n-----END CERTIFICATE-----',
                      '-----BEGIN CERTIFICATE-----\n\n-----END CERTIFICATE-----',
                      self.data['ca'].replace('END CERTIFICATE', 'END OTHER')):
            with self.assertRaises(ValueError):
                p.validate_pem(value, 'CERTIFICATE')
        self.assertTrue(p.valid_hex('a' * 64))
        for value in (None, 'A' * 64, 'a' * 63, 'g' * 64, 'a' * 63 + '\n'):
            self.assertFalse(p.valid_hex(value))

    def test_remote_accepts_redis_owned_ca_only_with_safe_permissions(self):
        root = SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=0, st_size=100)
        directory = SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0)
        ca = SimpleNamespace(st_mode=stat.S_IFREG | 0o640, st_uid=999, st_size=100)
        for changed_index, record, rejected in (
                (4, ca, False),
                (4, SimpleNamespace(st_mode=stat.S_IFREG | 0o664, st_uid=999, st_size=100), True),
                (4, SimpleNamespace(st_mode=stat.S_IFLNK | 0o640, st_uid=999, st_size=100), True),
                (0, ca, True), (5, ca, True)):
            records = [root] * 6
            records[4] = ca
            records[changed_index] = record
            with patch.object(p.subprocess, 'run', return_value=SimpleNamespace(stdout='999:999\n')) as docker, patch.object(p.os, 'lstat', return_value=directory), patch.object(p.os, 'open', return_value=7), patch.object(p.os, 'fstat', side_effect=records), patch.object(p.os, 'fdopen') as opened, patch.object(p.sys, 'argv', ['-', 'check']), contextlib.redirect_stdout(io.StringIO()):
                if rejected:
                    with self.assertRaises(SystemExit):
                        exec(p.REMOTE, {})
                else:
                    exec(p.REMOTE, {})
                    self.assertEqual(opened.call_count, 6)
                    opened.return_value.__enter__.return_value.read.assert_not_called()

    def test_remote_python_ignores_environment_and_rejects_optimization(self):
        self.execute()
        self.assertIn('python3 -E - check', self.calls[-1][0][-1])
        self.assertNotIn(' -O ', self.calls[-1][0][-1])
        with patch.object(p.os, 'open') as opened, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit):
                exec(compile(p.REMOTE, '<synthetic-remote>', 'exec', optimize=1), {})
            opened.assert_not_called()

    def test_failed_or_mismatched_readback_never_announces_created(self):
        for mode, error in (('Name', 'readback-mismatch'), ('Type', 'readback-mismatch'), ('Value', 'readback-mismatch'), ('failure', 'command-failed')):
            self.calls.clear()
            self.existing.clear()
            self.readback_mode = mode
            with self.assertRaises(ValueError) as raised:
                self.execute(True)
            self.assertEqual(str(raised.exception), error)
            self.assertNotIn('created', self.stdout.getvalue())
            self.assertNotIn('SECRET', self.stdout.getvalue())
            self.assertEqual(sum('put-parameter' in args for args, _ in self.calls), 1)
            self.assertIn('get-parameter', self.calls[-1][0])

    def test_remote_metadata_permission_checks(self):
        self.assertIn('os.O_NOFOLLOW', p.REMOTE)
        self.assertIn('s.st_uid not in', p.REMOTE)
        self.assertIn('stat.S_ISREG', p.REMOTE)
        self.assertNotIn('ig_admin', p.REMOTE)
        self.assertIn("if sys.argv[1] == 'read'", p.REMOTE)


    def test_original_url_controls_abort_before_writes(self):
        original = self.data['ig_hub.env']
        for control in ('\t', '\r', '\n', '\x01', '\x7f', '\x85'):
            self.data['ig_hub.env'] = original.replace('ig_hub:', 'ig_' + control + 'hub:')
            with self.assertRaises(ValueError):
                self.execute(True)
            self.assertFalse(any('put-parameter' in c for c, _ in self.calls))

    def test_remote_exact_container_owners_and_no_secret_read(self):
        root = SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=0, st_size=100)
        for bad_path in (None, '/opt/instagram-coordination/private', '/opt', '/',
                         '/etc/ssh', '/opt/instagram-coordination/tls', 'ca', 'host'):
            def directory(path):
                uid = 12345 if path == bad_path else (999 if path.endswith('/tls') else 0)
                return SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=uid)
            records = [root] * 6
            records[4] = SimpleNamespace(st_mode=stat.S_IFREG | 0o640, st_uid=12345 if bad_path == 'ca' else 999, st_size=100)
            if bad_path == 'host':
                records[5] = records[4]
            with patch.object(p.subprocess, 'run', return_value=SimpleNamespace(stdout='999:999\n')) as docker, patch.object(p.os, 'lstat', side_effect=directory), patch.object(p.os, 'open', return_value=7), patch.object(p.os, 'fstat', side_effect=records), patch.object(p.os, 'fdopen') as opened, patch.object(p.sys, 'argv', ['-', 'check']), contextlib.redirect_stdout(io.StringIO()):
                if bad_path is None:
                    exec(p.REMOTE, {})
                    opened.return_value.__enter__.return_value.read.assert_not_called()
                else:
                    with self.assertRaises(SystemExit):
                        exec(p.REMOTE, {})
                self.assertEqual(docker.call_args.args[0], ['docker', 'inspect', '--format', '{{.Config.User}}', 'instagram-coordination-redis'])

    def test_remote_rejects_unconfirmed_numeric_user(self):
        for user in ('', 'redis', '999', '999:redis', '999:999:999'):
            with patch.object(p.subprocess, 'run', return_value=SimpleNamespace(stdout=user)), patch.object(p.os, 'open') as opened:
                with self.assertRaises(SystemExit):
                    exec(p.REMOTE, {})
                opened.assert_not_called()

    def test_readback_diagnostics_through_real_main_with_mocked_commands(self):
        for mode, code in (('Type', 'readback-mismatch'), ('failure', 'command-failed'), ('unknown', 'unexpected-error')):
            self.existing.clear()
            self.calls.clear()
            self.readback_mode = mode
            self.execute(True, entrypoint=True)
            self.assertIn('aborted readback ' + code, self.stderr.getvalue())
            self.assertIn('publicação parcial', self.stderr.getvalue())
            if mode in ('failure', 'unknown'):
                self.assertIn('hub2you ssm get-parameter', self.stderr.getvalue())
            self.assertNotIn('SECRET', self.stderr.getvalue() + self.stdout.getvalue())
            self.assertNotIn('created', self.stdout.getvalue())

    def test_entrypoint_readback_and_unknown_errors_never_leak(self):
        for error, expected in ((p.Failure('readback-mismatch'), 'readback-mismatch'),
                                (p.Failure('command-failed'), 'command-failed'),
                                (ValueError('SECRET'), 'unexpected-error'),
                                (p.Failure('SECRET'), 'unexpected-error')):
            stderr = io.StringIO()
            with patch.object(p, 'main', side_effect=error), patch.object(p, 'STAGE', 'readback'), contextlib.redirect_stderr(stderr):
                self.assertEqual(p.entrypoint(), 1)
            self.assertIn('aborted readback ' + expected, stderr.getvalue())
            self.assertNotIn('SECRET', stderr.getvalue())


if __name__ == '__main__':
    unittest.main()
