#!/usr/bin/env python3
"""Validate SSM envelopes and Docker env literals without evaluating shell code."""
import ipaddress
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit


def read_env(path):
    values = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        key, separator, value = line.partition('=')
        valid_key = (key and key[0] in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
                     and all(char in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_' for char in key))
        if not separator or not valid_key or key in values:
            raise ValueError('invalid env')
        values[key] = value
    return values


def validate(stage, app):
    files = {'ssh-key': ('SecureString', 'ssh.key'), 'redis-env': ('SecureString', 'redis.env'),
             'ca': ('String', 'ca.crt'), 'known-hosts': ('String', 'known_hosts')}
    for parameter, (expected_type, filename) in files.items():
        envelope = json.loads((stage / f'{parameter}.json').read_text())['Parameter']
        value = envelope['Value']
        if envelope['Type'] != expected_type or not isinstance(value, str) or not value.strip() or '\x00' in value:
            raise ValueError('invalid parameter')
        (stage / filename).write_text(value.rstrip('\n') + '\n')

    dedicated = read_env(stage / 'redis.env')
    allowed = {'INSTAGRAM_TESTER_COORDINATION_REDIS_URL', 'INSTAGRAM_TESTER_COORDINATION_EPOCH',
               'INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE', 'INSTAGRAM_TESTER_PROXY_IDENTITY'}
    if dedicated.keys() - allowed:
        raise ValueError('invalid coordination keys')
    redis = urlsplit(dedicated['INSTAGRAM_TESTER_COORDINATION_REDIS_URL'])
    if (redis.scheme != 'rediss' or redis.hostname != 'ig-coord.internal' or redis.port != 16381
            or not redis.password or redis.path != '/0' or redis.query or redis.fragment):
        raise ValueError('invalid coordination endpoint')
    effective = read_env(app / '.env') | read_env(app / 'instagram-tester.env') | dedicated
    host = effective['INSTAGRAM_TESTER_PROXY_HOST']
    port = effective['INSTAGRAM_TESTER_PROXY_PORT']
    address = ipaddress.IPv4Address(host)
    if (str(address) != host or not address.is_global or (not port or any(char not in '0123456789' for char in port) or str(int(port)) != port)
            or not 1 <= int(port) <= 65535 or effective['INSTAGRAM_TESTER_PROXY_AUTH_MODE'] != 'ip'
            or effective.get('INSTAGRAM_TESTER_PROXY_USERNAME') or effective.get('INSTAGRAM_TESTER_PROXY_PASSWORD')):
        raise ValueError('invalid direct proxy')
    identity = f'{host}:{int(port)}'
    # Validate every explicit source, including one overridden by dedicated env.
    for source in (read_env(app / '.env'), read_env(app / 'instagram-tester.env'), dedicated):
        if 'INSTAGRAM_TESTER_PROXY_IDENTITY' in source and source['INSTAGRAM_TESTER_PROXY_IDENTITY'] != identity:
            raise ValueError('divergent proxy identity')
    epoch = effective.get('INSTAGRAM_TESTER_COORDINATION_EPOCH', '')
    if not 16 <= len(epoch) <= 128 or any(char not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-' for char in epoch):
        raise ValueError('missing or invalid epoch')
    ca_path = '/run/igcoord/ca.crt'
    if dedicated.get('INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE', ca_path) != ca_path:
        raise ValueError('invalid CA path')
    dedicated.update({
        'INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE': ca_path,
        'INSTAGRAM_TESTER_COORDINATION_EPOCH': effective['INSTAGRAM_TESTER_COORDINATION_EPOCH'],
        'INSTAGRAM_TESTER_PROXY_IDENTITY': identity,
        'INSTAGRAM_TESTER_PROXY_HOST': 'ig-proxy.internal',
        'INSTAGRAM_TESTER_PROXY_PORT': '16380',
        'INSTAGRAM_TESTER_PROXY_AUTH_MODE': 'ip',
    })
    (stage / 'redis.env').write_text(''.join(f'{key}={value}\n' for key, value in dedicated.items()))
    # Only the already validated public destination is transported to ssh.
    (stage / 'tunnel.env').write_text(f'{host}\n{port}\n')


if __name__ == '__main__':
    try:
        validate(Path(sys.argv[1]), Path(sys.argv[2]))
    except (ValueError, KeyError, TypeError, OSError, IndexError):
        sys.exit('instagram_coordination_env_invalid')
