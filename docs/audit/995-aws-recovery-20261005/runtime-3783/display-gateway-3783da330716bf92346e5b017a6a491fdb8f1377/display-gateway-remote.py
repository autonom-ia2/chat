#!/usr/bin/env python3
"""Start/verify/stop only display+gateway; manager and publisher must remain inactive."""
import datetime
import http.client
import importlib.util
import json
import os
from pathlib import Path
import pwd
import socket
import stat
import subprocess
import sys
import time
from urllib.parse import urlsplit

SHA = '3783da330716bf92346e5b017a6a491fdb8f1377'
NODE = Path('/opt/instagram-meta-tools/node-v24.21.0-linux-x64/bin/node')
STACKS = ('hub2you', 'autonomia')
STACK = None

class GateError(Exception):
    pass

def require(condition, code):
    if not condition:
        raise GateError(code)

def run(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=40)
    require(result.returncode == 0, 'command_failed_' + Path(args[0]).name)
    return result.stdout

def unit(role, stack=None):
    stack = STACK if stack is None else stack
    return 'instagram-vps-' + role + '@' + stack + '.service'

def show(name):
    raw = run(['/usr/bin/systemctl', 'show', name,
               '--property=ActiveState,SubState,MainPID,UnitFileState,User,Group,SupplementaryGroups,ControlGroup'])
    return dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)

def protected_units():
    return {unit(role, stack): show(unit(role, stack))
            for stack in STACKS for role in ('manager', 'publisher')}

def assert_protected_inactive(states):
    require(all(s['ActiveState'] == 'inactive' and s['MainPID'] == '0' for s in states.values()),
            'manager_or_publisher_active')

def docker_state():
    ids = run(['/usr/bin/docker', 'ps', '-aq']).split()
    raw = run(['/usr/bin/docker', 'inspect', '--format',
               '{{.Id}} {{.State.Running}} {{.State.StartedAt}} {{.RestartCount}}', *ids])
    return {line.split()[0]: line.split()[1:] for line in raw.splitlines()}

def process_identity(pid, name, gid):
    fields = dict(line.split(':', 1) for line in Path('/proc', str(pid), 'status').read_text().splitlines() if ':' in line)
    uid = pwd.getpwnam(name).pw_uid
    require(set(map(int, fields['Uid'].split())) == {uid}, 'process_uid')
    require(set(map(int, fields['Gid'].split())) == {gid}, 'process_gid')
    require(set(map(int, fields['Groups'].split())) | {gid} == set(os.getgrouplist(name, gid)), 'process_groups')
    require(fields['NoNewPrivs'].strip() == '1' and int(fields['CapEff'].strip(), 16) == 0, 'process_privileges')
    return {'uid': uid, 'gid': gid, 'groups': sorted(set(map(int, fields['Groups'].split())) | {gid})}

def tcp_listeners(control_group):
    root = Path('/sys/fs/cgroup') / control_group.lstrip('/')
    pids = set()
    for file in root.rglob('cgroup.procs'):
        pids.update(int(value) for value in file.read_text().split())
    listeners = set()
    for pid in pids:
        proc = Path('/proc') / str(pid)
        inodes = set()
        try:
            for file in (proc / 'fd').iterdir():
                try:
                    value = os.readlink(file)
                except FileNotFoundError:
                    continue
                if value.startswith('socket:[') and value.endswith(']'):
                    inodes.add(value[8:-1])
            for family in ('tcp', 'tcp6'):
                for line in (proc / 'net' / family).read_text().splitlines()[1:]:
                    columns = line.split()
                    if columns[3] == '0A' and columns[9] in inodes:
                        address, port = columns[1].split(':')
                        listeners.add((family, address, int(port, 16)))
        except FileNotFoundError:
            continue
    return listeners

def focused_configuration():
    release = Path('/opt/instagram-meta/current').resolve(strict=True)
    require(release == Path('/opt/instagram-meta/releases') / SHA, 'release')
    envdir = release / 'scripts/instagram_testers/runtime/vps/env'
    sys.path.insert(0, str(envdir))
    spec = importlib.util.spec_from_file_location('verify_pair', envdir / 'verify-pair.py')
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    accounts, viewers = verifier.service_accounts()
    configs = {}
    for role in ('display', 'gateway'):
        path = Path('/etc/instagram-meta') / STACK / (role + '.env')
        verifier.private_path(path.parent, 0, 0o700, directory=True, gid=0)
        verifier.private_path(path, 0, 0o600, gid=0)
        values = verifier.read_literals(path, role)
        account = accounts[('iggw-' if role == 'gateway' else 'ig-') + STACK]
        verifier.validate(STACK, role, values, account.pw_uid, account.pw_gid)
        configs[role] = values
    return accounts, viewers, configs

def anonymous_http(config, timeout=3):
    parsed = urlsplit(config['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL'])
    port = int(config['INSTAGRAM_TESTER_GATEWAY_PORT'])
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=timeout)
    try:
        connection.request('GET', parsed.path, headers={'Host': parsed.netloc, 'X-Forwarded-Proto': 'https'})
        response = connection.getresponse()
        require(response.status == 401 and response.getheader('Set-Cookie') is None, 'anonymous_http_not_denied')
        response.read(8192)
    finally:
        connection.close()

def wait_ready(pair, configs, timeout=15):
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        require(remaining > 0, 'startup_timeout')
        states = [show(name) for name in pair]
        require(all(s['ActiveState'] not in ('failed', 'inactive') for s in states), 'startup_unit_failed')
        if all(s['ActiveState'] == 'active' and int(s['MainPID']) > 0 for s in states) and Path('/run/instagram-' + STACK + '/vnc.sock').is_socket():
            try:
                anonymous_http(configs['gateway'], timeout=min(2, remaining))
                return
            except (ConnectionRefusedError, TimeoutError):
                # Type=simple reports active before listen(); tolerate connection startup only.
                pass
        time.sleep(min(0.2, max(0, deadline - time.monotonic())))

def verify_active(accounts, viewers, configs):
    states = {role: show(unit(role)) for role in ('display', 'gateway')}
    require(all(s['ActiveState'] == 'active' and int(s['MainPID']) > 0 and s['UnitFileState'] == 'disabled'
                for s in states.values()), 'pair_not_active_disabled')
    browser = accounts['ig-' + STACK]
    gateway = accounts['iggw-' + STACK]
    viewer = viewers[STACK]
    xauth = Path(configs['display']['XAUTHORITY'])
    info = xauth.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid == browser.pw_uid and stat.S_IMODE(info.st_mode) == 0o600,
            'xauthority_permissions')
    runtime = Path('/run/instagram-' + STACK)
    info = runtime.lstat()
    require(stat.S_ISDIR(info.st_mode) and (info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)) ==
            (browser.pw_uid, viewer, 0o710), 'runtime_directory')
    vnc = runtime / 'vnc.sock'
    info = vnc.lstat()
    require(stat.S_ISSOCK(info.st_mode) and (info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)) ==
            (browser.pw_uid, viewer, 0o660), 'vnc_socket')
    require(not (runtime / 'browser-request.json').exists() and not (runtime / 'browser-request.json').is_symlink(),
            'unexpected_browser_marker')
    identities = {
        'display': process_identity(int(states['display']['MainPID']), 'ig-' + STACK, viewer),
        'gateway': process_identity(int(states['gateway']['MainPID']), 'iggw-' + STACK, gateway.pw_gid),
    }
    gateway_pid = int(states['gateway']['MainPID'])
    require(os.path.samefile(NODE, Path('/proc') / str(gateway_pid) / 'root/usr/bin/node'), 'private_node_not_bound')
    mounts = (Path('/proc') / str(gateway_pid) / 'mountinfo').read_text().splitlines()
    require(any(line.split()[4] == '/usr/bin/node' and 'ro' in line.split()[5].split(',') for line in mounts),
            'private_node_mount_not_readonly')
    require(not tcp_listeners(states['display']['ControlGroup']), 'display_tcp_listener')
    port = int(configs['gateway']['INSTAGRAM_TESTER_GATEWAY_PORT'])
    require(tcp_listeners(states['gateway']['ControlGroup']) == {('tcp', '0100007F', port)}, 'gateway_not_loopback_only')
    anonymous_http(configs['gateway'])
    return {'units': states, 'identities': identities, 'vnc_unix_mode': '0660',
            'runtime_mode': '0710', 'gateway_loopback_port': port,
            'private_node_readonly_mount_verified': True, 'anonymous_loopback_status': 401,
            'xauthority_mode': '0600', 'xauthority_owner_uid': browser.pw_uid,
            'full_verify_pair_executed': False, 'scope': 'display_gateway_only'}

def stop_pair():
    # Containment must not depend on current release, env files, signing keys or Docker.
    assert_protected_inactive(protected_units())
    run(['/usr/bin/systemctl', 'stop', unit('gateway'), unit('display')])
    states = {role: show(unit(role)) for role in ('display', 'gateway')}
    require(all(s['ActiveState'] == 'inactive' and s['MainPID'] == '0' for s in states.values()), 'stop_failed')
    return states

def ensure_preserved(protected_before, other_before, docker_before=None, host_node=None):
    after = protected_units()
    assert_protected_inactive(after)
    require(after == protected_before, 'protected_units_changed')
    require({name: show(name) for name in other_before} == other_before, 'other_stack_changed')
    if docker_before is not None:
        require(docker_state() == docker_before, 'existing_container_state_changed')
    if host_node is not None:
        require(run(['/usr/bin/node', '--version']).strip() == host_node, 'host_node_changed')

def main():
    global STACK
    require(len(sys.argv) == 3, 'arguments')
    phase, STACK = sys.argv[1:]
    require(phase in ('start', 'verify', 'stop') and STACK in STACKS, 'arguments')
    require(sys.platform == 'linux' and os.geteuid() == 0 and socket.gethostname() == 'srv707880', 'host_identity')
    protected_before = protected_units()
    assert_protected_inactive(protected_before)
    other_stack = 'autonomia' if STACK == 'hub2you' else 'hub2you'
    other_before = {unit(role, other_stack): show(unit(role, other_stack)) for role in ('display', 'gateway')}
    if phase == 'stop':
        result = {'pair_stopped': True, 'units': stop_pair(), 'scope': 'display_gateway_only'}
        ensure_preserved(protected_before, other_before)
    else:
        accounts, viewers, configs = focused_configuration()
        docker_before = docker_state()
        host_node = run(['/usr/bin/node', '--version']).strip()
        pair = [unit('display'), unit('gateway')]
        if phase == 'start':
            states = [show(name) for name in pair]
            require(all(s['ActiveState'] == 'inactive' and s['MainPID'] == '0' for s in states), 'pair_already_active')
            require(not list(Path(configs['gateway']['INSTAGRAM_TESTER_GATEWAY_STATE_DIR']).iterdir()), 'nonce_directory_not_empty')
            marker = Path(configs['gateway']['INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE'])
            require(not marker.exists() and not marker.is_symlink(), 'marker_present')
            try:
                run(['/usr/bin/systemctl', 'start', *pair])
                wait_ready(pair, configs)
                result = verify_active(accounts, viewers, configs)
                ensure_preserved(protected_before, other_before, docker_before, host_node)
            except Exception as error:
                rollback_ok = False
                rollback_reason = None
                try:
                    stop_pair()
                    rollback_ok = True
                    ensure_preserved(protected_before, other_before, docker_before, host_node)
                except Exception as rollback_error:
                    rollback_reason = str(rollback_error) if isinstance(rollback_error, GateError) else 'rollback_verification_failed'
                print(json.dumps({'status': 'START_FAILED', 'stack': STACK,
                                  'reason': str(error) if isinstance(error, GateError) else 'execution_failed',
                                  'rollback_pair_stopped': rollback_ok, 'rollback_reason': rollback_reason,
                                  'manager_publisher_start_requested': False, 'secret_values_emitted': False,
                                  'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}))
                return 1
        else:
            result = verify_active(accounts, viewers, configs)
        ensure_preserved(protected_before, other_before, docker_before, host_node)
        result['containers_preserved'] = len(docker_before)
    result.update({'status': 'PASS', 'phase': phase, 'stack': STACK, 'source_sha': SHA,
                   'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   'manager_publisher_start_requested': False, 'services_enabled': False,
                   'secret_values_emitted': False})
    print(json.dumps(result))
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({'status': 'FAILED_PRESERVE_STATE', 'stack': STACK,
                          'reason': str(error) if isinstance(error, GateError) else 'execution_failed',
                          'do_not_retry_blindly': True, 'secret_values_emitted': False}))
        sys.exit(1)
