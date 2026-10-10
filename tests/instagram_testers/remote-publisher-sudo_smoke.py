"""Disposable Linux fixture: real sshd, key restriction, sudo, wrapper and frames.

Provider/AWS/Docker operations are synthetic. Refuses execution outside the
explicit container marker before writing accounts, sudoers or SSH state.
"""
import json
import os
from pathlib import Path
import selectors
import socket
import subprocess
import sys
import tempfile
import time

assert sys.platform == 'linux' and os.geteuid() == 0
assert Path('/run/instagram-publisher-synthetic-fixture').read_text() == 'synthetic-only\n'
assert not Path('/etc/sudoers.d/instagram-tester-publisher').exists()
assert not Path('/usr/local/libexec/instagram-tester-publisher-root').exists()
ROOT = Path('/fixture')
PAYLOAD = json.dumps({'type': 'session', 'operation': 'bootstrap'})

with tempfile.TemporaryDirectory(prefix='publisher-sudo-fixture-') as tmp:
    directory = Path(tmp)
    key = directory / 'client'
    host_key = directory / 'host'
    for target in (key, host_key):
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(target)], check=True)
    installed = subprocess.run(['/bin/sh', str(ROOT / 'runtime/install-remote-publisher.sh')],
                               input=key.with_suffix('.pub').read_text(), capture_output=True, text=True, timeout=15)
    assert installed.returncode == 0
    with socket.socket() as port_socket:
        port_socket.bind(('127.0.0.1', 0))
        port = port_socket.getsockname()[1]
    config = directory / 'sshd_config'
    config.write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {host_key}
PidFile {directory}/sshd.pid
AuthorizedKeysFile .ssh/authorized_keys
AllowUsers chatwoot_publisher
StrictModes yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PermitRootLogin no
PermitEmptyPasswords no
UsePAM yes
PermitUserEnvironment no
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PrintMotd no
LogLevel ERROR
''')
    public_host_key = host_key.with_suffix('.pub').read_text().split()[:2]
    known_hosts = directory / 'known_hosts'
    known_hosts.write_text(f'[127.0.0.1]:{port} {" ".join(public_host_key)}\n')
    server = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 5
        while True:
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=.2):
                    break
            except OSError:
                assert server.poll() is None and time.monotonic() < deadline
                time.sleep(.05)
        ssh = ['ssh', '-T', '-i', str(key), '-p', str(port), '-o', 'BatchMode=yes',
               '-o', 'IdentitiesOnly=yes', '-o', 'IdentityAgent=none',
               '-o', 'StrictHostKeyChecking=yes', '-o', f'UserKnownHostsFile={known_hosts}',
               '-o', 'GlobalKnownHostsFile=/dev/null', '-o', 'LogLevel=ERROR',
               'chatwoot_publisher@127.0.0.1']
        legacy = subprocess.run(ssh, input=PAYLOAD, text=True, capture_output=True, timeout=5)
        assert legacy.returncode == 0 and json.loads(legacy.stdout)['type'] == 'bootstrap'
        frames = subprocess.Popen([*ssh, 'instagram_publisher_channel_v1'], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(frames.stdout, selectors.EVENT_READ)
                for _ in range(3):
                    frames.stdin.write(PAYLOAD + '\n')
                    frames.stdin.flush()
                    assert selector.select(timeout=3), 'channel must reply before stdin EOF'
                    reply = json.loads(frames.stdout.readline())
                    assert reply['type'] == 'bootstrap' and reply['version'] is None
                    assert frames.poll() is None
            frames.stdin.close()
            assert frames.wait(timeout=5) == 0
        finally:
            if frames.poll() is None:
                frames.kill()
                frames.wait(timeout=5)
        before = (ROOT / 'docker-events').read_text().splitlines()
        assert before == ['one-shot', 'channel']
        rejected = subprocess.run([*ssh, 'unapproved_remote_command'], input=PAYLOAD,
                                  text=True, capture_output=True, timeout=5)
        assert rejected.returncode != 0 and rejected.stdout == ''
        assert (ROOT / 'docker-events').read_text().splitlines() == before
        denied = subprocess.run(['runuser', '-u', 'chatwoot_publisher', '--',
                                 'sudo', '-n', '/usr/bin/id'], capture_output=True, timeout=5)
        assert denied.returncode != 0
        extra = subprocess.run(['runuser', '-u', 'chatwoot_publisher', '--',
                                'sudo', '-n', '/usr/local/libexec/instagram-tester-publisher-root', 'unexpected'],
                               capture_output=True, timeout=5)
        assert extra.returncode != 0
        assert (ROOT / 'docker-events').read_text().splitlines() == before
        rule_path = Path('/etc/sudoers.d/instagram-tester-publisher')
        rule = rule_path.read_text()
        assert 'Defaults!/usr/local/libexec/instagram-tester-publisher-root env_keep += "SSH_ORIGINAL_COMMAND"' in rule
        assert 'SETENV:' not in rule and 'ALL=(ALL)' not in rule
        # Reproduce the old production rule with the same real sshd/sudo path.
        rule_path.write_text(''.join(line + '\n' for line in rule.splitlines()
                                    if not line.startswith('Defaults!')))
        subprocess.run(['visudo', '-cf', str(rule_path)], check=True, capture_output=True)
        broken = subprocess.Popen([*ssh, 'instagram_publisher_channel_v1'], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        try:
            broken.stdin.write(PAYLOAD + '\n')
            broken.stdin.flush()
            with selectors.DefaultSelector() as selector:
                selector.register(broken.stdout, selectors.EVENT_READ)
                assert not selector.select(timeout=3), 'old rule unexpectedly replied before EOF'
            assert broken.poll() is None
            assert (ROOT / 'docker-events').read_text().splitlines() == [*before, 'one-shot']
        finally:
            broken.kill()
            broken.wait(timeout=5)
            rule_path.write_text(rule)
        print(json.dumps({'status': 'ok', 'real_ssh_sudo': True, 'legacy_one_shot': True,
                          'frames_before_eof': 3, 'unapproved_command_rejected': True,
                          'unrelated_sudo_denied': True, 'extra_wrapper_argument_denied': True,
                          'old_rule_reproduces_stall': True, 'provider_calls': 0}))
    finally:
        server.terminate()
        server.wait(timeout=5)
