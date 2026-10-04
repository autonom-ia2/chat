"""Offline gates; initialize rbenv first. Infrastructure is fake, paths stay in tmp."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

os.sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / 'scripts/instagram_testers/runtime'
spec = importlib.util.spec_from_file_location('validator', RUNTIME / 'validate-coordination-env.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class CoordinationRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='coordination-runtime-', dir=ROOT / 'tmp')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.app = self.directory / 'app'
        self.app.mkdir()
        self.stage = self.directory / 'stage'
        self.stage.mkdir()
        self.parameters = {
            'ssh-key': {'Type': 'SecureString', 'Value': 'PRIVATE_KEY_SENTINEL'},
            'redis-env': {'Type': 'SecureString', 'Value':
                'INSTAGRAM_TESTER_COORDINATION_REDIS_URL=rediss://ig_hub:REDIS_SECRET_SENTINEL@ig-coord.internal:16381/0\n'
                'INSTAGRAM_TESTER_COORDINATION_EPOCH=synthetic-epoch-2026\n'},
            'ca': {'Type': 'String', 'Value': 'TEST_CA'},
            'known-hosts': {'Type': 'String', 'Value': '85.31.60.100 ssh-ed25519 TEST_KEY'},
        }
        self.tester = ('INSTAGRAM_TESTER_PROXY_HOST=93.184.216.34\n'
                       'INSTAGRAM_TESTER_PROXY_PORT=8080\n'
                       'INSTAGRAM_TESTER_PROXY_AUTH_MODE=ip\n'
                       'INSTAGRAM_TESTER_PROXY_IDENTITY=93.184.216.34:8080\n')
        (self.app / '.env').write_text('REDIS_URL=redis://local/0\n')
        self.write_inputs()
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        self.log = self.directory / 'commands.jsonl'
        self.env = {**os.environ, 'PATH': f'{self.bin}:/usr/bin:/bin:/usr/sbin',
                    'FAKE_PARAMETERS': str(self.directory / 'parameters.json'), 'FAKE_LOG': str(self.log)}
        dispatcher = f"#!{os.sys.executable}\n" + r'''
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['FAKE_LOG'], 'a') as stream:
    stream.write(json.dumps([name, args]) + '\n')
if name == os.environ.get('FAIL_COMMAND'):
    sys.exit(77)
if name == 'id':
    print('0')
elif name == 'aws':
    parameter = args[args.index('--name') + 1].rsplit('/', 1)[1]
    if parameter == os.environ.get('FAIL_PARAMETER'):
        sys.exit(78)
    print(json.dumps({'Parameter': json.loads(Path(os.environ['FAKE_PARAMETERS']).read_text())[parameter]}))
elif name == 'docker':
    if args[:3] == ['network', 'inspect', 'bridge']:
        print(os.environ.get('GATEWAY', '172.17.0.1'))
    elif args[:2] != ['run', '--rm']:
        sys.exit(99)
elif name not in ('ssh', 'ssh-keygen', 'openssl', 'systemctl'):
    sys.exit(99)
'''
        for name in ('aws', 'ssh', 'ssh-keygen', 'openssl', 'systemctl', 'docker', 'id'):
            executable = self.bin / name
            executable.write_text(dispatcher)
            executable.chmod(0o700)
        self.installer = self.directory / 'install-coordination-tunnel.sh'
        source = (RUNTIME / self.installer.name).read_text()
        source = source.replace('/run/instagram-coordination.', str(self.directory / 'staging.'))
        source = source.replace('/etc/systemd/system/instagram-coordination-tunnel.service',
                                str(self.directory / 'tunnel.service'))
        self.installer.write_text(source)
        for name in ('validate-coordination-env.py', 'coordination-preflight.sh'):
            (self.directory / name).write_text((RUNTIME / name).read_text())

    def write_inputs(self):
        for name, value in self.parameters.items():
            (self.stage / f'{name}.json').write_text(json.dumps({'Parameter': value}))
        (self.app / 'instagram-tester.env').write_text(self.tester)
        (self.directory / 'parameters.json').write_text(json.dumps(self.parameters))

    def install(self, **env):
        return subprocess.run(['/bin/bash', '-x', str(self.installer), 'install', 'us-east-1', str(self.app)],
                              env={**self.env, **env}, text=True, capture_output=True, timeout=5)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_install_modes_ssm_types_and_supervision(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        coord = self.app / 'igcoord'
        self.assertEqual(coord.stat().st_mode & 0o777, 0o700)
        for name in ('ssh.key', 'redis.env', 'known_hosts', 'tunnel.env'):
            self.assertEqual((coord / name).stat().st_mode & 0o777, 0o600)
        self.assertEqual((coord / 'ca.crt').stat().st_mode & 0o777, 0o644)
        self.assertEqual((coord / 'tunnel.sh').stat().st_mode & 0o777, 0o700)
        self.assertEqual((coord / 'check.sh').stat().st_mode & 0o777, 0o700)
        output = result.stdout + result.stderr
        self.assertNotIn('PRIVATE_KEY_SENTINEL', output)
        self.assertNotIn('REDIS_SECRET_SENTINEL', output)
        service = (self.directory / 'tunnel.service').read_text()
        self.assertIn('Restart=always', service)
        self.assertIn('PartOf=docker.service', service)
        self.assertIn('RestartSec=5', service)
        self.assertIn('ProtectSystem=strict', service)
        self.assertIn('16380', (coord / 'redis.env').read_text())
        self.assertIn('ig-proxy.internal', (coord / 'redis.env').read_text())
        self.assertEqual((coord / 'tunnel.env').read_text(), '93.184.216.34\n8080\n')
        aws = [args for name, args in self.calls() if name == 'aws']
        self.assertEqual(len(aws), 4)
        self.assertTrue(all('--with-decryption' in args for args in aws))
        self.assertTrue(all(args[args.index('--name')+1].startswith('/chatwoot/prod/instagram-coordination/') for args in aws))

    def test_identity_is_derived_and_explicit_divergence_rejected(self):
        self.tester = self.tester.replace('INSTAGRAM_TESTER_PROXY_IDENTITY=93.184.216.34:8080\n', '')
        self.write_inputs()
        validator.validate(self.stage, self.app)
        self.assertIn('INSTAGRAM_TESTER_PROXY_IDENTITY=93.184.216.34:8080\n', (self.stage / 'redis.env').read_text())
        for identity in ('tag', '93.184.216.35:8080', '93.184.216.34:8081', '93.184.216.34:08080'):
            self.parameters['redis-env']['Value'] += f'INSTAGRAM_TESTER_PROXY_IDENTITY={identity}\n'
            self.write_inputs()
            with self.assertRaises(ValueError):
                validator.validate(self.stage, self.app)
            self.parameters['redis-env']['Value'] = self.parameters['redis-env']['Value'].rsplit('INSTAGRAM_TESTER_PROXY_IDENTITY=', 1)[0]

    def test_dedicated_redis_accepts_both_runtime_users_and_preserves_url(self):
        original = self.parameters['redis-env']['Value']
        for username in ('ig_hub', 'ig_auto'):
            with self.subTest(username=username):
                value = original.replace('ig_hub:REDIS_SECRET_SENTINEL', f'{username}:synthetic%40password%3Avalue')
                self.parameters['redis-env']['Value'] = value
                self.write_inputs()
                validator.validate(self.stage, self.app)
                dedicated = validator.read_env(self.stage / 'redis.env')
                self.assertEqual(dedicated['INSTAGRAM_TESTER_COORDINATION_REDIS_URL'],
                                 value.splitlines()[0].partition('=')[2])
                self.assertEqual(dedicated['INSTAGRAM_TESTER_COORDINATION_EPOCH'], 'synthetic-epoch-2026')
                self.assertEqual(dedicated['INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE'], '/run/igcoord/ca.crt')
                self.assertEqual(dedicated['INSTAGRAM_TESTER_PROXY_IDENTITY'], '93.184.216.34:8080')
                self.assertEqual((self.stage / 'tunnel.env').read_text(), '93.184.216.34\n8080\n')

    def test_dedicated_redis_rejects_missing_admin_unknown_and_encoded_users(self):
        original = self.parameters['redis-env']['Value']
        for userinfo in ('', ':REDIS_SECRET_SENTINEL@', 'ig_admin:REDIS_SECRET_SENTINEL@',
                         'default:REDIS_SECRET_SENTINEL@', 'IG_HUB:REDIS_SECRET_SENTINEL@',
                         'ig_hub_extra:REDIS_SECRET_SENTINEL@', '%69g_hub:REDIS_SECRET_SENTINEL@',
                         'ig%5Fhub:REDIS_SECRET_SENTINEL@', 'ig_%68ub:REDIS_SECRET_SENTINEL@',
                         '%69g_auto:REDIS_SECRET_SENTINEL@', 'ig%5fauto:REDIS_SECRET_SENTINEL@'):
            with self.subTest(userinfo=userinfo):
                self.parameters['redis-env']['Value'] = original.replace('ig_hub:REDIS_SECRET_SENTINEL@', userinfo)
                self.write_inputs()
                with self.assertRaises(ValueError):
                    validator.validate(self.stage, self.app)

    def test_dedicated_redis_rejects_password_line_breaks(self):
        original = self.parameters['redis-env']['Value']
        for line_break in ('\n', '\r', '\r\n', '%0a', '%0A', '%0d', '%0D', '%0D%0A'):
            with self.subTest(line_break=line_break):
                self.parameters['redis-env']['Value'] = original.replace('REDIS_SECRET_SENTINEL',
                                                                        f'REDIS_SECRET_SENTINEL{line_break}suffix')
                self.write_inputs()
                with self.assertRaises(ValueError):
                    validator.validate(self.stage, self.app)

    def test_dedicated_redis_rejects_literal_controls_in_username_and_password(self):
        original = self.parameters['redis-env']['Value']
        for ordinal in (*range(32), 127):
            for component in ('username', 'password'):
                with self.subTest(ordinal=ordinal, component=component):
                    username = f'ig_{chr(ordinal)}hub' if component == 'username' else 'ig_hub'
                    password = f'REDIS_SECRET_SENTINEL{chr(ordinal)}suffix' if component == 'password' else 'REDIS_SECRET_SENTINEL'
                    self.parameters['redis-env']['Value'] = original.replace(
                        'ig_hub:REDIS_SECRET_SENTINEL', f'{username}:{password}')
                    self.write_inputs()
                    with self.assertRaises(ValueError):
                        validator.validate(self.stage, self.app)

    def test_dedicated_redis_rejects_encoded_controls_in_username_and_password(self):
        original = self.parameters['redis-env']['Value']
        for ordinal in (*range(32), 127):
            for component in ('username', 'password'):
                with self.subTest(ordinal=ordinal, component=component):
                    username = f'ig_%{ordinal:02X}hub' if component == 'username' else 'ig_hub'
                    password = f'REDIS_SECRET_SENTINEL%{ordinal:02X}suffix' if component == 'password' else 'REDIS_SECRET_SENTINEL'
                    self.parameters['redis-env']['Value'] = original.replace(
                        'ig_hub:REDIS_SECRET_SENTINEL', f'{username}:{password}')
                    self.write_inputs()
                    with self.assertRaises(ValueError):
                        validator.validate(self.stage, self.app)

    def test_invalid_redis_credentials_do_not_install_restart_or_leak(self):
        original = self.parameters['redis-env']['Value']
        for userinfo in (':REDIS_SECRET_SENTINEL', 'ig_admin:REDIS_SECRET_SENTINEL',
                         '%69g_hub:REDIS_SECRET_SENTINEL', 'ig_hub:REDIS_SECRET_SENTINEL%0Ainjected'):
            with self.subTest(userinfo=userinfo):
                self.parameters['redis-env']['Value'] = original.replace('ig_hub:REDIS_SECRET_SENTINEL', userinfo)
                self.write_inputs()
                self.log.write_text('')
                result = self.install()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.app / 'igcoord').exists())
                self.assertFalse(any(command == 'systemctl' for command, _ in self.calls()))
                self.assertNotIn('REDIS_SECRET_SENTINEL', result.stdout + result.stderr)
                self.assertIn('instagram_coordination_env_invalid', result.stderr)

    def test_ruby_node_fingerprints_match_with_synthetic_transports(self):
        ruby = "require 'digest'; module Instagram; module Testers; end; end; load 'app/services/instagram/testers/validation.rb'; load 'app/services/instagram/testers/proxy.rb'; print Instagram::Testers::Proxy.new.fingerprint"
        node = "import {configuration} from './scripts/instagram_testers/session-observer.mjs'; process.stdout.write(configuration(process.env).proxyFingerprint)"
        env = {**os.environ, 'INSTAGRAM_TESTER_PROXY_PORT': '16380', 'INSTAGRAM_TESTER_PROXY_AUTH_MODE': 'ip',
               'INSTAGRAM_TESTER_PROXY_IDENTITY': '93.184.216.34:8080', 'INSTAGRAM_TESTER_PROXY_USERNAME': '',
               'INSTAGRAM_TESTER_PROXY_PASSWORD': '', 'INSTAGRAM_META_DEVELOPER_APP_ID': '1',
               'INSTAGRAM_META_BUSINESS_ID': '2', 'INSTAGRAM_TESTER_ROLES_DOC_ID': '3', 'INSTAGRAM_TESTER_ADMIN_USER_ID': '4'}
        ruby_result = subprocess.check_output(['ruby', '-e', ruby], cwd=ROOT, env={**env, 'INSTAGRAM_TESTER_PROXY_HOST': 'ig-proxy.internal'}, text=True)
        node_result = subprocess.check_output(['node', '--input-type=module', '-e', node], cwd=ROOT, env={**env, 'INSTAGRAM_TESTER_PROXY_HOST': '127.0.0.1'}, text=True)
        import hashlib
        self.assertEqual(ruby_result, hashlib.sha256(b'93.184.216.34:8080:ip').hexdigest())
        self.assertEqual(ruby_result, node_result)

    def test_parameter_fetch_and_type_failures_do_not_install_or_restart(self):
        for name in self.parameters:
            original = self.parameters[name]['Type']
            for scenario in ('fetch', 'type'):
                with self.subTest(parameter=name, scenario=scenario):
                    if scenario == 'type':
                        self.parameters[name]['Type'] = 'String' if original == 'SecureString' else 'SecureString'
                    self.write_inputs()
                    self.log.write_text('')
                    result = self.install(**({'FAIL_PARAMETER': name} if scenario == 'fetch' else {}))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse((self.app / 'igcoord').exists())
                    self.assertFalse(any(command == 'systemctl' for command, _ in self.calls()))
                    self.assertNotIn('REDIS_SECRET_SENTINEL', result.stderr)
                    self.parameters[name]['Type'] = original

    def test_invalid_key_ca_or_service_failure_cannot_report_success(self):
        for command in ('ssh-keygen', 'openssl', 'systemctl'):
            with self.subTest(command=command):
                result = self.install(FAIL_COMMAND=command)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('PRIVATE_KEY_SENTINEL', result.stdout + result.stderr)
                self.assertNotIn('REDIS_SECRET_SENTINEL', result.stdout + result.stderr)

    def test_rejects_proxy_credentials_shell_input_and_public_redis(self):
        invalid = ('INSTAGRAM_TESTER_PROXY_USERNAME=secret\n', 'INSTAGRAM_TESTER_PROXY_PASSWORD=secret\n',
                   'INSTAGRAM_TESTER_PROXY_HOST=$(touch evil)\n', 'INSTAGRAM_TESTER_PROXY_PORT=0\n',
                   'INSTAGRAM_TESTER_PROXY_AUTH_MODE=password\n', 'INSTAGRAM_TESTER_PROXY_HOST=127.0.0.1\n',
                   'INSTAGRAM_TESTER_PROXY_HOST=ig-proxy.internal\n', 'INSTAGRAM_TESTER_PROXY_IDENTITY=\n')
        original = self.tester
        for bad in invalid:
            key = bad.partition('=')[0]
            self.tester = ''.join(line+'\n' for line in original.splitlines() if not line.startswith(key+'=')) + bad
            self.write_inputs()
            with self.subTest(env=key, value=bad):
                with self.assertRaises(ValueError):
                    validator.validate(self.stage, self.app)
        self.tester = original
        self.parameters['redis-env']['Value'] = self.parameters['redis-env']['Value'].replace('ig-coord.internal:16381', '93.184.216.34:6381')
        self.write_inputs()
        with self.assertRaises(ValueError):
            validator.validate(self.stage, self.app)

    def test_missing_epoch_or_secret_key_in_dedicated_env_fails_closed(self):
        original = self.parameters['redis-env']['Value']
        for value in (original.replace('INSTAGRAM_TESTER_COORDINATION_EPOCH=synthetic-epoch-2026\n', ''),
                      original + 'INSTAGRAM_TESTER_PROXY_PASSWORD=secret\n',
                      original + 'INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE=/wrong/path\n'):
            self.parameters['redis-env']['Value'] = value
            self.write_inputs()
            with self.assertRaises(ValueError):
                validator.validate(self.stage, self.app)

    def test_tunnel_uses_bridge_two_forwards_and_pinned_host_key(self):
        (self.stage / 'tunnel.env').write_text('93.184.216.34\n8080\n')
        result = subprocess.run(['/bin/bash', str(self.installer), 'tunnel', str(self.stage)],
                                env=self.env, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        ssh = next(args for name, args in self.calls() if name == 'ssh')
        self.assertIn('172.17.0.1:16381:127.0.0.1:6381', ssh)
        self.assertIn('172.17.0.1:16380:93.184.216.34:8080', ssh)
        for option in ('StrictHostKeyChecking=yes', 'IdentitiesOnly=yes', 'BatchMode=yes',
                       'ExitOnForwardFailure=yes', 'ServerAliveInterval=15', 'ServerAliveCountMax=3',
                       'GlobalKnownHostsFile=/dev/null', 'UpdateHostKeys=no'):
            self.assertIn(option, ssh)
        self.assertEqual(ssh[-1], 'igcoord@85.31.60.100')
        self.assertNotIn('0.0.0.0', ' '.join(ssh))
        self.assertFalse(any('USERNAME' in arg or 'PASSWORD' in arg for arg in ssh))
        self.log.write_text('')
        result = subprocess.run(['/bin/bash', str(self.installer), 'tunnel', str(self.stage)],
                                env={**self.env, 'GATEWAY': ''}, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(name == 'ssh' for name, _ in self.calls()))

    def test_inactive_tunnel_blocks_rails_preflight_and_container_has_all_settings(self):
        (self.app / 'runtime.env').write_text('IMAGE_URI=test-image\n')
        check = self.directory / 'check.sh'
        check.write_text((RUNTIME / 'coordination-preflight.sh').read_text().replace('APP_DIR=/opt/chatwoot', f'APP_DIR={self.app}'))
        for fail in ('systemctl', ''):
            self.log.write_text('')
            result = subprocess.run(['/bin/bash', str(check)], env={**self.env, 'FAIL_COMMAND': fail},
                                    text=True, capture_output=True, timeout=5)
            if fail:
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(name == 'docker' for name, _ in self.calls()))
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                docker = next(args for name, args in self.calls() if name == 'docker')
                self.assertIn('ig-coord.internal:host-gateway', docker)
                self.assertIn('ig-proxy.internal:host-gateway', docker)
                self.assertIn(str(self.app / 'igcoord/redis.env'), docker)
                self.assertIn(f'{self.app}/igcoord/ca.crt:/run/igcoord/ca.crt:ro', docker)
                self.assertEqual(docker[-1], 'scripts/instagram_testers/runtime/coordination_preflight.rb')

    def test_rails_proxy_preflight_never_calls_meta_or_falls_back(self):
        preamble = r'''
require 'uri'
require 'digest'
require 'openssl'
require 'pathname'
class Object
  def present?; !nil? && (!respond_to?(:empty?) || !empty?); end
  def blank?; !present?; end
end
module Rails
  def self.env; Object.new.tap { |env| def env.production?; true; end }; end
end
module Instagram; module Testers
  class Error < StandardError; end
end; end
class ConnectionPool
  def initialize(**options, &block); @connection = block.call; end
  def with; yield @connection; end
end
class Redis
  def initialize(**options)
    raise 'wrong TLS configuration' unless options[:ssl_params][:ca_file] == ENV['INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE']
    raise 'verification disabled' unless options[:ssl_params][:verify_mode] == OpenSSL::SSL::VERIFY_PEER
  end
  def get(key)
    raise 'wrong integrity key' unless key == 'instagram_tester_coordination:integrity:epoch'
    puts 'integrity'
    ENV['FAIL_GATE'] == 'integrity' ? nil : ENV['INSTAGRAM_TESTER_COORDINATION_EPOCH']
  end
  def ping; puts 'ping'; ENV['FAIL_GATE'] == 'ping' ? 'FAIL' : 'PONG'; end
  class Namespace
    def initialize(namespace, redis:); @namespace = namespace; @redis = redis; end
    def get(key); @redis.get("#{@namespace}:#{key}"); end
    def ping; @redis.ping; end
  end
end
load 'app/services/instagram/testers/coordination_redis.rb'
load 'app/services/instagram/testers/validation.rb'
load 'app/services/instagram/testers/proxy.rb'
'''
        preamble += r'''
module HTTParty
  def self.get(url, **options)
    raise 'wrong URL' unless url == 'https://ipv4.webshare.io/'
    raise 'missing proxy' unless options[:http_proxyaddr] == 'ig-proxy.internal' && options[:http_proxyport] == 16380
    raise 'redirect enabled' unless options[:follow_redirects] == false
    puts 'proxy-request'
    raise 'SECRET_ERROR' if ENV['FAIL_GATE'] == 'transport'
    Struct.new(:code, :body).new(ENV['HTTP_CODE'].to_i, ENV.fetch('PROXY_BODY', '93.184.216.34'))
  end
end
'''
        (self.app / 'ca.crt').write_text('synthetic CA')
        for fail, code in (('', '200'), ('ping', '200'), ('integrity', '200'), ('config', '200'),
                           ('transport', '200'), ('', '407'), ('', '302'), ('', '500'), ('wrong-ip', '200'), ('html', '200'), ('ipv6', '200')):
            result = subprocess.run(['ruby', '-e', preamble + (RUNTIME / 'coordination_preflight.rb').read_text()],
                                    env={**os.environ, 'FAIL_GATE': fail, 'HTTP_CODE': code,
                                         'PROXY_BODY': {'wrong-ip': '93.184.216.35', 'html': '<html>OK</html>', 'ipv6': '::1'}.get(fail, '93.184.216.34'),
                                         'INSTAGRAM_TESTER_COORDINATION_REDIS_URL': 'rediss://ig_hub:synthetic@ig-coord.internal:16381/0',
                                         'INSTAGRAM_TESTER_COORDINATION_EPOCH': 'synthetic-epoch-2026',
                                         'INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE': str(self.app / 'ca.crt'),
                                         'INSTAGRAM_TESTER_PROXY_HOST': 'ig-proxy.internal',
                                         'INSTAGRAM_TESTER_PROXY_PORT': 'invalid' if fail == 'config' else '16380',
                                         'INSTAGRAM_TESTER_PROXY_AUTH_MODE': 'ip',
                                         'INSTAGRAM_TESTER_PROXY_IDENTITY': '93.184.216.34:8080',
                                         'INSTAGRAM_TESTER_PROXY_USERNAME': '', 'INSTAGRAM_TESTER_PROXY_PASSWORD': ''},
                                    cwd=ROOT, text=True, capture_output=True, timeout=5)
            with self.subTest(gate=fail, status=code):
                self.assertEqual(result.returncode == 0, not fail and code == '200', result.stderr)
                self.assertNotIn('SECRET_ERROR', result.stdout + result.stderr)
                if result.returncode:
                    self.assertEqual(result.stderr.strip(), 'instagram_coordination_preflight_failed')
                else:
                    self.assertEqual(result.stdout.splitlines(), ['integrity', 'ping', 'proxy-request',
                                                                 'instagram_coordination_preflight_ok'])
                if fail in ('ping', 'integrity', 'config'):
                    self.assertNotIn('proxy-request', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
