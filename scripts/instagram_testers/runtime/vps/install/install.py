#!/usr/bin/env python3
"""Install a prepared, immutable Linux runtime. Does not enable or start services."""
import json
import grp
import os
from pathlib import Path
import pwd
import shutil
import stat
import subprocess
import sys

STACKS = ('hub2you', 'autonomia')
UNITS = tuple(f'instagram-vps-{role}@.service' for role in ('display', 'manager', 'gateway', 'publisher'))
ACCOUNTS = {f'{prefix}-{stack}': f'/var/lib/{home}-{stack}'
            for stack in STACKS for prefix, home in (('ig', 'instagram'), ('igpub', 'instagram-publisher'),
                                                    ('iggw', 'instagram-gateway'))}
PUBLISHER_MODULES = ('publisher-broker.mjs', 'publisher-client.mjs', 'publisher-socket.mjs',
                     'ssm-current-reader.mjs')
BINS = ('/usr/bin/node', '/usr/bin/python3', '/usr/bin/Xtigervnc', '/usr/bin/xauth', '/usr/bin/mcookie',
        '/usr/bin/google-chrome', '/usr/bin/ssh', '/usr/bin/systemctl',
        '/usr/sbin/useradd', '/usr/sbin/groupadd', '/usr/sbin/runuser')
DEPS = {'@aws-sdk/client-ssm': '3.967.0', '@novnc/novnc': '1.7.0', 'jose': '6.2.12',
        'playwright': '1.59.1', 'ws': '8.22.0'}
SCRIPTS = ('session-manager.mjs', 'session-browser.mjs', 'session-observer.mjs', 'browser-operations.mjs',
           'runtime/publisher-tunnel.mjs', 'runtime/publisher-channel.mjs', 'runtime/operator-waiter.mjs',
           'runtime/operator-protocol.mjs',
           'runtime/browser-request-marker.mjs', 'runtime/entrypoint.mjs')


def require(condition):
    if not condition:
        raise ValueError('invalid installation')


def command(args, **kwargs):
    # No command output (including credential-like diagnostics) enters the audit log.
    return subprocess.run(args, capture_output=True, text=True, timeout=30, check=False, **kwargs)


class Installer:
    def __init__(self, source, sha, root=Path('/'), run=command, account=pwd.getpwnam, owner=0,
                 group=grp.getgrnam, groups=os.getgrouplist, account_list=pwd.getpwall, group_list=grp.getgrall):
        self.source, self.sha, self.root = Path(source), sha, Path(root)
        self.run, self.account, self.owner = run, account, owner
        self.group = group
        self.groups = groups
        self.account_list = account_list
        self.group_list = group_list
        self.viewers = {}
        self.scripts = self.source / 'scripts/instagram_testers'
        self.vps = self.scripts / 'runtime/vps'
        self.release = self.path(f'/opt/instagram-meta/releases/{sha}')
        self.current = self.path('/opt/instagram-meta/current')
        self.accounts = {}

    def path(self, absolute):
        return self.root / absolute.lstrip('/')

    def trusted(self, path):
        for entry in (path, *path.parents):
            if entry == self.root.parent:
                break
            require(not entry.is_symlink())
            if entry.exists():
                info = entry.stat()
                require(info.st_uid == self.owner and not info.st_mode & 0o022)

    def successful(self, args, **kwargs):
        result = self.run(args, **kwargs)
        require(result.returncode == 0)
        return result.stdout

    def exclusive_accounts(self):
        for record in self.account_list():
            for name, service in self.accounts.items():
                if service is not None and (record.pw_uid == service.pw_uid or record.pw_gid == service.pw_gid):
                    require(record.pw_name == name)
            require(all(viewer is None or viewer.gr_gid != record.pw_gid for viewer in self.viewers.values()))
        named_gids = {record.pw_gid: name for name, record in self.accounts.items() if record is not None}
        named_gids.update({viewer.gr_gid: f'igview-{stack}' for stack, viewer in self.viewers.items() if viewer is not None})
        for group in self.group_list():
            if group.gr_gid in named_gids:
                require(group.gr_name == named_gids[group.gr_gid])

    def preflight(self):
        require(len(self.sha) == 40 and all(c in '0123456789abcdef' for c in self.sha))
        require(self.source.is_absolute() and self.source.is_dir() and not self.source.is_symlink())
        self.trusted(self.source)
        for path in (self.scripts, self.scripts.parent, self.scripts / 'runtime', self.vps):
            require(path.is_dir() and not path.is_symlink())
            self.trusted(path)
        for name in SCRIPTS:
            require((self.scripts / name).is_file() and not (self.scripts / name).is_symlink())
            self.trusted(self.scripts / name)
        for name in ('package.json', 'package-lock.json', 'gateway.mjs', 'gateway-auth.mjs', 'env/check.py',
                     'env/verify-pair.py', 'web/console.html', 'web/console.js', 'web/enter.html', 'web/enter.js',
                     'install/manager.sh', *PUBLISHER_MODULES,
                     *[f'systemd/{unit}' for unit in UNITS]):
            require((self.vps / name).is_file() and not (self.vps / name).is_symlink())
        require({entry.name for entry in self.vps.iterdir()} <= {
            'package.json', 'package-lock.json', 'gateway.mjs', 'gateway-auth.mjs', 'web', 'node_modules',
            'install', 'systemd', 'env', 'iam', 'docs', *PUBLISHER_MODULES})
        # Reject links before opening dependency manifests.
        for base, dirs, files in os.walk(self.vps):
            dirs[:] = [name for name in dirs if name != '.bin']
            for name in (*dirs, *files):
                entry = Path(base) / name
                require(not entry.is_symlink())
                require(entry.is_dir() or entry.is_file())
                require(entry.stat().st_uid == self.owner and not entry.stat().st_mode & 0o022)
                require(not name.startswith('.env') and name not in ('credentials', 'id_ed25519', 'profile'))
        package = json.loads((self.vps / 'package.json').read_text())
        require(package['dependencies'] == DEPS)
        lock = json.loads((self.vps / 'package-lock.json').read_text())
        require(lock['packages']['']['dependencies'] == DEPS)
        for name, version in DEPS.items():
            require(json.loads((self.vps / 'node_modules' / name / 'package.json').read_text())['version'] == version)
            require(lock['packages'][f'node_modules/{name}']['version'] == version)
        require((self.vps / 'node_modules/playwright/index.mjs').is_file())
        require((self.vps / 'node_modules/playwright-core/package.json').is_file())
        for binary in BINS:
            require(os.access(self.path(binary), os.X_OK))
        require(any(os.access(self.path(f'{base}/aws'), os.X_OK) for base in ('/usr/bin', '/usr/local/bin')))
        require(any(os.access(self.path(f'{base}/session-manager-plugin'), os.X_OK)
                    for base in ('/usr/bin', '/usr/local/bin')))
        node_version = self.successful(['/usr/bin/node', '--version']).strip().removeprefix('v').split('.')
        require(len(node_version) == 3 and all(p.isascii() and p.isdecimal() for p in node_version))
        require(tuple(map(int, node_version)) >= (22, 12, 0))
        # Xvnc commonly exits nonzero for -help; inspect advertised flags only.
        help_result = self.run(['/usr/bin/Xtigervnc', '-help'])
        help_text = help_result.stdout + help_result.stderr
        require(all(flag in help_text.lower() for flag in ('rfbunixpath', 'rfbunixmode', 'rfbport')))
        require(int(self.path('/proc/sys/user/max_user_namespaces').read_text()) > 0)
        userns = self.path('/proc/sys/kernel/unprivileged_userns_clone')
        require(not userns.exists() or userns.read_text().strip() == '1')
        for directory in ('/opt/instagram-meta/releases', '/etc/instagram-meta', '/etc/systemd/system', '/var/lib'):
            self.trusted(self.path(directory))
        # Service users must traverse every existing ancestor of the immutable release.
        for directory in (self.release.parent, *self.release.parent.parents):
            if directory == self.root.parent:
                break
            if directory.exists():
                require(directory.is_dir() and directory.stat().st_mode & stat.S_IXOTH)
        require(not self.release.exists() and not self.release.is_symlink())
        temporary = self.current.with_name(f'current-{self.sha}')
        require(not temporary.exists() and not temporary.is_symlink())
        if self.current.is_symlink():
            target = self.current.resolve(strict=True)
            require(target.parent == self.path('/opt/instagram-meta/releases'))
            self.trusted(target)
            for unit in UNITS:
                previous = target / 'scripts/instagram_testers/runtime/vps/systemd' / unit
                self.trusted(previous)
                require(previous.is_file() and previous.read_bytes() == (self.vps / 'systemd' / unit).read_bytes())
        else:
            require(not self.current.exists())
        for stack in STACKS:
            for unit in UNITS:
                result = self.run(['/usr/bin/systemctl', 'show', '--property=ActiveState', '--value', unit.replace('@', f'@{stack}')])
                require(result.returncode == 0 and result.stdout.strip() in ('inactive', 'failed'))
            self.trusted(self.path(f'/etc/instagram-meta/{stack}'))
            # Legacy browser-owned publisher data requires an approved migration, never automatic deletion.
            legacy = self.path(f'/var/lib/instagram-{stack}/publisher')
            require(not legacy.exists() and not legacy.is_symlink())
            legacy_gateway = self.path(f'/var/lib/instagram-{stack}/gateway')
            require(not legacy_gateway.exists() and not legacy_gateway.is_symlink())
        for name, absolute_home in ACCOUNTS.items():
            home = self.path(absolute_home)
            try:
                record = self.account(name)
            except KeyError:
                require(not home.exists() and not home.is_symlink())
                try:
                    self.group(name)
                except KeyError:
                    pass
                else:
                    raise ValueError('invalid installation')
                self.accounts[name] = None
                continue
            require(record.pw_uid != 0 and record.pw_gid != 0 and record.pw_dir == absolute_home
                    and record.pw_shell == '/usr/sbin/nologin')
            require(self.group(name).gr_gid == record.pw_gid and not self.group(name).gr_mem)
            self.accounts[name] = record
            suffixes = ('', 'publisher') if name.startswith('igpub-') else (
                ('', 'gateway') if name.startswith('iggw-') else ('', 'profile'))
            for suffix in suffixes:
                directory = home / suffix
                require(directory.is_dir() and not directory.is_symlink())
                require(directory.stat().st_uid == record.pw_uid and directory.stat().st_gid == record.pw_gid
                        and stat.S_IMODE(directory.stat().st_mode) == 0o700)
            if not name.startswith('ig-'):
                continue
            authority = home / '.Xauthority'
            require(authority.is_file() and not authority.is_symlink())
            require(authority.stat().st_uid == record.pw_uid and stat.S_IMODE(authority.stat().st_mode) == 0o600)
            require(authority.stat().st_size > 0)
        existing_uids = [record.pw_uid for record in self.accounts.values() if record is not None]
        require(len(existing_uids) == len(set(existing_uids)))
        existing_gids = [record.pw_gid for record in self.accounts.values() if record is not None]
        require(len(existing_gids) == len(set(existing_gids)))
        for stack in STACKS:
            name = f'igview-{stack}'
            try:
                viewer = self.group(name)
            except KeyError:
                require(all(self.accounts[f'{prefix}-{stack}'] is None for prefix in ('ig', 'iggw')))
                self.viewers[stack] = None
                continue
            require(viewer.gr_gid != 0 and viewer.gr_gid not in existing_gids)
            require(set(viewer.gr_mem) == {f'{prefix}-{stack}' for prefix in ('ig', 'iggw')
                                          if self.accounts[f'{prefix}-{stack}'] is not None})
            existing_gids.append(viewer.gr_gid)
            self.viewers[stack] = viewer
        for name, record in self.accounts.items():
            if record is not None:
                expected = {record.pw_gid}
                if not name.startswith('igpub-'):
                    expected.add(self.viewers[name.split('-')[1]].gr_gid)
                require(set(self.groups(name, record.pw_gid)) == expected)
        self.exclusive_accounts()
        for unit in UNITS:
            destination = self.path(f'/etc/systemd/system/{unit}')
            self.trusted(destination)
            if destination.exists():
                # Never overwrite another install's units silently.
                require(destination.read_bytes() == (self.vps / 'systemd' / unit).read_bytes())

    def directory(self, path, mode, uid=0, gid=0):
        if not path.exists():
            path.mkdir(parents=True, mode=mode)
            os.chown(path, uid, gid)
            path.chmod(mode)

    def install(self):
        self.preflight()  # All rejection checks precede writes/user creation.
        self.directory(self.path('/opt/instagram-meta'), 0o755)
        self.directory(self.release.parent, 0o755)
        self.release.mkdir(mode=0o755)
        target_scripts = self.release / 'scripts/instagram_testers'
        target_scripts.mkdir(parents=True, mode=0o755)
        for name in SCRIPTS:
            target = target_scripts / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.scripts / name, target)
        shutil.copytree(self.vps, target_scripts / 'runtime/vps', ignore=shutil.ignore_patterns('.bin', '__pycache__'))
        for directory, _, files in os.walk(self.release):
            os.chown(directory, self.owner, 0)
            Path(directory).chmod(0o755)
            for name in files:
                entry = Path(directory) / name
                os.chown(entry, self.owner, 0)
                entry.chmod(0o644)
        self.directory(self.path('/etc/instagram-meta'), 0o700)
        for stack, viewer in self.viewers.items():
            if viewer is None:
                self.successful(['/usr/sbin/groupadd', '--system', f'igview-{stack}'])
                viewer = self.group(f'igview-{stack}')
                require(viewer.gr_gid != 0 and not viewer.gr_mem)
                require(all(other is None or other.gr_gid != viewer.gr_gid for other in self.viewers.values()))
                require(all(other is None or other.pw_gid != viewer.gr_gid for other in self.accounts.values()))
                self.viewers[stack] = viewer
        for name, absolute_home in ACCOUNTS.items():
            record = self.accounts[name]
            home = self.path(absolute_home)
            if record is None:
                supplementary = [] if name.startswith('igpub-') else ['--groups', f'igview-{name.split("-")[1]}']
                self.successful(['/usr/sbin/useradd', '--system', '--user-group', *supplementary, '--home-dir',
                                 absolute_home, '--shell', '/usr/sbin/nologin', name])
                record = self.account(name)
                require(record.pw_uid != 0 and record.pw_gid != 0 and record.pw_dir == absolute_home
                        and record.pw_shell == '/usr/sbin/nologin' and self.group(name).gr_gid == record.pw_gid
                        and not self.group(name).gr_mem)
                require(all(other is None or (other.pw_uid != record.pw_uid and other.pw_gid != record.pw_gid)
                            for other in self.accounts.values()))
                self.accounts[name] = record
                require(all(viewer.gr_gid != record.pw_gid for viewer in self.viewers.values()))
                expected = {record.pw_gid}
                if not name.startswith('igpub-'):
                    expected.add(self.viewers[name.split('-')[1]].gr_gid)
                require(set(self.groups(name, record.pw_gid)) == expected)
                suffixes = ('', 'publisher') if name.startswith('igpub-') else (
                    ('', 'gateway') if name.startswith('iggw-') else ('', 'profile'))
                for suffix in suffixes:
                    self.directory(home / suffix, 0o700, record.pw_uid, record.pw_gid)
                if not name.startswith('ig-'):
                    continue
                authority = home / '.Xauthority'
                with authority.open('x'):
                    pass
                authority.chmod(0o600)
                os.chown(authority, record.pw_uid, record.pw_gid)
                cookie = self.successful(['/usr/bin/mcookie']).strip()
                require(len(cookie) == 32 and all(c in '0123456789abcdef' for c in cookie))
                display = ':91' if name == 'ig-hub2you' else ':92'
                self.successful(['/usr/sbin/runuser', '-u', name, '--', '/usr/bin/xauth',
                                 '-f', str(authority), 'source', '-'], input=f'add {display} . {cookie}\n')
                require(authority.stat().st_size > 0)
        for stack in STACKS:
            require(set(self.group(f'igview-{stack}').gr_mem) == {f'ig-{stack}', f'iggw-{stack}'})
            self.directory(self.path(f'/etc/instagram-meta/{stack}'), 0o700)
        self.exclusive_accounts()
        for unit in UNITS:
            destination = self.path(f'/etc/systemd/system/{unit}')
            if not destination.exists():
                with destination.open('xb') as handle:
                    handle.write((self.vps / 'systemd' / unit).read_bytes())
                os.chown(destination, self.owner, 0)
                destination.chmod(0o644)
        # A failed install never selects a partially installed release.
        self.successful(['/usr/bin/systemctl', 'daemon-reload'])
        temporary = self.current.with_name(f'current-{self.sha}')
        require(not temporary.exists() and not temporary.is_symlink())
        temporary.symlink_to(self.release)
        os.replace(temporary, self.current)


if __name__ == '__main__':
    try:
        require(sys.platform == 'linux' and os.geteuid() == 0 and len(sys.argv) == 3)
        os.umask(0o077)
        Installer(Path(sys.argv[1]), sys.argv[2]).install()
        print('instagram_vps_installed_inactive')
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError):
        sys.exit('instagram_vps_install_failed')
