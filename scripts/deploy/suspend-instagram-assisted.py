"""Suspend assisted onboarding without touching base ENV or coordination data."""
import os
from pathlib import Path
import subprocess
import tempfile

APP_DIR = Path('/opt/chatwoot')
UNIT_DIR = Path('/etc/systemd/system')
OVERLAY = APP_DIR / 'instagram-tester.env'
FLAG = 'INSTAGRAM_TESTER_AUTOMATION_ENABLED'

# Read the effective published commands, including existing systemd overrides.
# Validate both before changing anything; preserve their image and arguments.
commands = {}
for service in ('chatwoot-web.service', 'chatwoot-worker.service'):
    source = subprocess.check_output(['systemctl', 'cat', service], text=True)
    command = ''
    for line in source.splitlines():
        if line.startswith('ExecStart='):
            command = line.removeprefix('ExecStart=')
    if 'docker run ' not in command:
        raise RuntimeError(f'instagram_recovery_published_command_missing:{service}')
    overlay_arg = f'--env-file {OVERLAY}'
    if overlay_arg not in command:
        base_arg = f'--env-file {APP_DIR / ".env"}'
        if base_arg not in command:
            raise RuntimeError(f'instagram_recovery_overlay_unavailable:{service}')
        commands[service] = command.replace(base_arg, f'{base_arg} {overlay_arg}', 1)

lines = OVERLAY.read_text().splitlines() if OVERLAY.exists() else []
lines = [line for line in lines if not line.startswith(f'{FLAG}=')]
descriptor, temporary_name = tempfile.mkstemp(prefix='.instagram-recovery-', dir=APP_DIR)
temporary = Path(temporary_name)
try:
    with os.fdopen(descriptor, 'w') as output:
        output.write('\n'.join([*lines, f'{FLAG}=false']) + '\n')
    temporary.replace(OVERLAY)
finally:
    temporary.unlink(missing_ok=True)

for service, command in commands.items():
    directory = UNIT_DIR / f'{service}.d'
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'zz-instagram-recovery.conf').write_text(f'[Service]\nExecStart=\nExecStart={command}\n')

assert [line for line in OVERLAY.read_text().splitlines() if line.startswith(f'{FLAG}=')] == [f'{FLAG}=false']
