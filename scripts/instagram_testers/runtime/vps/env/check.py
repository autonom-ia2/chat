#!/usr/bin/env python3
"""Offline, strict process-boundary checks. Never print environment values."""
import configparser
import grp
import os
from pathlib import Path
import pwd
import shlex
import stat
import sys
from urllib.parse import urlsplit

RELEASE = '/opt/instagram-meta/current/scripts/instagram_testers/runtime/vps'
STACKS = {'hub2you': (':91', '18441', 'hub2you'), 'autonomia': (':92', '18442', 'financial')}
HEX = '0123456789abcdefABCDEF'


def require(condition):
    if not condition:
        raise ValueError('invalid runtime')


def private_path(path, uid, mode, directory=False, gid=None):
    path = Path(path)
    for ancestor in (path, *path.parents):
        require(not ancestor.is_symlink())
    for ancestor in path.parents:
        info = ancestor.stat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid in (0, uid) and not info.st_mode & 0o022)
        if str(ancestor) in ('/', '/var', '/var/lib', '/run', '/etc', '/etc/instagram-meta'):
            require(info.st_uid == 0)
    info = path.stat()
    require(info.st_uid == uid and stat.S_IMODE(info.st_mode) == mode)
    require(gid is None or info.st_gid == gid)
    require(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode))
    require(directory or info.st_size > 0)


def origin(value):
    parsed = urlsplit(value)
    require(parsed.scheme == 'https' and parsed.hostname and parsed.username is None
            and parsed.password is None and not parsed.query and not parsed.fragment)
    require(parsed.port in (None, 443) and parsed.path in ('', '/'))
    require(value == f'https://{parsed.hostname}')
    return value


def root_executable(path):
    path = Path(path)
    require(path.is_absolute() and path.is_file() and os.access(path, os.X_OK))
    for entry in (path, *path.parents):
        require(not entry.is_symlink())
        info = entry.stat()
        require(info.st_uid == 0 and not info.st_mode & 0o022)


def validate(stack, role, env, uid, gid=None):
    require(stack in STACKS and role in ('display', 'manager', 'gateway', 'publisher'))
    display, port, profile = STACKS[stack]
    prefix = {'publisher': 'instagram-publisher', 'gateway': 'instagram-gateway'}.get(role, 'instagram')
    home = f'/var/lib/{prefix}-{stack}'
    runtime = f'/run/instagram-{stack}'
    require(env['INSTAGRAM_TESTER_RUNTIME_STACK'] == stack)
    private_path(home, uid, 0o700, directory=True, gid=gid)
    socket = f'/run/instagram-publisher-{stack}/publisher.sock'
    if role in ('display', 'manager', 'gateway'):
        require(not any(name.startswith('AWS_') or (name.startswith('INSTAGRAM_TESTER_PUBLISHER_')
                        and not (role == 'manager' and name == 'INSTAGRAM_TESTER_PUBLISHER_SOCKET')) for name in env))
        legacy = Path(f'{home}/publisher')
        require(not legacy.exists() and not legacy.is_symlink())
    if role in ('display', 'manager'):
        require(env['DISPLAY'] == display and env['XAUTHORITY'] == f'{home}/.Xauthority')
        private_path(env['XAUTHORITY'], uid, 0o600)
    if role == 'manager':
        require(env.get('INSTAGRAM_TESTER_RUNTIME_MODE') == 'vps')
        require(env.get('INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED', 'false') in ('true', 'false'))
        require(env.get('PATH') == '/usr/local/bin:/usr/bin:/bin')
        require(env['HOME'] == home and env['INSTAGRAM_TESTER_CHROMIUM_SANDBOX'] == 'true')
        require(env['INSTAGRAM_TESTER_BROWSER_PROFILE'] == f'{home}/profile')
        require(env['INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE'] == f'{runtime}/browser-request.json')
        require(env['INSTAGRAM_TESTER_PLAYWRIGHT_MODULE'] == f'{RELEASE}/node_modules/playwright/index.mjs')
        private_path(env['INSTAGRAM_TESTER_BROWSER_PROFILE'], uid, 0o700, directory=True)
        require(env['INSTAGRAM_TESTER_PROXY_AUTH_MODE'] == 'ip')
        host = env['INSTAGRAM_TESTER_PROXY_HOST']
        require(host and all(c in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-' for c in host))
        proxy_port = env['INSTAGRAM_TESTER_PROXY_PORT']
        require(proxy_port.isascii() and proxy_port.isdecimal() and str(int(proxy_port)) == proxy_port
                and 1 <= int(proxy_port) <= 65535)
        require(not env.get('INSTAGRAM_TESTER_PROXY_USERNAME') and not env.get('INSTAGRAM_TESTER_PROXY_PASSWORD'))
        require(env['INSTAGRAM_TESTER_PUBLISHER_SOCKET'] == socket)
    if role == 'publisher':
        require(env['HOME'] == home and env.get('PATH') == '/usr/local/bin:/usr/bin:/bin')
        require(env['INSTAGRAM_TESTER_PUBLISHER_SOCKET'] == socket)
        private_path(f'{home}/publisher', uid, 0o700, directory=True, gid=gid)
        require(env['INSTAGRAM_TESTER_PUBLISHER_SSH_KEY'] == f'{home}/publisher/id_ed25519')
        private_path(env['INSTAGRAM_TESTER_PUBLISHER_SSH_KEY'], uid, 0o600)
        require(env['AWS_CONFIG_FILE'] == f'{home}/publisher/aws-config')
        require(env['AWS_SHARED_CREDENTIALS_FILE'] == '/dev/null' and env['AWS_EC2_METADATA_DISABLED'] == 'true')
        require(env['AWS_PAGER'] == '')
        private_path(env['AWS_CONFIG_FILE'], uid, 0o600)
        require(not any((name.startswith('AWS_') and name not in (
            'AWS_CONFIG_FILE', 'AWS_SHARED_CREDENTIALS_FILE', 'AWS_EC2_METADATA_DISABLED', 'AWS_PAGER'))
            or (name.startswith('INSTAGRAM_TESTER_PUBLISHER_') and name not in (
                'INSTAGRAM_TESTER_PUBLISHER_SOCKET', 'INSTAGRAM_TESTER_PUBLISHER_SSH_KEY',
                'INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT'))
            or name.startswith('INSTAGRAM_TESTER_PROXY_') or name in (
                'DISPLAY', 'XAUTHORITY', 'INSTAGRAM_TESTER_BROWSER_PROFILE',
                'INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY') for name in env))
        config = configparser.ConfigParser(interpolation=None)
        config.read(env['AWS_CONFIG_FILE'])
        require(config.sections() == [f'profile {profile}'])
        values = dict(config[f'profile {profile}'])
        require(values.keys() == {'region', 'credential_process'} and values['region'] == 'us-east-1')
        require(values['credential_process'] and 'REQUIRED_' not in values['credential_process'])
        helper = shlex.split(values['credential_process'])
        require(helper)
        root_executable(helper[0])
        # The helper/principal must be provisioned separately. Never call it here.
        require(env['INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT'] == 'ChatwootInstagramPublisherHostKey')
    if role == 'gateway':
        require(env['INSTAGRAM_TESTER_GATEWAY_PORT'] == port)
        require(env['INSTAGRAM_TESTER_VNC_SOCKET'] == f'{runtime}/vnc.sock')
        require(env['INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE'] == f'{runtime}/browser-request.json')
        require(env['INSTAGRAM_TESTER_GATEWAY_STATE_DIR'] == f'{home}/gateway')
        private_path(env['INSTAGRAM_TESTER_GATEWAY_STATE_DIR'], uid, 0o700, directory=True, gid=gid)
        key = env['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY']
        require(len(key) >= 64 and len(key) % 2 == 0 and all(c in HEX for c in key))
        require('REQUIRED_' not in key)
        browser = urlsplit(env['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL'])
        require(browser.path == f'/{stack}/')
        origin(env['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL'].removesuffix(f'/{stack}/'))
        origin(env['INSTAGRAM_TESTER_OPERATOR_ISSUER'])
        require(not any(name.startswith('INSTAGRAM_TESTER_PROXY_') for name in env))
    require(not any(env.get(name) for name in ('DEBUG', 'PWDEBUG', 'NODE_OPTIONS')))


def service_accounts():
    accounts = {f'{prefix}-{stack}': pwd.getpwnam(f'{prefix}-{stack}')
                for stack in STACKS for prefix in ('ig', 'igpub', 'iggw')}
    require(len({record.pw_uid for record in accounts.values()}) == 6)
    gids = {record.pw_gid for record in accounts.values()}
    require(len(gids) == 6 and 0 not in gids)
    viewers = {}
    for stack in STACKS:
        viewer = grp.getgrnam(f'igview-{stack}')
        require(viewer.gr_gid != 0 and viewer.gr_gid not in gids)
        require(set(viewer.gr_mem) == {f'ig-{stack}', f'iggw-{stack}'})
        viewers[stack] = viewer.gr_gid
        gids.add(viewer.gr_gid)
    for name, record in accounts.items():
        prefix, stack = name.split('-')
        home_prefix = {'ig': 'instagram', 'igpub': 'instagram-publisher', 'iggw': 'instagram-gateway'}[prefix]
        primary = grp.getgrnam(name)
        require(record.pw_uid != 0 and record.pw_dir == f'/var/lib/{home_prefix}-{stack}'
                and record.pw_shell == '/usr/sbin/nologin' and primary.gr_gid == record.pw_gid and not primary.gr_mem)
        expected = {record.pw_gid} if prefix == 'igpub' else {record.pw_gid, viewers[stack]}
        require(set(os.getgrouplist(name, record.pw_gid)) == expected)
    for record in pwd.getpwall():
        for name, service in accounts.items():
            if record.pw_uid == service.pw_uid or record.pw_gid == service.pw_gid:
                require(record.pw_name == name)
        require(record.pw_gid not in viewers.values())
    named_gids = {record.pw_gid: name for name, record in accounts.items()}
    named_gids.update({gid: f'igview-{stack}' for stack, gid in viewers.items()})
    for group in grp.getgrall():
        if group.gr_gid in named_gids:
            require(group.gr_name == named_gids[group.gr_gid])
    return accounts, viewers


def check_process(stack, role, env, uid, gid, groups=None):
    require(stack in STACKS and role in ('display', 'manager', 'gateway', 'publisher'))
    accounts, viewers = service_accounts()
    prefix = {'publisher': 'igpub', 'gateway': 'iggw'}.get(role, 'ig')
    record = accounts[f'{prefix}-{stack}']
    browser = accounts[f'ig-{stack}']
    primary_gid = viewers[stack] if role == 'display' else (
        record.pw_gid if role == 'gateway' else browser.pw_gid)
    # Match initgroups with the unit's effective primary GID, including explicit viewer membership.
    expected_groups = set(os.getgrouplist(f'{prefix}-{stack}', primary_gid))
    require(uid == record.pw_uid and gid == primary_gid)
    require(set(os.getgroups() if groups is None else groups) | {gid} == expected_groups)
    validate(stack, role, env, uid, record.pw_gid)
    # systemd creates these ephemeral directories; never create or bind a socket here.
    runtime = f'/run/instagram-publisher-{stack}' if role == 'publisher' else f'/run/instagram-{stack}'
    runtime_uid = uid if role == 'publisher' else browser.pw_uid
    runtime_gid = browser.pw_gid if role == 'publisher' else viewers[stack]
    private_path(runtime, runtime_uid, 0o710, directory=True, gid=runtime_gid)
    if role == 'gateway':
        private_path(f'/var/lib/instagram-{stack}', browser.pw_uid, 0o700, directory=True, gid=browser.pw_gid)


if __name__ == '__main__':
    try:
        require(len(sys.argv) == 3)
        check_process(*sys.argv[1:], os.environ, os.getuid(), os.getgid())
    except (ValueError, KeyError, TypeError, OSError, configparser.Error):
        sys.exit('instagram_vps_preflight_failed')
