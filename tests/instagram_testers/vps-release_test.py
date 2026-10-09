#!/usr/bin/env python3
"""Offline tests for the VPS release tool. A dictionary-backed fake VPS answers every
remote command; a temporary git repository provides the release commits. No SSH,
no AWS, no Meta, no network."""
import ast
import base64
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
VPS_REL = 'scripts/instagram_testers/runtime/vps'
TOOL_PATH = ROOT / VPS_REL / 'release/vps_release.py'
INSTALL_PATH = ROOT / VPS_REL / 'install/install.py'

spec = importlib.util.spec_from_file_location('vps_release', TOOL_PATH)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def literal(name):
    tree = ast.parse(INSTALL_PATH.read_text())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(getattr(t, 'id', None) == name for t in node.targets):
            return ast.literal_eval(node.value)
    raise AssertionError(name)


SCRIPTS = literal('SCRIPTS')
PUBLISHER_MODULES = literal('PUBLISHER_MODULES')
DEPS = literal('DEPS')
STACKS = ('hub2you', 'autonomia')
ROLES = ('display', 'gateway', 'publisher', 'manager')
UNITS = [f'instagram-vps-{role}@{stack}.service' for stack in STACKS for role in ROLES]
CANARY = 'CANARYSECRETabcdefghijklmnopqrstuvwxyz0123456789XYZ'
DROPIN_BYTES = b'[Service]\nBindReadOnlyPaths=/opt/instagram-meta-tools/node-v24.21.0-linux-x64/bin/node:/usr/bin/node\n'
CPU_BYTES = b'[Service]\nCPUQuota=200%\n'
MODULES_DIGEST = 'd' * 64
GIT = ['git', '-c', 'user.name=t', '-c', 'user.email=t@example.invalid', '-c', 'commit.gpgsign=false']


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(repo, *args):
    return subprocess.run([*GIT, '-C', str(repo), *args], check=True, capture_output=True, text=True).stdout.strip()


def build_repo(base):
    repo = base / 'repo'
    repo.mkdir()
    git(repo, 'init', '-q', '-b', 'main')
    tracked = git(ROOT, 'ls-files', VPS_REL).splitlines()
    for name in [f'scripts/instagram_testers/{s}' for s in SCRIPTS] + tracked:
        if '/release/' in name:
            continue
        target = repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, target)
    (repo / VPS_REL / 'release').mkdir()
    shutil.copyfile(TOOL_PATH, repo / VPS_REL / 'release/vps_release.py')
    git(repo, 'add', '-A')
    git(repo, 'commit', '-q', '-m', 'prev')
    prev = git(repo, 'rev-parse', 'HEAD')
    with (repo / 'scripts/instagram_testers/session-manager.mjs').open('a') as handle:
        handle.write('// new release\n')
    git(repo, 'commit', '-q', '-am', 'new')
    new = git(repo, 'rev-parse', 'HEAD')
    git(repo, 'update-ref', 'refs/remotes/origin/main', new)
    # Working-tree noise that must never reach the artifact.
    (repo / VPS_REL / 'node_modules/ws').mkdir(parents=True)
    (repo / VPS_REL / 'node_modules/ws/package.json').write_text('{"version": "mac"}')
    with (repo / VPS_REL / 'gateway.mjs').open('a') as handle:
        handle.write('// dirty working tree\n')
    templates = {unit: sha((repo / VPS_REL / 'systemd' / unit).read_bytes())
                 for unit in [f'instagram-vps-{r}@.service' for r in ROLES]}
    return repo, prev, new, templates


class FakeVPS:
    """Answers commands by their `: vps_release <op> <args>;` label."""

    def __init__(self, prev, new, templates):
        self.prev, self.new, self.templates = prev, new, templates
        self.calls = []
        self.now = 1_760_000_000.0
        self.hostname, self.uid = 'srv707880', '0'
        self.current = f'/opt/instagram-meta/releases/{prev}'
        self.links = {}
        self.node_version = 'v24.21.0'
        self.hashes = {}
        self.fs = {}
        self.execs = set()
        self.counts = {}
        self.journal = {stack: [] for stack in STACKS}
        self.backups = {}
        self.uploads = {}
        self.stage_exists = False
        self.receipt = None
        self.deps = dict(DEPS)
        self.verify_pair_ok = {'stage': True, 'current': True}
        self.installer = 'ok'
        self.install_transient_polls = 0
        self.transient = {}
        self.manager_exits = {stack: True for stack in STACKS}
        self.lock_left = set()
        self.start_behavior = {}
        self.http = {stack: ('401', '0') for stack in STACKS}
        self.publisher_probes = {stack: [] for stack in STACKS}
        self.node_override = {}
        self.manifest_check_rc = '0'
        self.scan_count = '0'
        self.digest = MODULES_DIGEST
        self.df = 50 * 1024 ** 3
        self.running = {}
        self.journal_on_term = {stack: [] for stack in STACKS}
        self.journal_on_start = {stack: [] for stack in STACKS}
        self.waiter_after_start = {}
        self.term_rc = 0
        self.journal_complete = True
        self.malformed = {}
        self.pid = 1000
        self.units = {}
        for name in UNITS:
            role = name.split('-')[2].split('@')[0]
            stack = name.split('@')[1].split('.')[0]
            self.units[name] = {
                'Id': name, 'LoadState': 'loaded', 'ActiveState': 'inactive', 'SubState': 'dead',
                'Result': 'success', 'MainPID': '0', 'NRestarts': '0', 'UnitFileState': 'disabled',
                'FragmentPath': f'/etc/systemd/system/instagram-vps-{role}@.service',
                'DropInPaths': self.expected_dropins(role, stack),
                'CPUQuotaPerSecUSec': '2s' if role == 'publisher' else '500ms',
                'ExecMainStartTimestamp': ''}
            self.activate(name)
        self.units_start_time()
        self.populate()

    @staticmethod
    def expected_dropins(role, stack):
        if role == 'display':
            return ''
        node = f'/etc/systemd/system/instagram-vps-{role}@.service.d/20-private-node.conf'
        if role == 'publisher':
            return f'{node} /etc/systemd/system/instagram-vps-publisher@{stack}.service.d/30-cpu-quota.conf'
        return node

    def units_start_time(self):
        for unit in self.units.values():
            if unit['ActiveState'] == 'active':
                unit['ExecMainStartTimestamp'] = f'@{int(self.now) - 3600}'

    def activate(self, name, behavior='ok'):
        unit = self.units[name]
        self.pid += 1
        if behavior == 'crashloop':
            unit.update(ActiveState='activating', SubState='auto-restart', MainPID='0', Result='exit-code')
            return
        unit.update(ActiveState='active', SubState='running', MainPID=str(self.pid), NRestarts='0',
                    Result='success', ExecMainStartTimestamp=f'@{int(self.now)}')
        self.running[name] = self.current.rsplit('/', 1)[1]

    # -- filesystem model ------------------------------------------------------------------
    def put(self, path, kind='directory', user='root', group='root', mode='755', size='4096', mtime='1000'):
        self.fs[path] = [kind, user, group, mode, size, mtime]

    def populate(self):
        for path in ('/', '/opt', '/opt/instagram-meta', '/opt/instagram-meta/releases',
                     f'/opt/instagram-meta/releases/{self.prev}', '/opt/instagram-meta-tools',
                     '/opt/instagram-meta-tools/node-v24.21.0-linux-x64',
                     '/opt/instagram-meta-tools/node-v24.21.0-linux-x64/bin', '/opt/instagram-meta-staging',
                     '/etc', '/etc/systemd', '/etc/systemd/system', '/var', '/var/lib'):
            self.put(path)
        self.put('/opt/instagram-meta/current', 'symbolic link', mode='777', size='60')
        self.put(tool.NODE, 'regular file', size='100')
        self.put(tool.NPM_CLI, 'regular file', mode='644', size='100')
        self.put('/etc/instagram-meta', mode='700')
        for stack in STACKS:
            self.put(f'/etc/instagram-meta/{stack}', mode='700')
            self.put(f'/etc/instagram-meta/{stack}/manager.env', 'regular file', mode='600', size='900', mtime='1000')
            self.put(f'/etc/systemd/system/instagram-vps-publisher@{stack}.service.d')
            self.put(tool.cpu_override(stack), 'regular file', mode='644', size='30')
            self.hashes[tool.cpu_override(stack)] = tool.CPU_OVERRIDE_SHA256
            for prefix, home, sub in (('ig', 'instagram', 'profile'), ('igpub', 'instagram-publisher', 'publisher'),
                                      ('iggw', 'instagram-gateway', 'gateway')):
                self.put(f'/var/lib/{home}-{stack}', user=f'{prefix}-{stack}', group=f'{prefix}-{stack}', mode='700')
                self.put(f'/var/lib/{home}-{stack}/{sub}', user=f'{prefix}-{stack}', group=f'{prefix}-{stack}',
                         mode='700')
            self.put(f'/var/lib/instagram-{stack}/.Xauthority', 'regular file', f'ig-{stack}', f'ig-{stack}', '600', '50')
            self.counts[f'flag_{stack}'] = '0'
            self.counts[f'url_{stack}'] = '1'
        for role in ('gateway', 'publisher', 'manager'):
            self.put(f'/etc/systemd/system/instagram-vps-{role}@.service.d')
            self.put(tool.node_dropin(role), 'regular file', mode='644', size='100')
            self.hashes[tool.node_dropin(role)] = tool.NODE_DROPIN_SHA256
        self.hashes[tool.NODE] = tool.NODE_SHA256
        for unit, digest in self.templates.items():
            self.put(f'/etc/systemd/system/{unit}', 'regular file', mode='644', size='1000')
            self.hashes[f'/etc/systemd/system/{unit}'] = digest
        self.execs = set(tool.REQUIRED_EXECUTABLES) | {'/usr/bin/aws', '/usr/bin/session-manager-plugin'}
        self.counts.update({'xvnc_rfbunixpath': '1', 'xvnc_rfbunixmode': '1', 'xvnc_rfbport': '1',
                            'max_userns': '63000', 'userns_clone': 'absent', 'systemd': '255'})

    def session_procs(self, stack):
        # manager.sh runs session-manager.mjs, or the waiter whose children are the browser/manager.
        if f'session_procs_{stack}' in self.counts:
            return self.counts[f'session_procs_{stack}']
        manager = self.units[f'instagram-vps-manager@{stack}.service']
        waiting = self.counts.get(f'waiter_{stack}', '0') != '0'
        return '1' if manager['ActiveState'] == 'active' and not waiting else '0'

    def release_templates(self, release):
        if not self.fs.get(f'/opt/instagram-meta/releases/{release}'):
            return {}
        return {f'/opt/instagram-meta/releases/{release}/{VPS_REL}/systemd/{unit}': digest
                for unit, digest in self.templates.items()}

    def dynamic_fs(self):
        fs = dict(self.fs)
        for stack in STACKS:
            if self.units[f'instagram-vps-manager@{stack}.service']['ActiveState'] == 'active' or stack in self.lock_left:
                fs[f'/var/lib/instagram-{stack}/profile/.instagram-manager.lock'] = [
                    'regular empty file', f'ig-{stack}', f'ig-{stack}', '600', '0', '1000']
            if self.units[f'instagram-vps-display@{stack}.service']['ActiveState'] == 'active':
                fs[f'/run/instagram-{stack}/vnc.sock'] = ['socket', f'ig-{stack}', f'igview-{stack}', '660', '0', '1']
            if self.units[f'instagram-vps-publisher@{stack}.service']['ActiveState'] == 'active':
                fs[f'/run/instagram-publisher-{stack}/publisher.sock'] = [
                    'socket', f'igpub-{stack}', f'ig-{stack}', '660', '0', '1']
        if self.stage_exists:
            stage = f'/opt/instagram-meta-staging/release-{self.new}'
            fs[stage] = ['directory', 'root', 'root', '700', '4096', '1']
            fs[f'{stage}/src'] = ['directory', 'root', 'root', '755', '4096', '1']
            for name in ('artifact.tar', 'manifest.sha256', 'stage.json'):
                if name in self.uploads or (name == 'stage.json' and self.receipt):
                    fs[f'{stage}/{name}'] = ['regular file', 'root', 'root', '600', '10', '1']
        return fs

    # -- rendering ---------------------------------------------------------------------------
    def show(self, names):
        blocks = []
        for name in names:
            if name in self.units:
                props = self.units[name]
            else:
                props = self.transient.get(name, {'Id': name, 'LoadState': 'not-found', 'ActiveState': 'inactive'})
            blocks.append('\n'.join(f'{k}={v}' for k, v in props.items()))
        return '\n\n'.join(blocks) + '\n'

    def stat_lines(self, fs):
        return ''.join(f'{p}|{"|".join(v)}\n' for p, v in sorted(fs.items()))

    def snapshot(self):
        fs = self.dynamic_fs()
        hashes = dict(self.hashes)
        hashes.update(self.release_templates(self.prev))
        hashes.update(self.release_templates(self.new))
        hashes.update({f'/opt/instagram-meta/current/{VPS_REL}/systemd/{unit}': digest
                       for unit, digest in self.templates.items()} if fs.get(self.current) else {})
        counts = dict(self.counts)
        for stack in STACKS:
            counts.setdefault(f'waiter_{stack}', '0')
            counts[f'session_procs_{stack}'] = self.session_procs(stack)
            counts[f'procs_{stack}'] = str(sum(1 for n, u in self.units.items()
                                               if f'@{stack}.' in n and u['MainPID'] != '0'))
        transient = [f'instagram-install-{self.new}.service', f'instagram-stage-npm-{self.new}.service']
        links = [('/opt/instagram-meta/current', self.current)] + [
            (f'/opt/instagram-meta/current-{s}', self.links.get(s, '')) for s in (self.new, self.prev)]
        out = ['@@ id', self.hostname, self.uid, '@@ now', str(int(self.now)), '@@ units',
               self.show(UNITS).rstrip('\n'), '', '@@ transient', self.show(transient).rstrip('\n'), '',
               '@@ links', *[f'{p} {t}' for p, t in links], '@@ stat', self.stat_lines(fs).rstrip('\n'),
               '@@ exec', *sorted(self.execs), '@@ sha', *[f'{h}  {p}' for p, h in sorted(hashes.items())],
               '@@ node', self.node_version, '@@ df', '        Avail', str(self.df), '@@ counts',
               *[f'{k} {v}' for k, v in sorted(counts.items())], '@@ passwd']
        uid = 2000
        gids = {}
        for stack in STACKS:
            for prefix, home in (('ig', 'instagram'), ('igpub', 'instagram-publisher'), ('iggw', 'instagram-gateway')):
                uid += 1
                gids[f'{prefix}-{stack}'] = uid
                out.append(f'{prefix}-{stack}:x:{uid}:{uid}::/var/lib/{home}-{stack}:/usr/sbin/nologin')
        out.append('@@ group')
        for name, gid in gids.items():
            out.append(f'{name}:x:{gid}:')
        viewers = {}
        for index, stack in enumerate(STACKS):
            viewers[stack] = 3000 + index
            out.append(f'igview-{stack}:x:{viewers[stack]}:ig-{stack},iggw-{stack}')
        out.append('@@ passwd_all')
        out.append('root:0:0')
        out.extend(f'{n}:{g}:{g}' for n, g in gids.items())
        out.append('@@ group_all')
        out.append('root:0')
        out.extend(f'{n}:{g}' for n, g in gids.items())
        out.extend(f'igview-{s}:{g}' for s, g in viewers.items())
        out.append('@@ idg')
        for name, gid in gids.items():
            stack = name.split('-')[1]
            out.append(f'{name} {gid}' if name.startswith('igpub-') else f'{name} {gid} {viewers[stack]}')
        out.append('@@ end')
        text = '\n'.join(out) + '\n'
        return self.malformed.get('snapshot', lambda t: t)(text)

    # -- dispatcher --------------------------------------------------------------------------
    def __call__(self, command, stdin=None, timeout=None):
        self.calls.append((command, stdin))
        self.now += 0.5
        head, _, _ = command.partition(';')
        words = head.split()
        assert words[:2] == [':', 'vps_release'], command
        op, args = words[2], words[3:]
        return getattr(self, 'op_' + op)(args, stdin)

    def sleep(self, seconds):
        self.now += seconds

    def clock(self):
        return self.now

    def op_snapshot(self, args, stdin):
        return 0, self.snapshot()

    def op_files(self, args, stdin):
        out = []
        for role in ('gateway', 'publisher', 'manager'):
            out += [f'@@ file {tool.node_dropin(role)}', base64.b64encode(DROPIN_BYTES).decode()]
        for stack in STACKS:
            out += [f'@@ file {tool.cpu_override(stack)}', base64.b64encode(CPU_BYTES).decode()]
        out.append('@@ end')
        return 0, '\n'.join(out) + '\n'

    def op_backup_write(self, args, stdin):
        path = args[0]
        if path in self.backups:
            return 1, ''
        self.backups[path] = stdin
        return 0, f'{sha(stdin)}  {path}\n'

    def op_backup_read(self, args, stdin):
        if args[0] not in self.backups:
            return 1, ''
        return 0, self.malformed.get('backup', lambda b: b)(self.backups[args[0]]).decode()

    def op_stage_mkdir(self, args, stdin):
        if self.stage_exists:
            return 1, ''
        self.stage_exists = True
        return 0, ''

    def op_stage_upload(self, args, stdin):
        self.uploads[args[1]] = stdin if args[1] != 'artifact.tar' or 'tar' not in self.malformed else b'x'
        return 0, ''

    def op_stage_hash(self, args, stdin):
        lines = [f'{sha(self.uploads[n])}  /opt/instagram-meta-staging/release-{self.new}/{n}'
                 for n in ('artifact.tar', 'manifest.sha256') if n in self.uploads]
        return 0, '\n'.join(lines + ['@@ end']) + '\n'

    def op_stage_extract(self, args, stdin):
        return 0, ''

    def op_stage_npm(self, args, stdin):
        return 0, ''

    def op_stage_verify(self, args, stdin):
        out = ['@@ sha']
        for name in ('artifact.tar', 'manifest.sha256'):
            if name in self.uploads:
                out.append(f'{sha(self.uploads[name])}  /opt/instagram-meta-staging/release-{self.new}/{name}')
        manifest = self.uploads.get('manifest.sha256', b'').decode()
        out += ['@@ check', self.manifest_check_rc, '@@ count', str(len(manifest.splitlines())),
                '@@ scan', self.scan_count]
        for name, version in self.deps.items():
            out += [f'@@ dep {name}', base64.b64encode(json.dumps({'version': version}).encode()).decode()]
        out += ['@@ playwright', 'ok', '@@ digest', self.digest, '@@ end']
        return 0, self.malformed.get('stage_verify', lambda t: t)('\n'.join(out) + '\n')

    def op_stage_receipt(self, args, stdin):
        self.receipt = stdin
        return 0, ''

    def op_transient(self, args, stdin):
        names = [f'instagram-install-{self.new}.service', f'instagram-stage-npm-{self.new}.service']
        if self.install_transient_polls:
            self.install_transient_polls -= 1
            if not self.install_transient_polls:
                self.transient.pop(names[0], None)
        return 0, self.show(names) + '@@ end\n'

    def op_verify_pair(self, args, stdin):
        if self.verify_pair_ok[args[0]]:
            return 0, 'instagram_vps_env_pair_ok\n'
        return 1, ''

    def op_guard(self, args, stdin):
        stack = args[0]
        fs = self.dynamic_fs()
        paths = [f'/run/instagram-{stack}/browser-request.json',
                 f'/var/lib/instagram-{stack}/profile/.instagram-manager.lock']
        out = ['@@ now', str(int(self.now)), '@@ stat', *[f'{p}|{"|".join(fs[p])}' for p in paths if p in fs],
               '@@ counts', f'waiter_{stack} {self.counts.get(f"waiter_{stack}", "0")}',
               f'session_procs_{stack} {self.session_procs(stack)}', '@@ end']
        return 0, '\n'.join(out) + '\n'

    def op_term(self, args, stdin):
        stack = args[0]
        name = f'instagram-vps-manager@{stack}.service'
        if self.term_rc:
            return self.term_rc, ''
        self.journal[stack] += [(self.now, line) for line in self.journal_on_term[stack]]
        if self.manager_exits[stack]:
            self.units[name].update(MainPID='0', ActiveState='activating', SubState='auto-restart', Result='exit-code')
            self.running.pop(name, None)
            self.counts.pop(f'waiter_{stack}', None)
        return 0, ''

    def op_units(self, args, stdin):
        return 0, self.malformed.get('units', lambda t: t)(self.show(args[0].split(',')) + '@@ end\n')

    def op_journal(self, args, stdin):
        stack, since = args[0], float(args[1].lstrip('@'))
        lines = [line for at, line in self.journal[stack] if at >= since]
        if self.journal_complete:
            lines.append('@@ end')
        return 0, ''.join(line + '\n' for line in lines)

    def op_stop(self, args, stdin):
        for name in args[0].split(','):
            unit = self.units[name]
            unit.update(ActiveState='inactive', SubState='dead', MainPID='0')
            self.running.pop(name, None)
            if name.startswith('instagram-vps-manager@'):
                self.counts.pop(f"waiter_{name.split('@')[1].split('.')[0]}", None)
        return 0, ''

    def op_install_run(self, args, stdin):
        name = f'instagram-install-{self.new}.service'
        if self.installer in ('ok', 'drop_ok'):
            self.put(f'/opt/instagram-meta/releases/{self.new}')
            self.current = f'/opt/instagram-meta/releases/{self.new}'
        if self.installer.startswith('drop'):
            self.transient[name] = {'Id': name, 'LoadState': 'loaded', 'ActiveState': 'active'}
            self.install_transient_polls = 3
            return 255, ''
        return (0, '') if self.installer == 'ok' else (1, '')

    def op_links(self, args, stdin):
        lines = [f'/opt/instagram-meta/current {self.current}']
        lines += [f'/opt/instagram-meta/current-{s} {self.links.get(s, "")}' for s in args[0].split(',')]
        return 0, self.malformed.get('links', lambda t: t)('\n'.join(lines) + '\n@@ end\n')

    def op_release_check(self, args, stdin):
        return 0, f'@@ rc\n{self.manifest_check_rc}\n@@ end\n'

    def op_start(self, args, stdin):
        for name in args[0].split(','):
            unit = self.units[name]
            if unit['Result'] == 'start-limit-hit':
                return 1, ''
            stack = name.split('@')[1].split('.')[0]
            behavior = self.start_behavior.get(name, 'ok')
            if behavior == 'fail':
                unit.update(ActiveState='failed', SubState='failed', Result='exit-code')
                return 1, ''
            self.activate(name, behavior)
            if name.startswith('instagram-vps-manager@'):
                self.journal[stack] += [(self.now, line) for line in self.journal_on_start[stack]]
                if stack in self.waiter_after_start:
                    self.counts[f'waiter_{stack}'] = '1'
        return 0, ''

    def op_ready_pair(self, args, stdin):
        stack = args[0]
        names = [f'instagram-vps-display@{stack}.service', f'instagram-vps-gateway@{stack}.service']
        fs = self.dynamic_fs()
        sock = f'/run/instagram-{stack}/vnc.sock'
        out = ['@@ units', self.show(names).rstrip('\n'), '', '@@ stat']
        if sock in fs:
            out.append(f'{sock}|{"|".join(fs[sock])}')
        out += self.http_lines(stack, '@@ http')
        out.append('@@ end')
        return 0, '\n'.join(out) + '\n'

    def http_lines(self, stack, header):
        gateway = self.units[f'instagram-vps-gateway@{stack}.service']
        if gateway['ActiveState'] != 'active':
            return [header, 'refused']
        status, cookie = self.http[stack]
        return [header, f'status={status} set_cookie={cookie}']

    def op_ready_publisher(self, args, stdin):
        stack = args[0]
        name = f'instagram-vps-publisher@{stack}.service'
        fs = self.dynamic_fs()
        sock = f'/run/instagram-publisher-{stack}/publisher.sock'
        probes = self.publisher_probes[stack]
        probe = probes.pop(0) if probes else 'publisher_ready'
        out = ['@@ units', self.show([name]).rstrip('\n'), '', '@@ stat']
        if sock in fs:
            out.append(f'{sock}|{"|".join(fs[sock])}')
        out += ['@@ probe', probe, '@@ end']
        return 0, '\n'.join(out) + '\n'

    def op_runtime(self, args, stdin):
        pids = dict(item.split('=') for item in args[1].split(',') if '=' in item)
        by_pid = {u['MainPID']: n for n, u in self.units.items()}
        out = ['@@ sha']
        for unit, pid in pids.items():
            out.append(f'{self.node_override.get(unit, tool.NODE_SHA256)}  /proc/{pid}/root/usr/bin/node')
        out.append('@@ cwd')
        for unit, pid in pids.items():
            name = by_pid.get(pid)
            out.append(f'{pid} /opt/instagram-meta/releases/{self.running.get(name, "unknown")}')
        out.append('@@ ss')
        for index, stack in enumerate(STACKS):
            if self.units[f'instagram-vps-gateway@{stack}.service']['ActiveState'] == 'active':
                out.append(f'LISTEN 0      511        127.0.0.1:{18441 + index}      0.0.0.0:*')
        fs = self.dynamic_fs()
        out.append('@@ stat')
        out += [f'{p}|{"|".join(v)}' for p, v in sorted(fs.items()) if v[0] == 'socket']
        for stack in STACKS:
            out += self.http_lines(stack, f'@@ http {stack}')
        out.append('@@ counts')
        out += [f'waiter_{s} {self.counts.get(f"waiter_{s}", "0")}' for s in STACKS]
        out.append('@@ end')
        return 0, self.malformed.get('runtime', lambda t: t)('\n'.join(out) + '\n')

    def op_cas(self, args, stdin):
        prev, new = args
        target = f'/opt/instagram-meta/releases/{new}'
        if self.current != target or prev in self.links:
            return 1, ''
        self.current = f'/opt/instagram-meta/releases/{prev}'
        return 0, ''

    def op_cas_finish(self, args, stdin):
        prev, new = args
        if self.current != f'/opt/instagram-meta/releases/{new}' or \
                self.links.get(prev) != f'/opt/instagram-meta/releases/{prev}':
            return 1, ''
        self.current = self.links.pop(prev)
        return 0, ''

    def op_reset_failed(self, args, stdin):
        for unit in self.units.values():
            if unit['Result'] == 'start-limit-hit' or unit['ActiveState'] == 'failed':
                unit.update(Result='success', ActiveState='inactive', SubState='dead')
        return 0, ''


class Harness(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo, self.prev, self.new, self.templates = build_repo(Path(self.temporary.name))
        self.vps = FakeVPS(self.prev, self.new, self.templates)
        for name, value in (('NODE_DROPIN_SHA256', sha(DROPIN_BYTES)), ('CPU_OVERRIDE_SHA256', sha(CPU_BYTES))):
            patcher = mock.patch.object(tool, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.vps.hashes.update({tool.node_dropin(r): sha(DROPIN_BYTES) for r in ('gateway', 'publisher', 'manager')})
        self.vps.hashes.update({tool.cpu_override(s): sha(CPU_BYTES) for s in STACKS})

    def run_tool(self, *argv, runner=None):
        out, err = io.StringIO(), io.StringIO()
        code = tool.main(list(argv), runner=self.vps if runner is None else runner, repo=self.repo,
                         out=out, err=err, clock=self.vps.clock, sleep=self.vps.sleep)
        self.outputs = (out.getvalue(), err.getvalue())
        return code, out.getvalue(), err.getvalue()

    def ops(self, start=0):
        return [c.partition(';')[0].split()[2] for c, _ in self.vps.calls[start:]]

    def commands(self, start=0):
        return [c for c, _ in self.vps.calls[start:]]

    def backup(self):
        code, out, _ = self.run_tool('backup', '--sha', self.new, '--from', self.prev)
        self.assertEqual(code, 0, out)
        return next(word.partition('=')[2] for line in out.splitlines() for word in line.split()
                    if word.startswith('path='))

    def stage(self):
        code, out, _ = self.run_tool('stage', '--sha', self.new, '--from', self.prev)
        self.assertEqual(code, 0, out)
        return next(word.partition('=')[2] for line in out.splitlines() for word in line.split()
                    if word.startswith('modules_digest='))

    def install(self, *extra, backup=None, digest=MODULES_DIGEST):
        backup = backup or self.backup()
        if not self.vps.stage_exists:
            self.stage()
        self.mark = len(self.vps.calls)
        return self.run_tool('install', '--sha', self.new, '--from', self.prev, '--backup', backup,
                             '--modules-digest', digest, *extra)

    def assertNoMutation(self, start):
        mutating = {'term', 'stop', 'start', 'install_run', 'cas', 'cas_finish', 'reset_failed'}
        self.assertFalse(mutating & set(self.ops(start)), self.ops(start))


class StaticContractTests(unittest.TestCase):
    def test_ssh_options_are_strict_and_exact(self):
        argv = tool.ssh_argv(': vps_release snapshot;')
        self.assertEqual(argv[:1], ['/usr/bin/ssh'])
        self.assertEqual(argv[-2:], ['n8n', ': vps_release snapshot;'])
        options = argv[1:-2]
        self.assertEqual(options, ['-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                                   '-o', 'HostKeyAlgorithms=ssh-ed25519', '-o', 'ForwardAgent=no',
                                   '-o', 'UpdateHostKeys=no', '-o', 'ConnectTimeout=8', '-o', 'ControlMaster=no',
                                   '-o', 'ControlPath=none', '-o', 'ClearAllForwardings=yes'])
        joined = ' '.join(argv)
        for bad in ('StrictHostKeyChecking=no', 'accept-new', 'UserKnownHostsFile', ' -A '):
            self.assertNotIn(bad, joined)

    def test_tool_never_uses_regular_expressions(self):
        tree = ast.parse(TOOL_PATH.read_text())
        imported = {alias.name for node in ast.walk(tree) if isinstance(node, (ast.Import, ast.ImportFrom))
                    for alias in node.names} | {node.module for node in ast.walk(tree)
                                                if isinstance(node, ast.ImportFrom)}
        self.assertNotIn('re', imported)
        self.assertNotIn('fnmatch', imported)

    def test_allowed_top_level_matches_installer_literal(self):
        tree = ast.parse(INSTALL_PATH.read_text())
        found = None
        for node in ast.walk(tree):
            if isinstance(node, ast.Compare) and isinstance(node.ops[0], ast.LtE) and \
                    isinstance(node.comparators[0], ast.Set):
                found = {elt.value for elt in node.comparators[0].elts if isinstance(elt, ast.Constant)}
        self.assertIsNotNone(found)
        self.assertEqual(set(tool.BASE_TOP) | set(PUBLISHER_MODULES) | {'node_modules'},
                         found | set(PUBLISHER_MODULES))
        self.assertNotIn('release', tool.BASE_TOP)

    def test_constants_match_audited_facts(self):
        self.assertEqual(tool.DEFAULT_FROM, '61f20cfd107361a431fda51f02cace751cc4978d')
        self.assertEqual(tool.NODE, '/opt/instagram-meta-tools/node-v24.21.0-linux-x64/bin/node')
        self.assertEqual(tool.NODE_SHA256, '7fde7b8afa198da66257f42ee2001d874c7355631e6d1579a5fb5ef1f246df4c')
        self.assertEqual(tool.NODE_DROPIN_SHA256, '21296e432301fe7634c65c399c24c692799745466e0e7ce1e829775c112ec1ba')
        self.assertEqual(tool.CPU_OVERRIDE_SHA256, '41c6db5c35846b239a0da96950bc1e599703b0b1aabbb274a6f99f95d168ea43')

    def test_cli_rejects_bad_sha_and_missing_backup_without_calls(self):
        calls = []

        def runner(*args, **kwargs):
            calls.append(args)
            return 0, ''
        for argv in (['preflight', '--sha', 'ABC'], ['install', '--sha', 'a' * 40, '--modules-digest', 'd' * 64],
                     ['preflight', '--sha', 'g' * 40], ['rollback', '--to', 'a' * 40]):
            with self.subTest(argv=argv), contextlib.redirect_stderr(io.StringIO()):
                code = tool.main(argv, runner=runner, repo=ROOT, out=io.StringIO(), err=io.StringIO())
                self.assertEqual(code, 2)
        self.assertEqual(calls, [])

    def test_ssh_runner_never_inherits_the_operator_terminal(self):
        result = subprocess.CompletedProcess([], 0, b'ok', b'')
        with mock.patch.object(tool.subprocess, 'run', return_value=result) as run:
            self.assertEqual(tool.ssh_runner(': vps_release snapshot;'), (0, 'ok'))
            self.assertIs(run.call_args.kwargs['stdin'], subprocess.DEVNULL)
            self.assertNotIn('input', run.call_args.kwargs)
            tool.ssh_runner(': vps_release backup_write x;', stdin=b'{}')
            self.assertEqual(run.call_args.kwargs['input'], b'{}')
            self.assertNotIn('stdin', run.call_args.kwargs)


def collapsed(ops):
    # Polls repeat a read; the plan lists it once.
    return [op for index, op in enumerate(ops) if index == 0 or ops[index - 1] != op]


def planned_ops(out):
    # (op, optional): optional steps depend on remote state and may be absent from a real run.
    plan = []
    for line in out.splitlines():
        prefix = next((p for p in (tool.OPTIONAL_STAGE, tool.OPTIONAL_NOOP) if line.startswith(p)), '')
        optional, command = bool(prefix), line.removeprefix(prefix)
        if command.startswith(': vps_release '):
            plan.append((command.partition(';')[0].split()[2], optional))
    return plan


def plan_variants(plan):
    optional = [index for index, (_, is_optional) in enumerate(plan) if is_optional]
    for mask in range(2 ** len(optional)):
        dropped = {index for bit, index in enumerate(optional) if mask >> bit & 1}
        yield collapsed([op for index, (op, _) in enumerate(plan) if index not in dropped])


class DryRunTests(Harness):
    def test_every_subcommand_dry_run_makes_no_remote_call_and_prints_commands(self):
        backup = '/tmp/instagram-vps_state_20261009T120000Z.json'
        cases = {
            'preflight': ['--sha', self.new, '--from', self.prev],
            'backup': ['--sha', self.new, '--from', self.prev],
            'stage': ['--sha', self.new, '--from', self.prev],
            'install': ['--sha', self.new, '--from', self.prev, '--backup', backup, '--modules-digest', MODULES_DIGEST],
            'verify': ['--sha', self.new, '--backup', backup],
            'rollback': ['--to', self.prev, '--from', self.new, '--backup', backup],
        }
        before = set(Path(self.temporary.name).rglob('*'))
        for name, args in cases.items():
            with self.subTest(name=name):
                code, out, _ = self.run_tool('--dry-run', name, *args)
                self.assertEqual(code, 0, out)
                self.assertEqual(self.vps.calls, [])
                self.assertIn(': vps_release ', out)
        self.assertEqual(before, set(Path(self.temporary.name).rglob('*')))
        _, out, _ = self.run_tool('--dry-run', 'install', *cases['install'])
        self.assertIn(tool.installer_command(self.new), out)
        self.assertLess(out.index('vps_release term hub2you'), out.index('vps_release install_run'))
        _, out, _ = self.run_tool('--dry-run', 'rollback', *cases['rollback'])
        self.assertIn('mv -T', out)

    def test_dry_run_plan_matches_the_real_run(self):
        backup = self.backup()
        self.stage()
        common = ['--sha', self.new, '--from', self.prev, '--backup', backup]
        flows = (('install', [*common, '--modules-digest', MODULES_DIGEST]),
                 ('verify', ['--sha', self.new, '--backup', backup]),
                 ('rollback', ['--to', self.prev, '--from', self.new, '--backup', backup]))
        for name, args in flows:
            with self.subTest(flow=name):
                _, out, _ = self.run_tool('--dry-run', name, *args)
                mark = len(self.vps.calls)
                code, real, _ = self.run_tool(name, *args)
                self.assertEqual(code, 0, real)
                self.assertIn(collapsed(self.ops(mark)), list(plan_variants(planned_ops(out))))

    def test_every_remote_command_parses_as_shell(self):
        bash = shutil.which('bash')
        if not bash:
            self.skipTest('bash not available')
        backup = self.backup()
        self.stage()
        self.run_tool('install', '--sha', self.new, '--from', self.prev, '--backup', backup,
                      '--modules-digest', MODULES_DIGEST)
        self.run_tool('rollback', '--to', self.prev, '--from', self.new, '--backup', backup)
        for command in sorted(set(self.commands())):
            with self.subTest(command=command[:60]):
                result = subprocess.run([bash, '-n', '-c', command], capture_output=True, check=False)
                self.assertEqual(result.returncode, 0, command)


class PreflightTests(Harness):
    def test_happy_path_is_read_only(self):
        code, out, _ = self.run_tool('preflight', '--sha', self.new, '--from', self.prev)
        self.assertEqual(code, 0, out)
        self.assertIn('vps_release_preflight_ok', out)
        self.assertNoMutation(0)
        self.assertEqual(set(self.ops()), {'snapshot'})

    def test_each_precondition_mismatch_exits_2_without_mutation(self):
        def unit(name, **values):
            return lambda v: v.units[name].update(values)

        def fs(path, index=None, value=None, delete=False):
            def change(v):
                if delete:
                    v.fs.pop(path)
                else:
                    v.fs[path][index] = value
            return change
        cases = {
            'hostname': lambda v: setattr(v, 'hostname', 'other'),
            'uid': lambda v: setattr(v, 'uid', '1000'),
            'current': lambda v: setattr(v, 'current', '/opt/instagram-meta/releases/' + 'f' * 40),
            'enabled': unit('instagram-vps-gateway@hub2you.service', UnitFileState='enabled'),
            'not_found': unit('instagram-vps-display@autonomia.service', LoadState='not-found'),
            'override_missing': unit('instagram-vps-publisher@hub2you.service',
                                     DropInPaths=tool.node_dropin('publisher')),
            'extra_dropin': unit('instagram-vps-display@hub2you.service', DropInPaths='/etc/x.conf'),
            'quota': unit('instagram-vps-publisher@autonomia.service', CPUQuotaPerSecUSec='500ms'),
            'override_hash': lambda v: v.hashes.__setitem__(tool.cpu_override('hub2you'), '0' * 64),
            'node_hash': lambda v: v.hashes.__setitem__(tool.NODE, '0' * 64),
            'dropin_hash': lambda v: v.hashes.__setitem__(tool.node_dropin('manager'), '0' * 64),
            'node_version': lambda v: setattr(v, 'node_version', 'v18.19.1'),
            'etc_template': lambda v: v.hashes.__setitem__(
                '/etc/systemd/system/instagram-vps-publisher@.service', '0' * 64),
            'release_exists': lambda v: v.put(f'/opt/instagram-meta/releases/{v.new}'),
            'tmp_link_exists': lambda v: v.links.__setitem__(v.new, '/x'),
            'transient_busy': lambda v: v.transient.__setitem__(
                f'instagram-install-{v.new}.service', {'Id': 'x', 'LoadState': 'loaded', 'ActiveState': 'active'}),
            'staging_writable': fs('/opt/instagram-meta-staging', 3, '775'),
            'bin_missing': lambda v: v.execs.discard('/usr/bin/systemd-run'),
            'aws_missing': lambda v: v.execs.discard('/usr/bin/aws'),
            'marker': lambda v: v.put('/run/instagram-hub2you/browser-request.json', 'regular file', 'ig-hub2you',
                                      'igview-hub2you', '640', '10'),
            'waiter': lambda v: v.counts.__setitem__('waiter_autonomia', '1'),
            'xauthority_mode': fs('/var/lib/instagram-hub2you/.Xauthority', 3, '644'),
            'legacy_dir': lambda v: v.put('/var/lib/instagram-autonomia/publisher'),
            'home_owner': fs('/var/lib/instagram-gateway-hub2you/gateway', 1, 'root'),
            'gateway_url': lambda v: v.counts.__setitem__('url_hub2you', '0'),
            'disk': lambda v: setattr(v, 'df', 10),
            'xvnc_flags': lambda v: v.counts.__setitem__('xvnc_rfbunixpath', '0'),
            'etc_meta_writable': fs('/etc/instagram-meta', 3, '722'),
            'start_unparseable': unit('instagram-vps-manager@autonomia.service',
                                      ExecMainStartTimestamp='Thu 2026-10-09 12:00:00 UTC'),
            'systemd_old': lambda v: v.counts.__setitem__('systemd', '249'),
            'lock_with_inactive_manager': lambda v: (
                v.units['instagram-vps-manager@hub2you.service'].update(ActiveState='inactive', MainPID='0'),
                v.lock_left.add('hub2you')),
        }
        for name, change in cases.items():
            with self.subTest(name=name):
                self.vps = FakeVPS(self.prev, self.new, self.templates)
                self.vps.hashes.update({tool.node_dropin(r): sha(DROPIN_BYTES)
                                        for r in ('gateway', 'publisher', 'manager')})
                self.vps.hashes.update({tool.cpu_override(s): sha(CPU_BYTES) for s in STACKS})
                change(self.vps)
                code, out, _ = self.run_tool('preflight', '--sha', self.new, '--from', self.prev)
                self.assertEqual(code, 2, out)
                self.assertIn('FAIL ', out)
                self.assertNoMutation(0)

    def test_git_preconditions(self):
        other = git(self.repo, 'rev-parse', 'HEAD~1')
        code, out, _ = self.run_tool('preflight', '--sha', other, '--from', self.new)
        self.assertEqual(code, 2)
        self.assertIn('FAIL git_no_downgrade', out)
        self.assertEqual(self.vps.calls, [])
        git(self.repo, 'update-ref', 'refs/remotes/origin/main', self.prev)
        code, out, _ = self.run_tool('preflight', '--sha', self.new, '--from', self.prev)
        self.assertEqual(code, 2)
        self.assertIn('FAIL git_target_in_origin_main', out)


class BackupTests(Harness):
    def test_backup_writes_noclobber_json_without_env(self):
        path = self.backup()
        self.assertTrue(path.startswith('/tmp/instagram-vps_state_') and path.endswith('Z.json'))
        command = next(c for c, _ in self.vps.calls if ' backup_write ' in c)
        self.assertIn('umask 077', command)
        self.assertIn('set -C', command)
        data = json.loads(self.vps.backups[path])
        for key in ('schema', 'utc', 'hostname', 'target_sha', 'from_sha', 'current_target', 'units',
                    'hashes', 'files', 'flags', 'active'):
            self.assertIn(key, data)
        self.assertEqual(data['current_target'], f'/opt/instagram-meta/releases/{self.prev}')
        self.assertEqual(base64.b64decode(data['files'][tool.cpu_override('hub2you')]), CPU_BYTES)
        self.assertNotIn('INSTAGRAM_TESTER', json.dumps(data))
        self.assertEqual(sorted(data['active']['hub2you']), sorted(ROLES))

    def test_existing_backup_file_is_never_overwritten(self):
        self.vps.op_backup_write = lambda args, stdin: (1, '')
        code, out, _ = self.run_tool('backup', '--sha', self.new, '--from', self.prev)
        self.assertEqual(code, 2, out)
        self.assertIn('backup_write', out)


class StageTests(Harness):
    def artifact(self):
        return self.vps.uploads['artifact.tar']

    def test_artifact_is_exactly_the_git_selection(self):
        self.stage()
        with tarfile.open(fileobj=io.BytesIO(self.artifact())) as archive:
            members = {m.name: m for m in archive.getmembers()}
            files = {name for name, m in members.items() if m.isfile()}
            for m in members.values():
                self.assertTrue(m.isfile() or m.isdir())
                self.assertEqual(m.mode & 0o022, 0)
            gateway = archive.extractfile(f'{VPS_REL}/gateway.mjs').read()
        expected = {f'scripts/instagram_testers/{s}' for s in SCRIPTS}
        expected |= {n for n in git(self.repo, 'ls-files', VPS_REL).splitlines() if '/release/' not in n}
        self.assertEqual(files, expected)
        self.assertNotIn(b'dirty working tree', gateway)
        self.assertFalse(any('node_modules' in n or '/release/' in n for n in files))
        manifest = self.vps.uploads['manifest.sha256'].decode().splitlines()
        self.assertEqual(len(manifest), len(expected))
        with tarfile.open(fileobj=io.BytesIO(self.artifact())) as archive:
            for line in manifest:
                digest, _, path = line.partition('  ')
                self.assertEqual(sha(archive.extractfile(path.removeprefix('./')).read()), digest)
        self.assertEqual(json.loads(self.vps.receipt)['modules_digest'], MODULES_DIGEST)

    def test_npm_runs_on_linux_with_private_node_and_isolation(self):
        self.stage()
        npm = next(c for c, _ in self.vps.calls if ' stage_npm ' in c)
        for needle in ('umask 077', 'systemd-run --wait --collect --pipe --quiet', f'--unit=instagram-stage-npm-{self.new}',
                       '--property=PrivateTmp=yes', '--setenv=HOME=/tmp', 'npm_config_userconfig=/tmp/npmrc-absent',
                       tool.NODE, tool.NPM_CLI, 'ci --ignore-scripts --no-audit --no-fund', 'RuntimeMaxSec=900'):
            self.assertIn(needle, npm)
        scan = next(c for c, _ in self.vps.calls if ' stage_verify ' in c)
        for needle in ("-name '.env*'", '-name credentials', '-name id_ed25519', '-name profile', '! -type f ! -type d',
                       '-perm /022', '! -user root', '-type l', "-name .bin -prune"):
            self.assertIn(needle, scan)

    def test_stage_failures(self):
        cases = {
            'stage_exists': (lambda v: setattr(v, 'stage_exists', True), 2),
            'tar_mismatch': (lambda v: v.malformed.__setitem__('tar', True), 3),
            'dep_version': (lambda v: v.deps.__setitem__('ws', '8.0.0'), 3),
            'scan': (lambda v: setattr(v, 'scan_count', '1'), 3),
            'manifest_check': (lambda v: setattr(v, 'manifest_check_rc', '1'), 3),
        }
        for name, (change, expected) in cases.items():
            with self.subTest(name=name):
                self.vps = FakeVPS(self.prev, self.new, self.templates)
                self.vps.hashes.update({tool.node_dropin(r): sha(DROPIN_BYTES)
                                        for r in ('gateway', 'publisher', 'manager')})
                self.vps.hashes.update({tool.cpu_override(s): sha(CPU_BYTES) for s in STACKS})
                change(self.vps)
                code, out, _ = self.run_tool('stage', '--sha', self.new, '--from', self.prev)
                self.assertEqual(code, expected, out)
                self.assertNoMutation(0)
                self.assertFalse(any(' rm ' in c for c in self.commands()))

    def test_unknown_top_level_and_symlink_abort_locally(self):
        for kind in ('unknown', 'symlink'):
            with self.subTest(kind=kind):
                path = self.repo / VPS_REL / ('extra.mjs' if kind == 'unknown' else 'web/link.js')
                if kind == 'unknown':
                    path.write_text('x')
                else:
                    path.symlink_to('console.js')
                git(self.repo, 'add', '-A')
                git(self.repo, 'commit', '-q', '-m', kind)
                head = git(self.repo, 'rev-parse', 'HEAD')
                git(self.repo, 'update-ref', 'refs/remotes/origin/main', head)
                self.vps.calls.clear()
                code, out, _ = self.run_tool('stage', '--sha', head, '--from', self.prev)
                self.assertEqual(code, 2, out)
                self.assertEqual(self.vps.calls, [])
                git(self.repo, 'rm', '-q', str(path.relative_to(self.repo)))
                git(self.repo, 'commit', '-q', '-m', 'undo')


class InstallTests(Harness):
    def test_happy_path_order(self):
        code, out, _ = self.install()
        self.assertEqual(code, 0, out)
        self.assertIn('vps_release_install_ok', out)
        commands = self.commands(self.mark)
        ops = self.ops(self.mark)
        term = ops.index('term')
        first_stop = ops.index('stop')
        self.assertLess(term, first_stop)
        self.assertIn('systemctl kill --kill-whom=main --signal=SIGTERM instagram-vps-manager@hub2you.service',
                      commands[term])
        install = ops.index('install_run')
        self.assertIn(tool.installer_command(self.new), commands[install])
        starts = [c.partition(';')[0].split()[3] for c in commands if c.partition(';')[0].split()[2] == 'start']
        self.assertEqual(starts, [
            'instagram-vps-display@hub2you.service,instagram-vps-gateway@hub2you.service',
            'instagram-vps-publisher@hub2you.service', 'instagram-vps-manager@hub2you.service',
            'instagram-vps-display@autonomia.service,instagram-vps-gateway@autonomia.service',
            'instagram-vps-publisher@autonomia.service', 'instagram-vps-manager@autonomia.service'])
        self.assertLess(ops.index('verify_pair'), term)
        self.assertEqual(self.vps.current, f'/opt/instagram-meta/releases/{self.new}')
        self.assertFalse(any('SIGKILL' in c or 'reset-failed' in c for c in commands))

    def test_aborts_before_any_stop(self):
        backup = self.backup()
        self.stage()

        def manager_env_newer(v):
            v.fs['/etc/instagram-meta/hub2you/manager.env'][5] = str(int(v.now) + 10)
        cases = {
            'flag_without_confirmation': ([], lambda v: v.counts.__setitem__('flag_hub2you', '1')),
            'env_newer_than_process': ([], manager_env_newer),
            'marker': ([], lambda v: v.put('/run/instagram-autonomia/browser-request.json', 'regular file')),
            'waiter': ([], lambda v: v.counts.__setitem__('waiter_hub2you', '1')),
            'manifest_tampered': ([], lambda v: v.uploads.__setitem__('manifest.sha256', b'x')),
            'digest_mismatch': (['--modules-digest', 'e' * 64], lambda v: None),
            'verify_pair_new': ([], lambda v: v.verify_pair_ok.__setitem__('stage', False)),
            'host_check': ([], lambda v: v.execs.discard('/usr/bin/google-chrome')),
            'backup_divergent': ([], lambda v: v.units['instagram-vps-manager@autonomia.service'].update(
                ActiveState='inactive', MainPID='0')),
        }
        saved = (dict(self.vps.uploads), dict(self.vps.counts))
        for name, (extra, change) in cases.items():
            with self.subTest(name=name):
                self.vps.uploads, self.vps.counts = dict(saved[0]), dict(saved[1])
                snapshot = json.loads(json.dumps(self.vps.units))
                fs = json.loads(json.dumps(self.vps.fs))
                change(self.vps)
                start = len(self.vps.calls)
                args = ['install', '--sha', self.new, '--from', self.prev, '--backup', backup,
                        '--modules-digest', MODULES_DIGEST]
                if extra:
                    args[-1] = extra[1]
                code, out, _ = self.run_tool(*args)
                self.assertEqual(code, 2, out)
                self.assertNoMutation(start)
                self.vps.units, self.vps.fs = snapshot, fs
                self.vps.verify_pair_ok['stage'] = True
                self.vps.execs.add('/usr/bin/google-chrome')
                self.vps.fs.pop('/run/instagram-autonomia/browser-request.json', None)

    def test_flag_with_confirmation_proceeds(self):
        self.vps.counts['flag_hub2you'] = '1'
        code, out, _ = self.install('--queue-idle-confirmed', 'hub2you')
        self.assertEqual(code, 0, out)

    def rollback_line(self, _out=None):
        return f'rollback --to {self.prev} --from {self.new} --backup /tmp/instagram-vps_state_'

    def assertFailedAfterChange(self, code, out, current_new, rollback=True):
        self.assertEqual(code, 3, out)
        if rollback:
            self.assertIn(self.rollback_line(out), out)
        else:
            self.assertNotIn(self.rollback_line(out), out)
        commands = self.commands(self.mark)
        self.assertFalse(any('SIGKILL' in c or '.instagram-manager.lock' in c and ('mv ' in c or 'rm ' in c)
                             for c in commands))
        expected = self.new if current_new else self.prev
        self.assertEqual(self.vps.current, f'/opt/instagram-meta/releases/{expected}')

    def test_post_mutation_failures(self):
        cases = {
            'manager_never_exits': (lambda v: v.manager_exits.__setitem__('hub2you', False), False, 'manager_stop_timeout'),
            'lock_left': (lambda v: v.lock_left.add('hub2you'), False, 'manager_lock_present'),
            'claim_in_flight': (lambda v: v.journal_on_term.__setitem__('hub2you', [json.dumps({
                'event': 'instagram_browser_operation_lifecycle', 'phase': 'claim_requested',
                'request_present': True, 'claim_received': False, 'complete_received': False})]), False,
                'operation_outcome_uncertain'),
            'executor_failed': (lambda v: v.journal_on_term.__setitem__('autonomia', [json.dumps({
                'event': 'instagram_browser_operation_executor_failed', 'phase': 'invite_execution'})]), False,
                'operation_outcome_uncertain'),
            'manager_failed_line': (lambda v: v.journal_on_term.__setitem__('hub2you', ['instagram_manager_failed']),
                                    False, 'operation_outcome_uncertain'),
            'journal_incomplete': (lambda v: setattr(v, 'journal_complete', False), False,
                                   'operation_outcome_uncertain'),
            'installer_rc': (lambda v: setattr(v, 'installer', 'fail'), False, 'installer_failed'),
            'installer_drop_prev': (lambda v: setattr(v, 'installer', 'drop_fail'), False, 'installer_failed'),
            'verify_pair_after': (lambda v: v.verify_pair_ok.__setitem__('current', False), True, 'verify_pair'),
            'release_manifest': (lambda v: None, True, 'release_manifest'),
            'gateway_403': (lambda v: v.http.__setitem__('hub2you', ('403', '0')), True, 'gateway_not_ready'),
            'set_cookie': (lambda v: v.http.__setitem__('autonomia', ('401', '1')), True, 'gateway_not_ready'),
            'publisher_never_ready': (lambda v: v.publisher_probes.__setitem__('hub2you', ['publisher_closed'] * 500),
                                      True, 'publisher_not_ready'),
            'gateway_crashloop': (lambda v: v.start_behavior.__setitem__(
                'instagram-vps-gateway@autonomia.service', 'crashloop'), True, 'gateway_not_ready'),
            'start_limit': (lambda v: None, True, 'start_limit_hit'),
        }
        for name, (change, current_new, token) in cases.items():
            with self.subTest(name=name):
                self.vps = FakeVPS(self.prev, self.new, self.templates)
                self.vps.hashes.update({tool.node_dropin(r): sha(DROPIN_BYTES)
                                        for r in ('gateway', 'publisher', 'manager')})
                self.vps.hashes.update({tool.cpu_override(s): sha(CPU_BYTES) for s in STACKS})
                backup = self.backup()
                self.stage()
                change(self.vps)
                if name == 'release_manifest':
                    self.vps.op_release_check = lambda a, s: (0, '@@ rc\n1\n@@ end\n')
                if name == 'start_limit':
                    original_install = self.vps.op_install_run

                    def install_then_limit(a, s, original_install=original_install):
                        result = original_install(a, s)
                        self.vps.units['instagram-vps-manager@hub2you.service']['Result'] = 'start-limit-hit'
                        return result
                    self.vps.op_install_run = install_then_limit
                code, out, _ = self.install(backup=backup)
                self.assertFailedAfterChange(code, out, current_new)
                self.assertIn(token, out)
                self.assertNotIn(CANARY, out + self.outputs[1])
                if name == 'manager_never_exits':
                    self.assertIn('sigterm_entregue', out)
                    self.assertNotIn('verify --sha', out)
                if name == 'gateway_crashloop':
                    stops = [c for c in self.commands(self.mark) if ' stop instagram-vps-display@autonomia' in c]
                    self.assertTrue(stops)

    def test_term_not_delivered_changes_nothing(self):
        self.vps.term_rc = 1
        code, out, _ = self.install()
        self.assertEqual(code, 2, out)
        self.assertIn('manager_term_failed', out)
        self.assertIn('nada_mudou', out)
        self.assertFalse({'stop', 'install_run', 'start'} & set(self.ops(self.mark)))
        self.assertEqual(self.vps.units['instagram-vps-manager@hub2you.service']['ActiveState'], 'active')

    def test_installer_connection_drop_then_success_is_resolved_by_current(self):
        self.vps.installer = 'drop_ok'
        code, out, _ = self.install()
        self.assertEqual(code, 0, out)
        self.assertIn('transient', self.ops(self.mark))

    def test_inactive_manager_in_backup_is_not_started(self):
        self.vps.units['instagram-vps-manager@autonomia.service'].update(ActiveState='inactive', MainPID='0',
                                                                         SubState='dead')
        code, out, _ = self.install()
        self.assertEqual(code, 0, out)
        self.assertFalse(any('start instagram-vps-manager@autonomia' in c for c in self.commands(self.mark)))
        self.assertEqual(self.vps.units['instagram-vps-manager@autonomia.service']['ActiveState'], 'inactive')

    def test_operator_required_after_install_prints_rollback_and_exits_4(self):
        self.vps.journal_on_start['hub2you'] = ['instagram_session_operator_required']
        code, out, _ = self.install()
        self.assertEqual(code, 4, out)
        self.assertIn(self.rollback_line(out), out)
        self.assertIn('prev_saudavel_no_backup', out)


class VerifyTests(Harness):
    def setUp(self):
        super().setUp()
        self.path = self.backup()

    def verify(self):
        return self.run_tool('verify', '--sha', self.prev, '--backup', self.path)

    def test_healthy_state_passes(self):
        code, out, _ = self.verify()
        self.assertEqual(code, 0, out)
        self.assertIn('vps_release_verify_ok', out)
        self.assertNoMutation(0)

    def test_unhealthy_states_fail(self):
        cases = {
            'restarts': lambda v: v.units['instagram-vps-gateway@hub2you.service'].update(NRestarts='1'),
            'quota': lambda v: v.units['instagram-vps-publisher@hub2you.service'].update(CPUQuotaPerSecUSec='500ms'),
            'override': lambda v: v.hashes.__setitem__(tool.cpu_override('autonomia'), '0' * 64),
            'node': lambda v: v.node_override.__setitem__('instagram-vps-publisher@autonomia.service', '0' * 64),
            'enabled': lambda v: v.units['instagram-vps-manager@hub2you.service'].update(UnitFileState='enabled'),
            'token': lambda v: v.journal['hub2you'].append((v.now, 'instagram_session_session_update_rejected')),
            'release': lambda v: v.running.__setitem__('instagram-vps-gateway@autonomia.service', 'f' * 40),
            'listener': lambda v: v.http.__setitem__('hub2you', ('200', '0')),
        }
        base_units = json.loads(json.dumps(self.vps.units))
        for name, change in cases.items():
            with self.subTest(name=name):
                self.vps.units = json.loads(json.dumps(base_units))
                self.vps.hashes[tool.cpu_override('autonomia')] = sha(CPU_BYTES)
                self.vps.node_override.clear()
                self.vps.journal['hub2you'].clear()
                self.vps.http['hub2you'] = ('401', '0')
                for unit, values in self.vps.units.items():
                    if values['MainPID'] != '0':
                        self.vps.running[unit] = self.prev
                change(self.vps)
                code, out, _ = self.verify()
                self.assertEqual(code, 3, out)
                self.assertIn('FAIL ', out)

    def test_unreadable_manager_start_fails_instead_of_skipping_bootstrap(self):
        manager = self.vps.units['instagram-vps-manager@hub2you.service']
        manager['ExecMainStartTimestamp'] = 'Thu 2026-10-09 12:00:00 UTC'
        self.vps.journal['hub2you'].append((self.vps.now - 5, 'instagram_manager_failed'))
        code, out, _ = self.verify()
        self.assertEqual(code, 3, out)
        self.assertIn('FAIL manager_start_known:hub2you', out)

    def test_incomplete_journal_read_fails(self):
        self.vps.journal_complete = False
        code, out, _ = self.verify()
        self.assertEqual(code, 3, out)
        self.assertIn('FAIL journal_read_complete:hub2you', out)

    def test_operator_required_is_code_4(self):
        self.vps.journal['autonomia'].append((self.vps.now, 'instagram_manager_operator_required'))
        code, out, _ = self.verify()
        self.assertEqual(code, 4, out)
        self.assertIn('rollback_nao_resolve', out)


class RollbackTests(Harness):
    def installed(self):
        self.path = self.backup()
        self.stage()
        code, out, _ = self.run_tool('install', '--sha', self.new, '--from', self.prev, '--backup', self.path,
                                     '--modules-digest', MODULES_DIGEST)
        self.assertEqual(code, 0, out)
        self.mark = len(self.vps.calls)

    def rollback(self, *extra):
        return self.run_tool('rollback', '--to', self.prev, '--from', self.new, '--backup', self.path, *extra)

    def test_cas_after_stop_and_restart_in_order(self):
        self.installed()
        code, out, _ = self.rollback()
        self.assertEqual(code, 0, out)
        self.assertEqual(self.vps.current, f'/opt/instagram-meta/releases/{self.prev}')
        ops = self.ops(self.mark)
        commands = self.commands(self.mark)
        cas = ops.index('cas')
        self.assertLess(ops.index('stop'), ops.index('reset_failed'))
        self.assertLess(ops.index('reset_failed'), cas)
        self.assertLess(cas, ops.index('start'))
        self.assertIn('ln -s', commands[cas])
        self.assertIn('mv -T', commands[cas])
        reset = commands[ops.index('reset_failed')]
        self.assertIn('systemctl reset-failed ' + ' '.join(UNITS), reset)
        self.assertTrue(self.vps.fs.get(f'/opt/instagram-meta/releases/{self.new}'))
        self.assertFalse(any(' rm ' in c or 'unlink' in c for c in commands))

    def test_crash_looping_new_manager_still_rolls_back(self):
        self.installed()
        self.vps.units['instagram-vps-manager@hub2you.service'].update(
            ActiveState='failed', SubState='failed', MainPID='0', Result='start-limit-hit')
        code, out, _ = self.rollback()
        self.assertEqual(code, 0, out)
        self.assertEqual(self.vps.units['instagram-vps-manager@hub2you.service']['ActiveState'], 'active')

    def test_refusals_before_stop(self):
        self.installed()
        cases = {
            'current_elsewhere': lambda v: setattr(v, 'current', '/opt/instagram-meta/releases/' + 'c' * 40),
            'prev_missing': lambda v: v.fs.pop(f'/opt/instagram-meta/releases/{v.prev}'),
            'templates_differ': lambda v: v.hashes.__setitem__(
                '/etc/systemd/system/instagram-vps-display@.service', '0' * 64),
            'installer_running': lambda v: v.transient.__setitem__(
                f'instagram-install-{v.new}.service', {'Id': 'x', 'LoadState': 'loaded', 'ActiveState': 'active'}),
            'tmp_link_elsewhere': lambda v: v.links.__setitem__(v.prev, '/opt/instagram-meta/releases/' + 'c' * 40),
            'marker': lambda v: v.put('/run/instagram-hub2you/browser-request.json', 'regular file'),
            'lock_inactive_manager': lambda v: (
                v.units['instagram-vps-manager@autonomia.service'].update(ActiveState='inactive', MainPID='0'),
                v.lock_left.add('autonomia')),
        }
        base = (self.vps.current, json.loads(json.dumps(self.vps.units)), json.loads(json.dumps(self.vps.fs)),
                dict(self.vps.hashes))
        for name, change in cases.items():
            with self.subTest(name=name):
                self.vps.current = base[0]
                self.vps.units = json.loads(json.dumps(base[1]))
                self.vps.fs = json.loads(json.dumps(base[2]))
                self.vps.hashes = dict(base[3])
                self.vps.transient.clear()
                self.vps.links.clear()
                self.vps.lock_left.clear()
                change(self.vps)
                start = len(self.vps.calls)
                code, out, _ = self.rollback()
                self.assertEqual(code, 2, out)
                self.assertNoMutation(start)

    def test_skip_swap_when_already_prev(self):
        self.path = self.backup()
        for name in UNITS:
            if 'gateway' in name:
                self.vps.units[name].update(ActiveState='inactive', MainPID='0')
        mark = len(self.vps.calls)
        code, out, _ = self.rollback()
        self.assertEqual(code, 0, out)
        self.assertNotIn('cas', self.ops(mark))
        self.assertNotIn('cas_finish', self.ops(mark))

    def test_noop_when_prev_is_running_healthy(self):
        self.path = self.backup()
        for name, unit in self.vps.units.items():
            self.vps.running[name] = self.prev
        mark = len(self.vps.calls)
        code, out, _ = self.rollback()
        self.assertEqual(code, 0, out)
        self.assertIn('rollback_noop', out)
        self.assertNoMutation(mark)

    def test_leftover_tmp_link_completes_with_mv_only(self):
        self.installed()
        self.vps.links[self.prev] = f'/opt/instagram-meta/releases/{self.prev}'
        self.vps.put(f'/opt/instagram-meta/current-{self.prev}', 'symbolic link', mode='777', size='60')
        code, out, _ = self.rollback()
        self.assertEqual(code, 0, out)
        ops = self.ops(self.mark)
        self.assertIn('cas_finish', ops)
        self.assertNotIn('cas', ops)
        finish = self.commands(self.mark)[ops.index('cas_finish')]
        self.assertNotIn('ln -s', finish)
        self.assertIn('mv -T', finish)

    def printed_rollback(self, out):
        line = next(line for line in out.splitlines() if line.startswith('rollback: '))
        words = line.split()
        self.assertEqual(words[1:3], ['python3', tool.TOOL])
        return words[3:]

    def test_printed_rollback_after_operator_required_install_restores_prev(self):
        self.vps.waiter_after_start['hub2you'] = True
        self.vps.journal_on_start['hub2you'] = ['instagram_manager_operator_required']
        code, out, _ = self.install_new()
        self.assertEqual(code, 4, out)
        self.vps.waiter_after_start.clear()
        self.vps.journal_on_start['hub2you'] = []
        mark = len(self.vps.calls)
        code, out, _ = self.run_tool(*self.printed_rollback(out))
        self.assertEqual(code, 0, out)
        self.assertIn('vps_release_rollback_ok', out)
        self.assertEqual(self.vps.current, f'/opt/instagram-meta/releases/{self.prev}')
        self.assertIn('term', self.ops(mark))

    def test_waiter_without_flag_refuses_and_names_the_flag(self):
        self.installed()
        self.vps.counts['waiter_autonomia'] = '1'
        code, out, _ = self.rollback()
        self.assertEqual(code, 2, out)
        self.assertIn('FAIL operator_waiter_stop_allowed:autonomia', out)
        self.assertIn(f'rollback --to {self.prev} --from {self.new} --backup {self.path} --stop-operator-waiter', out)
        self.assertNoMutation(self.mark)

    def test_waiter_serving_a_person_refuses_even_with_flag(self):
        self.installed()
        for name, change in {'browser_child': lambda v: v.counts.update(waiter_hub2you='1', session_procs_hub2you='1'),
                             'marker': lambda v: (v.counts.update(waiter_hub2you='1'), v.put(
                                 '/run/instagram-hub2you/browser-request.json', 'regular file'))}.items():
            with self.subTest(name=name):
                change(self.vps)
                mark = len(self.vps.calls)
                code, out, _ = self.rollback('--stop-operator-waiter')
                self.assertEqual(code, 2, out)
                self.assertNoMutation(mark)
                self.vps.counts.pop('session_procs_hub2you', None)
                self.vps.fs.pop('/run/instagram-hub2you/browser-request.json', None)

    def test_waiter_appearing_after_checks_is_rechecked_before_term(self):
        self.installed()
        original = self.vps.op_guard

        def guard_with_person(args, stdin):
            self.vps.counts.update(waiter_hub2you='1', session_procs_hub2you='1')
            return original(args, stdin)
        self.vps.op_guard = guard_with_person
        code, out, _ = self.rollback('--stop-operator-waiter')
        self.assertEqual(code, 2, out)
        self.assertIn('human_window_open', out)
        self.assertNoMutation(self.mark)

    def test_rollback_after_stop_timeout_restarts_prev_cleanly(self):
        self.vps.manager_exits['hub2you'] = False
        code, out, _ = self.install_new()
        self.assertEqual(code, 3, out)
        # The manager finally exits 143 and Restart=on-failure brings it back on PREV.
        self.vps.manager_exits['hub2you'] = True
        manager = 'instagram-vps-manager@hub2you.service'
        self.vps.activate(manager)
        self.vps.units[manager]['NRestarts'] = '1'
        mark = len(self.vps.calls)
        code, out, _ = self.run_tool(*self.printed_rollback(out))
        self.assertEqual(code, 0, out)
        self.assertNotIn('rollback_noop', out)
        self.assertIn('reset_failed', self.ops(mark))
        self.assertNotIn('cas', self.ops(mark))
        self.assertEqual(self.vps.units[manager]['NRestarts'], '0')

    def install_new(self):
        self.path = self.backup()
        self.stage()
        return self.run_tool('install', '--sha', self.new, '--from', self.prev, '--backup', self.path,
                             '--modules-digest', MODULES_DIGEST)

    def test_units_active_fallback_without_backup(self):
        self.installed()
        self.vps.calls.clear()
        code, out, _ = self.run_tool('rollback', '--to', self.prev, '--from', self.new,
                                     '--units-active', 'hub2you=display,gateway',
                                     '--units-active', 'autonomia=display,gateway,publisher,manager')
        self.assertEqual(code, 0, out)
        self.assertNotIn('backup_read', self.ops())
        self.assertFalse(any('start instagram-vps-manager@hub2you' in c for c in self.commands()))


class LeakTests(Harness):
    def test_canary_never_reaches_output(self):
        def inject(text):
            return text.replace('Result=success', f'Result={CANARY}', 1)
        scenarios = {
            'snapshot': lambda v: v.malformed.__setitem__('snapshot', lambda t: t.replace(
                'MainPID=0', f'MainPID={CANARY}', 1).replace('srv707880', CANARY)),
            'snapshot_sha': lambda v: v.malformed.__setitem__('snapshot', lambda t: t.replace(
                tool.NODE_SHA256, CANARY)),
            'snapshot_stat': lambda v: v.malformed.__setitem__('snapshot', lambda t: t.replace('|755|', f'|{CANARY}|', 1)),
            'snapshot_df': lambda v: v.malformed.__setitem__('snapshot', lambda t: t.replace(str(v.df), CANARY)),
            'units': lambda v: v.malformed.__setitem__('units', inject),
            'stage_verify': lambda v: v.malformed.__setitem__('stage_verify', lambda t: t.replace(
                '@@ count\n', f'@@ count\n{CANARY}', 1)),
            'journal': lambda v: v.journal_on_term.__setitem__('hub2you', [CANARY, '{"event": "' + CANARY + '"']),
            'backup': lambda v: v.malformed.__setitem__('backup', lambda b: b.replace(b'"schema"', CANARY.encode(), 1)),
            'links': lambda v: v.malformed.__setitem__('links', lambda t: t.replace('/opt/instagram-meta/releases/',
                                                                                   CANARY, 1)),
            'runtime': lambda v: v.malformed.__setitem__('runtime', lambda t: t.replace('@@ cwd\n', f'@@ cwd\n{CANARY}\n')),
        }
        for name, change in scenarios.items():
            with self.subTest(name=name):
                self.vps = FakeVPS(self.prev, self.new, self.templates)
                self.vps.hashes.update({tool.node_dropin(r): sha(DROPIN_BYTES)
                                        for r in ('gateway', 'publisher', 'manager')})
                self.vps.hashes.update({tool.cpu_override(s): sha(CPU_BYTES) for s in STACKS})
                if name in ('backup', 'stage_verify', 'journal', 'units', 'links', 'runtime'):
                    backup = self.backup()
                    self.stage()
                    change(self.vps)
                    self.mark = len(self.vps.calls)
                    code, out, err = self.run_tool('install', '--sha', self.new, '--from', self.prev, '--backup',
                                                   backup, '--modules-digest', MODULES_DIGEST)
                else:
                    change(self.vps)
                    code, out, err = self.run_tool('preflight', '--sha', self.new, '--from', self.prev)
                self.assertNotIn(CANARY, out + err)
                self.assertNotIn('Traceback', out + err)
                self.assertIn(code, (0, 2, 3))

    def test_internal_error_prints_fixed_token_only(self):
        def boom(command, stdin=None, timeout=None):
            raise RuntimeError(CANARY)
        code, out, err = self.run_tool('preflight', '--sha', self.new, '--from', self.prev, runner=boom)
        self.assertEqual(code, 2)
        self.assertIn('vps_release_internal_error', out + err)
        self.assertNotIn(CANARY, out + err)
        self.assertNotIn('Traceback', out + err)


class ForbiddenCommandTests(Harness):
    FORBIDDEN = {'enable', 'disable', 'restart', 'rm', 'unlink', 'rmdir', '-delete', 'aws', 'docker', 'tailscale',
                 'redis-cli', 'SIGKILL', '--signal=SIGKILL', '-9', 'KILL', 'ssm'}

    def test_no_forbidden_command_in_any_flow(self):
        self.backup()
        self.stage()
        path = next(iter(self.vps.backups))
        self.run_tool('install', '--sha', self.new, '--from', self.prev, '--backup', path,
                      '--modules-digest', MODULES_DIGEST)
        self.run_tool('verify', '--sha', self.new, '--backup', path)
        rollback_start = len(self.vps.calls)
        self.run_tool('rollback', '--to', self.prev, '--from', self.new, '--backup', path)
        for index, (command, _) in enumerate(self.vps.calls):
            tokens = command.replace(';', ' ').replace('|', ' ').replace('&&', ' ').split()
            with self.subTest(command=command[:80]):
                self.assertFalse(self.FORBIDDEN & set(tokens), command)
                if 'reset-failed' in tokens:
                    self.assertGreaterEqual(index, rollback_start)
                    self.assertEqual(command.split('reset-failed', 1)[1].split(), UNITS)
                if 'mv' in tokens:
                    self.assertIn('mv -T /opt/instagram-meta/current-', command)
                    self.assertTrue(command.rstrip().endswith('/opt/instagram-meta/current'))
                for word in (t.strip('"\')(') for t in tokens):
                    if word.startswith('/etc/instagram-meta/') and word.endswith('.env'):
                        segment = command[:command.index(word)].rsplit('$(', 1)[-1].rsplit(';', 1)[-1]
                        self.assertTrue(segment.split()[0] in ('grep', 'stat'), command)
                self.assertNotIn('> /var/lib', command)
                self.assertNotIn('>/var/lib', command)


if __name__ == '__main__':
    unittest.main()
