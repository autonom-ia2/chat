#!/usr/bin/env python3
"""Human-operated, create-only coordination publisher; never log payloads."""
import argparse
import base64
import json
import os
import subprocess
import sys
from urllib.parse import urlsplit

STACKS = (('hub2you', '354307071110', 'ig_hub'), ('financial', '140023375763', 'ig_auto'))
PREFIX = '/chatwoot/prod/instagram-coordination/'
HOST = '85.31.60.100'
TYPES = {'ssh-key': 'SecureString', 'redis-env': 'SecureString', 'ca': 'String', 'known-hosts': 'String'}
CONFIRM = 'PUBLICAR INSTAGRAM 354307071110 140023375763'
SSH = ['ssh', '-o', 'StrictHostKeyChecking=yes', '-o', 'UpdateHostKeys=no', '-o', 'BatchMode=yes',
       '-o', 'ConnectTimeout=10', '-o', 'ForwardAgent=no', '-o', 'ClearAllForwardings=yes']
REMOTE = r'''
import json, os, stat, subprocess, sys
paths = {name: '/opt/instagram-coordination/private/' + name for name in
         ('ig_hub.key', 'ig_auto.key', 'ig_hub.env', 'ig_auto.env')}
paths.update({'ca': '/opt/instagram-coordination/tls/ca.crt',
              'host': '/etc/ssh/ssh_host_ed25519_key.pub'})
try:
    if not __debug__:
        raise ValueError()
    redis_user = subprocess.run(['docker', 'inspect', '--format', '{{.Config.User}}',
                                 'instagram-coordination-redis'], check=True, capture_output=True,
                                text=True, timeout=10).stdout.strip().split(':')
    if len(redis_user) != 2 or any(not v.isascii() or not v.isdecimal() for v in redis_user):
        raise ValueError()
    redis_uid = int(redis_user[0])
    result = {}
    for name, path in paths.items():
        parent = os.path.dirname(path)
        while True:
            s = os.lstat(parent)
            owners = {0, redis_uid} if parent == '/opt/instagram-coordination/tls' else {0}
            if not stat.S_ISDIR(s.st_mode) or s.st_mode & 0o022 or s.st_uid not in owners:
                raise ValueError()
            if parent == '/':
                break
            parent = os.path.dirname(parent)
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, 'r') as f:
            s = os.fstat(f.fileno())
            if not stat.S_ISREG(s.st_mode) or not 0 < s.st_size <= 4096:
                raise ValueError()
            if s.st_uid not in ({0, redis_uid} if name == 'ca' else {0}):
                raise ValueError()
            if s.st_mode & (0o077 if name.endswith(('.key', '.env')) else 0o022):
                raise ValueError()
            result[name] = f.read(4097) if sys.argv[1] == 'read' else 'metadata-ok'
    print(json.dumps(result))
except Exception:
    sys.exit(1)
'''


CODES = frozenset(('command-failed', 'account-mismatch', 'pem-shape', 'host-mismatch',
                   'source-shape', 'source-value', 'metadata-shape', 'host-key-shape',
                   'env-shape', 'redis-endpoint', 'env-value', 'tty-required', 'consent-required',
                   'existing-type-mismatch', 'existing-mismatch', 'readback-mismatch', 'unsupported-operation'))
STAGE = 'consent'
FAILED_AWS = None
PUT_ATTEMPTED = False

class Failure(ValueError):
    pass


def run(args, payload=None):
    env = dict(os.environ, AWS_PAGER='', AWS_CLI_AUTO_PROMPT='off')
    result = subprocess.run(args, input=payload, text=True, capture_output=True, env=env, timeout=60)
    if result.returncode:
        raise Failure('command-failed')
    return result.stdout


def aws(profile, service, operation, payload):
    global FAILED_AWS, PUT_ATTEMPTED
    if profile not in ('hub2you', 'financial'):
        raise Failure('unsupported-operation')
    stdin = None
    if (service, operation) == ('sts', 'get-caller-identity'):
        options = []
    elif (service, operation) == ('ssm', 'describe-parameters'):
        name = payload['ParameterFilters'][0]['Values'][0]
        options = ['--parameter-filters', 'Key=Name,Option=Equals,Values=' + name]
    elif (service, operation) == ('ssm', 'get-parameter'):
        options = ['--name', payload['Name'], '--with-decryption']
    elif (service, operation) == ('ssm', 'put-parameter'):
        options = ['--name', payload['Name'], '--type', payload['Type'], '--no-overwrite', '--value', 'file:///dev/stdin']
        stdin = payload['Value']
    else:
        raise Failure('unsupported-operation')
    FAILED_AWS = (profile, service, operation)
    if operation == 'put-parameter':
        PUT_ATTEMPTED = True
    result = json.loads(run(['aws', '--profile', profile, '--region', 'us-east-1', '--no-cli-pager',
                             '--no-cli-auto-prompt', service, operation, '--output', 'json'] + options, stdin))
    FAILED_AWS = None
    return result


def identity(profile, account):
    if aws(profile, 'sts', 'get-caller-identity', {}).get('Account') != account:
        raise Failure('account-mismatch')


def validate_pem(value, label):
    lines = value.removesuffix('\n').split('\n')
    if len(lines) < 3 or lines[0] != f'-----BEGIN {label}-----' or lines[-1] != f'-----END {label}-----':
        raise Failure('pem-shape')
    body = ''.join(lines[1:-1])
    if not body or any(not line for line in lines[1:-1]):
        raise Failure('pem-shape')
    if not base64.b64decode(body, validate=True):
        raise Failure('pem-shape')


def valid_hex(value):
    return isinstance(value, str) and len(value) == 64 and all(character in '0123456789abcdef' for character in value)


def source(read):
    config = dict(line.split(' ', 1) for line in run(SSH + ['-G', 'n8n']).splitlines() if ' ' in line)
    if config.get('hostname') != HOST or config.get('port') != '22':
        raise Failure('host-mismatch')
    data = json.loads(run(SSH + ['n8n', 'sudo -n python3 -E - ' + ('read' if read else 'check')], REMOTE))
    expected = {'ig_hub.key', 'ig_auto.key', 'ig_hub.env', 'ig_auto.env', 'ca', 'host'}
    if not isinstance(data, dict) or data.keys() != expected:
        raise Failure('source-shape')
    if any(not isinstance(v, str) or not v or len(v.encode()) > 4096 or '\x00' in v for v in data.values()):
        raise Failure('source-value')
    if not read:
        if set(data.values()) != {'metadata-ok'}:
            raise Failure('metadata-shape')
        return data
    validate_pem(data['ca'], 'CERTIFICATE')
    public = data['host'].strip().split()
    if len(public) not in (2, 3) or public[0] != 'ssh-ed25519':
        raise Failure('host-key-shape')
    decoded = base64.b64decode(public[1], validate=True)
    if len(decoded) != 51 or decoded[:19] != b'\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x20':
        raise Failure('host-key-shape')
    for _, _, user in STACKS:
        validate_pem(data[user + '.key'], 'OPENSSH PRIVATE KEY')
        rows = data[user + '.env'].splitlines()
        values = dict(row.split('=', 1) for row in rows)
        allowed = {'INSTAGRAM_TESTER_COORDINATION_' + k for k in ('REDIS_URL', 'EPOCH', 'REDIS_CA_FILE')}
        if values.keys() != allowed or len(rows) != len(values):
            raise Failure('env-shape')
        url = values['INSTAGRAM_TESTER_COORDINATION_REDIS_URL']
        if any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in url):
            raise Failure('redis-endpoint')
        endpoint = urlsplit(url)
        if (endpoint.scheme != 'rediss' or endpoint.hostname != 'ig-coord.internal' or endpoint.port != 16381
                or endpoint.username != user or not valid_hex(endpoint.password)
                or endpoint.path != '/0' or endpoint.query or endpoint.fragment):
            raise Failure('redis-endpoint')
        if (not valid_hex(values['INSTAGRAM_TESTER_COORDINATION_EPOCH'])
                or values['INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE'] != '/run/igcoord/ca.crt'):
            raise Failure('env-value')
    data['known-hosts'] = HOST + ' ssh-ed25519 ' + public[1] + '\n'
    return data


def main():
    global STAGE, FAILED_AWS, PUT_ATTEMPTED
    STAGE = 'consent'
    FAILED_AWS = None
    PUT_ATTEMPTED = False
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.apply:
        if not sys.stdin.isatty():
            raise Failure('tty-required')
        print('Digite exatamente: ' + CONFIRM, file=sys.stderr)
        if sys.stdin.readline().rstrip('\n') != CONFIRM:
            raise Failure('consent-required')
    STAGE = 'inventory'
    existing = {}
    for profile, account, _ in STACKS:
        identity(profile, account)
        for name, kind in TYPES.items():
            full = PREFIX + name
            rows = aws(profile, 'ssm', 'describe-parameters',
                       {'ParameterFilters': [{'Key': 'Name', 'Option': 'Equals', 'Values': [full]}]})['Parameters']
            if len(rows) > 1 or (rows and (rows[0]['Name'] != full or rows[0]['Type'] != kind)):
                raise Failure('existing-type-mismatch')
            existing[profile, name] = bool(rows)
    STAGE = 'source'
    data = source(args.apply)
    STAGE = 'compare'
    planned = []
    for profile, account, user in STACKS:
        for name, kind in TYPES.items():
            full = PREFIX + name
            if not args.apply:
                print(('existing' if existing[profile, name] else 'missing'), profile, full)
                continue
            value = data[user + ('.key' if name == 'ssh-key' else '.env')] if name in ('ssh-key', 'redis-env') else data[name]
            if existing[profile, name]:
                old = aws(profile, 'ssm', 'get-parameter', {'Name': full, 'WithDecryption': True})['Parameter']
                if old['Name'] != full or old['Type'] != kind or old['Value'] != value:
                    raise Failure('existing-mismatch')
                print('preserved', profile, full)
            else:
                planned.append((profile, account, full, kind, value))
    for profile, account, full, kind, value in planned:
        STAGE = 'publish'
        identity(profile, account)
        aws(profile, 'ssm', 'put-parameter', {'Name': full, 'Type': kind, 'Value': value, 'Overwrite': False})
        STAGE = 'readback'
        published = aws(profile, 'ssm', 'get-parameter', {'Name': full, 'WithDecryption': True})['Parameter']
        if published['Name'] != full or published['Type'] != kind or published['Value'] != value:
            raise Failure('readback-mismatch')
        print('created', profile, full)


def entrypoint():
    try:
        main()
        return 0
    except (Exception, KeyboardInterrupt) as error:
        code = error.args[0] if isinstance(error, Failure) and error.args and error.args[0] in CODES else 'unexpected-error'
        message = ('Execução interrompida; pode haver publicação parcial nesta execução.' if PUT_ATTEMPTED
                   else 'Nenhuma publicação iniciada nesta execução.')
        print('aborted', STAGE, code, *(FAILED_AWS or ()), message, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(entrypoint())
