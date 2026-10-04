"""Offline fiction: no Docker, SSH, network or real infrastructure writes."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'scripts/instagram_testers/runtime/provision-coordination-host.sh'


class ProvisionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.script = self.base / 'provision.sh'
        self.rootdir = self.base / 'coord'
        self.sshconfig = self.base / 'sshd.conf'
        self.home = self.base / 'home'
        source = SOURCE.read_text().replace('/opt/instagram-coordination', str(self.rootdir))
        source = source.replace('/etc/ssh/sshd_config.d/70-instagram-coordination.conf', str(self.sshconfig))
        source = source.replace('/home/igcoord', str(self.home))
        self.script.write_text(source)
        self.env = {**os.environ, 'PATH': f'{self.bin}:/usr/bin:/bin', 'TEST_HOME': str(self.home)}
        fake = f'#!{os.sys.executable}\n' + r'''
import os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
a = sys.argv[1:]
if os.environ.get('FAIL') == name:
    sys.exit(71)
if name == 'id': print('0')
elif name == 'getent': print(os.environ.get(a[0].upper(), 'root:x:0:0:root:/root:/bin/bash'))
elif name == 'ss': print(os.environ.get('LISTENERS_FAKE', ''))
elif name == 'curl': print(os.environ.get('EGRESS', '8.8.4.4') + '\n' + os.environ.get('HTTP_FAKE', '200 200'))
elif name == 'docker':
    if a[0] == 'version': print(os.environ.get('VERSION_FAKE', '28.0.0'))
    elif a[:2] == ['volume','ls']: print(os.environ.get('VOLUME_FAKE', ''))
    elif a[:2] == ['network','ls']: print(os.environ.get('NETWORK_FAKE', ''))
    elif a[0] == 'ps': print(os.environ.get('CONTAINER_FAKE', ''))
    elif a[:2] == ['image','inspect']: print('redis@sha256:fiction')
    elif a[0] == 'run' and a[-1].startswith('id'): print('999')
    elif a[0] == 'exec':
        lines = sys.stdin.read().splitlines()[1:]
        for line in lines:
            if line == 'PING': print('PONG')
            elif line.startswith('SET '): print('OK')
            elif line.startswith('WAITAOF'): print(os.environ.get('SYNC_FAKE', '1\n0'))
            elif line.startswith('ACL DRYRUN'):
                user, operation, key = line.split()[2:5]
                decision = 'OK' if operation == 'GET' else f"User {user} has no permissions to access the '{key}' key"
                print(os.environ.get('ACL_FAKE', decision))
elif name == 'openssl':
    if a[0] == 'rand': print('FICTION_SECRET_SENTINEL')
    for flag in ('-out', '-keyout'):
        if flag in a: Path(a[a.index(flag)+1]).write_text('FICTION_CERT')
elif name == 'ssh-keygen':
    key = Path(a[a.index('-f')+1]); key.write_text('FICTION_PRIVATE_KEY')
    Path(str(key)+'.pub').write_text('ssh-ed25519 FICTION_PUBLIC_KEY')
elif name == 'install':
    import subprocess
    clean = []
    index = 0
    while index < len(a):
        if a[index] in ('-o', '-g'): index += 2
        else: clean.append(a[index]); index += 1
    sys.exit(subprocess.run(['/usr/bin/install', *clean]).returncode)
elif name == 'useradd': Path(os.environ['TEST_HOME']).mkdir()
elif name == 'sshd' and '-T' in a:
    print('authenticationmethods publickey\npubkeyauthentication yes\npasswordauthentication no\nkbdinteractiveauthentication no\nauthorizedkeysfile .ssh/authorized_keys\nauthorizedkeyscommand none\ntrustedusercakeys none\nallowtcpforwarding local\nallowstreamlocalforwarding no\nmaxsessions 0\npermittty no\nallowagentforwarding no\nx11forwarding no')
'''
        for name in ('id', 'getent', 'ss', 'curl', 'docker', 'openssl', 'ssh-keygen',
                     'sshd', 'systemctl', 'useradd', 'usermod', 'chown', 'install'):
            path = self.bin / name
            path.write_text(fake)
            path.chmod(0o700)

    def run_script(self, **overrides):
        result = subprocess.run(['/bin/bash', '-x', str(self.script), '8.8.8.8', '8080', '8.8.4.4'],
                                env={**self.env, **overrides}, text=True, capture_output=True, timeout=15)
        self.assertNotIn('FICTION_SECRET_SENTINEL', result.stdout + result.stderr)
        self.assertNotIn('FICTION_PRIVATE_KEY', result.stdout + result.stderr)
        return result

    def test_new_install_and_rerun_refusal(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        acl = (self.rootdir / 'etc/users.acl').read_text()
        self.assertIn('(~instagram_tester_coordination:integrity:epoch -@all +get)', acl)
        self.assertIn('invite:* -@all +get +set +del +watch)', acl)
        compose = (self.rootdir / 'compose.yml').read_text()
        self.assertIn('127.0.0.1:6381:6381', compose)
        self.assertNotIn('network_mode: host', compose)
        self.assertIn('memswap_limit: 256m', compose)
        config = (self.rootdir / 'etc/redis.conf').read_text()
        for setting in ('appendfsync always', 'noeviction', 'aof-load-truncated no', 'port 0'):
            self.assertIn(setting, config)
        before = (self.rootdir / 'private/epoch').read_bytes()
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual(before, (self.rootdir / 'private/epoch').read_bytes())
        self.assertEqual((self.rootdir / 'private/ig_admin.pass').stat().st_mode & 0o777, 0o600)
        self.assertNotIn('ig_admin', (self.home / '.ssh/authorized_keys').read_text())

    def test_collisions_and_failed_inspections_block_before_writes(self):
        for env in ({'VERSION_FAKE': '27.5.0'}, {'VOLUME_FAKE': 'instagram_coordination_data'},
                    {'CONTAINER_FAKE': 'instagram-coordination-redis'},
                    {'NETWORK_FAKE': 'instagram-coordination-bridge'},
                    {'PASSWD': 'igcoord:x:100:100::/home/igcoord:/bin/sh'},
                    {'GROUP': 'igcoord:x:100:'}, {'LISTENERS_FAKE': 'LISTEN'},
                    {'EGRESS': '1.1.1.1'}, {'HTTP_FAKE': '302 200'}, {'HTTP_FAKE': '200 407'}, {'FAIL': 'docker'}, {'FAIL': 'getent'},
                    {'FAIL': 'ss'}, {'FAIL': 'curl'}, {'FAIL': 'sshd'}):
            with self.subTest(env=env):
                self.assertNotEqual(self.run_script(**env).returncode, 0)
                self.assertFalse(self.rootdir.exists())
        for path in (self.rootdir, self.sshconfig, self.home):
            path.symlink_to(self.base / 'missing')
            self.assertNotEqual(self.run_script().returncode, 0)
            path.unlink()

    def test_unexpected_acl_decision_preserves_partial_install_and_blocks_ssh(self):
        self.assertNotEqual(self.run_script(ACL_FAKE='NOAUTH Authentication required').returncode, 0)
        self.assertTrue(self.rootdir.exists())
        self.assertFalse(self.sshconfig.exists())
        self.assertFalse(self.home.exists())

    def test_persistence_failure_preserves_partial_install_and_blocks_ssh(self):
        self.assertNotEqual(self.run_script(SYNC_FAKE='0\n0').returncode, 0)
        self.assertTrue(self.rootdir.exists())
        self.assertFalse(self.sshconfig.exists())
        self.assertNotEqual(self.run_script().returncode, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
