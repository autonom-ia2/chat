#!/usr/bin/env python3
"""Synthetic filesystem + injected commands only. No AWS/SSH/Meta/browser calls."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
VPS = ROOT / 'scripts/instagram_testers/runtime/vps'

spec = importlib.util.spec_from_file_location('vps_install', VPS / 'install/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
spec = importlib.util.spec_from_file_location('check', VPS / 'env/check.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
sys.modules['check'] = check
spec = importlib.util.spec_from_file_location('verify_pair', VPS / 'env/verify-pair.py')
pair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pair)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.source = self.base / 'source'
        self.root = self.base / 'fake-linux'
        self.root.mkdir(mode=0o755)
        for name in ('opt', 'etc/systemd/system', 'var/lib'):
            (self.root / name).mkdir(parents=True, exist_ok=True)
        # Synthetic / and /opt must be traversable regardless of the caller's umask.
        self.root.chmod(0o755)
        (self.root / 'opt').chmod(0o755)
        self.scripts = self.source / 'scripts/instagram_testers'
        self.vps = self.scripts / 'runtime/vps'
        for name in installer.SCRIPTS:
            path = self.scripts / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('// synthetic inert artifact; never execute\n')
        for name in ('install', 'systemd', 'env', 'iam', 'docs'):
            shutil.copytree(VPS / name, self.vps / name)
        (self.vps / 'gateway.mjs').write_text('// synthetic gateway, never executed\n')
        (self.vps / 'gateway-auth.mjs').write_text('// synthetic auth, never executed\n')
        (self.vps / 'web').mkdir()
        for name in installer.PUBLISHER_MODULES:
            (self.vps / name).write_text('// synthetic publisher module; never executed\n')
        for name in ('console.html', 'console.js', 'enter.html', 'enter.js'):
            (self.vps / 'web' / name).write_text('synthetic inert asset\n')
        (self.vps / 'package.json').write_text(json.dumps({'dependencies': installer.DEPS}))
        packages = {'': {'dependencies': installer.DEPS}}
        for name, version in installer.DEPS.items():
            path = self.vps / 'node_modules' / name
            path.mkdir(parents=True)
            (path / 'package.json').write_text(json.dumps({'version': version}))
            packages[f'node_modules/{name}'] = {'version': version}
        path = self.vps / 'node_modules/playwright-core'
        path.mkdir()
        (path / 'package.json').write_text('{}')
        (self.vps / 'node_modules/playwright/index.mjs').write_text('// fake\n')
        (self.vps / 'package-lock.json').write_text(json.dumps({'packages': packages}))
        for name in (*installer.BINS, '/usr/local/bin/session-manager-plugin', '/usr/local/bin/aws'):
            path = self.root / name.lstrip('/')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('inert mock; never executed\n')
            path.chmod(0o755)
        path = self.root / 'proc/sys/user'
        path.mkdir(parents=True)
        (path / 'max_user_namespaces').write_text('1024\n')
        self.accounts = {}
        self.groups = {}
        self.calls = []
        self.state = 'inactive'
        self.failed_command = None
        self.install = installer.Installer(self.source, 'a' * 40, root=self.root,
                                           run=self.run_command, account=self.account, owner=os.getuid(), group=self.group, groups=self.grouplist,
                account_list=lambda: list(self.accounts.values()), group_list=lambda: list(self.groups.values()))
        self.chown = patch.object(installer.os, 'chown').start()
        original_stat = Path.stat
        def synthetic_ownership(path, *args, **kwargs):
            info = original_stat(path, *args, **kwargs)
            for name, absolute_home in installer.ACCOUNTS.items():
                home = self.root / absolute_home.lstrip('/')
                if (path == home or home in path.parents) and name in self.accounts:
                    parts = list(info)
                    parts[4] = self.accounts[name].pw_uid
                    parts[5] = self.accounts[name].pw_gid
                    return os.stat_result(parts)
            return info
        patch.object(Path, 'stat', synthetic_ownership).start()
        self.addCleanup(patch.stopall)

    def account(self, name):
        return self.accounts[name]

    def group(self, name):
        return self.groups[name]

    def grouplist(self, name, gid):
        return [gid, *[group.gr_gid for group in self.groups.values() if name in group.gr_mem]]

    def run_command(self, args, **kwargs):
        self.calls.append((args, kwargs))
        if args == self.failed_command:
            return SimpleNamespace(returncode=1, stdout='', stderr='SYNTHETIC_PRIVATE_ERROR')
        output = ''
        if args == ['/usr/bin/node', '--version']:
            output = 'v22.12.0\n'
        elif args == ['/usr/bin/Xtigervnc', '-help']:
            output = 'rfbunixpath rfbunixmode rfbport\n'
        elif args[:2] == ['/usr/bin/systemctl', 'show']:
            output = self.state + '\n'
        elif args[0] == '/usr/sbin/groupadd':
            self.groups[args[-1]] = SimpleNamespace(gr_name=args[-1], gr_gid=os.getgid() + 2000 + len(self.groups), gr_mem=[])
        elif args[0] == '/usr/sbin/useradd':
            name = args[-1]
            offset = (list(installer.ACCOUNTS).index(name) + 1) * 100
            self.accounts[name] = SimpleNamespace(pw_name=name, pw_uid=os.getuid() + offset, pw_gid=os.getgid() + offset,
                pw_dir=args[args.index('--home-dir') + 1], pw_shell='/usr/sbin/nologin')
            self.groups[name] = SimpleNamespace(gr_name=name, gr_gid=self.accounts[name].pw_gid, gr_mem=[])
            if '--groups' in args:
                self.groups[args[args.index('--groups') + 1]].gr_mem.append(name)
        elif args == ['/usr/bin/mcookie']:
            output = 'b' * 32 + '\n'
        elif args[0] == '/usr/sbin/runuser':
            Path(args[args.index('-f') + 1]).write_text('synthetic xauth data')
        return SimpleNamespace(returncode=0, stdout=output, stderr='')

    def test_installs_inactive_six_exclusive_users_private_paths_and_unix_display(self):
        self.install.install()
        self.assertEqual(set(self.accounts), set(installer.ACCOUNTS))
        self.assertEqual(self.install.current.resolve(), self.install.release)
        self.assertEqual(stat.S_IMODE((self.root / 'opt/instagram-meta').stat().st_mode), 0o755)
        self.assertEqual(self.calls[-1][0], ['/usr/bin/systemctl', 'daemon-reload'])
        for stack in installer.STACKS:
            home = self.root / f'var/lib/instagram-{stack}'
            for suffix in ('', 'profile'):
                self.assertEqual(stat.S_IMODE((home / suffix).stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((home / '.Xauthority').stat().st_mode), 0o600)
            publisher_home = self.root / f'var/lib/instagram-publisher-{stack}'
            for path in (publisher_home, publisher_home / 'publisher'):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
                self.assertEqual(path.stat().st_uid, self.accounts[f'igpub-{stack}'].pw_uid)
                self.assertEqual(path.stat().st_gid, self.accounts[f'igpub-{stack}'].pw_gid)
            self.assertFalse((home / 'publisher').exists())
            self.assertFalse((home / 'gateway').exists())
            gateway_home = self.root / f'var/lib/instagram-gateway-{stack}'
            for path in (gateway_home, gateway_home / 'gateway'):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
                self.assertEqual(path.stat().st_uid, self.accounts[f'iggw-{stack}'].pw_uid)
                self.assertEqual(path.stat().st_gid, self.accounts[f'iggw-{stack}'].pw_gid)
            viewer = self.groups[f'igview-{stack}']
            self.assertEqual(set(viewer.gr_mem), {f'ig-{stack}', f'iggw-{stack}'})
            for prefix in ('ig', 'iggw', 'igpub'):
                name = f'{prefix}-{stack}'
                expected = {self.accounts[name].pw_gid} | (set() if prefix == 'igpub' else {viewer.gr_gid})
                self.assertEqual(set(self.grouplist(name, self.accounts[name].pw_gid)), expected)
            self.assertFalse((publisher_home / 'publisher/id_ed25519').exists())
            self.assertFalse((publisher_home / 'publisher/aws-config').exists())
            self.assertFalse((self.root / f'run/instagram-publisher-{stack}').exists())
            self.assertFalse((self.root / f'etc/instagram-meta/{stack}/publisher.env').exists())
            self.assertFalse((self.root / f'etc/instagram-meta/{stack}/manager.env').exists())
            self.assertEqual(stat.S_IMODE((self.root / f'etc/instagram-meta/{stack}').stat().st_mode), 0o700)
        self.assertTrue(all(call[0][0] not in ('/usr/bin/aws', '/usr/bin/ssh', '/usr/bin/google-chrome')
                            for call in self.calls))
        self.assertFalse(any(any(word in args for word in ('start', 'restart', 'enable', 'stop'))
                             for args, _ in self.calls))
        self.assertTrue(all(stat.S_IMODE(p.stat().st_mode) == 0o644
                            for p in self.install.release.rglob('*') if p.is_file()))
        self.assertEqual(len({record.pw_uid for record in self.accounts.values()}), 6)
        self.assertEqual(len({group.gr_gid for group in self.groups.values()}), 8)

    def test_legacy_gateway_state_is_preserved_and_refused_before_writes(self):
        legacy = self.root / 'var/lib/instagram-hub2you/gateway'
        legacy.mkdir(parents=True, mode=0o700)
        nonce = legacy / 'synthetic-nonce'
        nonce.write_text('preserve replay state')
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertEqual(nonce.read_text(), 'preserve replay state')
        self.assertFalse(self.install.release.exists())
        self.assertFalse(self.accounts)
        self.chown.assert_not_called()
        nonce.unlink()
        legacy.rmdir()
        legacy.symlink_to(self.base / 'absent-state')
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertTrue(legacy.is_symlink())

    def test_gateway_orphan_home_or_group_refused_before_writes(self):
        home = self.root / 'var/lib/instagram-gateway-hub2you'
        home.mkdir(mode=0o700)
        with self.assertRaises(ValueError):
            self.install.install()
        home.rmdir()
        self.groups['iggw-hub2you'] = SimpleNamespace(gr_gid=901, gr_mem=[])
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.accounts)
        self.assertFalse(self.install.release.exists())
        self.chown.assert_not_called()

    def test_exact_groups_refused_before_upgrade_writes_without_repair(self):
        self.install.install()
        self.install.sha = '2' * 40
        self.install.release = self.install.path(f'/opt/instagram-meta/releases/{self.install.sha}')
        for name, member in (('ig-hub2you', 'iggw-hub2you'), ('iggw-hub2you', 'ig-hub2you'),
                             ('igview-hub2you', 'igpub-hub2you'), ('igview-autonomia', 'unknown-user')):
            self.groups[name].gr_mem.append(member)
            self.chown.reset_mock()
            with self.subTest(group=name, member=member), self.assertRaises(ValueError):
                self.install.install()
            self.assertIn(member, self.groups[name].gr_mem)
            self.chown.assert_not_called()
            self.assertFalse(self.install.release.exists())
            self.groups[name].gr_mem.remove(member)
        viewer = self.groups['igview-hub2you']
        viewer.gr_mem.remove('iggw-hub2you')
        with self.assertRaises(ValueError):
            self.install.install()
        viewer.gr_mem.append('iggw-hub2you')
        previous_gid = viewer.gr_gid
        for bad_gid in (0, self.accounts['ig-hub2you'].pw_gid, self.groups['igview-autonomia'].gr_gid):
            viewer.gr_gid = bad_gid
            with self.subTest(gid=bad_gid), self.assertRaises(ValueError):
                self.install.install()
        viewer.gr_gid = previous_gid
        previous_groups = self.install.groups
        self.install.groups = lambda name, gid: [*previous_groups(name, gid), 9999]
        with self.assertRaises(ValueError):
            self.install.install()
        self.install.groups = previous_groups
        self.assertFalse(self.install.release.exists())

    def test_foreign_primary_gid_or_uid_alias_refused_before_writes(self):
        self.install.install()
        self.install.sha = '3' * 40
        self.install.release = self.install.path(f'/opt/instagram-meta/releases/{self.install.sha}')
        service = self.accounts['iggw-hub2you']
        for uid, gid in ((service.pw_uid, 9999), (9999, self.accounts['ig-hub2you'].pw_gid),
                         (9999, self.groups['igview-hub2you'].gr_gid)):
            self.install.account_list = lambda: [*self.accounts.values(), SimpleNamespace(pw_name='outsider', pw_uid=uid, pw_gid=gid)]
            self.chown.reset_mock()
            with self.subTest(uid=uid, gid=gid), self.assertRaises(ValueError):
                self.install.install()
            self.chown.assert_not_called()
            self.assertFalse(self.install.release.exists())
        self.install.account_list = lambda: list(self.accounts.values())
        for name in self.groups:
            alias = SimpleNamespace(gr_name='group-alias', gr_gid=self.groups[name].gr_gid, gr_mem=['outsider'])
            self.install.group_list = lambda: [*self.groups.values(), alias]
            with self.subTest(group_alias=name), self.assertRaises(ValueError):
                self.install.install()
            self.assertFalse(self.install.release.exists())

    def test_new_gateway_alias_or_unexpected_group_never_selects_release(self):
        previous_run = self.install.run
        def unsafe_gateway(args, **kwargs):
            result = previous_run(args, **kwargs)
            if args[0] == '/usr/sbin/useradd' and args[-1] == 'iggw-hub2you':
                self.groups['ig-hub2you'].gr_mem.append('iggw-hub2you')
            return result
        self.install.run = unsafe_gateway
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.install.current.exists())
        self.assertFalse((self.root / 'var/lib/instagram-gateway-hub2you').exists())

    def test_gateway_home_state_and_identity_invalid_upgrade_refused(self):
        self.install.install()
        self.install.sha = '4' * 40
        self.install.release = self.install.path(f'/opt/instagram-meta/releases/{self.install.sha}')
        record = self.accounts['iggw-hub2you']
        for field, value in (('pw_uid', 0), ('pw_uid', self.accounts['ig-hub2you'].pw_uid),
                             ('pw_gid', self.accounts['ig-hub2you'].pw_gid), ('pw_shell', '/bin/sh'),
                             ('pw_dir', '/var/lib/instagram-hub2you')):
            previous = getattr(record, field)
            setattr(record, field, value)
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.install.install()
            setattr(record, field, previous)
        home = self.root / record.pw_dir.lstrip('/')
        for path in (home, home / 'gateway'):
            path.chmod(0o710)
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.install.install()
            path.chmod(0o700)
        state = home / 'gateway'
        state.rmdir()
        state.symlink_to(self.base)
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.install.release.exists())

    def test_active_or_transitioning_service_rejects_before_any_write(self):
        for state in ('active', 'activating', 'deactivating', 'reloading', ''):
            with self.subTest(state=state):
                self.state = state
                with self.assertRaises(ValueError):
                    self.install.install()
                self.assertFalse((self.root / 'opt/instagram-meta').exists())
                self.assertFalse(self.accounts)

    def test_dependency_missing_or_wrong_version_rejects_without_writes(self):
        path = self.vps / 'node_modules/jose/package.json'
        path.write_text('{"version":"0.0.0"}')
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.install.release.exists())
        path.unlink()
        with self.assertRaises(OSError):
            self.install.install()
        self.assertFalse(self.accounts)

    def test_missing_gateway_rejects_without_selecting_release(self):
        (self.vps / 'gateway.mjs').unlink()
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.install.current.exists())

    def test_all_imported_publisher_modules_required_and_packaged(self):
        self.install.preflight()
        for name in installer.PUBLISHER_MODULES:
            path = self.vps / name
            path.unlink()
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.install.install()
            self.assertFalse(self.accounts)
            self.assertFalse(self.install.release.exists())
            path.write_text('// synthetic inert module\n')
        self.install.install()
        for name in installer.PUBLISHER_MODULES:
            self.assertTrue((self.install.release / 'scripts/instagram_testers/runtime/vps' / name).is_file())

    def test_shared_entrypoint_required_and_packaged(self):
        helper = self.scripts / 'runtime/entrypoint.mjs'
        content = helper.read_text()
        helper.unlink()
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.accounts)
        self.assertFalse(self.install.release.exists())
        self.chown.assert_not_called()
        helper.write_text(content)
        self.install.install()
        installed = self.install.release / 'scripts/instagram_testers/runtime/entrypoint.mjs'
        self.assertEqual(installed.read_text(), content)
        self.assertEqual(stat.S_IMODE(installed.stat().st_mode), 0o644)

    def test_active_publisher_rejected_before_writes(self):
        previous_run = self.install.run
        def publisher_active(args, **kwargs):
            if args[-1].startswith('instagram-vps-publisher@'):
                return SimpleNamespace(returncode=0, stdout='active\n', stderr='')
            return previous_run(args, **kwargs)
        self.install.run = publisher_active
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.accounts)
        self.assertFalse(self.install.release.exists())

    def test_publisher_home_without_account_refused_before_writes(self):
        home = self.root / 'var/lib/instagram-publisher-autonomia'
        home.mkdir(mode=0o700)
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.accounts)
        self.assertFalse(self.install.release.exists())
        self.chown.assert_not_called()

    def test_new_account_uid_or_gid_alias_fails_without_selecting_release(self):
        previous_run = self.install.run
        def alias_account(args, **kwargs):
            result = previous_run(args, **kwargs)
            if args[0] == '/usr/sbin/useradd' and args[-1] == 'igpub-hub2you':
                self.accounts['igpub-hub2you'].pw_gid = self.accounts['ig-hub2you'].pw_gid
            return result
        self.install.run = alias_account
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.install.current.exists())
        self.assertFalse((self.root / 'var/lib/instagram-publisher-hub2you').exists())

    def test_legacy_browser_publisher_refused_without_touching_data(self):
        for stack in installer.STACKS:
            with self.subTest(stack=stack):
                legacy = self.root / f'var/lib/instagram-{stack}/publisher'
                legacy.mkdir(parents=True, mode=0o700)
                data = legacy / 'synthetic-state'
                data.write_text('synthetic preserved data')
                self.calls.clear()
                with self.assertRaises(ValueError):
                    self.install.install()
                self.assertEqual(data.read_text(), 'synthetic preserved data')
                self.assertFalse(self.accounts)
                self.assertFalse(self.install.release.exists())
                self.chown.assert_not_called()
                data.unlink()
                legacy.rmdir()
                legacy.parent.rmdir()
        dangling = self.root / 'var/lib/instagram-hub2you/publisher'
        dangling.parent.mkdir()
        dangling.symlink_to(self.base / 'nonexistent')
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertTrue(dangling.is_symlink())

    def test_six_accounts_reject_root_aliases_and_unsafe_publisher_home_before_writes(self):
        self.install.install()
        next_install = installer.Installer(self.source, '1' * 40, root=self.root,
                run=self.run_command, account=self.account, owner=os.getuid(), group=self.group, groups=self.grouplist,
                account_list=lambda: list(self.accounts.values()), group_list=lambda: list(self.groups.values()))
        publisher = self.accounts['igpub-hub2you']
        browser = self.accounts['ig-hub2you']
        for field, value in (('pw_uid', 0), ('pw_gid', 0), ('pw_uid', browser.pw_uid),
                             ('pw_gid', browser.pw_gid), ('pw_dir', browser.pw_dir), ('pw_shell', '/bin/sh')):
            with self.subTest(field=field, value=value):
                previous = getattr(publisher, field)
                setattr(publisher, field, value)
                self.chown.reset_mock()
                with self.assertRaises(ValueError):
                    next_install.install()
                self.chown.assert_not_called()
                self.assertFalse(next_install.release.exists())
                setattr(publisher, field, previous)
        home = self.root / 'var/lib/instagram-publisher-hub2you'
        for mode in (0o710, 0o750, 0o755, 0o770):
            home.chmod(mode)
            with self.subTest(mode=oct(mode)), self.assertRaises(ValueError):
                next_install.install()
            self.assertEqual(stat.S_IMODE(home.stat().st_mode), mode)
        home.chmod(0o700)
        directory = home / 'publisher'
        directory.rmdir()
        directory.symlink_to(self.base)
        with self.assertRaises(ValueError):
            next_install.install()
        self.assertFalse(next_install.release.exists())

    def test_symlink_source_or_target_refused(self):
        path = self.vps / 'node_modules/jose/package.json'
        path.unlink()
        path.symlink_to(self.vps / 'package.json')
        with self.assertRaises(ValueError):
            self.install.install()
        path.unlink()
        path.write_text(json.dumps({'version': installer.DEPS['jose']}))
        (self.root / 'opt/instagram-meta').symlink_to(self.base / 'elsewhere')
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.accounts)

    def test_untrusted_destination_permissions_refused(self):
        (self.root / 'opt').chmod(0o777)
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.accounts)

    def test_inaccessible_release_ancestors_refused_before_any_write(self):
        self.install.release.parent.mkdir(parents=True)
        ancestors = (self.root, self.root / 'opt', self.root / 'opt/instagram-meta', self.install.release.parent)
        for directory in ancestors:
            for mode in (0o700, 0o750, 0o744):
                with self.subTest(directory=directory.relative_to(self.root), mode=oct(mode)):
                    directory.chmod(mode)
                    before = {path.relative_to(self.root): (path.stat().st_mode, path.read_bytes() if path.is_file() else None)
                              for path in (self.root, *self.root.rglob('*'))}
                    self.calls.clear()
                    with patch.object(self.install, 'directory') as create_directory, self.assertRaises(ValueError):
                        self.install.install()
                    create_directory.assert_not_called()
                    self.chown.assert_not_called()
                    self.assertFalse(self.accounts)
                    self.assertFalse(self.install.release.exists())
                    self.assertFalse(self.install.current.exists())
                    self.assertFalse(any(args[0] in ('/usr/sbin/useradd', '/usr/sbin/runuser', '/usr/bin/mcookie')
                                         or args == ['/usr/bin/systemctl', 'daemon-reload'] for args, _ in self.calls))
                    after = {path.relative_to(self.root): (path.stat().st_mode, path.read_bytes() if path.is_file() else None)
                             for path in (self.root, *self.root.rglob('*'))}
                    self.assertEqual(after, before)
                    directory.chmod(0o755)

    def test_traversable_existing_release_ancestors_pass_preflight_without_chmod(self):
        self.install.release.parent.mkdir(parents=True)
        ancestors = (self.root, self.root / 'opt', self.root / 'opt/instagram-meta', self.install.release.parent)
        for mode in (0o755, 0o711):
            with self.subTest(mode=oct(mode)):
                for directory in ancestors:
                    directory.chmod(mode)
                self.install.preflight()
                self.assertTrue(all(stat.S_IMODE(directory.stat().st_mode) == mode for directory in ancestors))
                self.assertFalse(self.install.release.exists())
                self.chown.assert_not_called()

    def test_bin_symlinks_ignored_but_never_dereferenced(self):
        bin_dir = self.vps / 'node_modules/.bin'
        bin_dir.mkdir()
        (bin_dir / 'playwright').symlink_to(self.base / 'outside')
        self.install.install()
        self.assertFalse((self.install.release / 'scripts/instagram_testers/runtime/vps/node_modules/.bin').exists())

    def test_existing_release_refused_and_profiles_preserved_on_upgrade(self):
        self.install.install()
        profile = self.root / 'var/lib/instagram-hub2you/profile/synthetic-state'
        profile.write_text('do not destroy')
        nonce = self.root / 'var/lib/instagram-gateway-hub2you/gateway/synthetic-nonce'
        nonce.write_text('do not destroy')
        publisher_state = self.root / 'var/lib/instagram-publisher-hub2you/publisher/synthetic-state'
        publisher_state.write_text('do not destroy')
        publisher_state.chmod(0o600)
        with self.assertRaises(ValueError):
            self.install.install()
        previous = self.install.release
        next_install = installer.Installer(self.source, 'c' * 40, root=self.root,
                run=self.run_command, account=self.account, owner=os.getuid(), group=self.group, groups=self.grouplist,
                account_list=lambda: list(self.accounts.values()), group_list=lambda: list(self.groups.values()))
        next_install.install()
        self.assertEqual(next_install.current.resolve(), next_install.release)
        self.assertTrue(previous.is_dir())
        self.assertEqual(profile.read_text(), 'do not destroy')
        self.assertEqual(nonce.read_text(), 'do not destroy')
        self.assertEqual(publisher_state.read_text(), 'do not destroy')
        self.assertEqual(stat.S_IMODE(publisher_state.stat().st_mode), 0o600)
        self.assertEqual(sum(args[0] == '/usr/sbin/useradd' for args, _ in self.calls), 6)

    def test_fail_during_install_never_changes_current_or_removes_state(self):
        self.install.install()
        previous = self.install.current.resolve()
        next_install = installer.Installer(self.source, 'd' * 40, root=self.root,
                run=self.run_command, account=self.account, owner=os.getuid(), group=self.group, groups=self.grouplist,
                account_list=lambda: list(self.accounts.values()), group_list=lambda: list(self.groups.values()))
        self.failed_command = ['/usr/bin/systemctl', 'daemon-reload']
        with self.assertRaises(ValueError):
            next_install.install()
        self.assertEqual(next_install.current.resolve(), previous)
        self.assertTrue(next_install.release.exists())
        self.assertEqual(set(self.accounts), set(installer.ACCOUNTS))

    def test_wrong_existing_account_or_foreign_unit_refused(self):
        self.accounts['ig-hub2you'] = SimpleNamespace(pw_uid=123, pw_gid=123,
            pw_dir='/foreign-data', pw_shell='/bin/sh')
        with self.assertRaises(ValueError):
            self.install.install()
        self.accounts.clear()
        destination = self.root / f'etc/systemd/system/{installer.UNITS[0]}'
        destination.write_text('foreign unit')
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertEqual(destination.read_text(), 'foreign unit')
        self.assertFalse(self.accounts)

    def test_userns_disabled_or_bad_revision_refused(self):
        (self.root / 'proc/sys/user/max_user_namespaces').write_text('0')
        with self.assertRaises(ValueError):
            self.install.install()
        self.install.sha = 'NOT_A_REVISION'
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertFalse(self.accounts)

    def test_empty_authority_and_aliased_accounts_block_upgrade(self):
        self.install.install()
        authority = self.root / 'var/lib/instagram-hub2you/.Xauthority'
        authority.write_text('')
        next_install = installer.Installer(self.source, 'e' * 40, root=self.root,
                run=self.run_command, account=self.account, owner=os.getuid(), group=self.group, groups=self.grouplist,
                account_list=lambda: list(self.accounts.values()), group_list=lambda: list(self.groups.values()))
        with self.assertRaises(ValueError):
            next_install.install()
        authority.write_text('synthetic xauth data')
        self.accounts['ig-autonomia'].pw_uid = self.accounts['ig-hub2you'].pw_uid
        with self.assertRaises(ValueError):
            next_install.install()
        self.assertFalse(next_install.release.exists())

    def test_legacy_current_refused_without_changing_it(self):
        previous = self.root / ('opt/instagram-meta/releases/' + 'f' * 40)
        previous.mkdir(parents=True)
        self.install.current.symlink_to(previous)
        with self.assertRaises(ValueError):
            self.install.install()
        self.assertEqual(self.install.current.resolve(), previous)
        self.assertFalse(self.accounts)


class SyntheticAccounts:
    def group_record(self, name):
        if name.startswith('igview-'):
            stack = name.split('-')[1]
            return SimpleNamespace(gr_name=name, gr_gid=801 + list(check.STACKS).index(stack),
                                   gr_mem=[f'ig-{stack}', f'iggw-{stack}'])
        return SimpleNamespace(gr_name=name, gr_gid=self.accounts[name].pw_gid, gr_mem=[])

    def account_groups(self, name, gid):
        return [gid] if name.startswith('igpub-') else [gid, self.group_record(f'igview-{name.split("-")[1]}').gr_gid]


class ConfigTests(SyntheticAccounts, unittest.TestCase):
    def setUp(self):
        # Exercise trusted ancestors without inheriting a world-writable /tmp root.
        self.temporary = tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent)
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name).resolve() / 'config.env'
        self.private_patcher = patch.object(check, 'private_path')
        self.private_patcher.start()
        self.executable_patcher = patch.object(check, 'root_executable')
        self.executable_patcher.start()
        self.addCleanup(patch.stopall)
        self.accounts = {name: SimpleNamespace(pw_name=name, pw_uid=101 + index, pw_gid=201 + index,
            pw_dir=home, pw_shell='/usr/sbin/nologin') for index, (name, home) in enumerate(installer.ACCOUNTS.items())}
        patch.object(check.os, 'getgrouplist', side_effect=self.account_groups).start()
        patch.object(check.pwd, 'getpwall', side_effect=lambda: list(self.accounts.values())).start()
        patch.object(check.grp, 'getgrall', side_effect=lambda: [self.group_record(name) for name in (
            *self.accounts, 'igview-hub2you', 'igview-autonomia')]).start()
        self.envs = {}
        for stack in check.STACKS:
            for role in pair.ALLOWED:
                values = {}
                for line in (VPS / f'env/{stack}.{role}.env.example').read_text().splitlines():
                    key, _, value = line.partition('=')
                    values[key] = value
                if role == 'gateway':
                    values['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY'] = ('ab' if stack == 'hub2you' else 'cd') * 32
                    values['INSTAGRAM_TESTER_OPERATOR_ISSUER'] = 'https://rails.invalid'
                if role == 'manager':
                    values['INSTAGRAM_TESTER_PROXY_HOST'] = 'proxy.invalid'
                    values['INSTAGRAM_TESTER_PROXY_PORT'] = '8080'
                self.envs[stack, role] = values
        def synthetic_config(parser, path):
            profile = 'hub2you' if 'hub2you' in path else 'financial'
            parser.read_string(f'[profile {profile}]\nregion=us-east-1\ncredential_process=/approved/mock-helper\n')
            return [path]
        patch.object(check.configparser.ConfigParser, 'read', synthetic_config).start()

    def test_correct_contract_both_stacks_all_roles(self):
        for (stack, role), values in self.envs.items():
            with self.subTest(stack=stack, role=role):
                check.validate(stack, role, values, 123)

    def test_account_contract_refuses_gateway_publisher_group_and_foreign_id_aliases(self):
        with patch.object(check.pwd, 'getpwnam', side_effect=lambda name: self.accounts[name]), \
                patch.object(check.grp, 'getgrnam', side_effect=self.group_record):
            check.service_accounts()
            for name in self.accounts:
                expected = self.account_groups(name, self.accounts[name].pw_gid)
                for bad in ([*expected, 9999], [self.accounts[name].pw_gid]):
                    if bad == expected:
                        continue
                    with self.subTest(name=name, groups=bad), patch.object(check.os, 'getgrouplist',
                            side_effect=lambda account, gid: bad if account == name else self.account_groups(account, gid)), \
                            self.assertRaises(ValueError):
                        check.service_accounts()
            for field, value in (('pw_uid', self.accounts['ig-hub2you'].pw_uid),
                                 ('pw_gid', self.accounts['ig-hub2you'].pw_gid), ('pw_shell', '/bin/sh'),
                                 ('pw_dir', '/var/lib/instagram-hub2you')):
                record = self.accounts['iggw-hub2you']
                previous = getattr(record, field)
                setattr(record, field, value)
                with self.subTest(field=field), self.assertRaises(ValueError):
                    check.service_accounts()
                setattr(record, field, previous)
            for uid, gid in ((self.accounts['iggw-hub2you'].pw_uid, 9999),
                             (9999, self.accounts['ig-hub2you'].pw_gid), (9999, 801)):
                foreign = SimpleNamespace(pw_name='outsider', pw_uid=uid, pw_gid=gid)
                with self.subTest(uid=uid, gid=gid), patch.object(check.pwd, 'getpwall',
                        return_value=[*self.accounts.values(), foreign]), self.assertRaises(ValueError):
                    check.service_accounts()

    def test_viewer_and_primary_groups_are_exact_and_distinct(self):
        groups = {name: self.group_record(name) for name in (*self.accounts, 'igview-hub2you', 'igview-autonomia')}
        with patch.object(check.pwd, 'getpwnam', side_effect=lambda name: self.accounts[name]), \
                patch.object(check.grp, 'getgrnam', side_effect=lambda name: groups[name]):
            for name, group in groups.items():
                original = group.gr_gid
                for gid in (0, self.accounts['igpub-hub2you'].pw_gid, 801):
                    if gid == original:
                        continue
                    group.gr_gid = gid
                    with self.subTest(name=name, gid=gid), self.assertRaises(ValueError):
                        check.service_accounts()
                    group.gr_gid = original
                original_members = group.gr_mem
                group.gr_mem = [*original_members, 'outsider']
                with self.subTest(name=name), self.assertRaises(ValueError):
                    check.service_accounts()
                group.gr_mem = original_members
            groups['igview-hub2you'].gr_mem = ['ig-hub2you']
            with self.assertRaises(ValueError):
                check.service_accounts()

    def test_group_gid_aliases_do_not_authorize_foreign_members(self):
        groups = [self.group_record(name) for name in (*self.accounts, 'igview-hub2you', 'igview-autonomia')]
        with patch.object(check.pwd, 'getpwnam', side_effect=lambda name: self.accounts[name]), \
                patch.object(check.grp, 'getgrnam', side_effect=self.group_record):
            for group in groups:
                alias = SimpleNamespace(gr_name='alias', gr_gid=group.gr_gid, gr_mem=['outsider'])
                with self.subTest(group=group.gr_name), patch.object(check.grp, 'getgrall', return_value=[*groups, alias]), \
                        self.assertRaises(ValueError):
                    check.service_accounts()

    def test_gateway_new_state_path_and_no_numeric_identity_env(self):
        for stack in check.STACKS:
            baseline = self.envs[stack, 'gateway']
            self.assertEqual(baseline['INSTAGRAM_TESTER_GATEWAY_STATE_DIR'],
                             f'/var/lib/instagram-gateway-{stack}/gateway')
            with self.assertRaises(ValueError):
                check.validate(stack, 'gateway', baseline | {
                    'INSTAGRAM_TESTER_GATEWAY_STATE_DIR': f'/var/lib/instagram-{stack}/gateway'}, 123)
            for variable in ('INSTAGRAM_TESTER_BROWSER_UID', 'INSTAGRAM_TESTER_VIEWER_GID',
                             'INSTAGRAM_TESTER_GATEWAY_UID', 'INSTAGRAM_TESTER_GATEWAY_GID'):
                self.path.write_text(''.join(f'{key}={value}\n' for key, value in (baseline | {variable: '123'}).items()))
                with self.subTest(variable=variable), self.assertRaises(ValueError):
                    pair.read_literals(self.path, 'gateway')

    def test_examples_and_literal_parser_separate_browser_and_publisher_env(self):
        for (stack, role), values in self.envs.items():
            with self.subTest(stack=stack, role=role):
                self.path.write_text(''.join(f'{key}={value}\n' for key, value in values.items()))
                self.assertEqual(pair.read_literals(self.path, role), values)
                if role != 'publisher':
                    self.assertFalse(any(key.startswith('AWS_') for key in values))
                    self.assertEqual({key for key in values if key.startswith('INSTAGRAM_TESTER_PUBLISHER_')},
                                     {'INSTAGRAM_TESTER_PUBLISHER_SOCKET'} if role == 'manager' else set())

    def test_browser_roles_refuse_every_aws_and_publisher_variable_even_empty(self):
        for stack in check.STACKS:
            for role in ('display', 'manager', 'gateway'):
                baseline = self.envs[stack, role]
                for key in ('AWS_CONFIG_FILE', 'AWS_PROFILE', 'AWS_ACCESS_KEY_ID', 'AWS_UNKNOWN',
                            'INSTAGRAM_TESTER_PUBLISHER_SSH_KEY', 'INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT',
                            'INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON', 'INSTAGRAM_TESTER_PUBLISHER_UNKNOWN'):
                    for value in ('', 'synthetic'):
                        with self.subTest(stack=stack, role=role, key=key, value=value), self.assertRaises(ValueError):
                            check.validate(stack, role, baseline | {key: value}, 123)
                if role != 'manager':
                    with self.assertRaises(ValueError):
                        check.validate(stack, role, baseline | {'INSTAGRAM_TESTER_PUBLISHER_SOCKET': ''}, 123)

    def test_publisher_rejects_wrong_paths_legacy_document_aws_overrides_and_browser_env(self):
        for stack in check.STACKS:
            baseline = self.envs[stack, 'publisher']
            mutations = {'HOME': f'/var/lib/instagram-{stack}',
                'PATH': '/tmp:/usr/bin',
                'INSTAGRAM_TESTER_PUBLISHER_SOCKET': '/tmp/publisher.sock',
                'INSTAGRAM_TESTER_PUBLISHER_SSH_KEY': f'/var/lib/instagram-{stack}/publisher/id_ed25519',
                'AWS_CONFIG_FILE': '/tmp/aws-config', 'AWS_SHARED_CREDENTIALS_FILE': '/tmp/credentials',
                'AWS_EC2_METADATA_DISABLED': 'false', 'AWS_PAGER': '/tmp/pager',
                'AWS_ACCESS_KEY_ID': 'synthetic', 'AWS_SECRET_ACCESS_KEY': '', 'AWS_PROFILE': '',
                'AWS_WEB_IDENTITY_TOKEN_FILE': '/tmp/synthetic',
                'INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT': 'AWS-RunShellScript',
                'INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON': '[]',
                'DISPLAY': ':91', 'XAUTHORITY': '/tmp/auth',
                'INSTAGRAM_TESTER_BROWSER_PROFILE': '/tmp/profile', 'INSTAGRAM_TESTER_PROXY_HOST': '',
                'INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY': 'ab' * 32, 'NODE_OPTIONS': '--inspect'}
            for key, value in mutations.items():
                with self.subTest(stack=stack, key=key), self.assertRaises(ValueError):
                    check.validate(stack, 'publisher', baseline | {key: value}, 123)

    def test_publisher_reads_only_its_private_home_and_files_without_executing_helper(self):
        with patch.object(check, 'private_path') as private, patch.object(check, 'root_executable') as helper:
            check.validate('hub2you', 'publisher', self.envs['hub2you', 'publisher'], 321)
            self.assertEqual(private.call_args_list, [
                unittest.mock.call('/var/lib/instagram-publisher-hub2you', 321, 0o700, directory=True, gid=None),
                unittest.mock.call('/var/lib/instagram-publisher-hub2you/publisher', 321, 0o700, directory=True, gid=None),
                unittest.mock.call('/var/lib/instagram-publisher-hub2you/publisher/id_ed25519', 321, 0o600),
                unittest.mock.call('/var/lib/instagram-publisher-hub2you/publisher/aws-config', 321, 0o600)])
            helper.assert_called_once_with('/approved/mock-helper')
        with patch.object(check.configparser.ConfigParser, 'read') as read:
            check.validate('hub2you', 'manager', self.envs['hub2you', 'manager'], 123)
            read.assert_not_called()

    def test_publisher_rejects_aws_config_extra_profiles_keys_region_and_relative_helper(self):
        configs = ('[profile hub2you]\nregion=us-east-2\ncredential_process=/approved/mock-helper\n',
                   '[profile financial]\nregion=us-east-1\ncredential_process=/approved/mock-helper\n',
                   '[profile hub2you]\nregion=us-east-1\ncredential_process=/approved/mock-helper\naws_access_key_id=synthetic\n',
                   '[profile hub2you]\nregion=us-east-1\ncredential_process=/approved/mock-helper\n[default]\nregion=us-east-1\n',
                   '[profile hub2you]\nregion=us-east-1\ncredential_process=REQUIRED_HELPER\n')
        for body in configs:
            with self.subTest(config=body.splitlines()[0]):
                with patch.object(check.configparser.ConfigParser, 'read', lambda parser, path: parser.read_string(body)), \
                        self.assertRaises(ValueError):
                    check.validate('hub2you', 'publisher', self.envs['hub2you', 'publisher'], 123)
        self.executable_patcher.stop()
        with patch.object(check.configparser.ConfigParser, 'read', lambda parser, path: parser.read_string(
                '[profile hub2you]\nregion=us-east-1\ncredential_process=relative-helper\n')), self.assertRaises(ValueError):
            check.validate('hub2you', 'publisher', self.envs['hub2you', 'publisher'], 123)

    def test_process_boundary_dynamic_uids_gids_and_ephemeral_directory(self):
        with patch.object(check.pwd, 'getpwnam', side_effect=lambda name: self.accounts[name]), \
                patch.object(check.grp, 'getgrnam', side_effect=self.group_record):
            for stack in check.STACKS:
                for role in pair.ALLOWED:
                    prefix = {'publisher': 'igpub', 'gateway': 'iggw'}.get(role, 'ig')
                    record = self.accounts[f'{prefix}-{stack}']
                    browser = self.accounts[f'ig-{stack}']
                    viewer_gid = self.group_record(f'igview-{stack}').gr_gid
                    gid = viewer_gid if role == 'display' else (record.pw_gid if role == 'gateway' else browser.pw_gid)
                    groups = {gid} | (set() if role == 'publisher' else {viewer_gid})
                    with self.subTest(stack=stack, role=role), \
                            patch.object(check, 'validate') as validate, \
                            patch.object(check, 'private_path') as private:
                        check.check_process(stack, role, self.envs[stack, role], record.pw_uid, gid, groups)
                        validate.assert_called_once_with(stack, role, self.envs[stack, role], record.pw_uid, record.pw_gid)
                        runtime = f'/run/instagram-{"publisher-" if role == "publisher" else ""}{stack}'
                        private.assert_any_call(runtime, record.pw_uid if role == 'publisher' else browser.pw_uid,
                            0o710, directory=True, gid=browser.pw_gid if role == 'publisher' else viewer_gid)
                        if role == 'gateway':
                            private.assert_any_call(f'/var/lib/instagram-{stack}', browser.pw_uid,
                                0o700, directory=True, gid=browser.pw_gid)
                        for bad_uid, bad_gid in ((0, gid), (record.pw_uid, 0), (record.pw_uid + 500, gid),
                                                 (record.pw_uid, gid + 500)):
                            with self.assertRaises(ValueError):
                                check.check_process(stack, role, self.envs[stack, role], bad_uid, bad_gid, groups)
                        with self.assertRaises(ValueError):
                            check.check_process(stack, role, self.envs[stack, role], record.pw_uid, gid, groups | {9999})
                        if role in ('manager', 'gateway'):
                            with self.assertRaises(ValueError):
                                check.check_process(stack, role, self.envs[stack, role], record.pw_uid, gid, groups - {viewer_gid})

    def test_root_helper_rejects_relative_symlink_nonexecutable_untrusted_owner_or_ancestor(self):
        self.executable_patcher.stop()
        self.path.write_text('inert synthetic helper; never execute\n')
        self.path.chmod(0o755)
        original_stat = Path.stat
        def root_owned(path, *args, **kwargs):
            parts = list(original_stat(path, *args, **kwargs))
            parts[4] = 0
            return os.stat_result(parts)
        with self.assertRaises(ValueError):
            check.root_executable('relative-helper')
        with patch.object(Path, 'stat', root_owned):
            # Temporary ancestors may be writable; model trusted permissions without changing them.
            def trusted_stat(path, *args, **kwargs):
                parts = list(root_owned(path, *args, **kwargs))
                if path != self.path:
                    parts[0] &= ~0o022
                return os.stat_result(parts)
            with patch.object(Path, 'stat', trusted_stat):
                check.root_executable(self.path)
                self.path.chmod(0o644)
                with self.assertRaises(ValueError):
                    check.root_executable(self.path)
                self.path.chmod(0o755)
                link = self.path.with_name('helper-link')
                link.symlink_to(self.path)
                with self.assertRaises(ValueError):
                    check.root_executable(link)
                for bad_path in (self.path, self.path.parent):
                    for field, value in ((4, 999), (0, stat.S_IFREG | 0o777 if bad_path == self.path else stat.S_IFDIR | 0o777)):
                        def untrusted_stat(path, *args, **kwargs):
                            parts = list(trusted_stat(path, *args, **kwargs))
                            if path == bad_path:
                                parts[field] = value
                            return os.stat_result(parts)
                        with self.subTest(path=bad_path.name, field=field), patch.object(Path, 'stat', untrusted_stat), self.assertRaises(ValueError):
                            check.root_executable(self.path)

    def test_gateway_rejects_bad_paths_origins_keys_ports_and_foreign_secrets(self):
        baseline = self.envs['hub2you', 'gateway']
        mutations = {
            'INSTAGRAM_TESTER_RUNTIME_STACK': 'autonomia',
            'INSTAGRAM_TESTER_GATEWAY_PORT': '0',
            'INSTAGRAM_TESTER_VNC_SOCKET': '/run/instagram-autonomia/vnc.sock',
            'INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE': '/tmp/request.json',
            'INSTAGRAM_TESTER_GATEWAY_STATE_DIR': '/tmp/nonces',
            'INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY': 'x' * 64,
            'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL': 'http://runtime.invalid/hub2you/',
            'INSTAGRAM_TESTER_OPERATOR_ISSUER': 'https://user:synthetic@rails.invalid',
            'AWS_CONFIG_FILE': '/synthetic/config',
            'DEBUG': 'pw:protocol',
        }
        for key, value in mutations.items():
            with self.subTest(key=key), self.assertRaises(ValueError):
                check.validate('hub2you', 'gateway', baseline | {key: value}, 123)
        for url in ('https://runtime.invalid/hub2you/?ticket=synthetic',
                    'https://runtime.invalid/hub2you/#fragment', 'https://runtime.invalid/autonomia/',
                    'https://runtime.invalid:8080/hub2you/'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                check.validate('hub2you', 'gateway', baseline | {'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL': url}, 123)

    def test_manager_refuses_disabled_sandbox_wrong_profile_legacy_and_static_credentials(self):
        baseline = self.envs['hub2you', 'manager']
        for key, value in {'INSTAGRAM_TESTER_CHROMIUM_SANDBOX': 'false',
                'INSTAGRAM_TESTER_BROWSER_PROFILE': '/var/lib/instagram-autonomia/profile',
                'INSTAGRAM_TESTER_PROXY_HOST': '$(touch /tmp/never)',
                'INSTAGRAM_TESTER_PROXY_PORT': '00080', 'INSTAGRAM_TESTER_PROXY_AUTH_MODE': 'userpass',
                'INSTAGRAM_TESTER_PUBLISHER_SOCKET': '/run/instagram-publisher-autonomia/publisher.sock',
                'INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT': 'AWS-RunShellScript',
                'AWS_ACCESS_KEY_ID': 'synthetic', 'AWS_SHARED_CREDENTIALS_FILE': '/synthetic/credentials',
                'NODE_OPTIONS': '--inspect=0.0.0.0', 'PWDEBUG': '1'}.items():
            with self.subTest(key=key), self.assertRaises(ValueError):
                check.validate('hub2you', 'manager', baseline | {key: value}, 123)

    def test_literal_parser_rejects_duplicate_unknown_expansion_and_placeholders(self):
        values = self.envs['hub2you', 'gateway']
        body = ''.join(f'{key}={value}\n' for key, value in values.items())
        self.path.write_text(body)
        self.assertEqual(pair.read_literals(self.path, 'gateway'), values)
        for extra in ('LD_PRELOAD=/tmp/never\n', 'INSTAGRAM_TESTER_RUNTIME_STACK=hub2you\n'):
            self.path.write_text(body + extra)
            with self.assertRaises(ValueError):
                pair.read_literals(self.path, 'gateway')
        self.path.write_text(body.replace('https://rails.invalid', '"https://rails.invalid"'))
        with self.assertRaises(ValueError):
            pair.read_literals(self.path, 'gateway')
        self.path.write_text(body.replace('https://rails.invalid', 'REQUIRED_ISSUER'))
        with self.assertRaises(ValueError):
            pair.read_literals(self.path, 'gateway')

    def test_pair_compares_key_bytes_and_fails_when_keys_equal(self):
        with patch.object(check.pwd, 'getpwnam', side_effect=lambda name: self.accounts[name]), \
                patch.object(check.grp, 'getgrnam', side_effect=self.group_record), \
                patch.object(pair, 'private_path'), \
                patch.object(pair, 'read_literals', side_effect=lambda path, role: self.envs[path.parent.name, role]):
            pair.verify()
            self.envs['autonomia', 'gateway']['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY'] = 'AB' * 32
            with self.assertRaises(ValueError):
                pair.verify()

    def test_pair_refuses_root_shared_uid_gid_wrong_home_shell_and_group(self):
        with patch.object(check.pwd, 'getpwnam', side_effect=lambda name: self.accounts[name]), \
                patch.object(check.grp, 'getgrnam', side_effect=self.group_record), \
                patch.object(pair, 'private_path'), \
                patch.object(pair, 'read_literals', side_effect=lambda path, role: self.envs[path.parent.name, role]):
            record = self.accounts['igpub-autonomia']
            browser = self.accounts['ig-autonomia']
            for field, value in (('pw_uid', 0), ('pw_gid', 0), ('pw_uid', browser.pw_uid),
                                 ('pw_gid', browser.pw_gid), ('pw_dir', browser.pw_dir), ('pw_shell', '/bin/sh')):
                previous = getattr(record, field)
                setattr(record, field, value)
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    pair.verify()
                setattr(record, field, previous)
            with patch.object(check.grp, 'getgrnam', return_value=SimpleNamespace(gr_gid=999, gr_mem=[])), self.assertRaises(ValueError):
                pair.verify()

    def test_private_files_reject_symlink_or_insecure_permissions(self):
        self.private_patcher.stop()
        self.path.write_text('synthetic data')
        self.path.chmod(0o600)
        check.private_path(self.path, os.getuid(), 0o600)
        self.path.write_text('')
        with self.assertRaises(ValueError):
            check.private_path(self.path, os.getuid(), 0o600)
        self.path.write_text('synthetic data')
        self.path.chmod(0o644)
        with self.assertRaises(ValueError):
            check.private_path(self.path, os.getuid(), 0o600)
        link = self.path.with_name('link')
        link.symlink_to(self.path)
        with self.assertRaises(ValueError):
            check.private_path(link, os.getuid(), 0o600)
        with self.assertRaises(ValueError):
            check.private_path(self.path, os.getuid() + 500, 0o644)
        directory = self.path.with_name('publisher-runtime')
        directory.mkdir(mode=0o710)
        directory.chmod(0o710)
        check.private_path(directory, os.getuid(), 0o710, directory=True)
        for mode in (0o700, 0o711, 0o750, 0o770, 0o755):
            directory.chmod(mode)
            with self.subTest(mode=oct(mode)), self.assertRaises(ValueError):
                check.private_path(directory, os.getuid(), 0o710, directory=True)


class ConfigFilesystemTests(SyntheticAccounts, unittest.TestCase):
    """Real permission/type/parser checks against a mapped, inert Linux filesystem."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / 'synthetic-linux'
        self.root.mkdir()
        self.accounts = {name: SimpleNamespace(pw_name=name, pw_uid=101 + index, pw_gid=201 + index,
            pw_dir=home, pw_shell='/usr/sbin/nologin') for index, (name, home) in enumerate(installer.ACCOUNTS.items())}
        patch.object(check.os, 'getgrouplist', side_effect=self.account_groups).start()
        patch.object(check.pwd, 'getpwall', side_effect=lambda: list(self.accounts.values())).start()
        patch.object(check.grp, 'getgrall', side_effect=lambda: [self.group_record(name) for name in (
            *self.accounts, 'igview-hub2you', 'igview-autonomia')]).start()
        self.owners = {}
        for name, record in self.accounts.items():
            home = self.root / record.pw_dir.lstrip('/')
            home.mkdir(parents=True, mode=0o700)
            self.owners[record.pw_dir] = (record.pw_uid, record.pw_gid)
            suffixes = ('publisher',) if name.startswith('igpub-') else (('gateway',) if name.startswith('iggw-') else ('profile',))
            for suffix in suffixes:
                (home / suffix).mkdir(mode=0o700)
            if name.startswith('igpub-'):
                (home / 'publisher/id_ed25519').write_bytes(b'inert synthetic bytes, no private key\n')
                stack = name.split('-')[1]
                profile = check.STACKS[stack][2]
                (home / 'publisher/aws-config').write_text(
                    f'[profile {profile}]\nregion=us-east-1\ncredential_process=/usr/local/bin/service-helper\n')
                for file in (home / 'publisher').iterdir():
                    file.chmod(0o600)
            elif name.startswith('ig-'):
                (home / '.Xauthority').write_bytes(b'inert synthetic xauth\n')
                (home / '.Xauthority').chmod(0o600)
        helper = self.root / 'usr/local/bin/service-helper'
        helper.parent.mkdir(parents=True)
        helper.write_text('inert synthetic helper; never execute\n')
        helper.chmod(0o755)
        for stack in check.STACKS:
            directory = self.root / f'etc/instagram-meta/{stack}'
            directory.mkdir(parents=True, mode=0o700)
            for role in pair.ALLOWED:
                body = (VPS / f'env/{stack}.{role}.env.example').read_text()
                body = body.replace('REQUIRED_APPROVED_PROXY_HOST', 'proxy.invalid').replace('REQUIRED_APPROVED_PROXY_PORT', '8080')
                body = body.replace('REQUIRED_RAILS_HTTPS_ORIGIN', 'https://rails.invalid')
                body = body.replace(f'REQUIRED_DISTINCT_{stack.upper()}_KEY', ('ab' if stack == 'hub2you' else 'cd') * 32)
                file = directory / f'{role}.env'
                file.write_text(body)
                file.chmod(0o600)
        original_stat, original_read, original_link = Path.stat, Path.read_text, Path.is_symlink
        original_access = os.access
        original_config_read = check.configparser.ConfigParser.read
        def mapped(path):
            path = Path(path)
            if str(path).startswith(('/var', '/etc', '/usr', '/run')) or path == Path('/'):
                return self.root / str(path).lstrip('/')
            return path
        def synthetic_stat(path, *args, **kwargs):
            parts = list(original_stat(mapped(path), *args, **kwargs))
            parts[4], parts[5] = 0, 0
            for home, owner in self.owners.items():
                if str(path) == home or str(path).startswith(home + '/'):
                    parts[4], parts[5] = owner
            return os.stat_result(parts)
        patch.object(Path, 'stat', synthetic_stat).start()
        patch.object(Path, 'is_symlink', lambda path: original_link(mapped(path))).start()
        patch.object(Path, 'read_text', lambda path, *args, **kwargs: original_read(mapped(path), *args, **kwargs)).start()
        patch.object(check.configparser.ConfigParser, 'read', lambda parser, path: original_config_read(parser, mapped(path))).start()
        patch.object(os, 'access', lambda path, mode: original_access(mapped(path), mode)).start()
        patch.object(check.pwd, 'getpwnam', side_effect=lambda name: self.accounts[name]).start()
        patch.object(check.grp, 'getgrnam', side_effect=self.group_record).start()
        self.addCleanup(patch.stopall)

    def test_complete_offline_pair_with_real_private_file_checks(self):
        pair.verify()
        self.assertFalse((self.root / 'run').exists())

    def test_gateway_home_state_root_env_and_browser_home_permissions_fail_closed(self):
        pair.verify()
        directories = ('var/lib/instagram-gateway-hub2you', 'var/lib/instagram-gateway-hub2you/gateway',
                       'var/lib/instagram-hub2you')
        for relative in directories:
            path = self.root / relative
            for mode in (0o710, 0o750, 0o770):
                path.chmod(mode)
                with self.subTest(path=relative, mode=oct(mode)), self.assertRaises(ValueError):
                    pair.verify()
                path.chmod(0o700)
        gateway_home = '/var/lib/instagram-gateway-hub2you'
        original = self.owners[gateway_home]
        for bad in ((self.accounts['ig-hub2you'].pw_uid, original[1]), (original[0], 801)):
            self.owners[gateway_home] = bad
            with self.subTest(owner=bad), self.assertRaises(ValueError):
                pair.verify()
        self.owners[gateway_home] = original
        self.owners['/etc/instagram-meta/hub2you/gateway.env'] = (0, 801)
        with self.assertRaises(ValueError):
            pair.verify()
        del self.owners['/etc/instagram-meta/hub2you/gateway.env']
        state = self.root / 'var/lib/instagram-gateway-hub2you/gateway'
        state.rmdir()
        state.symlink_to(self.root)
        with self.assertRaises(ValueError):
            pair.verify()

    def test_runtime_real_permission_checks_all_roles_wrong_owner_gid_mode_or_symlink(self):
        stack = 'hub2you'
        browser = self.accounts['ig-hub2you']
        publisher = self.accounts['igpub-hub2you']
        viewer_gid = self.group_record('igview-hub2you').gr_gid
        for relative, owner in (('/run/instagram-hub2you', (browser.pw_uid, viewer_gid)),
                                ('/run/instagram-publisher-hub2you', (publisher.pw_uid, browser.pw_gid))):
            directory = self.root / relative.lstrip('/')
            directory.mkdir(parents=True, mode=0o710)
            directory.chmod(0o710)
            self.owners[relative] = owner
        for role in pair.ALLOWED:
            prefix = {'publisher': 'igpub', 'gateway': 'iggw'}.get(role, 'ig')
            record = self.accounts[f'{prefix}-{stack}']
            gid = viewer_gid if role == 'display' else (record.pw_gid if role == 'gateway' else browser.pw_gid)
            groups = {gid} | (set() if role == 'publisher' else {viewer_gid})
            values = pair.read_literals(Path(f'/etc/instagram-meta/{stack}/{role}.env'), role)
            check.check_process(stack, role, values, record.pw_uid, gid, groups)
            relative = '/run/instagram-publisher-hub2you' if role == 'publisher' else '/run/instagram-hub2you'
            directory = self.root / relative.lstrip('/')
            for mode in (0o700, 0o711, 0o750, 0o770, 0o755):
                directory.chmod(mode)
                with self.subTest(role=role, mode=oct(mode)), self.assertRaises(ValueError):
                    check.check_process(stack, role, values, record.pw_uid, gid, groups)
            directory.chmod(0o710)
            original_owner = self.owners[relative]
            for owner in ((0, original_owner[1]), (original_owner[0], 0), (original_owner[0], 9999)):
                self.owners[relative] = owner
                with self.subTest(role=role, owner=owner), self.assertRaises(ValueError):
                    check.check_process(stack, role, values, record.pw_uid, gid, groups)
            self.owners[relative] = original_owner
        runtime = self.root / 'run/instagram-hub2you'
        runtime.rmdir()
        runtime.symlink_to(self.root)
        values = pair.read_literals(Path('/etc/instagram-meta/hub2you/gateway.env'), 'gateway')
        gateway = self.accounts['iggw-hub2you']
        with self.assertRaises(ValueError):
            check.check_process(stack, 'gateway', values, gateway.pw_uid, gateway.pw_gid, {gateway.pw_gid, viewer_gid})

    def test_untrusted_or_symlink_root_parent_fails_closed(self):
        directory = self.root / 'var/lib'
        directory.chmod(0o777)
        with self.assertRaises(ValueError):
            pair.verify()
        directory.chmod(0o755)
        self.owners['/var/lib'] = (self.accounts['ig-hub2you'].pw_uid, 201)
        with self.assertRaises(ValueError):
            pair.verify()
        del self.owners['/var/lib']
        directory.rename(directory.with_name('lib-preserved'))
        directory.symlink_to(directory.with_name('lib-preserved'))
        with self.assertRaises(ValueError):
            pair.verify()

    def test_publisher_key_config_home_and_env_modes_fail_closed(self):
        pair.verify()
        files = ('var/lib/instagram-publisher-hub2you/publisher/id_ed25519',
                 'var/lib/instagram-publisher-hub2you/publisher/aws-config',
                 'etc/instagram-meta/hub2you/publisher.env')
        directories = ('var/lib/instagram-publisher-hub2you', 'var/lib/instagram-publisher-hub2you/publisher',
                       'etc/instagram-meta/hub2you')
        for relative in (*files, *directories):
            path = self.root / relative
            correct = 0o600 if relative in files else 0o700
            for mode in (0o644, 0o660) if relative in files else (0o710, 0o750):
                path.chmod(mode)
                with self.subTest(path=relative, mode=oct(mode)), self.assertRaises(ValueError):
                    pair.verify()
                path.chmod(correct)
        for home in ('/var/lib/instagram-publisher-hub2you', '/var/lib/instagram-publisher-autonomia'):
            previous = self.owners[home]
            self.owners[home] = (self.accounts['ig-hub2you'].pw_uid, previous[1])
            with self.subTest(home=home), self.assertRaises(ValueError):
                pair.verify()
            self.owners[home] = previous

    def test_publisher_key_symlink_or_empty_preserved_but_refused(self):
        key = self.root / 'var/lib/instagram-publisher-hub2you/publisher/id_ed25519'
        original = key.read_bytes()
        key.write_bytes(b'')
        with self.assertRaises(ValueError):
            pair.verify()
        self.assertEqual(key.read_bytes(), b'')
        key.unlink()
        target = self.root / 'synthetic-key-target'
        target.write_bytes(original)
        target.chmod(0o600)
        key.symlink_to(target)
        with self.assertRaises(ValueError):
            pair.verify()
        self.assertTrue(key.is_symlink())
        self.assertEqual(target.read_bytes(), original)


class ArtifactTests(unittest.TestCase):
    def test_publisher_systemd_socket_boundary_network_and_manager_dependency(self):
        publisher = (VPS / 'systemd/instagram-vps-publisher@.service').read_text()
        settings = {}
        for line in publisher.splitlines():
            if '=' in line and not line.startswith('#'):
                key, _, value = line.partition('=')
                settings.setdefault(key, []).append(value)
        for key, value in {
            'User': 'igpub-%i', 'Group': 'ig-%i', 'EnvironmentFile': '/etc/instagram-meta/%i/publisher.env',
            'RuntimeDirectory': 'instagram-publisher-%i', 'RuntimeDirectoryMode': '0710', 'UMask': '0007',
            'ExecStart': '/usr/bin/node /opt/instagram-meta/current/scripts/instagram_testers/runtime/vps/publisher-broker.mjs',
            'ExecStartPre': '/usr/bin/python3 /opt/instagram-meta/current/scripts/instagram_testers/runtime/vps/env/check.py %i publisher',
            'After': 'network-online.target', 'Requires': 'network-online.target',
            'ReadWritePaths': '/run/instagram-publisher-%i', 'RestrictAddressFamilies': 'AF_UNIX AF_INET AF_INET6',
            'StandardOutput': 'null', 'StandardError': 'null', 'KillMode': 'control-group',
            'PrivateTmp': 'true', 'ProtectSystem': 'strict', 'ProtectHome': 'true',
            'NoNewPrivileges': 'true', 'CapabilityBoundingSet': ''}.items():
            self.assertEqual(settings[key], [value])
        self.assertIn('/var/lib/instagram-hub2you /var/lib/instagram-autonomia', settings['InaccessiblePaths'])
        for key in ('RuntimeDirectoryPreserve', 'ExecStopPost', 'ListenStream', 'SocketMode', 'SupplementaryGroups'):
            self.assertNotIn(key, settings)
        for role in ('display', 'manager', 'gateway'):
            unit = (VPS / f'systemd/instagram-vps-{role}@.service').read_text()
            self.assertIn('InaccessiblePaths=/var/lib/instagram-publisher-hub2you /var/lib/instagram-publisher-autonomia', unit)
            self.assertNotIn('publisher.env', unit)
        manager = (VPS / 'systemd/instagram-vps-manager@.service').read_text()
        self.assertIn('Requires=instagram-vps-display@%i.service instagram-vps-publisher@%i.service', manager)
        self.assertIn('After=network-online.target instagram-vps-display@%i.service instagram-vps-publisher@%i.service', manager)
        wrapper = (VPS / 'install/manager.sh').read_text()
        self.assertIn('$root/runtime/vps/publisher-client.mjs', wrapper)
        for prohibited in ('publisher-tunnel.mjs', 'AWS_', 'SSH_KEY', 'HOST_KEY_DOCUMENT'):
            self.assertNotIn(prohibited, wrapper)
        for stack in check.STACKS:
            values = (VPS / f'env/{stack}.publisher.env.example').read_text()
            self.assertIn(f'INSTAGRAM_TESTER_PUBLISHER_SOCKET=/run/instagram-publisher-{stack}/publisher.sock', values)
            self.assertIn(f'HOME=/var/lib/instagram-publisher-{stack}', values)
            self.assertIn(f'INSTAGRAM_TESTER_PUBLISHER_SSH_KEY=/var/lib/instagram-publisher-{stack}/publisher/id_ed25519', values)
            self.assertIn('INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT=ChatwootInstagramPublisherHostKey', values)

    def test_units_use_separate_uid_private_unix_vnc_and_chrome_sandbox_compatible_tmp(self):
        units = {role: (VPS / f'systemd/instagram-vps-{role}@.service').read_text()
                 for role in ('display', 'manager', 'gateway')}
        for body in units.values():
            for required in ('UMask=0077', 'PrivateTmp=true',
                             'ProtectSystem=strict', 'NoNewPrivileges=true', 'KillMode=control-group'):
                self.assertIn(required, body)
            for prohibited in ('ExecStopPost=', 'rm ', 'redis-cli', 'docker', 'websockify', 'x11vnc', 'sudo'):
                self.assertNotIn(prohibited, body)
        for required in ('/usr/bin/Xtigervnc', '-rfbport -1', '-rfbunixmode 0660',
                         '-rfbunixpath /run/instagram-%i/vnc.sock', '-nolisten tcp', '-auth ${XAUTHORITY}'):
            self.assertIn(required, units['display'])
        self.assertIn('JoinsNamespaceOf=instagram-vps-display@%i.service', units['manager'])
        self.assertIn('IPAddressDeny=any', units['gateway'])
        self.assertIn('IPAddressAllow=localhost', units['gateway'])
        self.assertIn('InaccessiblePaths=/var/lib/instagram-%i/profile /var/lib/instagram-%i/.Xauthority', units['gateway'])
        self.assertNotIn('RestrictNamespaces=', units['manager'])

    def test_gateway_uid_viewer_boundary_and_private_homes_match_units(self):
        units = {}
        for role in ('display', 'manager', 'gateway', 'publisher'):
            settings = {}
            for line in (VPS / f'systemd/instagram-vps-{role}@.service').read_text().splitlines():
                if '=' in line and not line.startswith('#'):
                    key, _, value = line.partition('=')
                    settings.setdefault(key, []).append(value)
            units[role] = settings
        for role, user, group, supplementary in (('display', 'ig-%i', 'igview-%i', []),
                                                ('manager', 'ig-%i', 'ig-%i', ['igview-%i']),
                                                ('gateway', 'iggw-%i', 'iggw-%i', ['igview-%i']),
                                                ('publisher', 'igpub-%i', 'ig-%i', [])):
            settings = units[role]
            self.assertEqual(settings['User'], [user])
            self.assertEqual(settings['Group'], [group])
            self.assertEqual(settings.get('SupplementaryGroups', []), supplementary)
        self.assertEqual(units['display']['RuntimeDirectoryMode'], ['0710'])
        self.assertIn('-rfbunixmode 0660', units['display']['ExecStart'][0])
        self.assertEqual(units['gateway']['ReadWritePaths'], ['/var/lib/instagram-gateway-%i/gateway'])
        for role in ('display', 'manager', 'publisher'):
            self.assertIn('/var/lib/instagram-gateway-hub2you /var/lib/instagram-gateway-autonomia',
                          units[role]['InaccessiblePaths'])
        for role in units:
            self.assertNotIn('browser-request.json', ' '.join(units[role].get('ExecStartPre', [])))

    def test_ssm_document_fixed_no_parameters_no_secret_read(self):
        document = json.loads((VPS / 'iam/ssm-publisher-host-key-document.json').read_text())
        self.assertEqual(document['parameters'], {})
        self.assertEqual(len(document['mainSteps']), 1)
        self.assertEqual(document['mainSteps'][0]['inputs']['runCommand'],
                         ['/usr/bin/cat /etc/ssh/ssh_host_ed25519_key.pub'])

    def test_iam_minimal_actions_no_invented_identity_and_only_required_wildcard(self):
        document = json.loads((VPS / 'iam/publisher-policy.template.json').read_text())
        actions = {action for s in document['Statement'] for action in (s['Action'] if isinstance(s['Action'], list) else [s['Action']])}
        self.assertEqual(actions, {'ssm:GetParameter', 'ssm:SendCommand', 'ssm:StartSession',
                                  'ssm:ListCommandInvocations', 'ssm:TerminateSession', 'ssmmessages:OpenDataChannel'})
        for statement in document['Statement']:
            self.assertEqual(statement['Effect'], 'Allow')
            if statement['Resource'] == '*':
                self.assertEqual(statement['Action'], 'ssm:ListCommandInvocations')
        body = json.dumps(document)
        self.assertNotIn('AWS-RunShellScript', body)
        instances = next(s for s in document['Statement'] if s['Sid'] == 'TaggedChatwootBlueGreenInstances')
        self.assertEqual(instances['Resource'], 'arn:aws:ec2:us-east-1:REQUIRED_ACCOUNT_ID:instance/*')
        self.assertEqual(instances['Condition']['StringEquals'], {'ssm:resourceTag/Project': 'chatwoot-autonomia',
                         'ssm:resourceTag/Environment': 'prod', 'ssm:resourceTag/ManagedBy': 'github-actions'})
        self.assertEqual(instances['Condition']['StringLike'], {'ssm:resourceTag/Name': 'REQUIRED_STACK_INSTANCE_NAME_PATTERN'})
        self.assertNotIn('REQUIRED_APPROVED_INSTANCE_ID', body)
        for file in ('deploy-hub2you-blue-green.yml', 'deploy-autonomia-blue-green.yml'):
            workflow = (ROOT / '.github/workflows' / file).read_text()
            for key, value in (('Project', 'chatwoot-autonomia'), ('Environment', 'prod'), ('ManagedBy', 'github-actions')):
                self.assertIn('Key=' + key + ',Value=' + value, workflow)
        self.assertIn('REQUIRED_APPROVED_PRINCIPAL_SESSION_ARN_PATTERN', body)

    def test_iam_docs_match_current_template_selector(self):
        template = (VPS / 'iam/publisher-policy.template.json').read_text()
        placeholders = ('REQUIRED_ACCOUNT_ID', 'REQUIRED_STACK_INSTANCE_NAME_PATTERN',
                        'REQUIRED_APPROVED_PRINCIPAL_SESSION_ARN_PATTERN')
        for path in (VPS / 'iam/README.md', ROOT / 'docs/runbooks/instagram-vps-runtime-995.md'):
            with self.subTest(path=path.relative_to(ROOT)):
                body = path.read_text()
                for placeholder in placeholders:
                    self.assertIn(placeholder, template)
                    self.assertIn(placeholder, body)
                self.assertNotIn('REQUIRED_APPROVED_INSTANCE_ID', body)
                self.assertIn('instance/*', body)
                for stack in installer.STACKS:
                    self.assertIn(f'chatwoot-{stack}-prod-ec2-green-*', body)
                    workflow = (ROOT / f'.github/workflows/deploy-{stack}-blue-green.yml').read_text()
                    self.assertIn(f'Key=Name,Value=chatwoot-{stack}-prod-ec2-green-', workflow)

    def test_shell_syntax_and_cli_reject_without_operational_execution(self):
        result = subprocess.run(['/bin/sh', '-n', str(VPS / 'install/manager.sh')],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        # Missing arguments fail before any operational call, regardless of platform/UID.
        result = subprocess.run([sys.executable, '-B', str(VPS / 'install/install.py')],
                                capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr.strip(), 'instagram_vps_install_failed')
        self.assertEqual(result.stdout, '')
        for name, failure in (('env/check.py', 'instagram_vps_preflight_failed'),
                              ('env/verify-pair.py', 'instagram_vps_env_pair_failed')):
            args = ['invalid-stack', 'publisher'] if name == 'env/check.py' else ['invalid-argument']
            result = subprocess.run([sys.executable, '-B', str(VPS / name), *args],
                                    capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stderr.strip(), failure)
            self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main(verbosity=2)
