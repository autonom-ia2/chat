#!/usr/bin/python3
"""Synthetic framed publisher, reached only through the real SSH/sudo wrapper."""
import json
from pathlib import Path
import sys

base = ['exec', '-i', 'chatwoot-web', 'bundle', 'exec', 'ruby',
        'scripts/instagram_testers/session_publisher.rb']
args = sys.argv[1:]
assert args in (base, [*base, '--channel'])
channel = args == [*base, '--channel']
with Path('/fixture/docker-events').open('a') as events:
    events.write('channel\n' if channel else 'one-shot\n')

def publish(raw):
    assert json.loads(raw) == {'type': 'session', 'operation': 'bootstrap'}
    print(json.dumps({'type': 'bootstrap', 'metadata': {
        'INSTAGRAM_META_DEVELOPER_APP_ID': '10001',
        'INSTAGRAM_META_BUSINESS_ID': '10002',
        'INSTAGRAM_TESTER_APP_NAME': 'Synthetic',
        'INSTAGRAM_TESTER_ADMIN_USER_ID': '12345',
        'INSTAGRAM_TESTER_ROLES_DOC_ID': '10003',
    }, 'revision': '1' * 64, 'version': None}, separators=(',', ':')), flush=True)

if channel:
    for line in sys.stdin:
        publish(line)
else:
    publish(sys.stdin.read())
