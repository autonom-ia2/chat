#!/usr/bin/env python3
"""Upgrade and roll back the Instagram VPS runtime (#1180) over `ssh n8n`.

Runs on the operator's Mac, stdlib only. Every remote command is built from constants and
validated SHAs and starts with `: vps_release <op>;` so it can be audited. The tool never
prints remote output: it prints only values it computed itself (states, counts, known hashes).
Runbook: docs/runbooks/instagram-vps-release.md.
"""
import argparse
import ast
import functools
import base64
import hashlib
import io
import json
from pathlib import Path
import shlex
import subprocess
import sys
import tarfile
import time

HOST_ALIAS = 'n8n'
HOSTNAME = 'srv707880'
SSH_OPTIONS = ('-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'HostKeyAlgorithms=ssh-ed25519',
               '-o', 'ForwardAgent=no', '-o', 'UpdateHostKeys=no', '-o', 'ConnectTimeout=8', '-o', 'ControlMaster=no',
               '-o', 'ControlPath=none', '-o', 'ClearAllForwardings=yes')
STACKS = ('hub2you', 'autonomia')
ROLES = ('display', 'gateway', 'publisher', 'manager')
NODE_ROLES = ('gateway', 'publisher', 'manager')
UNITS = tuple(f'instagram-vps-{role}@{stack}.service' for stack in STACKS for role in ROLES)
TEMPLATES = tuple(f'instagram-vps-{role}@.service' for role in ROLES)
PORTS = {'hub2you': 18441, 'autonomia': 18442}
GATEWAY_HOST = 'srv707880-claudete.tail0c0b18.ts.net'
NODE_DIR = '/opt/instagram-meta-tools/node-v24.21.0-linux-x64'
NODE = NODE_DIR + '/bin/node'
NPM_CLI = NODE_DIR + '/lib/node_modules/npm/bin/npm-cli.js'
NODE_VERSION = 'v24.21.0'
NODE_SHA256 = '7fde7b8afa198da66257f42ee2001d874c7355631e6d1579a5fb5ef1f246df4c'
NODE_DROPIN_SHA256 = '21296e432301fe7634c65c399c24c692799745466e0e7ce1e829775c112ec1ba'
CPU_OVERRIDE_SHA256 = '41c6db5c35846b239a0da96950bc1e599703b0b1aabbb274a6f99f95d168ea43'
PUBLISHER_QUOTA = '2s'
META = '/opt/instagram-meta'
CURRENT = META + '/current'
RELEASES = META + '/releases'
STAGING = '/opt/instagram-meta-staging'
DEFAULT_FROM = '61f20cfd107361a431fda51f02cace751cc4978d'
VPS_DIR = 'scripts/instagram_testers/runtime/vps'
TOOL = VPS_DIR + '/release/vps_release.py'
BASE_TOP = ('package.json', 'package-lock.json', 'gateway.mjs', 'gateway-auth.mjs', 'web', 'install', 'systemd',
            'env', 'iam', 'docs')
REQUIRED_VPS_FILES = ('package.json', 'package-lock.json', 'gateway.mjs', 'gateway-auth.mjs', 'env/check.py',
                      'env/verify-pair.py', 'web/console.html', 'web/console.js', 'web/enter.html', 'web/enter.js',
                      'install/manager.sh', *[f'systemd/{t}' for t in TEMPLATES])
INSTALLER_BINS = ('/usr/bin/node', '/usr/bin/python3', '/usr/bin/Xtigervnc', '/usr/bin/xauth', '/usr/bin/mcookie',
                  '/usr/bin/google-chrome', '/usr/bin/ssh', '/usr/bin/systemctl', '/usr/sbin/useradd',
                  '/usr/sbin/groupadd', '/usr/sbin/runuser')
TOOL_BINS = ('/usr/bin/systemd-run', '/usr/bin/journalctl', '/usr/bin/sha256sum', '/usr/bin/tar', '/usr/bin/ss',
             '/usr/bin/ps', '/usr/bin/grep', '/usr/bin/find', '/usr/bin/getent', '/usr/bin/base64', '/usr/bin/df',
             '/usr/bin/stat')
REQUIRED_EXECUTABLES = INSTALLER_BINS + TOOL_BINS
EITHER_EXECUTABLES = {'aws': ('/usr/bin/aws', '/usr/local/bin/aws'),
                      'session_manager_plugin': ('/usr/bin/session-manager-plugin',
                                                 '/usr/local/bin/session-manager-plugin')}
UNIT_PROPS = ('Id,LoadState,ActiveState,SubState,Result,MainPID,NRestarts,UnitFileState,FragmentPath,DropInPaths,'
              'CPUQuotaPerSecUSec,ExecMainStartTimestamp')
STAT_FORMAT = "--printf='%n|%F|%U|%G|%a|%s|%Y\\n'"
BACKUP_SCHEMA = 'vps_release_backup_v1'
MIN_FREE_BYTES = 1024 ** 3
BOOTSTRAP_SECONDS = 180
MANAGER_EXIT_SECONDS = 40
PAIR_READY_SECONDS = 20
PUBLISHER_READY_SECONDS = 60
TRANSIENT_WAIT_SECONDS = 900
MIN_SYSTEMD = 252  # `systemctl kill --kill-whom` (the VPS runs Ubuntu 24.04, systemd 255)
FAIL_TOKENS = ('instagram_session_session_update_rejected', 'instagram_manager_failed', 'instagram_vps_manager_failed')
OPERATOR_TOKENS = ('instagram_session_operator_required', 'instagram_manager_operator_required')
HEX = '0123456789abcdef'
GATEWAY_PROBE = (
    "import http.client,sys\n"
    "c=http.client.HTTPConnection('127.0.0.1',int(sys.argv[1]),timeout=2)\n"
    "try:\n"
    " c.request('GET',sys.argv[2],headers={'Host':sys.argv[3],'X-Forwarded-Proto':'https'})\n"
    " r=c.getresponse()\n"
    " print('status=%d set_cookie=%d'%(r.status,r.getheader('Set-Cookie') is not None))\n"
    "except ConnectionRefusedError:\n"
    " print('refused')\n"
    "except OSError:\n"
    " print('error')\n"
    "finally:\n"
    " c.close()\n")
# A ready broker keeps a silent connection open; before `ready` it destroys it at once
# (publisher-broker.mjs:141-146). Writing nothing means nothing is ever published.
PUBLISHER_PROBE = (
    "import socket,sys\n"
    "s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)\n"
    "s.settimeout(1.0)\n"
    "try:\n"
    " s.connect(sys.argv[1])\n"
    "except OSError:\n"
    " print('publisher_absent')\n"
    " raise SystemExit(0)\n"
    "try:\n"
    " s.recv(1)\n"
    " print('publisher_closed')\n"
    "except socket.timeout:\n"
    " print('publisher_ready')\n"
    "except OSError:\n"
    " print('publisher_closed')\n"
    "finally:\n"
    " s.close()\n")
LOCK_PROCEDURE = (
    'lock_do_manager: nao apagar. Procedimento do operador (runbook, secao "Lock do manager"):',
    '  1. confirmar unit do manager parada e `ps -u ig-<stack>` sem processos;',
    '  2. conferir inode, dono ig-<stack>, modo 0600 e tamanho 0 do lock;',
    '  3. renomear atomicamente para pasta de auditoria root 0700 no mesmo filesystem;',
    '  4. rodar de novo o comando indicado abaixo.')
WAITER_FLAG = '--stop-operator-waiter'
# Dry-run prefixes for steps that run only when the remote state calls for them.
OPTIONAL_STAGE = '# so se existir o stage do SHA: '
OPTIONAL_NOOP = '# so se current ja for PREV com as units rodando (rollback_noop encerra aqui): '
WAITER_LINE = ('operator_waiter_running: a sessao Meta espera uma pessoa e o waiter esta ocioso; '
               'o rollback so para o waiter de proposito:')


class Stop(Exception):
    def __init__(self, code, token, lines=()):
        super().__init__(token)
        self.code, self.token, self.lines = code, token, tuple(lines)


class Usage(Exception):
    pass


# -- pure helpers ---------------------------------------------------------------------------
def q(value):
    return shlex.quote(str(value))


def is_sha(value):
    return isinstance(value, str) and len(value) == 40 and all(c in HEX for c in value)


def is_digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in HEX for c in value)


def to_int(value):
    value = (value or '').strip()
    return int(value) if value.isascii() and value.isdigit() else None


def unit_name(role, stack):
    return f'instagram-vps-{role}@{stack}.service'


def split_unit(name):
    role, _, rest = name.removeprefix('instagram-vps-').partition('@')
    return role, rest.removesuffix('.service')


def node_dropin(role):
    return f'/etc/systemd/system/instagram-vps-{role}@.service.d/20-private-node.conf'


def cpu_override(stack):
    return f'/etc/systemd/system/instagram-vps-publisher@{stack}.service.d/30-cpu-quota.conf'


def expected_dropins(role, stack):
    if role == 'display':
        return set()
    if role == 'publisher':
        return {node_dropin(role), cpu_override(stack)}
    return {node_dropin(role)}


def stage_dir(sha):
    return f'{STAGING}/release-{sha}'


def marker(stack):
    return f'/run/instagram-{stack}/browser-request.json'


def lock(stack):
    return f'/var/lib/instagram-{stack}/profile/.instagram-manager.lock'


def homes(stack):
    return {f'ig-{stack}': (f'/var/lib/instagram-{stack}', 'profile'),
            f'igpub-{stack}': (f'/var/lib/instagram-publisher-{stack}', 'publisher'),
            f'iggw-{stack}': (f'/var/lib/instagram-gateway-{stack}', 'gateway')}


ACCOUNTS = {name: home for stack in STACKS for name, home in homes(stack).items()}


def utc_stamp(epoch):
    return time.strftime('%Y%m%dT%H%M%SZ', time.gmtime(epoch))


def valid_backup_path(path):
    prefix, suffix = '/tmp/instagram-vps_state_', '.json'
    if not (isinstance(path, str) and path.startswith(prefix) and path.endswith(suffix)):
        return False
    stamp = path[len(prefix):-len(suffix)]
    return (len(stamp) == 16 and stamp[8] == 'T' and stamp[15] == 'Z'
            and (stamp[:8] + stamp[9:15]).isdigit() and stamp.isascii())


def sha256(data):
    return hashlib.sha256(data).hexdigest()


# -- remote output parsing (split/partition only, never regex) -------------------------------
def sections(text):
    result, name = {}, None
    for line in text.splitlines():
        if line.startswith('@@ '):
            name = line[3:].strip()
            result[name] = []
        elif name is not None:
            result[name].append(line)
    return result


def before_end(text):
    lines = text.splitlines()
    if '@@ end' not in lines:
        return None
    return lines[:lines.index('@@ end')]


def parse_show(lines):
    units, current = {}, {}
    for line in [*lines, '']:
        if not line.strip():
            if 'Id' in current:
                units[current['Id']] = current
            current = {}
            continue
        key, separator, value = line.partition('=')
        if separator:
            current[key] = value
    return units


def parse_stat(lines):
    entries = {}
    for line in lines:
        fields = line.split('|')
        if len(fields) != 7:
            entries[fields[0]] = {'kind': None, 'user': None, 'group': None, 'mode': None, 'size': None, 'mtime': None}
            continue
        path, kind, user, group, mode, size, mtime = fields
        octal = int(mode, 8) if mode and all(c in '01234567' for c in mode) else None
        entries[path] = {'kind': kind, 'user': user, 'group': group, 'mode': octal, 'size': to_int(size),
                         'mtime': to_int(mtime)}
    return entries


def parse_sha(lines):
    hashes = {}
    for line in lines:
        digest, separator, path = line.partition('  ')
        if separator:
            hashes[path] = digest if is_digest(digest) else None
    return hashes


def parse_pairs(lines):
    return {key: value for key, _, value in (line.partition(' ') for line in lines)}


def parse_colon(lines, width):
    records = {}
    for line in lines:
        fields = line.split(':')
        if len(fields) == width:
            records[fields[0]] = fields
    return records


class Snapshot:
    def __init__(self, text):
        found = sections(text)
        if 'end' not in found:
            raise Stop(2, 'snapshot_incomplete')
        get = lambda name: found.get(name, [])  # noqa: E731
        self.identity = get('id')[:2]
        self.now = to_int((get('now') or [''])[0])
        self.units = parse_show(get('units'))
        self.transient = parse_show(get('transient'))
        self.links = {path: target for path, _, target in (line.partition(' ') for line in get('links'))}
        self.stat = parse_stat(get('stat'))
        self.execs = set(get('exec'))
        self.sha = parse_sha(get('sha'))
        self.node = (get('node') or [''])[0].strip()
        df = [line.strip() for line in get('df') if line.strip()]
        self.df = to_int(df[1]) if len(df) == 2 else None
        self.counts = parse_pairs(get('counts'))
        self.passwd = parse_colon(get('passwd'), 7)
        self.group = parse_colon(get('group'), 4)
        self.passwd_all = [line.split(':') for line in get('passwd_all')]
        self.group_all = [line.split(':') for line in get('group_all')]
        self.idg = {name: value.split() for name, _, value in (line.partition(' ') for line in get('idg'))}

    def unit(self, name):
        return self.units.get(name, {})

    def active(self, name):
        return self.unit(name).get('ActiveState') == 'active'

    def active_set(self):
        return {stack: sorted(role for role in ROLES if self.active(unit_name(role, stack))) for stack in STACKS}

    def entry(self, path):
        return self.stat.get(path)

    def exists(self, path):
        return path in self.stat

    def trusted(self, path, kind='directory', traversable=False):
        entry = self.entry(path)
        if not entry or entry['kind'] != kind or entry['user'] != 'root' or entry['mode'] is None:
            return False
        return not entry['mode'] & 0o022 and (not traversable or bool(entry['mode'] & 0o001))

    def owned(self, path, user, group, mode, kinds):
        entry = self.entry(path)
        return bool(entry) and entry['kind'] in kinds and (entry['user'], entry['group'], entry['mode']) == (
            user, group, mode)

    def start_epoch(self, name):
        return to_int(self.unit(name).get('ExecMainStartTimestamp', '').lstrip('@'))


class Checks:
    def __init__(self):
        self.items = []

    def add(self, name, ok):
        self.items.append((name, bool(ok)))

    def failed(self):
        return [name for name, ok in self.items if not ok]


# -- remote command builders (constants and validated values only) --------------------------
def label(op, *args):
    return ': vps_release ' + ' '.join([op, *map(str, args)]) + ';'


def ssh_argv(remote):
    return ['/usr/bin/ssh', *SSH_OPTIONS, HOST_ALIAS, remote]


def snapshot_paths(new, prev):
    paths = ['/', '/opt', META, RELEASES, CURRENT, f'{RELEASES}/{prev}', f'{RELEASES}/{new}', f'{META}/current-{new}',
             f'{META}/current-{prev}', '/opt/instagram-meta-tools', NODE_DIR, NODE_DIR + '/bin', NODE, NPM_CLI,
             STAGING, stage_dir(new), stage_dir(new) + '/src', stage_dir(new) + '/manifest.sha256',
             '/etc', '/etc/instagram-meta', '/etc/systemd', '/etc/systemd/system', '/var', '/var/lib']
    for stack in STACKS:
        paths += [f'/etc/instagram-meta/{stack}', f'/etc/instagram-meta/{stack}/manager.env', marker(stack),
                  lock(stack), f'/var/lib/instagram-{stack}/publisher', f'/var/lib/instagram-{stack}/gateway',
                  f'/var/lib/instagram-{stack}/.Xauthority', f'/run/instagram-{stack}/vnc.sock',
                  f'/run/instagram-publisher-{stack}/publisher.sock']
        for home, sub in homes(stack).values():
            paths += [home, f'{home}/{sub}']
    return paths


def hash_paths(new, prev):
    paths = [NODE, *[node_dropin(r) for r in NODE_ROLES], *[cpu_override(s) for s in STACKS]]
    for base in ('/etc/systemd/system', f'{CURRENT}/{VPS_DIR}/systemd', f'{RELEASES}/{prev}/{VPS_DIR}/systemd',
                 f'{RELEASES}/{new}/{VPS_DIR}/systemd'):
        paths += [f'{base}/{t}' for t in TEMPLATES]
    return paths


def links_body(shas):
    paths = ' '.join(q(p) for p in [CURRENT, *[f'{META}/current-{s}' for s in shas]])
    return f'for p in {paths}; do printf \'%s %s\\n\' "$p" "$(readlink "$p")"; done'


def waiter_counts(stack):
    # While operator-waiter.mjs runs, the only session-*.mjs processes of ig-<stack> are its children
    # (manager.sh runs session-manager.mjs and the waiter one after the other): a person's request.
    return [f'printf \'waiter_{stack} %s\\n\' "$(ps -o args= -u ig-{stack} | grep -cF runtime/operator-waiter.mjs)"',
            f'printf \'session_procs_{stack} %s\\n\' "$(ps -o args= -u ig-{stack} | grep -cF '
            '-e instagram_testers/session-browser.mjs -e instagram_testers/session-manager.mjs)"']


def counts_body():
    parts = []
    for stack in STACKS:
        users = ','.join(homes(stack))
        parts += [
            *waiter_counts(stack),
            f'printf \'flag_{stack} %s\\n\' "$(grep -cxF INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED=true '
            f'/etc/instagram-meta/{stack}/manager.env)"',
            f'printf \'url_{stack} %s\\n\' "$(grep -cxF INSTAGRAM_TESTER_OPERATOR_BROWSER_URL=https://{GATEWAY_HOST}/'
            f'{stack}/ /etc/instagram-meta/{stack}/gateway.env)"',
            f'printf \'procs_{stack} %s\\n\' "$(ps -o pid= -u {users} | wc -l)"']
    parts += ['h="$(/usr/bin/Xtigervnc -help 2>&1)"',
              'for f in rfbunixpath rfbunixmode rfbport; do printf \'xvnc_%s %s\\n\' "$f" '
              '"$(printf \'%s\' "$h" | grep -ciF "$f")"; done',
              'printf \'max_userns %s\\n\' "$(cat /proc/sys/user/max_user_namespaces)"',
              'printf \'systemd %s\\n\' "$(systemctl --version | head -n 1 | cut -d \' \' -f 2)"',
              'if [ -e /proc/sys/kernel/unprivileged_userns_clone ]; then printf \'userns_clone %s\\n\' '
              '"$(cat /proc/sys/kernel/unprivileged_userns_clone)"; else echo \'userns_clone absent\'; fi']
    return '; '.join(parts)


def snapshot_command(new, prev):
    accounts = ' '.join(ACCOUNTS)
    groups = accounts + ' ' + ' '.join(f'igview-{s}' for s in STACKS)
    executables = [*REQUIRED_EXECUTABLES, *[p for pair in EITHER_EXECUTABLES.values() for p in pair]]
    transient = f'instagram-install-{new}.service instagram-stage-npm-{new}.service'
    parts = [
        "echo '@@ id'; hostname; id -u", "echo '@@ now'; date +%s",
        f"echo '@@ units'; systemctl show --timestamp=unix --property={UNIT_PROPS} {' '.join(UNITS)}",
        f"echo '@@ transient'; systemctl show --property=Id,LoadState,ActiveState {transient}",
        "echo '@@ links'; " + links_body([new, prev]),
        f"echo '@@ stat'; stat {STAT_FORMAT} {' '.join(q(p) for p in snapshot_paths(new, prev))}",
        f"echo '@@ exec'; for p in {' '.join(executables)}; do [ -x \"$p\" ] && echo \"$p\"; done",
        f"echo '@@ sha'; sha256sum {' '.join(q(p) for p in hash_paths(new, prev))}",
        f"echo '@@ node'; {NODE} --version", "echo '@@ df'; df --output=avail -B1 /opt",
        "echo '@@ counts'; " + counts_body(), f"echo '@@ passwd'; getent passwd {accounts}",
        f"echo '@@ group'; getent group {groups}", "echo '@@ passwd_all'; getent passwd | cut -d: -f1,3,4",
        "echo '@@ group_all'; getent group | cut -d: -f1,3",
        f"echo '@@ idg'; for n in {accounts}; do printf '%s %s\\n' \"$n\" \"$(id -G \"$n\")\"; done",
        "echo '@@ end'"]
    return label('snapshot', new, prev) + ' ' + '; '.join(parts)


def files_command():
    files = ' '.join([*[node_dropin(r) for r in NODE_ROLES], *[cpu_override(s) for s in STACKS]])
    return (label('files') + f' for f in {files}; do echo "@@ file $f"; base64 -w0 "$f"; echo; done; '
            "echo '@@ end'")


def backup_write_command(path):
    return label('backup_write', path) + f' umask 077; set -C; cat > {q(path)} && sha256sum {q(path)}'


def backup_read_command(path):
    return label('backup_read', path) + f' cat {q(path)}'


def units_command(names):
    return (label('units', ','.join(names)) + f' systemctl show --timestamp=unix --property={UNIT_PROPS} '
            + ' '.join(names) + "; echo '@@ end'")


def guard_command(stack):
    return (label('guard', stack) + f" echo '@@ now'; date +%s; echo '@@ stat'; stat {STAT_FORMAT} "
            f"{marker(stack)} {lock(stack)}; echo '@@ counts'; " + '; '.join(waiter_counts(stack))
            + "; echo '@@ end'")


def term_command(stack):
    return label('term', stack) + f' systemctl kill --kill-whom=main --signal=SIGTERM {unit_name("manager", stack)}'


def stop_command(names):
    return label('stop', ','.join(names)) + ' systemctl stop ' + ' '.join(names)


def start_command(names):
    return label('start', ','.join(names)) + ' systemctl start ' + ' '.join(names)


def journal_command(stack, since):
    # `@@ end` only after a flushed, successful read: an empty answer must never mean "nothing happened".
    return (label('journal', stack, since) + f' journalctl --sync && journalctl -u {unit_name("manager", stack)} '
            f"--since=@{since} -o cat --no-pager && echo '@@ end'")


def installer_command(sha):
    source = stage_dir(sha) + '/src'
    return (f'systemd-run --wait --collect --unit=instagram-install-{sha} --property=Type=exec '
            f'--property=BindReadOnlyPaths={NODE}:/usr/bin/node /usr/bin/python3 '
            f'{source}/{VPS_DIR}/install/install.py {source} {sha}')


def install_command(sha):
    return label('install_run', sha) + ' ' + installer_command(sha)


def transient_command(sha):
    return (label('transient', sha) + f' systemctl show --property=Id,LoadState,ActiveState '
            f"instagram-install-{sha}.service instagram-stage-npm-{sha}.service; echo '@@ end'")


def links_command(shas):
    return label('links', ','.join(shas)) + ' ' + links_body(shas) + "; echo '@@ end'"


def release_check_command(sha):
    return (label('release_check', sha) + f" echo '@@ rc'; (cd {RELEASES}/{sha} && sha256sum -c --strict --quiet "
            f"{stage_dir(sha)}/manifest.sha256 >/dev/null 2>&1; echo $?); echo '@@ end'")


def verify_pair_command(where, sha=None):
    if where == 'stage':
        return label('verify_pair', 'stage', sha) + (
            f' /usr/bin/python3 -B {stage_dir(sha)}/src/{VPS_DIR}/env/verify-pair.py')
    return label('verify_pair', 'current') + f' /usr/bin/python3 -B {CURRENT}/{VPS_DIR}/env/verify-pair.py'


def gateway_probe(stack):
    return f'/usr/bin/python3 -B -I -c {q(GATEWAY_PROBE)} {PORTS[stack]} /{stack}/ {GATEWAY_HOST}'


def ready_pair_command(stack):
    names = [unit_name('display', stack), unit_name('gateway', stack)]
    return (label('ready_pair', stack) + f" echo '@@ units'; systemctl show --property={UNIT_PROPS} "
            + ' '.join(names) + f"; echo '@@ stat'; stat {STAT_FORMAT} /run/instagram-{stack}/vnc.sock; "
            f"echo '@@ http'; {gateway_probe(stack)}; echo '@@ end'")


def ready_publisher_command(stack):
    sock = f'/run/instagram-publisher-{stack}/publisher.sock'
    return (label('ready_publisher', stack) + f" echo '@@ units'; systemctl show --property={UNIT_PROPS} "
            f"{unit_name('publisher', stack)}; echo '@@ stat'; stat {STAT_FORMAT} {sock}; echo '@@ probe'; "
            f"/usr/bin/python3 -B -I -c {q(PUBLISHER_PROBE)} {sock}; echo '@@ end'")


def runtime_command(sha, pids):
    argument = ','.join(f'{u}={p}' for u, p in pids.items()) or 'none'
    procs = ' '.join(str(p) for p in pids.values())
    sockets = ' '.join(f'/run/instagram-{s}/vnc.sock /run/instagram-publisher-{s}/publisher.sock' for s in STACKS)
    parts = [f"echo '@@ sha'; " + (f"sha256sum {' '.join(f'/proc/{p}/root/usr/bin/node' for p in pids.values())}"
                                   if pids else 'true'),
             f"echo '@@ cwd'; for p in {procs}; do printf '%s %s\\n' \"$p\" \"$(readlink /proc/$p/cwd)\"; done",
             "echo '@@ ss'; ss -H -l -t -n", f"echo '@@ stat'; stat {STAT_FORMAT} {sockets}"]
    parts += [f"echo '@@ http {s}'; {gateway_probe(s)}" for s in STACKS]
    parts += ["echo '@@ counts'"] + [
        f'printf \'waiter_{s} %s\\n\' "$(ps -o args= -u ig-{s} | grep -cF runtime/operator-waiter.mjs)"'
        for s in STACKS]
    return label('runtime', sha, argument) + ' ' + '; '.join(parts) + "; echo '@@ end'"


def cas_command(prev, new):
    temporary = f'{META}/current-{prev}'
    return (label('cas', prev, new) + f' [ "$(readlink {CURRENT})" = {RELEASES}/{new} ] && [ ! -e {temporary} ] '
            f'&& [ ! -L {temporary} ] && ln -s {RELEASES}/{prev} {temporary} && mv -T {temporary} {CURRENT}')


def cas_finish_command(prev, new):
    temporary = f'{META}/current-{prev}'
    return (label('cas_finish', prev, new) + f' [ "$(readlink {CURRENT})" = {RELEASES}/{new} ] && [ -L {temporary} ] '
            f'&& [ "$(readlink {temporary})" = {RELEASES}/{prev} ] && [ "$(stat -c %U {temporary})" = root ] '
            f'&& mv -T {temporary} {CURRENT}')


def reset_failed_command():
    return label('reset_failed') + ' systemctl reset-failed ' + ' '.join(UNITS)


def stage_mkdir_command(sha):
    return label('stage_mkdir', sha) + f' [ -d {STAGING} ] || mkdir -m 0755 {STAGING}; mkdir -m 0700 {stage_dir(sha)}'


def stage_upload_command(sha, name):
    return label('stage_upload', sha, name) + f' umask 077; set -C; cat > {stage_dir(sha)}/{name}'


def stage_hash_command(sha):
    return (label('stage_hash', sha) + f' sha256sum {stage_dir(sha)}/artifact.tar {stage_dir(sha)}/manifest.sha256; '
            "echo '@@ end'")


def stage_extract_command(sha):
    return (label('stage_extract', sha) + f' mkdir -m 0755 {stage_dir(sha)}/src && cd {stage_dir(sha)}/src && '
            'umask 022 && tar -x --no-same-owner --no-same-permissions -f ../artifact.tar')


def stage_npm_command(sha):
    work = f'{stage_dir(sha)}/src/{VPS_DIR}'
    return (label('stage_npm', sha) + f' umask 077; systemd-run --wait --collect --pipe --quiet '
            f'--unit=instagram-stage-npm-{sha} --property=Type=exec --property=PrivateTmp=yes --property=UMask=0022 '
            f'--property=RuntimeMaxSec=900 --property=WorkingDirectory={work} '
            f'--setenv=PATH={NODE_DIR}/bin:/usr/bin:/bin --setenv=HOME=/tmp --setenv=npm_config_cache=/tmp/npm-cache '
            f'--setenv=npm_config_userconfig=/tmp/npmrc-absent {NODE} {NPM_CLI} ci --ignore-scripts --no-audit '
            f'--no-fund > {stage_dir(sha)}/npm-ci.log 2>&1')


def stage_verify_command(sha, deps):
    src = f'{stage_dir(sha)}/src'
    modules = f'{src}/{VPS_DIR}/node_modules'
    parts = [f"echo '@@ sha'; sha256sum {stage_dir(sha)}/artifact.tar {stage_dir(sha)}/manifest.sha256",
             f"echo '@@ check'; (cd {src} && sha256sum -c --strict --quiet ../manifest.sha256 >/dev/null 2>&1; "
             'echo $?)',
             f"echo '@@ count'; (cd {src} && find . -path ./{VPS_DIR}/node_modules -prune -o -type f -print | wc -l)",
             f"echo '@@ scan'; (cd {src} && find . -name .bin -prune -o \\( -type l -o ! -type f ! -type d "
             f"-o ! -user root -o -perm /022 -o -name {q('.env*')} -o -name credentials -o -name id_ed25519 "
             "-o -name profile \\) -print | wc -l)"]
    parts += [f"echo '@@ dep {name}'; base64 -w0 {modules}/{name}/package.json; echo" for name in deps]
    parts += [f"echo '@@ playwright'; [ -f {modules}/playwright/index.mjs ] && "
              f'[ -f {modules}/playwright-core/package.json ] && echo ok',
              f"echo '@@ digest'; (cd {modules} && find . -name .bin -prune -o -type f -print0 | LC_ALL=C sort -z "
              "| xargs -0 sha256sum | sha256sum | cut -d' ' -f1)", "echo '@@ end'"]
    return label('stage_verify', sha) + ' ' + '; '.join(parts)


def stage_receipt_command(sha):
    return label('stage_receipt', sha) + f' umask 077; set -C; cat > {stage_dir(sha)}/stage.json'


def tool_command(*words):
    return 'python3 ' + TOOL + ' ' + ' '.join(words)


# -- the tool -------------------------------------------------------------------------------
@functools.lru_cache(maxsize=256)
def git_object(repo, sha, path):
    # Objects addressed by commit SHA are immutable, so caching them is safe.
    result = subprocess.run(['git', '-C', repo, 'show', f'{sha}:{path}'], capture_output=True, check=False)
    return result.stdout if result.returncode == 0 else None


def ssh_runner(command, stdin=None, timeout=60):
    feed = {'stdin': subprocess.DEVNULL} if stdin is None else {'input': stdin}
    try:
        result = subprocess.run(ssh_argv(command), capture_output=True, timeout=timeout, check=False, **feed)
    except subprocess.TimeoutExpired:
        return None, ''
    return result.returncode, result.stdout.decode('utf-8', 'replace')


class Tool:
    def __init__(self, args, runner, repo, out, clock, sleep):
        self.args, self.runner, self.repo, self.out = args, runner, Path(repo), out
        self.clock, self.sleep = clock, sleep
        self.mutated = False
        self.stage_mutated = False
        self.rollback_hint = ()

    # output ----------------------------------------------------------------------------------
    def say(self, *words):
        print(' '.join(str(w) for w in words), file=self.out)

    def report(self, checks, verbose=False):
        for name, ok in checks.items:
            if verbose or not ok:
                self.say('PASS' if ok else 'FAIL', name)

    def require(self, checks, code=2, token='precondition_failed', verbose=False):
        self.report(checks, verbose)
        if checks.failed():
            raise Stop(code, token)

    # transport -------------------------------------------------------------------------------
    def remote(self, command, stdin=None, timeout=60, raw=False):
        rc, output = self.runner(command, stdin, timeout)
        if raw:
            return rc, output
        if rc is None or rc == 255:
            raise Stop(3 if self.mutated else 2, 'ssh_state_unknown')
        return rc, output

    def snapshot(self, new, prev):
        _, output = self.remote(snapshot_command(new, prev), timeout=90)
        return Snapshot(output)

    def unit_states(self, names):
        _, output = self.remote(units_command(names))
        lines = before_end(output)
        if lines is None:
            raise Stop(3 if self.mutated else 2, 'units_read_incomplete')
        return parse_show(lines)

    def guard(self, stack):
        _, output = self.remote(guard_command(stack))
        found = sections(output)
        if 'end' not in found:
            raise Stop(3 if self.mutated else 2, 'guard_incomplete')
        stat = parse_stat(found.get('stat', []))
        counts = parse_pairs(found.get('counts', []))
        return {'now': to_int((found.get('now') or [''])[0]), 'marker': marker(stack) in stat,
                'lock': lock(stack) in stat, 'waiter': to_int(counts.get(f'waiter_{stack}')),
                'session': to_int(counts.get(f'session_procs_{stack}'))}

    def current_target(self, shas):
        _, output = self.remote(links_command(shas))
        lines = before_end(output) or []
        return {path: target for path, _, target in (line.partition(' ') for line in lines)}

    # git -------------------------------------------------------------------------------------
    def git(self, *args):
        result = subprocess.run(['git', '-C', str(self.repo), *args], capture_output=True, check=False)
        return result.returncode, result.stdout

    def git_ok(self, *args):
        return self.git(*args)[0] == 0

    def git_show(self, sha, path):
        data = git_object(str(self.repo), sha, path)
        if data is None:
            raise Stop(2, 'git_show_failed')
        return data

    def local_templates(self, sha):
        return {t: sha256(self.git_show(sha, f'{VPS_DIR}/systemd/{t}')) for t in TEMPLATES}

    def installer_literals(self, sha):
        tree = ast.parse(self.git_show(sha, f'{VPS_DIR}/install/install.py').decode())
        found = {}
        for node in tree.body:
            if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                if node.targets[0].id in ('SCRIPTS', 'PUBLISHER_MODULES', 'DEPS'):
                    found[node.targets[0].id] = ast.literal_eval(node.value)
        allowed = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Compare) and isinstance(node.ops[0], ast.LtE) and \
                    isinstance(node.comparators[0], ast.Set):
                elements = node.comparators[0].elts
                allowed = {e.value for e in elements if isinstance(e, ast.Constant)}
                allowed |= {f'*{e.value.id}' for e in elements if isinstance(e, ast.Starred)
                            and isinstance(e.value, ast.Name)}
        found['allowed'] = allowed
        return found

    def local_checks(self, new, prev, allow_downgrade, target_in_main=True):
        checks = Checks()
        checks.add('git_new_commit', self.git_ok('cat-file', '-e', f'{new}^{{commit}}'))
        checks.add('git_prev_commit', self.git_ok('cat-file', '-e', f'{prev}^{{commit}}'))
        if target_in_main:
            checks.add('git_target_in_origin_main', self.git_ok('merge-base', '--is-ancestor', new, 'origin/main'))
        if not allow_downgrade:
            checks.add('git_no_downgrade', self.git_ok('merge-base', '--is-ancestor', prev, new))
        self.require(checks)
        literals = self.installer_literals(new)
        checks = Checks()
        checks.add('installer_literals', {'SCRIPTS', 'PUBLISHER_MODULES', 'DEPS'} <= literals.keys())
        self.require(checks)
        # install.py:101-103 is `{...constants, *PUBLISHER_MODULES}`; `release/` must stay outside it.
        checks.add('installer_allowed_top', literals['allowed'] == set(BASE_TOP) | {'node_modules',
                                                                                    '*PUBLISHER_MODULES'})
        templates_new, templates_prev = self.local_templates(new), self.local_templates(prev)
        checks.add('templates_new_equal_prev', templates_new == templates_prev)
        deps = literals['DEPS']
        package = json.loads(self.git_show(new, f'{VPS_DIR}/package.json'))
        lock_file = json.loads(self.git_show(new, f'{VPS_DIR}/package-lock.json'))
        checks.add('package_json_deps', package.get('dependencies') == deps)
        checks.add('package_lock_deps', lock_file.get('packages', {}).get('', {}).get('dependencies') == deps)
        checks.add('package_lock_versions', all(lock_file.get('packages', {}).get(f'node_modules/{n}', {}).get(
            'version') == v for n, v in deps.items()))
        self.require(checks)
        return {'literals': literals, 'templates': templates_new, 'deps': deps}

    def selection(self, sha, literals):
        rc, data = self.git('ls-tree', '-r', '-z', '--full-tree', sha, '--', VPS_DIR, 'scripts/instagram_testers')
        if rc != 0:
            raise Stop(2, 'git_ls_tree_failed')
        tree = {}
        for entry in data.decode().split('\0'):
            if entry:
                meta, _, path = entry.partition('\t')
                tree[path] = meta.split()[0]
        allowed = set(BASE_TOP) | set(literals['PUBLISHER_MODULES'])
        checks = Checks()
        selected = []
        for path, mode in sorted(tree.items()):
            if not path.startswith(VPS_DIR + '/'):
                continue
            top = path[len(VPS_DIR) + 1:].split('/')[0]
            if top == 'release':
                continue
            checks.add(f'git_tree_mode:{path}', mode in ('100644', '100755'))
            checks.add(f'git_tree_top_level:{path}', top in allowed)
            selected.append(path)
        for name in literals['SCRIPTS']:
            path = f'scripts/instagram_testers/{name}'
            checks.add(f'git_script:{name}', tree.get(path) in ('100644', '100755'))
            selected.append(path)
        for name in (*REQUIRED_VPS_FILES, *literals['PUBLISHER_MODULES']):
            checks.add(f'git_required:{name}', f'{VPS_DIR}/{name}' in selected)
        self.require(checks)
        return sorted(set(selected))

    def artifact(self, sha, literals):
        paths = self.selection(sha, literals)
        rc, tar = self.git('-c', 'tar.umask=0022', 'archive', '--format=tar', sha, '--', *paths)
        if rc != 0:
            raise Stop(2, 'git_archive_failed')
        lines, files = [], set()
        with tarfile.open(fileobj=io.BytesIO(tar)) as archive:
            for member in archive.getmembers():
                if not (member.isfile() or member.isdir()) or '\\' in member.name or '\n' in member.name:
                    raise Stop(2, 'artifact_member_type')
                if member.isfile():
                    files.add(member.name)
                    lines.append(f'{sha256(archive.extractfile(member).read())}  ./{member.name}\n')
        if files != set(paths):
            raise Stop(2, 'artifact_selection_mismatch')
        manifest = ''.join(sorted(lines, key=lambda line: line.partition('  ')[2])).encode()
        return {'tar': tar, 'manifest': manifest, 'count': len(files)}

    # snapshot checks -------------------------------------------------------------------------
    def check_identity(self, c, s):
        c.add('identity', s.identity == [HOSTNAME, '0'] and s.now is not None)

    def check_units(self, c, s):
        for name in UNITS:
            role, stack = split_unit(name)
            unit = s.unit(name)
            state = unit.get('UnitFileState', '')
            c.add(f'unit_loaded:{name}', unit.get('LoadState') == 'loaded' and unit.get(
                'FragmentPath') == f'/etc/systemd/system/instagram-vps-{role}@.service')
            c.add(f'unit_not_enabled:{name}', bool(state) and not state.startswith('enabled'))
            c.add(f'dropins_exact:{name}', set(unit.get('DropInPaths', '').split()) == expected_dropins(role, stack))
            if role == 'publisher':
                c.add(f'publisher_quota:{stack}', unit.get('CPUQuotaPerSecUSec') == PUBLISHER_QUOTA)

    def check_files(self, c, s, templates, current=True, release=None):
        c.add('node_sha256', s.sha.get(NODE) == NODE_SHA256)
        for role in NODE_ROLES:
            c.add(f'node_dropin:{role}', s.sha.get(node_dropin(role)) == NODE_DROPIN_SHA256)
        for stack in STACKS:
            c.add(f'cpu_override:{stack}', s.sha.get(cpu_override(stack)) == CPU_OVERRIDE_SHA256)
        for template, digest in templates.items():
            c.add(f'template_etc:{template}', s.sha.get(f'/etc/systemd/system/{template}') == digest)
            if current:
                c.add(f'template_current:{template}', s.sha.get(f'{CURRENT}/{VPS_DIR}/systemd/{template}') == digest)
            if release:
                c.add(f'template_release:{template}',
                      s.sha.get(f'{RELEASES}/{release}/{VPS_DIR}/systemd/{template}') == digest)

    def check_release_tree(self, c, s, prev):
        for path in ('/', '/opt', META, RELEASES):
            c.add(f'release_ancestor:{path}', s.trusted(path, traversable=True))
        c.add('release_prev_dir', s.trusted(f'{RELEASES}/{prev}'))

    def check_current(self, c, s, prev):
        entry = s.entry(CURRENT) or {}
        c.add('current_is_from', s.links.get(CURRENT) == f'{RELEASES}/{prev}' and entry.get(
            'kind') == 'symbolic link' and entry.get('user') == 'root')

    def check_target_absent(self, c, s, new):
        c.add('target_release_absent', not s.exists(f'{RELEASES}/{new}'))
        c.add('target_tmp_link_absent', not s.exists(f'{META}/current-{new}') and not s.links.get(
            f'{META}/current-{new}'))

    def check_node(self, c, s):
        c.add('node_version', s.node == NODE_VERSION)
        c.add('node_trusted', all(s.trusted(p) for p in ('/opt', '/opt/instagram-meta-tools', NODE_DIR,
                                                           NODE_DIR + '/bin')) and s.trusted(NODE, 'regular file'))
        c.add('npm_present', s.trusted(NPM_CLI, 'regular file'))

    def check_transient(self, c, s, new, idle_only=False):
        for name in (f'instagram-install-{new}.service', f'instagram-stage-npm-{new}.service'):
            unit = s.transient.get(name, {})
            free = unit.get('LoadState') == 'not-found'
            idle = free or unit.get('ActiveState') in ('inactive', 'failed')
            c.add(f'transient_{"idle" if idle_only else "free"}:{name}', idle if idle_only else free)

    def check_staging(self, c, s):
        c.add('staging_trusted', not s.exists(STAGING) or s.trusted(STAGING))
        c.add('disk_free_1gib', s.df is not None and s.df >= MIN_FREE_BYTES)

    def check_bins(self, c, s):
        for path in REQUIRED_EXECUTABLES:
            c.add(f'executable:{path}', path in s.execs)
        for name, paths in EITHER_EXECUTABLES.items():
            c.add(f'executable:{name}', any(p in s.execs for p in paths))

    def check_host(self, c, s):
        for path in ('/etc', '/etc/instagram-meta', '/etc/systemd', '/etc/systemd/system', '/var', '/var/lib'):
            c.add(f'host_trusted:{path}', s.trusted(path))
        c.add('host_xvnc_flags', all((to_int(s.counts.get(f'xvnc_{f}')) or 0) > 0
                                     for f in ('rfbunixpath', 'rfbunixmode', 'rfbport')))
        c.add('host_userns', (to_int(s.counts.get('max_userns')) or 0) > 0 and s.counts.get('userns_clone') in (
            'absent', '1'))
        c.add('host_systemd_version', (to_int(s.counts.get('systemd')) or 0) >= MIN_SYSTEMD)
        for name in UNITS:
            if s.active(name):
                c.add(f'start_timestamp:{name}', s.start_epoch(name) is not None)
        viewers = {}
        for stack in STACKS:
            c.add(f'host_trusted:/etc/instagram-meta/{stack}', s.trusted(f'/etc/instagram-meta/{stack}'))
            for legacy in ('publisher', 'gateway'):
                c.add(f'host_legacy_absent:{stack}:{legacy}', not s.exists(f'/var/lib/instagram-{stack}/{legacy}'))
            group = s.group.get(f'igview-{stack}')
            viewers[stack] = to_int(group[2]) if group else None
            c.add(f'host_viewer_members:{stack}', bool(group) and set(group[3].split(',')) == {
                f'ig-{stack}', f'iggw-{stack}'})
            c.add(f'host_xauthority:{stack}', s.owned(f'/var/lib/instagram-{stack}/.Xauthority', f'ig-{stack}',
                                                      f'ig-{stack}', 0o600, ('regular file',))
                  and (s.entry(f'/var/lib/instagram-{stack}/.Xauthority')['size'] or 0) > 0)
        self.check_accounts(c, s, viewers)

    def check_accounts(self, c, s, viewers):
        gids = {}
        for name, (home, sub) in ACCOUNTS.items():
            record = s.passwd.get(name)
            group = s.group.get(name)
            uid, gid = (to_int(record[2]), to_int(record[3])) if record else (None, None)
            gids[name] = gid
            c.add(f'host_account:{name}', bool(record) and uid not in (None, 0) and gid not in (None, 0)
                  and record[5] == home and record[6] == '/usr/sbin/nologin' and bool(group)
                  and to_int(group[2]) == gid and group[3] == '')
            stack = name.split('-')[1]
            expected = {str(gid)} if name.startswith('igpub-') else {str(gid), str(viewers.get(stack))}
            c.add(f'host_groups:{name}', set(s.idg.get(name, [])) == expected)
            for path in (home, f'{home}/{sub}'):
                c.add(f'host_home:{path}', s.owned(path, name, name, 0o700, ('directory',)))
        uids = [to_int(s.passwd[n][2]) for n in ACCOUNTS if n in s.passwd]
        all_gids = [g for g in gids.values() if g is not None] + [v for v in viewers.values() if v is not None]
        c.add('host_unique_ids', len(uids) == len(set(uids)) == 6 and len(all_gids) == len(set(all_gids)) == 8
              and 0 not in all_gids)
        # Mirror of install.py exclusive_accounts(): no other account or group shares these ids.
        service = {n: (s.passwd[n][2], s.passwd[n][3]) for n in ACCOUNTS if n in s.passwd}
        viewer_gids = {str(g): f'igview-{st}' for st, g in viewers.items() if g is not None}
        exclusive = True
        for record in s.passwd_all:
            if len(record) != 3:
                exclusive = False
                continue
            for name, (uid, gid) in service.items():
                if record[1] == uid or record[2] == gid:
                    exclusive = exclusive and record[0] == name
            exclusive = exclusive and record[2] not in viewer_gids
        named = {gid: name for name, (_, gid) in service.items()}
        named.update(viewer_gids)
        for record in s.group_all:
            if len(record) != 2:
                exclusive = False
            elif record[1] in named:
                exclusive = exclusive and record[0] == named[record[1]]
        c.add('host_exclusive_ids', exclusive)

    def check_human(self, c, s):
        for stack in STACKS:
            c.add(f'marker_absent:{stack}', not s.exists(marker(stack)))
            c.add(f'waiter_absent:{stack}', s.counts.get(f'waiter_{stack}') == '0')

    def check_gateway_url(self, c, s):
        for stack in STACKS:
            c.add(f'gateway_url:{stack}', s.counts.get(f'url_{stack}') == '1')

    def check_locks(self, c, s, stacks=STACKS):
        for stack in stacks:
            if not s.active(unit_name('manager', stack)):
                c.add(f'manager_lock_absent:{stack}', not s.exists(lock(stack)))

    def preflight_checks(self, s, new, prev, templates):
        c = Checks()
        self.check_identity(c, s)
        self.check_units(c, s)
        self.check_current(c, s, prev)
        self.check_release_tree(c, s, prev)
        self.check_target_absent(c, s, new)
        self.check_files(c, s, templates, release=prev)
        self.check_node(c, s)
        self.check_transient(c, s, new)
        self.check_staging(c, s)
        self.check_bins(c, s)
        self.check_host(c, s)
        self.check_human(c, s)
        self.check_gateway_url(c, s)
        self.check_locks(c, s)
        return c

    # subcommands -----------------------------------------------------------------------------
    def cmd_preflight(self):
        a = self.args
        local = self.local_checks(a.sha, a.source, a.allow_downgrade)
        s = self.snapshot(a.sha, a.source)
        checks = self.preflight_checks(s, a.sha, a.source, local['templates'])
        self.require(checks, verbose=True)
        for stack, roles in s.active_set().items():
            self.say('active', f'{stack}=' + ','.join(roles))
            self.say('browser_operations_flag', f'{stack}={to_int(s.counts.get(f"flag_{stack}"))}')
        self.say('stage_present', s.exists(stage_dir(a.sha)))
        self.say('vps_release_preflight_ok')
        return 0

    def cmd_backup(self):
        a = self.args
        local = self.local_checks(a.sha, a.source, a.allow_downgrade)
        s = self.snapshot(a.sha, a.source)
        self.require(self.preflight_checks(s, a.sha, a.source, local['templates']))
        _, output = self.remote(files_command())
        found = sections(output)
        files = {}
        checks = Checks()
        expected = {**{node_dropin(r): NODE_DROPIN_SHA256 for r in NODE_ROLES},
                    **{cpu_override(st): CPU_OVERRIDE_SHA256 for st in STACKS}}
        for path, digest in expected.items():
            encoded = ''.join(found.get(f'file {path}', [])).strip()
            try:
                data = base64.b64decode(encoded, validate=True)
            except ValueError:
                data = b''
            checks.add(f'backup_bytes:{path}', sha256(data) == digest)
            files[path] = encoded
        self.require(checks)
        path = f'/tmp/instagram-vps_state_{utc_stamp(s.now)}.json'
        document = {
            'schema': BACKUP_SCHEMA, 'utc': utc_stamp(s.now), 'hostname': HOSTNAME, 'target_sha': a.sha,
            'from_sha': a.source, 'current_target': f'{RELEASES}/{a.source}',
            'units': {n: {k: s.unit(n).get(k, '') for k in ('ActiveState', 'SubState', 'UnitFileState',
                                                               'DropInPaths', 'CPUQuotaPerSecUSec', 'NRestarts')}
                      for n in UNITS},
            'hashes': {p: s.sha.get(p) for p in [NODE, *expected, *[f'/etc/systemd/system/{t}' for t in TEMPLATES]]},
            'files': files,
            'flags': {st: to_int(s.counts.get(f'flag_{st}')) for st in STACKS},
            'active': s.active_set()}
        body = (json.dumps(document, indent=2, sort_keys=True) + '\n').encode()
        rc, output = self.remote(backup_write_command(path), stdin=body)
        written = parse_sha(output.splitlines()).get(path)
        if rc != 0 or written != sha256(body):
            raise Stop(2, 'backup_write')
        self.say('vps_release_backup_ok', f'path={path}', f'sha256={written}')
        return 0

    def read_backup(self, path):
        if not valid_backup_path(path):
            raise Stop(2, 'backup_path_invalid')
        rc, output = self.remote(backup_read_command(path))
        try:
            data = json.loads(output) if rc == 0 else None
        except ValueError:
            data = None
        if not isinstance(data, dict) or data.get('schema') != BACKUP_SCHEMA:
            raise Stop(2, 'backup_invalid')
        active = data.get('active')
        valid = (is_sha(data.get('target_sha')) and is_sha(data.get('from_sha')) and isinstance(active, dict)
                 and set(active) == set(STACKS) and all(isinstance(v, list) and set(v) <= set(ROLES)
                                                         for v in active.values())
                 and isinstance(data.get('hashes'), dict) and isinstance(data.get('units'), dict))
        if not valid:
            raise Stop(2, 'backup_invalid')
        data['active'] = self.consistent_active({k: sorted(v) for k, v in active.items()})
        return data

    @staticmethod
    def consistent_active(active):
        for roles in active.values():
            needs = {'gateway': {'display'}, 'manager': {'display', 'publisher'}}
            if any(needs.get(role, set()) - set(roles) for role in roles):
                raise Stop(2, 'active_set_inconsistent')
        return active

    def cmd_stage(self):
        a = self.args
        local = self.local_checks(a.sha, a.source, a.allow_downgrade)
        artifact = self.artifact(a.sha, local['literals'])
        s = self.snapshot(a.sha, a.source)
        c = Checks()
        self.check_identity(c, s)
        self.check_current(c, s, a.source)
        self.check_target_absent(c, s, a.sha)
        self.check_files(c, s, local['templates'], release=a.source)
        self.check_node(c, s)
        self.check_transient(c, s, a.sha)
        self.check_staging(c, s)
        self.check_bins(c, s)
        c.add('stage_absent', not s.exists(stage_dir(a.sha)))
        self.require(c)
        self.stage_mutated = True
        self.expect_rc(stage_mkdir_command(a.sha), 'stage_mkdir')
        self.expect_rc(stage_upload_command(a.sha, 'artifact.tar'), 'stage_upload', stdin=artifact['tar'])
        self.expect_rc(stage_upload_command(a.sha, 'manifest.sha256'), 'stage_upload', stdin=artifact['manifest'])
        _, output = self.remote(stage_hash_command(a.sha))
        hashes = parse_sha(before_end(output) or [])
        if hashes.get(f'{stage_dir(a.sha)}/artifact.tar') != sha256(artifact['tar']) or hashes.get(
                f'{stage_dir(a.sha)}/manifest.sha256') != sha256(artifact['manifest']):
            raise Stop(3, 'stage_hash')
        self.expect_rc(stage_extract_command(a.sha), 'stage_extract', timeout=300)
        rc, _ = self.remote(stage_npm_command(a.sha), timeout=1200, raw=True)
        if rc is None or rc == 255:
            self.wait_transient(a.sha, f'instagram-stage-npm-{a.sha}.service')
        elif rc != 0:
            raise Stop(3, 'npm_ci_failed')
        result = self.stage_state(a.sha, local['deps'], artifact, digest=None)
        c = Checks()
        for name, ok in result['checks']:
            c.add(name, ok)
        c.add('stage_tar_sha256', result['tar'] == sha256(artifact['tar']))
        self.require(c, code=3, token='stage_verify')
        receipt = {'sha': a.sha, 'tar_sha256': sha256(artifact['tar']), 'manifest_sha256': sha256(
            artifact['manifest']), 'files': artifact['count'], 'modules_digest': result['digest'],
            'deps': local['deps'], 'utc': utc_stamp(s.now)}
        self.expect_rc(stage_receipt_command(a.sha), 'stage_receipt',
                       stdin=(json.dumps(receipt, indent=2, sort_keys=True) + '\n').encode())
        self.say('vps_release_stage_ok', f'sha={a.sha}', f'manifest_sha256={sha256(artifact["manifest"])}',
                 f'modules_digest={result["digest"]}')
        self.say('proximo:', tool_command('install', '--sha', a.sha, '--from', a.source, '--backup', '<backup>',
                                          '--modules-digest', result['digest']))
        return 0

    def expect_rc(self, command, token, stdin=None, timeout=120):
        rc, _ = self.remote(command, stdin=stdin, timeout=timeout)
        if rc != 0:
            raise Stop(3, token)

    def stage_state(self, sha, deps, artifact, digest):
        _, output = self.remote(stage_verify_command(sha, deps), timeout=300)
        found = sections(output)
        hashes = parse_sha(found.get('sha', []))
        checks = [('stage_read_complete', 'end' in found),
                  ('stage_manifest_sha256', hashes.get(f'{stage_dir(sha)}/manifest.sha256') == sha256(
                      artifact['manifest'])),
                  ('stage_manifest_check', found.get('check') == ['0']),
                  ('stage_file_count', to_int((found.get('count') or [''])[0]) == artifact['count']),
                  ('stage_tree_scan', found.get('scan') == ['0']),
                  ('stage_playwright', found.get('playwright') == ['ok'])]
        for name, version in deps.items():
            try:
                package = json.loads(base64.b64decode(''.join(found.get(f'dep {name}', [])), validate=True))
            except ValueError:
                package = {}
            checks.append((f'stage_dep_version:{name}', isinstance(package, dict) and package.get('version') == version))
        got = (found.get('digest') or [''])[0].strip()
        checks.append(('stage_modules_digest', is_digest(got) and (digest is None or got == digest)))
        return {'checks': checks, 'digest': got if is_digest(got) else None,
                'tar': hashes.get(f'{stage_dir(sha)}/artifact.tar')}

    def wait_transient(self, sha, name):
        deadline = self.clock() + TRANSIENT_WAIT_SECONDS
        while self.clock() < deadline:
            rc, output = self.remote(transient_command(sha), raw=True)
            lines = before_end(output) if rc == 0 else None
            if lines is not None:
                unit = parse_show(lines).get(name, {})
                if unit.get('LoadState') == 'not-found' or unit.get('ActiveState') in ('inactive', 'failed'):
                    return
            self.sleep(5)
        raise Stop(3, 'transient_still_running')

    # install ---------------------------------------------------------------------------------
    def cmd_install(self):
        a = self.args
        self.rollback_hint = ('rollback:', tool_command('rollback', '--to', a.source, '--from', a.sha, '--backup',
                                                        a.backup))
        local = self.local_checks(a.sha, a.source, a.allow_downgrade)
        artifact = self.artifact(a.sha, local['literals'])
        backup = self.read_backup(a.backup)
        s = self.phase_a(a, local, artifact, backup)
        self.stop_runtime(s, strict=True)
        self.run_installer(a.sha, a.source)
        self.after_install(a.sha, local['templates'], backup)
        self.start_runtime(backup['active'], reset=False)
        code = self.verify_state(a.sha, backup['active'], backup, local['templates'], context='install')
        if code == 0:
            self.say('vps_release_install_ok', f'current={a.sha}')
        return code

    def phase_a(self, a, local, artifact, backup):
        checks = Checks()
        checks.add('backup_matches_release', backup['target_sha'] == a.sha and backup['from_sha'] == a.source
                   and backup.get('current_target') == f'{RELEASES}/{a.source}')
        self.require(checks)
        result = self.stage_state(a.sha, local['deps'], artifact, digest=a.modules_digest)
        s = self.snapshot(a.sha, a.source)
        c = self.preflight_checks(s, a.sha, a.source, local['templates'])
        for name, ok in result['checks']:
            c.add(name, ok)
        c.add('stage_dir_trusted', s.trusted(stage_dir(a.sha)) and s.entry(stage_dir(a.sha))['mode'] == 0o700)
        for path, digest in backup['hashes'].items():
            c.add(f'backup_hash:{path}', s.sha.get(path) == digest)
        c.add('backup_active_set', s.active_set() == backup['active'])
        for name in UNITS:
            c.add(f'backup_unit_file_state:{name}', s.unit(name).get('UnitFileState') == backup['units'].get(
                name, {}).get('UnitFileState'))
        rc, output = self.remote(verify_pair_command('stage', a.sha))
        c.add('verify_pair_new_release', rc == 0 and output.strip() == 'instagram_vps_env_pair_ok')
        confirmed = set(a.queue_idle_confirmed)
        for stack in STACKS:
            name = unit_name('manager', stack)
            if not s.active(name):
                continue
            flag = s.counts.get(f'flag_{stack}')
            mtime = (s.entry(f'/etc/instagram-meta/{stack}/manager.env') or {}).get('mtime')
            started = s.start_epoch(name)
            proven_off = flag == '0' and mtime is not None and started is not None and mtime < started
            c.add(f'queue_idle:{stack}', proven_off or stack in confirmed)
        self.require(c)
        return s

    def stop_runtime(self, s, strict):
        stopped_any = False
        for stack in STACKS:
            name = unit_name('manager', stack)
            if not s.active(name):
                continue
            guard = self.guard(stack)
            self.check_guard(guard, strict)
            since = guard['now']
            rc, _ = self.remote(term_command(stack), raw=True)
            if rc is None or rc == 255:
                self.mutated = True
                raise Stop(3, 'ssh_state_unknown')
            if rc != 0:
                raise Stop(3 if self.mutated else 2, 'manager_term_failed', (
                    'sigterm_nao_entregue: o manager segue rodando como estava',))
            self.mutated = True
            if not self.wait_manager_exit(name):
                lines = ()
                if not stopped_any and strict:
                    lines = ('nada_trocado current=PREV; sigterm_entregue mas o manager nao saiu em 40 s',
                             'aguarde ele sair (Restart=on-failure religa em PREV com NRestarts=1) e rode o rollback '
                             'abaixo, que religa PREV limpo',)
                raise Stop(3, 'manager_stop_timeout', lines)
            self.remote(stop_command([name]))
            stopped_any = True
            if self.interrupted(stack, since):
                if strict:
                    raise Stop(3, 'operation_outcome_uncertain', (
                        'resultado incerto: nao repetir a operacao; reconciliar no Rails antes de qualquer reenvio',))
                self.say('WARN operation_outcome_uncertain', stack)
            if self.guard(stack)['lock']:
                raise Stop(3, 'manager_lock_present', LOCK_PROCEDURE)
        self.remote(stop_command(list(UNITS)), timeout=120)
        self.mutated = True
        after = self.snapshot(self.args_new(), self.args_prev())
        c = Checks()
        for name in UNITS:
            unit = after.unit(name)
            c.add(f'stopped:{name}', unit.get('ActiveState') in ('inactive', 'failed') and unit.get('MainPID') == '0')
        for stack in STACKS:
            c.add(f'no_processes:{stack}', after.counts.get(f'procs_{stack}') == '0')
        self.require(c, code=3, token='units_not_stopped')

    def check_guard(self, guard, strict):
        code = 3 if self.mutated else 2
        if guard['marker']:
            raise Stop(code, 'human_window_open')
        if guard['waiter'] == 0:
            return
        if strict:
            raise Stop(code, 'operator_waiter_running')
        if not self.args.stop_operator_waiter:
            raise Stop(code, 'operator_waiter_running', (WAITER_LINE, self.rollback_hint[1] + ' ' + WAITER_FLAG))
        if guard['session'] != 0:
            raise Stop(code, 'human_window_open')

    def wait_manager_exit(self, name):
        deadline = self.clock() + MANAGER_EXIT_SECONDS
        while self.clock() < deadline:
            if self.unit_states([name]).get(name, {}).get('MainPID') == '0':
                return True
            self.sleep(1)
        return False

    def journal_lines(self, stack, since):
        rc, output = self.remote(journal_command(stack, since))
        lines = output.splitlines()
        if rc != 0 or not lines or lines[-1] != '@@ end':
            return None
        return lines[:-1]

    def interrupted(self, stack, since):
        lines = self.journal_lines(stack, since)
        if lines is None:
            self.say('WARN journal_read_incomplete', stack)
            return True
        for line in lines:
            text = line.strip()
            if text == 'instagram_manager_failed':
                return True
            if not text.startswith('{'):
                continue
            try:
                event = json.loads(text)
            except ValueError:
                continue
            if not isinstance(event, dict):
                continue
            if event.get('event') == 'instagram_browser_operation_executor_failed':
                return True
            if event.get('event') == 'instagram_browser_operation_lifecycle' and event.get(
                    'request_present') is True and event.get('complete_received') is not True:
                return True
        return False

    def args_new(self):
        return self.args.sha if self.args.command == 'install' else self.args.source

    def args_prev(self):
        return self.args.source if self.args.command == 'install' else self.args.to

    def run_installer(self, new, prev):
        rc, _ = self.remote(install_command(new), timeout=900, raw=True)
        if rc is None or rc == 255:
            self.wait_transient(new, f'instagram-install-{new}.service')
        target = self.current_target([new]).get(CURRENT)
        if target == f'{RELEASES}/{new}' and rc in (0, None, 255):
            return
        if target == f'{RELEASES}/{prev}':
            raise Stop(3, 'installer_failed', ('current=PREV; o rollback abaixo so religa as units',))
        raise Stop(3, 'installer_state_unknown')

    def after_install(self, new, templates, backup):
        rc, output = self.remote(release_check_command(new))
        if sections(output).get('rc') != ['0']:
            raise Stop(3, 'release_manifest')
        rc, output = self.remote(verify_pair_command('current'))
        if rc != 0 or output.strip() != 'instagram_vps_env_pair_ok':
            raise Stop(3, 'verify_pair')
        s = self.snapshot(new, self.args.source)
        c = Checks()
        self.check_files(c, s, templates)
        for path, digest in backup['hashes'].items():
            c.add(f'host_file_unchanged:{path}', s.sha.get(path) == digest)
        self.require(c, code=3, token='host_files_changed')

    # start -----------------------------------------------------------------------------------
    def start_runtime(self, active, reset):
        for stack in STACKS:
            roles = active[stack]
            if not roles:
                continue
            names = [unit_name(r, stack) for r in ROLES if r in roles]
            states = self.unit_states(names)
            if not reset and any(states.get(n, {}).get('Result') == 'start-limit-hit' for n in names):
                raise Stop(3, 'start_limit_hit')
            pair = [unit_name(r, stack) for r in ('display', 'gateway') if r in roles]
            if pair:
                rc, _ = self.remote(start_command(pair), timeout=90)
                if rc != 0 or not self.pair_ready(stack, 'gateway' in roles):
                    self.remote(stop_command(pair))
                    raise Stop(3, 'gateway_not_ready')
            if 'publisher' in roles:
                name = unit_name('publisher', stack)
                rc, _ = self.remote(start_command([name]), timeout=90)
                if rc != 0 or not self.publisher_ready(stack):
                    self.remote(stop_command([name]))
                    raise Stop(3, 'publisher_not_ready')
            if 'manager' in roles:
                if self.guard(stack)['lock']:
                    raise Stop(3, 'manager_lock_present', LOCK_PROCEDURE)
                rc, _ = self.remote(start_command([unit_name('manager', stack)]), timeout=90)
                if rc != 0:
                    raise Stop(3, 'manager_start_failed')

    @staticmethod
    def broken(unit):
        return unit.get('ActiveState') in ('failed', 'inactive') or unit.get('SubState') == 'auto-restart'

    def pair_ready(self, stack, with_gateway):
        deadline = self.clock() + PAIR_READY_SECONDS
        names = [unit_name('display', stack)] + ([unit_name('gateway', stack)] if with_gateway else [])
        while self.clock() < deadline:
            _, output = self.remote(ready_pair_command(stack))
            found = sections(output)
            units = parse_show(found.get('units', []))
            if any(self.broken(units.get(n, {})) for n in names):
                return False
            alive = all(units.get(n, {}).get('ActiveState') == 'active' and (to_int(units.get(n, {}).get(
                'MainPID')) or 0) > 0 for n in names)
            sock = parse_stat(found.get('stat', [])).get(f'/run/instagram-{stack}/vnc.sock', {})
            http = (found.get('http') or [''])[0].strip()
            if alive and sock.get('kind') == 'socket':
                if not with_gateway:
                    return True
                if http == 'status=401 set_cookie=0':
                    return True
                if http != 'refused':
                    return False
            self.sleep(0.2)
        return False

    def publisher_ready(self, stack):
        deadline = self.clock() + PUBLISHER_READY_SECONDS
        name = unit_name('publisher', stack)
        first_pid = None
        while self.clock() < deadline:
            _, output = self.remote(ready_publisher_command(stack))
            found = sections(output)
            unit = parse_show(found.get('units', [])).get(name, {})
            if self.broken(unit) or unit.get('NRestarts') != '0':
                return False
            pid = to_int(unit.get('MainPID'))
            first_pid = first_pid or pid
            sock = parse_stat(found.get('stat', [])).get(f'/run/instagram-publisher-{stack}/publisher.sock', {})
            socket_ok = (sock.get('kind'), sock.get('user'), sock.get('group'), sock.get('mode')) == (
                'socket', f'igpub-{stack}', f'ig-{stack}', 0o660)
            if pid and pid != first_pid:
                return False
            if socket_ok and pid and found.get('probe') == ['publisher_ready']:
                return True
            self.sleep(1)
        return False

    # verify ----------------------------------------------------------------------------------
    def cmd_verify(self):
        a = self.args
        backup = self.read_backup(a.backup)
        templates = self.local_templates(a.sha)
        return self.verify_state(a.sha, backup['active'], backup, templates, context='standalone')

    def verify_state(self, sha, active, backup, templates, context):
        s = self.wait_bootstrap(sha, active)
        c = Checks()
        c.add('current_target', s.links.get(CURRENT) == f'{RELEASES}/{sha}')
        if s.exists(stage_dir(sha) + '/manifest.sha256'):
            _, output = self.remote(release_check_command(sha))
            c.add('release_manifest', sections(output).get('rc') == ['0'])
        self.check_units(c, s)
        self.check_files(c, s, templates)
        if backup:
            for path, digest in backup['hashes'].items():
                c.add(f'backup_hash:{path}', s.sha.get(path) == digest)
        pids = {}
        for name in UNITS:
            role, stack = split_unit(name)
            unit = s.unit(name)
            if role in active[stack]:
                c.add(f'running:{name}', unit.get('ActiveState') == 'active' and unit.get('SubState') == 'running'
                      and (to_int(unit.get('MainPID')) or 0) > 0 and unit.get('NRestarts') == '0')
                if role in NODE_ROLES and to_int(unit.get('MainPID')):
                    pids[name] = to_int(unit.get('MainPID'))
            else:
                c.add(f'not_started:{name}', unit.get('ActiveState') != 'active')
            if backup:
                c.add(f'unit_file_state:{name}', unit.get('UnitFileState') == backup['units'].get(name, {}).get(
                    'UnitFileState'))
        operator = self.check_runtime(c, sha, active, pids)
        rc, output = self.remote(verify_pair_command('current'))
        c.add('verify_pair', rc == 0 and output.strip() == 'instagram_vps_env_pair_ok')
        for stack in STACKS:
            if 'manager' in active[stack]:
                started = s.start_epoch(unit_name('manager', stack))
                c.add(f'manager_start_known:{stack}', started is not None and s.now is not None)
                if started is None:
                    continue
                tokens = self.journal_tokens(stack, started)
                c.add(f'journal_read_complete:{stack}', tokens['complete'])
                c.add(f'bootstrap:{stack}', not tokens['fail'])
                operator = operator or tokens['operator']
                if tokens['route_failed']:
                    self.say('route_failed_lines', f'{stack}={tokens["route_failed"]}')
        return self.verify_outcome(c, operator, context)

    def other_sha(self, sha):
        for name in ('source', 'to'):
            value = getattr(self.args, name, None)
            if is_sha(value) and value != sha:
                return value
        return sha

    def wait_bootstrap(self, sha, active):
        for _ in range(3):
            s = self.snapshot(sha, self.other_sha(sha))
            ages = [s.now - s.start_epoch(unit_name('manager', st)) for st in STACKS
                    if 'manager' in active[st] and s.start_epoch(unit_name('manager', st)) is not None
                    and s.now is not None]
            missing = max([BOOTSTRAP_SECONDS - age for age in ages] + [0])
            if missing <= 0:
                return s
            self.say('aguardando_bootstrap_segundos', missing)
            self.sleep(missing)
        return s

    def check_runtime(self, c, sha, active, pids):
        _, output = self.remote(runtime_command(sha, pids))
        found = sections(output)
        c.add('runtime_read_complete', 'end' in found)
        hashes = {path.split('/')[2]: digest for path, digest in parse_sha(found.get('sha', [])).items()
                  if path.startswith('/proc/')}
        cwd = {pid: target for pid, _, target in (line.partition(' ') for line in found.get('cwd', []))}
        for name, pid in pids.items():
            c.add(f'node_effective:{name}', hashes.get(str(pid)) == NODE_SHA256)
            c.add(f'running_release:{name}', cwd.get(str(pid)) == f'{RELEASES}/{sha}')
        listeners = [line.split()[3] for line in found.get('ss', []) if len(line.split()) >= 4]
        stat = parse_stat(found.get('stat', []))
        counts = parse_pairs(found.get('counts', []))
        operator = False
        for stack in STACKS:
            roles = active[stack]
            if 'gateway' in roles:
                hosts = [addr.rpartition(':')[0] for addr in listeners if addr.rpartition(':')[2] == str(PORTS[stack])]
                c.add(f'gateway_loopback_only:{stack}', bool(hosts) and set(hosts) == {'127.0.0.1'})
                c.add(f'gateway_401_no_cookie:{stack}', found.get(f'http {stack}') == ['status=401 set_cookie=0'])
            if 'display' in roles:
                c.add(f'vnc_socket:{stack}', (stat.get(f'/run/instagram-{stack}/vnc.sock') or {}).get('kind') == 'socket'
                      and self.socket_owned(stat, f'/run/instagram-{stack}/vnc.sock', f'ig-{stack}', f'igview-{stack}'))
            if 'publisher' in roles:
                c.add(f'publisher_socket:{stack}', self.socket_owned(
                    stat, f'/run/instagram-publisher-{stack}/publisher.sock', f'igpub-{stack}', f'ig-{stack}'))
            if 'manager' in roles and counts.get(f'waiter_{stack}') != '0':
                operator = True
        return operator

    @staticmethod
    def socket_owned(stat, path, user, group):
        entry = stat.get(path) or {}
        return (entry.get('kind'), entry.get('user'), entry.get('group'), entry.get('mode')) == (
            'socket', user, group, 0o660)

    def journal_tokens(self, stack, since):
        lines = self.journal_lines(stack, since)
        result = {'fail': False, 'operator': False, 'route_failed': 0, 'complete': lines is not None}
        for line in lines or []:
            text = line.strip()
            if text in FAIL_TOKENS:
                result['fail'] = True
            elif text in OPERATOR_TOKENS:
                result['operator'] = True
            elif text.startswith('{'):
                try:
                    event = json.loads(text)
                except ValueError:
                    continue
                if isinstance(event, dict) and event.get('event') == 'instagram_browser_route_failed':
                    result['route_failed'] += 1
        return result

    def verify_outcome(self, c, operator, context):
        self.report(c)
        if c.failed():
            raise Stop(3, 'verify_failed')
        if operator:
            lines = (('prev_saudavel_no_backup; a decisao de rollback e do operador',) if context == 'install'
                     else ('rollback_nao_resolve: a sessao Meta pede uma pessoa',))
            raise Stop(4, 'operator_required', lines)
        self.say('vps_release_verify_ok')
        return 0

    # rollback --------------------------------------------------------------------------------
    def cmd_rollback(self):
        a = self.args
        prev, new = a.to, a.source
        hint = ['--backup', a.backup] if a.backup else [w for spec in a.units_active for w in ('--units-active', spec)]
        waiter = [WAITER_FLAG] if a.stop_operator_waiter else []
        self.rollback_hint = ('rode de novo o rollback:', tool_command('rollback', '--to', prev, '--from', new, *hint,
                                                                       *waiter))
        templates = self.local_templates(prev)
        backup = self.read_backup(a.backup) if a.backup else None
        if backup and (backup['from_sha'] != prev or backup['target_sha'] != new):
            raise Stop(2, 'backup_mismatch')
        active = backup['active'] if backup else self.parse_units_active(a.units_active)
        s = self.snapshot(new, prev)
        finish = self.rollback_checks(s, prev, new, templates, active)
        if self.rollback_is_noop(s, prev, active):
            self.say('rollback_noop current=PREV e conjunto ativo rodando PREV; nada mudou')
            self.say('confira com:', tool_command('verify', '--sha', prev, *hint))
            return 0
        self.stop_runtime(s, strict=False)
        self.remote(reset_failed_command())
        if s.links.get(CURRENT) == f'{RELEASES}/{new}':
            command = cas_finish_command(prev, new) if finish else cas_command(prev, new)
            rc, _ = self.remote(command)
            if rc != 0:
                raise Stop(3, 'cas_failed')
        if self.current_target([prev]).get(CURRENT) != f'{RELEASES}/{prev}':
            raise Stop(3, 'cas_failed')
        rc, output = self.remote(verify_pair_command('current'))
        if rc != 0 or output.strip() != 'instagram_vps_env_pair_ok':
            raise Stop(3, 'verify_pair')
        self.start_runtime(active, reset=True)
        code = self.verify_state(prev, active, backup, templates, context='rollback')
        if code == 0:
            self.say('vps_release_rollback_ok', f'current={prev}')
        return code

    def rollback_checks(self, s, prev, new, templates, active):
        c = Checks()
        self.check_identity(c, s)
        self.check_transient(c, s, new, idle_only=True)
        c.add('release_prev_dir', s.trusted(f'{RELEASES}/{prev}'))
        self.check_files(c, s, templates, current=False, release=prev)
        c.add('current_is_new_or_prev', s.links.get(CURRENT) in (f'{RELEASES}/{new}', f'{RELEASES}/{prev}'))
        temporary = f'{META}/current-{prev}'
        link = s.links.get(temporary, '')
        entry = s.entry(temporary) or {}
        finish = bool(link) and link == f'{RELEASES}/{prev}' and entry.get('kind') == 'symbolic link' and entry.get(
            'user') == 'root'
        c.add('tmp_link_absent_or_prev', (not link and not s.exists(temporary)) or finish)
        for stack in STACKS:
            c.add(f'marker_absent:{stack}', not s.exists(marker(stack)))
            if s.counts.get(f'waiter_{stack}') != '0':
                c.add(f'operator_waiter_stop_allowed:{stack}', self.args.stop_operator_waiter)
                c.add(f'operator_waiter_idle:{stack}', s.counts.get(f'session_procs_{stack}') == '0')
        self.check_locks(c, s, [st for st in STACKS if 'manager' in active[st]])
        self.report(c)
        if c.failed():
            lines = ()
            if not self.args.stop_operator_waiter and any(n.startswith('operator_waiter_stop_allowed:')
                                                          for n in c.failed()):
                lines = (WAITER_LINE, self.rollback_hint[1] + ' ' + WAITER_FLAG)
            raise Stop(2, 'precondition_failed', lines)
        return finish

    def rollback_is_noop(self, s, prev, active):
        if s.links.get(CURRENT) != f'{RELEASES}/{prev}':
            return False
        names = [unit_name(r, st) for st in STACKS for r in active[st]]
        if not all(s.active(n) and s.unit(n).get('SubState') == 'running' and s.unit(n).get('NRestarts') == '0'
                   for n in names):
            return False
        pids = {n: to_int(s.unit(n).get('MainPID')) for n in names if split_unit(n)[0] in NODE_ROLES}
        if not all(pids.values()):
            return False
        c = Checks()
        self.check_runtime(c, prev, active, pids)
        return not c.failed()

    @staticmethod
    def parse_units_active(specs):
        active = {stack: [] for stack in STACKS}
        for spec in specs:
            stack, separator, roles = spec.partition('=')
            names = [r for r in roles.split(',') if r]
            if not separator or stack not in STACKS or not set(names) <= set(ROLES) or active[stack]:
                raise Stop(2, 'units_active_invalid')
            active[stack] = sorted(names)
        if not any(active.values()):
            raise Stop(2, 'units_active_invalid')
        return Tool.consistent_active(active)

    # dry run ---------------------------------------------------------------------------------
    def dry_run(self):
        a = self.args
        plan = getattr(self, f'plan_{a.command}')()
        for command, stdin in plan:
            self.say(command)
            if stdin:
                self.say(f'  <stdin: {stdin}>')
        self.say('vps_release_dry_run', f'{len(plan)}_comandos_remotos', 'nenhuma_chamada_ssh')
        return 0

    def plan_preflight(self):
        self.local_checks(self.args.sha, self.args.source, self.args.allow_downgrade)
        return [(snapshot_command(self.args.sha, self.args.source), None)]

    def plan_backup(self):
        return self.plan_preflight() + [(files_command(), None), (backup_write_command(
            '/tmp/instagram-vps_state_<UTC>.json'), 'backup JSON')]

    def plan_stage(self):
        a = self.args
        local = self.local_checks(a.sha, a.source, a.allow_downgrade)
        artifact = self.artifact(a.sha, local['literals'])
        describe = lambda name, data: f'{name}, {len(data)} bytes, sha256 {sha256(data)}'  # noqa: E731
        return [(snapshot_command(a.sha, a.source), None), (stage_mkdir_command(a.sha), None),
                (stage_upload_command(a.sha, 'artifact.tar'), describe('artifact.tar', artifact['tar'])),
                (stage_upload_command(a.sha, 'manifest.sha256'), describe('manifest.sha256', artifact['manifest'])),
                (stage_hash_command(a.sha), None), (stage_extract_command(a.sha), None),
                (stage_npm_command(a.sha), None), (stage_verify_command(a.sha, local['deps']), None),
                (stage_receipt_command(a.sha), 'stage.json')]

    def plan_stop(self, new, prev):
        plan = []
        for stack in STACKS:
            plan += [(guard_command(stack), None), (term_command(stack), None),
                     (units_command([unit_name('manager', stack)]), None),
                     (stop_command([unit_name('manager', stack)]), None), (journal_command(stack, '<T>'), None),
                     (guard_command(stack), None)]
        return plan + [(stop_command(list(UNITS)), None), (snapshot_command(new, prev), None)]

    def plan_start(self, sha, other, stage=True):
        plan = []
        for stack in STACKS:
            pair = [unit_name('display', stack), unit_name('gateway', stack)]
            plan += [(units_command([unit_name(r, stack) for r in ROLES]), None), (start_command(pair), None),
                     (ready_pair_command(stack), None), (start_command([unit_name('publisher', stack)]), None),
                     (ready_publisher_command(stack), None), (guard_command(stack), None),
                     (start_command([unit_name('manager', stack)]), None)]
        return plan + self.plan_verify_state(sha, other, stage)

    @staticmethod
    def plan_pids():
        return {unit_name(r, st): f'<MainPID:{unit_name(r, st)}>' for st in STACKS for r in NODE_ROLES}

    def plan_verify_state(self, sha, other, stage=True):
        check = release_check_command(sha)
        return [(snapshot_command(sha, other), None), (check if stage else OPTIONAL_STAGE + check, None),
                (runtime_command(sha, self.plan_pids()), None), (verify_pair_command('current'), None)] + [
            (journal_command(st, '<ExecMainStartTimestamp>'), None) for st in STACKS]

    def plan_install(self):
        a = self.args
        local = self.local_checks(a.sha, a.source, a.allow_downgrade)
        self.artifact(a.sha, local['literals'])
        plan = [(backup_read_command(a.backup), None), (stage_verify_command(a.sha, local['deps']), None),
                (snapshot_command(a.sha, a.source), None), (verify_pair_command('stage', a.sha), None)]
        plan += self.plan_stop(a.sha, a.source)
        plan += [(install_command(a.sha), None), (links_command([a.sha]), None), (release_check_command(a.sha), None),
                 (verify_pair_command('current'), None), (snapshot_command(a.sha, a.source), None)]
        return plan + self.plan_start(a.sha, a.source)

    def plan_verify(self):
        self.local_templates(self.args.sha)
        return [(backup_read_command(self.args.backup), None)] + self.plan_verify_state(
            self.args.sha, self.args.sha, stage=False)

    def plan_rollback(self):
        a = self.args
        self.local_templates(a.to)
        plan = [(backup_read_command(a.backup), None)] if a.backup else []
        plan += [(snapshot_command(a.source, a.to), None),
                 (OPTIONAL_NOOP + runtime_command(a.to, self.plan_pids()), None)] + self.plan_stop(a.source, a.to)
        plan += [(reset_failed_command(), None), (cas_command(a.to, a.source), None),
                 ('# ou, se current-<PREV> ja aponta para PREV: ' + cas_finish_command(a.to, a.source), None),
                 (links_command([a.to]), None), (verify_pair_command('current'), None)]
        return plan + self.plan_start(a.to, a.source, stage=False)

    # dispatch --------------------------------------------------------------------------------
    def run(self):
        if self.args.dry_run:
            return self.dry_run()
        return getattr(self, f'cmd_{self.args.command}')()

    def finish(self, stop):
        for line in stop.lines:
            self.say(line)
        if stop.code == 4:
            self.say('vps_release_operator_required', f'token={stop.token}')
            if self.args.command == 'install':
                self.say(*self.rollback_hint, WAITER_FLAG)
            return 4
        if self.stage_mutated and not self.mutated:
            self.say('vps_release_stage_failed', f'token={stop.token}', 'runtime_intocado',
                     'limpar_stage_pelo_runbook')
            return 3
        if stop.code == 2 and not self.mutated:
            self.say('vps_release_precondition_failed', f'token={stop.token}', 'nada_mudou')
            return 2
        if self.args.command == 'verify':
            self.say('vps_release_verify_failed', f'token={stop.token}')
            return 3
        self.say('vps_release_failed_after_change', f'token={stop.token}')
        if self.rollback_hint:
            self.say(*self.rollback_hint)
        return 3


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise Usage(message)


def parse_args(argv):
    parser = Parser(prog='vps_release.py', description=__doc__.splitlines()[0])
    parser.add_argument('--dry-run', action='store_true')
    sub = parser.add_subparsers(dest='command', required=True)

    def release(name, backup=False, digest=False):
        command = sub.add_parser(name)
        command.add_argument('--sha', required=True)
        command.add_argument('--from', dest='source', default=DEFAULT_FROM)
        command.add_argument('--allow-downgrade', action='store_true')
        if backup:
            command.add_argument('--backup', required=True)
        if digest:
            command.add_argument('--modules-digest', required=True)
            command.add_argument('--queue-idle-confirmed', default='')
        return command
    release('preflight')
    release('backup')
    release('stage')
    release('install', backup=True, digest=True)
    verify = sub.add_parser('verify')
    verify.add_argument('--sha', required=True)
    verify.add_argument('--backup', required=True)
    rollback = sub.add_parser('rollback')
    rollback.add_argument('--to', required=True)
    rollback.add_argument('--from', dest='source', required=True)
    rollback.add_argument('--backup')
    rollback.add_argument('--units-active', action='append', default=[])
    rollback.add_argument(WAITER_FLAG, dest='stop_operator_waiter', action='store_true')
    args = parser.parse_args(argv)
    for name in ('sha', 'source', 'to'):
        if getattr(args, name, None) is not None and not is_sha(getattr(args, name)):
            raise Usage(f'{name} must be 40 lowercase hex characters')
    if getattr(args, 'backup', None) is not None and not valid_backup_path(args.backup):
        raise Usage('--backup must be /tmp/instagram-vps_state_<UTC>.json')
    if args.command == 'install':
        if not is_digest(args.modules_digest):
            raise Usage('--modules-digest must be 64 lowercase hex characters')
        args.queue_idle_confirmed = [s for s in args.queue_idle_confirmed.split(',') if s]
        if not set(args.queue_idle_confirmed) <= set(STACKS):
            raise Usage('--queue-idle-confirmed accepts hub2you,autonomia')
    if args.command == 'rollback' and bool(args.backup) == bool(args.units_active):
        raise Usage('rollback needs exactly one of --backup or --units-active')
    if args.command in ('preflight', 'backup', 'stage', 'install') and args.sha == args.source:
        raise Usage('--sha and --from must differ')
    return args


def main(argv=None, runner=None, repo=None, out=None, err=None, clock=None, sleep=None):
    out = out or sys.stdout
    err = err or sys.stderr
    tool = None
    try:
        try:
            args = parse_args(sys.argv[1:] if argv is None else argv)
        except Usage as usage:
            print(f'usage_error: {usage}', file=err)
            return 2
        root = Path(repo) if repo else Path(__file__).resolve().parents[5]
        tool = Tool(args, runner or ssh_runner, root, out, clock or time.monotonic, sleep or time.sleep)
        return tool.run()
    except Stop as stop:
        if tool is None:
            print(f'vps_release_precondition_failed token={stop.token}', file=out)
            return 2
        return tool.finish(stop)
    except BaseException:  # noqa: BLE001 - never print exception text: it may carry remote output.
        mutated = tool is not None and tool.mutated
        print('vps_release_internal_error', 'codigo=3' if mutated else 'codigo=2', file=out)
        if mutated and tool.rollback_hint:
            print(*tool.rollback_hint, file=out)
        return 3 if mutated else 2


if __name__ == '__main__':
    sys.exit(main())
