#!/usr/bin/env python3
"""Root-only, offline activation gate for both stacks; prints no values."""
import os
import configparser
from pathlib import Path
import sys

from check import STACKS, private_path, require, service_accounts, validate


COMMON = {'INSTAGRAM_TESTER_RUNTIME_STACK'}
DISPLAY = COMMON | {'DISPLAY', 'XAUTHORITY'}
MANAGER = DISPLAY | {
    'HOME', 'PATH', 'INSTAGRAM_TESTER_RUNTIME_MODE', 'INSTAGRAM_TESTER_CHROMIUM_SANDBOX', 'INSTAGRAM_TESTER_BROWSER_PROFILE',
    'INSTAGRAM_TESTER_PLAYWRIGHT_MODULE', 'INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE',
    'INSTAGRAM_TESTER_PROXY_HOST', 'INSTAGRAM_TESTER_PROXY_PORT', 'INSTAGRAM_TESTER_PROXY_AUTH_MODE',
    'INSTAGRAM_TESTER_PUBLISHER_SOCKET',
}
PUBLISHER = COMMON | {
    'HOME', 'PATH', 'INSTAGRAM_TESTER_PUBLISHER_SOCKET',
    'INSTAGRAM_TESTER_PUBLISHER_SSH_KEY', 'INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT',
    'AWS_CONFIG_FILE', 'AWS_SHARED_CREDENTIALS_FILE', 'AWS_EC2_METADATA_DISABLED', 'AWS_PAGER',
}
GATEWAY = COMMON | {
    'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL', 'INSTAGRAM_TESTER_OPERATOR_ISSUER',
    'INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY', 'INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE',
    'INSTAGRAM_TESTER_VNC_SOCKET', 'INSTAGRAM_TESTER_GATEWAY_PORT', 'INSTAGRAM_TESTER_GATEWAY_STATE_DIR',
}
ALLOWED = {'display': DISPLAY, 'manager': MANAGER, 'gateway': GATEWAY, 'publisher': PUBLISHER}
OPTIONAL = {'manager': {
    'INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED',
    'INSTAGRAM_TESTER_SEARCH_STATUS_ENABLED',
    'INSTAGRAM_TESTER_WARM_INVITE_ENABLED',
}}


def read_literals(path, role):
    values = {}
    optional = OPTIONAL.get(role, set())
    for line in path.read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        key, separator, value = line.partition('=')
        require(separator and key in ALLOWED[role] | optional and key not in values)
        # This is intentionally a strict subset of systemd EnvironmentFile syntax.
        require(not any(c.isspace() or ord(c) < 32 or c in '\\"\'' for c in value))
        require('REQUIRED_' not in value)
        values[key] = value
    require(values.keys() - optional == ALLOWED[role])
    return values


def verify():
    keys = []
    accounts, _ = service_accounts()
    for stack in STACKS:
        for role in ALLOWED:
            prefix = {'publisher': 'igpub', 'gateway': 'iggw'}.get(role, 'ig')
            record = accounts[f'{prefix}-{stack}']
            path = Path(f'/etc/instagram-meta/{stack}/{role}.env')
            private_path(path.parent, 0, 0o700, directory=True, gid=0)
            private_path(path, 0, 0o600, gid=0)
            values = read_literals(path, role)
            validate(stack, role, values, record.pw_uid, record.pw_gid)
            if role == 'gateway':
                keys.append(bytes.fromhex(values['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY']))
    require(keys[0] != keys[1])


if __name__ == '__main__':
    try:
        require(os.geteuid() == 0 and len(sys.argv) == 1)
        verify()
        print('instagram_vps_env_pair_ok')
    except (ValueError, KeyError, TypeError, OSError, configparser.Error):
        sys.exit('instagram_vps_env_pair_failed')
