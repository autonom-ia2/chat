#!/usr/bin/env python3
"""Run one coordinated display/gateway phase; retain intent if outcome is ambiguous."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import resource
import shlex
import subprocess
import sys

BASE = Path(__file__).resolve().parent
os.umask(0o077)
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
phase, stack = sys.argv[1:]
assert phase in ('start', 'verify', 'stop') and stack in ('hub2you', 'autonomia')
receipt = BASE / (phase + '-' + stack + '.json')
intent = BASE / (phase + '-' + stack + '.intent.json')
assert not any(p.exists() or p.is_symlink() for p in (receipt, intent)), 'existing phase: reconcile before any repeated execution'
program = (BASE / 'display-gateway-remote.py').read_text()
with intent.open('x') as handle:
    json.dump({'phase': phase, 'stack': stack, 'remote_sha256': hashlib.sha256(program.encode()).hexdigest(),
               'requested_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}, handle, indent=2)
    handle.write('\n')
command = '/usr/bin/python3 -c ' + shlex.quote(program) + ' ' + phase + ' ' + stack
args = ['/usr/bin/ssh', '-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
        '-o', 'HostKeyAlgorithms=ssh-ed25519', '-o', 'ForwardAgent=no',
        '-o', 'UpdateHostKeys=no', '-o', 'ConnectTimeout=8', 'n8n', command]
try:
    result = subprocess.run(args, capture_output=True, text=True, timeout=120)
    record = {'phase': phase, 'stack': stack, 'returncode': result.returncode,
              'stdout': result.stdout, 'stderr': result.stderr}
except Exception:
    record = {'phase': phase, 'stack': stack, 'returncode': 1,
              'status': 'OUTCOME_UNAVAILABLE_RECONCILE_BEFORE_RETRY'}
with receipt.open('x') as handle:
    json.dump(record, handle, indent=2)
    handle.write('\n')
print(json.dumps(record))
sys.exit(record['returncode'])
