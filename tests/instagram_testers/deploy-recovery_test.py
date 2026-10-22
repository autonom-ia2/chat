"""Offline Bash recovery tests. Every infrastructure command is a local fake.

Only selected run blocks/functions are executed, never user-data/bootstrap.
Absolute publisher executables are replaced with fakes before Bash runs.
AWS fakes return API envelopes and apply only the workflow's exact projections.
"""
import json
import os
import shutil
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = [ROOT / '.github/workflows' / f'deploy-{stack}-blue-green.yml'
             for stack in ('hub2you', 'autonomia')]
HELPER = ROOT / 'scripts/deploy/blue-green-recovery.sh'


def run_block(source, name):
    lines = source.splitlines()
    start = lines.index(f'      - name: {name}')
    start = lines.index('        run: |', start) + 1
    block = []
    for line in lines[start:]:
        if line and not line.startswith('          '):
            break
        block.append(line[10:] if line else '')
    return '\n'.join(block)


def fake_aws():
    """Executed only through the test-created aws executable."""
    state_path = Path(os.environ['FAKE_STATE'])
    state = json.loads(state_path.read_text())
    state.setdefault('events', [])
    state.setdefault('time', 0)
    state.setdefault('drain_seconds', 300)
    args = sys.argv[2:]
    service, operation = args[:2]
    expected_services = {
        **dict.fromkeys(('describe-load-balancers', 'describe-listeners', 'describe-target-health',
                         'modify-listener', 'deregister-targets', 'delete-target-group'), 'elbv2'),
        **dict.fromkeys(('get-parameter', 'put-parameter', 'describe-instance-information',
                         'send-command', 'get-command-invocation'), 'ssm'),
        **dict.fromkeys(('describe-instances', 'start-instances', 'stop-instances', 'terminate-instances',
                         'create-tags'), 'ec2'),
        'describe-images': 'ecr',
    }
    expected_service = ({'command-executed': 'ssm', 'instance-running': 'ec2', 'instance-stopped': 'ec2',
                         'target-deregistered': 'elbv2', 'target-in-service': 'elbv2'}[args[2]] if operation == 'wait' else expected_services[operation])
    assert service == expected_service
    state['calls'].append(args)
    state['events'].append([operation, state['time']])
    number = len(state['calls'])

    def arg(name):
        return args[args.index(name) + 1]

    def save():
        state_path.write_text(json.dumps(state))

    def worker_event(event, instance, running):
        # Model effects, including the enabled unit at EC2 boot. SSM submission
        # alone is not proof that the remote stop has completed.
        active = set(state.setdefault('running_workers', []))
        if running:
            active.add(instance)
        else:
            active.discard(instance)
        state['running_workers'] = sorted(active)
        state.setdefault('worker_timeline', []).append([event, instance, sorted(active)])

    command_kind = None
    payload = None
    if operation == 'send-command':
        parameters = arg('--parameters')
        if parameters.startswith('commands='):
            # O AWS CLI real só decodifica \" no formato abreviado: \n, \\ e afins viram texto e quebram o script (#1406).
            assert '\n' not in parameters, 'multi-line SSM command must use full JSON --parameters'
            escapes = [parameters[i + 1:i + 2] for i, char in enumerate(parameters) if char == '\\']
            assert all(escape == '"' for escape in escapes), 'SSM shorthand only decodes \\" escapes'
            payload = json.loads(parameters.removeprefix('commands='))
            assert payload[0] == 'set -eu'
            command_kind = 'service'
        else:
            parameters = json.loads(parameters)
            assert set(parameters) == {'commands'}
            payload = parameters['commands']
            if payload[0] == 'set -eu':
                # Único JSON multi-linha hoje: a suspensão do Instagram, que precisa chegar inteira (#1406).
                script = (Path(__file__).resolve().parents[2] / 'scripts/deploy/suspend-instagram-assisted.py').read_text().rstrip('\n')
                base = ['set -eu', f"sudo python3 - <<'INSTAGRAM_RECOVERY'\n{script}\nINSTAGRAM_RECOVERY",
                        'sudo systemctl daemon-reload']
                assert payload[:3] == base and len(payload) in (3, 4)
                if len(payload) == 4:
                    # #1540: green suspension writes the marker in the same command.
                    prefix = 'printf "%s\\n" "INSTAGRAM_ASSISTED_SUSPENDED step='
                    suffix = '" | sudo tee /opt/chatwoot/instagram-assisted-suspended >/dev/null'
                    assert payload[3].startswith(prefix) and payload[3].endswith(suffix), payload[3]
                    code = payload[3][len(prefix):-len(suffix)]
                    assert code and all(char in 'abcdefghijklmnopqrstuvwxyz_' for char in code), code
                    state.setdefault('marker_commands', {})[f'command-{len(state["calls"])}'] = f'INSTAGRAM_ASSISTED_SUSPENDED step={code}'
                command_kind = 'service'
            elif len(payload) != 1 or not isinstance(payload[0], str):
                raise AssertionError('unexpected JSON SSM payload')
            elif payload[0] == 'if [ -e /run/chatwoot-deploy.running ]; then echo DEPLOY_RUNNING; else echo DEPLOY_IDLE; fi':
                command_kind = 'deploy-status'
            else:
                assert payload[0] == ('systemd-run --unit=green-retire --no-block sh -c '
                                      '"while [ -e /run/chatwoot-deploy.running ]; do sleep 5; done; shutdown -h now"')
                command_kind = 'retirement'
            if command_kind == 'service':
                assert arg('--instance-ids') in ('i-blue', 'i-green', 'i-older', 'i-next', 'i-other')
            else:
                assert arg('--instance-ids') == 'i-green'
        assert isinstance(payload, list) and all(isinstance(item, str) for item in payload)
        assert arg('--document-name') == 'AWS-RunShellScript'
    injected_failure = (operation == state.get('fail_operation') or
                        (command_kind is not None and command_kind == state.get('fail_command_kind')) or
                        (operation == 'get-command-invocation' and
                         state.get('fail_invocation_kind') is not None and
                         state['commands'][arg('--command-id')]['kind'] == state['fail_invocation_kind']) or
                        number == state.get('fail_at')) or (operation == 'put-parameter' and
                       '--name' in args and arg('--name') == state.get('fail_parameter'))
    if injected_failure and not state.get('fail_after_apply'):
        save()
        sys.exit(77)

    result = None
    if operation == 'describe-load-balancers':
        envelope = {'LoadBalancers': [{'LoadBalancerArn': 'lb-test'}]}
        result = envelope['LoadBalancers'][0]['LoadBalancerArn']
        assert arg('--query') == 'LoadBalancers[0].LoadBalancerArn'
    elif operation == 'describe-listeners':
        if '--load-balancer-arn' in args:
            envelope = {'Listeners': [{'Port': 443, 'ListenerArn': 'listener-test'}]}
            assert arg('--query') == 'Listeners[?Port==`443`].ListenerArn | [0]'
            result = next(item['ListenerArn'] for item in envelope['Listeners'] if item['Port'] == 443)
        else:
            assert '--query' not in args
            result = state.get('listener_envelope', {'Listeners': [{'DefaultActions': [
                {'Type': 'forward', 'TargetGroupArn': state['listener']}]}]})
    elif operation == 'describe-target-health':
        assert '--query' not in args
        target = state['targets'][arg('--target-group-arn')]
        result = state.get('target_envelopes', {}).get(arg('--target-group-arn'), state.get('target_envelope', {'TargetHealthDescriptions': [
            {'Target': {'Id': target, 'Port': 3000}, 'TargetHealth': {'State': 'healthy'}}]}))
    elif operation == 'get-parameter':
        if arg('--name') not in state['parameters']:
            save()
            print(f'An error occurred (ParameterNotFound) when calling the GetParameter operation: {arg("--name")}',
                  file=sys.stderr)
            sys.exit(254)
        envelope = {'Parameter': {'Value': state['parameters'][arg('--name')], 'Type': 'String'}}
        assert arg('--query') == 'Parameter.Value'
        result = envelope['Parameter']['Value']
    elif operation == 'put-parameter':
        value = arg('--value')
        name = arg('--name')
        state['parameters'][name] = value
        state['writes'].append([name, value, state['listener']])
        result = {'Version': len(state['writes'])}
    elif operation == 'modify-listener':
        action = arg('--default-actions')
        assert action.startswith('Type=forward,TargetGroupArn=')
        if not state.get('ignore_switch'):
            state['listener'] = action.split('TargetGroupArn=', 1)[1]
        result = {'Listeners': [{'DefaultActions': [{'Type': 'forward', 'TargetGroupArn': state['listener']}]}]}
    elif operation == 'describe-instances' and '--filters' in args:
        # Listagem do aviso de green esquecida: saída em texto, uma instância por linha.
        assert arg('--output') == 'text'
        assert arg('--query') == "Reservations[].Instances[].[InstanceId,LaunchTime,Tags[?Key=='Name'].Value | [0]]"
        filters = args[args.index('--filters') + 1:args.index('--query')]
        assert filters == ['Name=tag:BlueGreenRole,Values=green', 'Name=tag:Project,Values=chatwoot-autonomia',
                           'Name=tag:Environment,Values=prod', 'Name=instance-state-name,Values=running']
        result = '\n'.join('\t'.join(row) for row in state.get('running_greens', []))
    elif operation == 'describe-instances':
        instance = arg('--instance-ids')
        name = state.get('instance_states', {}).get(instance, state.get('instance_state', 'running'))
        assert arg('--query') == 'Reservations[0].Instances[0].State.Name'
        if name == 'not-found':
            save()
            print(f'An error occurred (InvalidInstanceID.NotFound) when calling DescribeInstances: {instance}',
                  file=sys.stderr)
            sys.exit(254)
        if name == 'api-error':
            save()
            print('An error occurred (RequestLimitExceeded) when calling DescribeInstances', file=sys.stderr)
            sys.exit(254)
        envelope = {'Reservations': [{'Instances': [{'State': {'Name': name}}]}]}
        result = envelope['Reservations'][0]['Instances'][0]['State']['Name']
    elif operation == 'describe-images':
        assert arg('--repository-name') == 'repo-test'
        assert arg('--image-ids') == 'imageTag=sha-test'
        image = state.get('image', 'absent')
        if image != 'present':
            save()
            code = 'ImageNotFoundException' if image == 'absent' else 'AccessDeniedException'
            print(f'An error occurred ({code}) when calling DescribeImages', file=sys.stderr)
            sys.exit(254)
        result = {'imageDetails': [{'imageTags': ['sha-test']}]}
    elif operation == 'stop-instances':
        instance = arg('--instance-ids')
        state.setdefault('stopped', []).append(instance)
        state.setdefault('instance_states', {})[instance] = 'stopping'
        result = {}
    elif operation == 'describe-instance-information':
        envelope = {'InstanceInformationList': [{'PingStatus': 'Online'}]}
        assert arg('--query') == 'InstanceInformationList[0].PingStatus'
        result = envelope['InstanceInformationList'][0]['PingStatus']
    elif operation == 'send-command':
        instance = arg('--instance-ids')
        command_id = f'command-{number}'
        state.setdefault('commands', {})[command_id] = {'kind': command_kind, 'instance': instance, 'payload': payload}
        actions = []
        if any('INSTAGRAM_TESTER_AUTOMATION_ENABLED' in item for item in payload):
            state.setdefault('command_suspensions', {})[command_id] = instance
        if any('/opt/chatwoot/igcoord/check.sh' in item for item in payload):
            state.setdefault('command_coordination_checks', {})[command_id] = instance
        if any('stop chatwoot-worker.service' in item for item in payload):
            state['workers'].append(['stop', instance])
            actions.append(['ssm-worker-stopped', instance, False])
        if any('restart chatwoot-web.service' in item for item in payload):
            state.setdefault('command_web_restarts', {})[command_id] = instance
        # try-restart keeps a stopped worker stopped and a running one running (#1540).
        if any('start chatwoot-worker.service' in item and 'try-restart' not in item for item in payload):
            state['workers'].append(['start', instance])
            actions.append(['ssm-worker-started', instance, True])
        state.setdefault('command_worker_actions', {})[command_id] = actions
        envelope = {'Command': {'CommandId': command_id}}
        assert arg('--query') == 'Command.CommandId'
        result = envelope['Command']['CommandId']
    elif operation == 'get-command-invocation':
        command = state['commands'][arg('--command-id')]
        assert arg('--instance-id') == command['instance']
        envelope = {'Status': 'Success', 'StandardOutputContent': 'synthetic', 'StandardErrorContent': ''}
        if command['kind'] == 'deploy-status':
            envelope['StandardOutputContent'] = state.get('deploy_status', 'DEPLOY_IDLE')
        elif arg('--command-id') in state.get('command_coordination_checks', {}):
            marker = state.get('markers', {}).get(command['instance'])
            if marker:
                # The remote command prints the marker instead of running check.sh.
                envelope['StandardOutputContent'] = marker + '\n'
            elif command['instance'] in (state.get('fail_coordination_instance'), state.get('missing_coordination_instance')):
                envelope = {'Status': state.get('coordination_status', 'Failed'), 'StandardOutputContent': '',
                            'StandardErrorContent': state.get('coordination_error', '') if
                            command['instance'] == state.get('fail_coordination_instance') else ''}
            if 'invocation_raw' in state:
                save()
                print(state['invocation_raw'])
                sys.exit(0)
        elif command['kind'] == 'retirement':
            envelope['Status'] = state.get('retirement_status', 'Success')
            envelope['StandardOutputContent'] = ''
            if envelope['Status'] == 'Success':
                state['retirement_scheduled'] = True
        query = arg('--query')
        if query == '[Status,StandardOutputContent]':
            assert arg('--output') == 'text'
            assert command['kind'] in ('deploy-status', 'retirement')
            result = f"{envelope['Status']}\t{envelope['StandardOutputContent']}"
        else:
            assert query == '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}'
            assert arg('--output') == 'json'
            result = {'Status': envelope['Status'], 'Output': envelope['StandardOutputContent'],
                      'Error': envelope['StandardErrorContent']}
    elif operation == 'wait':
        assert args[2] in ('command-executed', 'instance-running', 'instance-stopped', 'target-deregistered',
                           'target-in-service')
        if args[2] == 'target-in-service':
            assert arg('--target-group-arn') == 'tg-green' and arg('--targets') == 'Id=i-green,Port=3000'
            state.setdefault('green_in_service', []).append(number)
        if args[2] == 'instance-stopped':
            state.setdefault('instance_states', {})[arg('--instance-ids')] = 'stopped'
            state.setdefault('waited_stopped', []).append(arg('--instance-ids'))
        if args[2] == 'command-executed':
            instance = state.get('command_coordination_checks', {}).get(arg('--command-id'))
            if instance:
                state.setdefault('coordination_checks', []).append([instance, number])
                if instance in (state.get('fail_coordination_instance'), state.get('missing_coordination_instance')):
                    save()
                    sys.exit(78)
            suspended = state.get('command_suspensions', {}).get(arg('--command-id'))
            if suspended:
                if suspended == state.get('fail_suspension_instance'):
                    save()
                    sys.exit(79)
                state.setdefault('suspensions', []).append([suspended, number])
                marker = state.get('marker_commands', {}).get(arg('--command-id'))
                if marker:
                    state.setdefault('markers', {})[suspended] = marker
            restarted = state.get('command_web_restarts', {}).get(arg('--command-id'))
            if restarted:
                if restarted == state.get('fail_restart_instance'):
                    save()
                    sys.exit(80)
                state.setdefault('web_restarts', []).append([restarted, number])
            for action in state['command_worker_actions'][arg('--command-id')]:
                worker_event(*action)
        if args[2] == 'target-deregistered':
            state['time'] += state['drain_seconds']
            state['target_drained_at'] = state['time']
        result = ''
    elif operation == 'create-tags':
        assert arg('--resources') == 'i-green'
        assert arg('--tags') == 'Key=DeployCleanup,Value=pending'
        state['tags'] = {'i-green': {'DeployCleanup': 'pending'}}
        result = {}
    elif operation in ('start-instances', 'deregister-targets', 'delete-target-group', 'terminate-instances'):
        if operation == 'start-instances' and state.get('boot_worker_enabled'):
            worker_event('boot-worker-started', arg('--instance-ids'), True)
        elif operation == 'deregister-targets':
            state['deregistered_at'] = state['time']
        elif operation == 'delete-target-group':
            state['target_deleted_at'] = state['time']
        elif operation == 'terminate-instances':
            state['terminated_at'] = state['time']
            state.setdefault('terminated', []).append(arg('--instance-ids'))
        if operation == 'delete-target-group':
            state.setdefault('deleted_target_groups', []).append(arg('--target-group-arn'))
        result = {}
    else:
        raise AssertionError(f'unsupported fake operation: {service}/{operation}')
    save()
    if injected_failure:
        sys.exit(77)
    print(json.dumps(result) if isinstance(result, (dict, list)) else result)


class DeployRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='deploy-recovery-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        # Allow only Bash's local utilities; deny infrastructure names by default.
        for name in ('aws', 'docker', 'sshd', 'systemctl', 'sudo', 'ssh', 'curl', 'dnf', 'cloud-init', 'journalctl', 'systemd-run', 'shutdown'):
            executable = self.bin / name
            executable.write_text('#!/bin/sh\nprintf "%s\\n" unexpected_infrastructure_command >&2\nexit 99\n')
            executable.chmod(0o700)
        (self.bin / 'aws').write_text(f'#!{sys.executable}\nimport runpy, sys\nsys.argv.insert(1, "--fake-aws")\nrunpy.run_path({str(Path(__file__).resolve())!r}, run_name="__main__")\n')
        (self.bin / 'sleep').write_text(f'#!{sys.executable}\nimport json, os, sys\nfrom pathlib import Path\np=Path(os.environ["FAKE_STATE"]); s=json.loads(p.read_text()); s["events"].append(["sleep", s["time"], int(sys.argv[1])]); p.write_text(json.dumps(s)); sys.exit(77) if os.environ.get("FAKE_SLEEP_FAIL") else None; s["time"] += int(sys.argv[1]); p.write_text(json.dumps(s))\n')
        (self.bin / 'sleep').chmod(0o700)
        self.state_path = self.directory / 'state.json'
        self.env = {
            'PATH': f'{self.bin}:/usr/bin:/bin', 'FAKE_STATE': str(self.state_path),
            'GITHUB_ENV': str(self.directory / 'github-env'),
            'CURRENT_TG_PARAMETER': 'current-tg', 'CURRENT_INSTANCE_PARAMETER': 'current-instance',
            'PREVIOUS_TG_PARAMETER': 'previous-tg', 'PREVIOUS_INSTANCE_PARAMETER': 'previous-instance',
            # #1979: congelamento em duas chaves; sem as chaves no SSM falso, a produção está descongelada.
            'DEPLOY_FREEZE_PARAMETER': 'deploy-freeze', 'DEPLOY_FREEZE_RELEASED_PARAMETER': 'deploy-freeze-released',
            'LISTENER_ARN': 'listener-test', 'ALB_NAME': 'lb-test',
            'BLUE_TG_ARN': 'tg-blue', 'BLUE_INSTANCE_ID': 'i-blue',
            'GREEN_TG_ARN': 'tg-green', 'GREEN_INSTANCE_ID': 'i-green',
            'GREEN_WORKER_START_ATTEMPTED': 'true',
            'BLUE_WORKER_STOPPED': 'true',  # Existing recovery cases follow the worker-stop intent step.
            # Existing recovery cases happen after the image reached ECR (#1350 covers the earlier failures).
            'GREEN_IMAGE_PUBLISHED': 'true', 'ECR_REPOSITORY': 'repo-test', 'GITHUB_SHA': 'sha-test',
        }

    def execute(self, script, **changes):
        state = {'listener': 'tg-green', 'targets': {'tg-blue': 'i-blue', 'tg-green': 'i-green'},
                 'parameters': {'current-tg': 'tg-green', 'current-instance': 'i-green',
                                'previous-tg': 'tg-blue', 'previous-instance': 'i-blue'},
                 'calls': [], 'writes': [], 'workers': [], 'events': [], 'time': 0, 'drain_seconds': 300}
        state.update(changes)
        self.state_path.write_text(json.dumps(state))
        (self.directory / 'github-env').write_text('')
        # Bound the whole fake process group: a timed-out child must never write into
        # the next injection's state file after Bash has been killed.
        with subprocess.Popen(['/bin/bash', '-euo', 'pipefail', '-c', script],
                              cwd=ROOT, env=self.env, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, start_new_session=True) as process:
            try:
                stdout, stderr = process.communicate(timeout=30)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
                raise
            result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
        return result, json.loads(self.state_path.read_text())

    def assert_pointers(self, state, target, instance):
        self.assertEqual(state['parameters']['current-tg'], target)
        self.assertEqual(state['parameters']['current-instance'], instance)
        for name, value, listener in state['writes']:
            if name == 'current-tg':
                self.assertEqual(value, listener)
            if name == 'current-instance':
                self.assertEqual(value, state['targets'][listener])

    def test_publisher_required_steps_and_baseline_reproduction(self):
        for workflow in WORKFLOWS:
            for baseline in (False, True):
                source = workflow.read_text()
                start = source.index('            if ! (\n')
                end = source.index('            cleanup_instagram_tester_publisher\n          }', start)
                block = '\n'.join(line[12:] for line in source[start:end].splitlines()) + '\ncleanup_instagram_tester_publisher'
                if baseline:
                    # Reconstruct the audited conditional errexit bug without
                    # depending on Git history in shallow/future CI checkouts.
                    block = block.replace(' &&\n', '\n').replace('if ! (\n', 'if ! (\n  set -e\n', 1)
                block = block.replace('/bin/sh "$stage_dir/install-remote-publisher.sh"', 'fake_step installer')
                block = block.replace('/usr/sbin/sshd -t', 'fake_step sshd-check')
                script = '''
count_file="$FAKE_STATE.count"; log_file="$FAKE_STATE.steps"
printf '0' > "$count_file"; : > "$log_file"
fake_step() {
  local count
  count=$(cat "$count_file"); count=$((count+1)); printf '%s' "$count" > "$count_file"
  printf '%s\\n' "$*" >> "$log_file"
  [ "$count" != "$FAIL_STEP" ]
}
docker() { fake_step docker "$@"; }
test() { fake_step test "$@"; }
chmod() { fake_step chmod "$@"; }
systemctl() { fake_step systemctl "$@"; }
cleanup_instagram_tester_publisher() { printf 'cleanup\\n' >> "$log_file"; }
source_container=synthetic-container
stage_dir="$TEST_DIR"
publisher_setup() {
''' + block + '\n}\npublisher_setup\n'
                (self.directory / 'public-key').write_text('synthetic-public-key\n')
                for step in range(0, 14):
                    with self.subTest(stack=workflow.name, baseline=baseline, fail_step=step):
                        env = {**self.env, 'TEST_DIR': str(self.directory), 'FAIL_STEP': str(step)}
                        result = subprocess.run(['/bin/bash', '-euo', 'pipefail', '-c', script], env=env,
                                                text=True, capture_output=True, timeout=5)
                        expected_success = step == 0 or (baseline and step < 13)
                        self.assertEqual(result.returncode == 0, expected_success, result.stderr)
                        steps = Path(f'{self.state_path}.steps').read_text().splitlines()
                        expected_count = 13 if expected_success or baseline else step
                        self.assertEqual(len(steps), expected_count + 1)
                        self.assertEqual(steps[-1], 'cleanup')

    def test_rollback_and_cleanup_success_ordering(self):
        for workflow in WORKFLOWS:
            for name in ('Restore previous target group', 'Cleanup failed green resources before traffic shift'):
                with self.subTest(stack=workflow.name, path=name):
                    result, state = self.execute(run_block(workflow.read_text(), name))
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assert_pointers(state, 'tg-blue', 'i-blue')
                    self.assertEqual(state['workers'], [['stop', 'i-green'], ['start', 'i-blue']])
                    calls = state['calls']
                    modify = next(i for i, call in enumerate(calls) if call[1] == 'modify-listener')
                    first_pointer = next(i for i, call in enumerate(calls) if call[1] == 'put-parameter')
                    self.assertLess(modify, first_pointer)
                    stop = next(i for i, call in enumerate(calls)
                                if call[1] == 'send-command' and 'stop chatwoot-worker.service' in call[call.index('--parameters')+1])
                    start = next(i for i, call in enumerate(calls)
                                 if call[1] == 'send-command' and 'start chatwoot-worker.service' in call[call.index('--parameters')+1])
                    self.assertEqual(calls[stop+1][:3], ['ssm', 'wait', 'command-executed'])
                    self.assertLess(stop+1, start)

    def test_stopped_previous_boot_has_zero_worker_overlap(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                result, state = self.execute(run_block(workflow.read_text(), 'Restore previous target group'),
                    instance_state='stopped', boot_worker_enabled=True, running_workers=['i-green'])
                self.assertEqual(result.returncode, 0, result.stderr)
                timeline = state['worker_timeline']
                self.assertEqual(timeline[0], ['ssm-worker-stopped', 'i-green', []])
                self.assertEqual(timeline[1], ['boot-worker-started', 'i-blue', ['i-blue']])
                self.assertTrue(all(len(event[2]) <= 1 for event in timeline), timeline)
                self.assertEqual(state['running_workers'], ['i-blue'])
                self.assert_pointers(state, 'tg-blue', 'i-blue')

    def test_failed_current_worker_stop_wait_cannot_boot_previous(self):
        for workflow in WORKFLOWS:
            script = run_block(workflow.read_text(), 'Restore previous target group')
            initial = dict(instance_state='stopped', boot_worker_enabled=True, running_workers=['i-green'])
            _, success = self.execute(script, **initial)
            stop = next(i for i, call in enumerate(success['calls'], 1)
                        if call[1] == 'send-command' and 'stop chatwoot-worker.service' in call[call.index('--parameters')+1])
            for number in (stop, stop+1):
                with self.subTest(stack=workflow.name, fail_at=number):
                    result, state = self.execute(script, fail_at=number, **initial)
                    self.assertEqual(result.returncode, 77)
                    self.assertEqual(state['running_workers'], ['i-green'])
                    self.assertFalse(any(call[1] in ('start-instances', 'modify-listener', 'put-parameter')
                                         for call in state['calls']))

    def test_previous_boot_failure_retains_resources_without_false_success(self):
        for workflow in WORKFLOWS:
            script = run_block(workflow.read_text(), 'Restore previous target group')
            initial = dict(instance_state='stopped', boot_worker_enabled=True, running_workers=['i-green'])
            _, success = self.execute(script, **initial)
            boot = next(i for i, call in enumerate(success['calls'], 1) if call[1] == 'start-instances')
            for number, applied in ((boot, False), (boot, True), (boot+1, False)):
                with self.subTest(stack=workflow.name, fail_at=number, response_lost=applied):
                    result, state = self.execute(script, fail_at=number, fail_after_apply=applied, **initial)
                    self.assertEqual(result.returncode, 77)
                    self.assertEqual(state['workers'], [['stop', 'i-green']])
                    self.assertEqual(state['running_workers'], [] if number == boot and not applied else ['i-blue'])
                    self.assertTrue(all(len(event[2]) <= 1 for event in state.get('worker_timeline', [])))
                    self.assertEqual(state['listener'], 'tg-green')
                    self.assertEqual(state['writes'], [])
                    self.assertFalse(any(call[1] in ('modify-listener', 'delete-target-group', 'terminate-instances')
                                         for call in state['calls']))

    def test_every_required_api_failure_aborts_instead_of_accidental_success(self):
        for workflow in WORKFLOWS:
            for name in ('Restore previous target group', 'Cleanup failed green resources before traffic shift',
                         'Shift HTTPS listener to green', 'Switch Sidekiq workers to green'):
                script = run_block(workflow.read_text(), name)
                initial = ({'listener': 'tg-blue'} if name == 'Shift HTTPS listener to green'
                           else {'instance_state': 'stopped'} if name == 'Restore previous target group' else {})
                result, success = self.execute(script, **initial)
                self.assertEqual(result.returncode, 0, result.stderr)
                for number, args in enumerate(success['calls'], start=1):
                    if args[1] == 'describe-instance-information':
                        continue  # Existing bounded poll tolerates transient SSM discovery failure.
                    with self.subTest(stack=workflow.name, path=name, fail_at=number, operation=args[:2]):
                        result, failed = self.execute(script, fail_at=number, **initial)
                        if (args[1] == 'wait' and args[2] == 'command-executed' and
                                args[args.index('--command-id')+1] in success.get('command_coordination_checks', {})):
                            # #1540: the waiter alone decides nothing; the Success status read next keeps the deploy going.
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(failed['calls'][number][1], 'get-command-invocation')
                            self.assertEqual(failed.get('suspensions', []), [])
                            self.assertEqual(failed['calls'], success['calls'])
                            continue
                        tolerant_probe = (name == 'Cleanup failed green resources before traffic shift' and
                            (args[1] == 'get-command-invocation' or
                             (args[1] == 'send-command' and args[args.index('--parameters')+1].startswith('{')
                              and json.loads(args[args.index('--parameters')+1])['commands'][0] != 'set -eu')))
                        if tolerant_probe:
                            self.assert_pointers(failed, 'tg-blue', 'i-blue')
                            self.assertEqual(failed['workers'], [['stop', 'i-green'], ['start', 'i-blue']])
                            self.assertNotIn('tags', failed)
                            self.assertEqual(failed['calls'][:number], success['calls'][:number])
                            if args[1] == 'get-command-invocation':
                                # Bounded invocation poll retries a transient failure and confirms IDLE.
                                self.assertEqual(result.returncode, 0, result.stderr)
                                self.assertEqual(failed['calls'][number], args)
                                self.assertEqual(failed['calls'][-1][:2], ['ec2', 'terminate-instances'])
                                self.assertIn('terminated_at', failed)
                            else:
                                # Failed probe submission leaves status unknown: keep green and fail loudly.
                                self.assertEqual(result.returncode, 1, result.stderr)
                                self.assertIn('blue_green_deploy_status_unknown', result.stderr)
                                self.assertEqual(len(failed['calls']), number)
                                self.assertNotIn('terminated_at', failed)
                                self.assertFalse(any(call[1] == 'terminate-instances' for call in failed['calls']))
                            continue
                        self.assertNotEqual(result.returncode, 0)
                        if args[1] == 'modify-listener':
                            self.assertEqual([call[1] for call in failed['calls'][number:]],
                                             ['describe-listeners', 'describe-target-health'])
                        elif args[1] == 'put-parameter' and args[args.index('--name')+1].startswith('previous-'):
                            repairs = failed['calls'][number:]
                            self.assertEqual([call[1] for call in repairs], ['put-parameter', 'put-parameter'])
                            self.assertEqual([call[call.index('--name')+1] for call in repairs],
                                             ['previous-tg', 'previous-instance'])
                            self.assertEqual([call[call.index('--value')+1] for call in repairs], ['tg-blue', 'i-blue'])
                            self.assertEqual(failed['parameters']['previous-tg'], 'tg-blue')
                            self.assertEqual(failed['parameters']['previous-instance'], 'i-blue')
                            # PREVIOUS now follows a confirmed green listener and both CURRENT writes.
                            self.assertEqual(failed['listener'], 'tg-green')
                            self.assert_pointers(failed, 'tg-green', 'i-green')
                            self.assertEqual(sum(call[1] == 'modify-listener' for call in failed['calls']), 1)
                            self.assertLess(next(i for i, call in enumerate(failed['calls'], 1)
                                                 if call[1] == 'modify-listener'), number)
                            self.assertNotIn('TRAFFIC_SHIFT_DONE=true', (self.directory / 'github-env').read_text())
                        else:
                            self.assertEqual(len(failed['calls']), number, result.stderr)
                        self.assertEqual(failed['calls'][:number], success['calls'][:number])
                        if name in ('Restore previous target group', 'Cleanup failed green resources before traffic shift'):
                            if args[1] == 'modify-listener':
                                self.assertEqual(failed['writes'], [])
                                self.assertEqual(failed['listener'], 'tg-green')
                            if args[1] in ('modify-listener', 'describe-listeners', 'describe-target-health', 'put-parameter'):
                                self.assertFalse(any(call[1] == 'terminate-instances' for call in failed['calls']))

    def test_cleanup_repairs_partial_pointer_writes_and_uncertain_switch(self):
        for workflow in WORKFLOWS:
            shift = run_block(workflow.read_text(), 'Shift HTTPS listener to green')
            cleanup = run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift')
            _, success = self.execute(shift, listener='tg-blue')
            for number, args in enumerate(success['calls'], start=1):
                if (args[1] == 'wait' and args[2] == 'command-executed' and
                        args[args.index('--command-id')+1] in success.get('command_coordination_checks', {})):
                    continue  # #1540: the check's waiter alone fails nothing (covered by the API-failure test).
                with self.subTest(stack=workflow.name, fail_at=number):
                    result, failed = self.execute(shift, listener='tg-blue', fail_at=number,
                                                  fail_after_apply=args[1] == 'modify-listener')
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('TRAFFIC_SHIFT_DONE=true', (self.directory / 'github-env').read_text())
                    markers = (self.directory / 'github-env').read_text()
                    attempted = 'PREVIOUS_WRITE_ATTEMPTED=true' in markers
                    self.env['PREVIOUS_WRITE_ATTEMPTED'] = 'true' if attempted else 'false'
                    try:
                        result, recovered = self.execute(cleanup, listener=failed['listener'], parameters=failed['parameters'])
                    finally:
                        del self.env['PREVIOUS_WRITE_ATTEMPTED']
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assert_pointers(recovered, 'tg-blue', 'i-blue')
                    if attempted:
                        self.assertEqual(recovered['parameters']['previous-tg'], 'tg-blue')
                        self.assertEqual(recovered['parameters']['previous-instance'], 'i-blue')

    def test_failed_rollback_response_after_applied_switch_reconciles_without_success(self):
        for workflow in WORKFLOWS:
            for name in ('Restore previous target group', 'Cleanup failed green resources before traffic shift'):
                script = run_block(workflow.read_text(), name)
                _, success = self.execute(script)
                number = next(i for i, call in enumerate(success['calls'], 1) if call[1] == 'modify-listener')
                result, state = self.execute(script, fail_at=number, fail_after_apply=True)
                self.assertEqual(result.returncode, 77)
                self.assert_pointers(state, 'tg-blue', 'i-blue')
                self.assertEqual(state['workers'], [['stop', 'i-green'], ['start', 'i-blue']])
                self.assertFalse(any(call[1] == 'terminate-instances' for call in state['calls']))

    def test_previous_pair_mismatch_or_ambiguity_has_zero_mutations(self):
        for workflow in WORKFLOWS:
            for name in ('Restore previous target group', 'Cleanup failed green resources before traffic shift'):
                for scenario in ('mismatch', 'missing', 'ambiguous'):
                    changes = dict(instance_state='stopped', boot_worker_enabled=True, running_workers=['i-green'])
                    if scenario == 'mismatch':
                        changes['targets'] = {'tg-blue': 'i-other', 'tg-green': 'i-green'}
                    else:
                        targets = [] if scenario == 'missing' else [
                            {'Target': {'Id': 'i-blue', 'Port': 3000}},
                            {'Target': {'Id': 'i-other', 'Port': 3000}}]
                        changes['target_envelopes'] = {'tg-blue': {'TargetHealthDescriptions': targets}}
                    with self.subTest(stack=workflow.name, path=name, scenario=scenario):
                        result, state = self.execute(run_block(workflow.read_text(), name), **changes)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(state['listener'], 'tg-green')
                        self.assertEqual(state['workers'], [])
                        self.assertEqual(state['running_workers'], ['i-green'])
                        self.assertEqual(state.get('worker_timeline', []), [])
                        self.assertEqual(state['writes'], [])
                        mutations = ('start-instances', 'send-command', 'modify-listener', 'put-parameter',
                                     'deregister-targets', 'delete-target-group', 'terminate-instances')
                        self.assertFalse(any(call[1] in mutations for call in state['calls']))

    def test_partial_previous_pair_write_reconciles_without_listener_or_worker_change(self):
        for workflow in WORKFLOWS:
            script = run_block(workflow.read_text(), 'Shift HTTPS listener to green')
            _, success = self.execute(script, listener='tg-blue')
            number = next(i for i, call in enumerate(success['calls'], 1)
                          if call[1] == 'put-parameter' and call[call.index('--name')+1] == 'previous-instance')
            for applied in (False, True):
                with self.subTest(stack=workflow.name, response_lost=applied):
                    parameters = {'current-tg': 'tg-blue', 'current-instance': 'i-blue',
                                  'previous-tg': 'tg-green', 'previous-instance': 'i-green'}
                    result, state = self.execute(script, listener='tg-blue', parameters=parameters,
                                                 fail_at=number, fail_after_apply=applied)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(state['parameters']['previous-tg'], 'tg-blue')
                    self.assertEqual(state['parameters']['previous-instance'], 'i-blue')
                    # No further switch or worker change during PREVIOUS repair: green was confirmed first.
                    self.assertEqual(state['listener'], 'tg-green')
                    self.assert_pointers(state, 'tg-green', 'i-green')
                    self.assertEqual(state['workers'], [])
                    calls = state['calls']
                    switches = [i for i, call in enumerate(calls) if call[1] == 'modify-listener']
                    self.assertEqual(len(switches), 1)
                    current = [i for i, call in enumerate(calls)
                               if call[1] == 'put-parameter' and call[call.index('--name')+1].startswith('current-')]
                    previous = [i for i, call in enumerate(calls)
                                if call[1] == 'put-parameter' and call[call.index('--name')+1].startswith('previous-')]
                    self.assertEqual(len(current), 2)
                    self.assertLess(switches[0], min(current))
                    self.assertLess(max(current), min(previous))
                    self.assertNotIn('TRAFFIC_SHIFT_DONE=true', (self.directory / 'github-env').read_text())

    def test_cleanup_waits_for_inflight_publisher_and_target_drain_before_removal(self):
        budget_source = (ROOT / 'scripts/instagram_testers/runtime/publisher-tunnel.mjs').read_text()
        budget_ms = int(budget_source.split('export const PUBLISH_BUDGET_MS = ', 1)[1].split(';', 1)[0].replace('_', ''))
        for workflow in WORKFLOWS:
            result, state = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'))
            with self.subTest(stack=workflow.name):
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertGreaterEqual(state['deregistered_at'] * 1000, budget_ms)
                self.assertIn('target_drained_at', state)
                self.assertGreaterEqual(state['target_deleted_at'], state['target_drained_at'])
                self.assertGreaterEqual(state['terminated_at'], state['target_drained_at'])
                events = state['events']
                pointer = max(i for i, event in enumerate(events) if event[0] == 'put-parameter')
                sleep = next(i for i, event in enumerate(events) if event[0] == 'sleep')
                deregister = next(i for i, event in enumerate(events) if event[0] == 'deregister-targets')
                self.assertLess(pointer, sleep)
                self.assertLess(sleep, deregister)
                self.assertGreaterEqual(events[sleep][2] * 1000, budget_ms)

    def test_cleanup_failed_confirmation_or_drain_preserves_resources(self):
        for workflow in WORKFLOWS:
            script = run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift')
            _, success = self.execute(script)
            modify = next(i for i, call in enumerate(success['calls'], 1) if call[1] == 'modify-listener')
            confirm = next(i for i, call in enumerate(success['calls'], 1)
                           if i > modify and call[1] == 'describe-listeners')
            wait = next(i for i, call in enumerate(success['calls'], 1)
                        if call[:3] == ['elbv2', 'wait', 'target-deregistered'])
            for number in (confirm, wait):
                with self.subTest(stack=workflow.name, fail_at=number):
                    result, state = self.execute(script, fail_at=number)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(any(call[1] in ('delete-target-group', 'terminate-instances') for call in state['calls']))
                    if number == confirm:
                        self.assertEqual(state['writes'], [])
                        self.assertEqual(state['workers'], [['stop', 'i-green']])
            self.env['FAKE_SLEEP_FAIL'] = 'true'
            try:
                result, state = self.execute(script)
            finally:
                del self.env['FAKE_SLEEP_FAIL']
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(any(call[1] in ('deregister-targets', 'delete-target-group', 'terminate-instances') for call in state['calls']))

    def test_partial_previous_persistent_failure_cannot_mutate_recovery_destination(self):
        for workflow in WORKFLOWS:
            shift = run_block(workflow.read_text(), 'Shift HTTPS listener to green')
            parameters = {'current-tg': 'tg-blue', 'current-instance': 'i-blue',
                          'previous-tg': 'tg-green', 'previous-instance': 'i-green'}
            result, state = self.execute(shift, listener='tg-blue', parameters=parameters,
                                         fail_parameter='previous-instance')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(state['listener'], 'tg-green')
            self.assert_pointers(state, 'tg-green', 'i-green')
            self.assertEqual(state['workers'], [])
            self.assertEqual(sum(call[1] == 'modify-listener' for call in state['calls']), 1)
            self.assertNotIn('TRAFFIC_SHIFT_DONE=true', (self.directory / 'github-env').read_text())
            self.env['PREVIOUS_WRITE_ATTEMPTED'] = 'true'
            try:
                result, retained = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'),
                                                 listener=state['listener'], parameters=state['parameters'],
                                                 fail_parameter='previous-instance')
            finally:
                del self.env['PREVIOUS_WRITE_ATTEMPTED']
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(retained['workers'], [])
            self.assertFalse(any(call[1] in ('modify-listener', 'deregister-targets', 'delete-target-group', 'terminate-instances')
                                 for call in retained['calls']))
            result, retained = self.execute(run_block(workflow.read_text(), 'Restore previous target group'),
                                             listener=state['listener'], parameters=state['parameters'])
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(retained['writes'], [])
            self.assertEqual(retained['workers'], [])
            self.assertFalse(any(call[1] in ('modify-listener', 'start-instances', 'send-command') for call in retained['calls']))

            self.env['PREVIOUS_WRITE_ATTEMPTED'] = 'true'
            try:
                result, repaired = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'),
                                                 listener=state['listener'], parameters=state['parameters'])
            finally:
                del self.env['PREVIOUS_WRITE_ATTEMPTED']
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(repaired['parameters']['previous-tg'], 'tg-blue')
            self.assertEqual(repaired['parameters']['previous-instance'], 'i-blue')
            self.assertEqual(repaired['workers'], [['stop', 'i-green'], ['start', 'i-blue']])

    def test_cleanup_without_known_blue_binding_has_zero_mutations(self):
        for workflow in WORKFLOWS:
            for key in ('BLUE_INSTANCE_ID', 'BLUE_TG_ARN', 'LISTENER_ARN'):
                original = self.env[key]
                self.env[key] = ''
                try:
                    result, state = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'))
                finally:
                    self.env[key] = original
                with self.subTest(stack=workflow.name, missing=key):
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(state['calls'], [])
                    self.assertEqual(state['workers'], [])
                    self.assertEqual(state['writes'], [])

    def test_listener_mismatch_retains_green_and_does_not_write_false_pointers(self):
        for workflow in WORKFLOWS:
            for name in ('Restore previous target group', 'Cleanup failed green resources before traffic shift'):
                result, state = self.execute(run_block(workflow.read_text(), name), ignore_switch=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(state['writes'], [])
                self.assertEqual(state['listener'], 'tg-green')
                self.assertFalse(any(call[1] == 'terminate-instances' for call in state['calls']))

    def test_listener_api_envelopes_and_single_active_target(self):
        script = f'source "{HELPER}"\nreconcile_current_destination listener-test tg-blue i-blue'
        weighted = {'Listeners': [{'DefaultActions': [{'Type': 'forward', 'ForwardConfig': {'TargetGroups': [
            {'TargetGroupArn': 'tg-blue', 'Weight': 100}, {'TargetGroupArn': 'tg-green', 'Weight': 0}]}}]}]}
        for envelope in (None, weighted):
            changes = {'listener': 'tg-blue'}
            if envelope:
                changes['listener_envelope'] = envelope
            result, state = self.execute(script, **changes)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_pointers(state, 'tg-blue', 'i-blue')
        for envelope in ({}, {'Listeners': []}, {'Listeners': [{'DefaultActions': []}]},
                         {'Listeners': [{'DefaultActions': [{'Type': 'forward', 'ForwardConfig': {'TargetGroups': [
                             {'TargetGroupArn': 'tg-blue', 'Weight': 50}, {'TargetGroupArn': 'tg-green', 'Weight': 50}]}}]}]}):
            result, state = self.execute(script, listener='tg-blue', listener_envelope=envelope)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(state['writes'], [])
        for envelope in ({}, {'TargetHealthDescriptions': []}, {'TargetHealthDescriptions': [
                {'Target': {'Id': 'i-blue', 'Port': 3000}}, {'Target': {'Id': 'i-green', 'Port': 3000}}]},
                {'TargetHealthDescriptions': [{'Target': {'Id': 'i-other', 'Port': 3000}}]},
                {'TargetHealthDescriptions': [{'Target': {'Id': 'i-blue', 'Port': 80}}]}):
            result, state = self.execute(script, listener='tg-blue', target_envelope=envelope)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(state['writes'], [])

    def test_repeat_rollback_does_not_stop_the_restored_worker(self):
        for workflow in WORKFLOWS:
            result, state = self.execute(run_block(workflow.read_text(), 'Restore previous target group'),
                                         listener='tg-blue', running_workers=['i-blue'], boot_worker_enabled=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state['workers'], [['start', 'i-blue']])
            self.assertEqual(state['worker_timeline'], [['ssm-worker-started', 'i-blue', ['i-blue']]])
            self.assert_pointers(state, 'tg-blue', 'i-blue')

    def test_remote_worker_commands_abort_at_each_mandatory_step(self):
        # Execute exact SSM command strings with shell-function replacements. No
        # sudo/systemctl/files under /opt are touched, even on successful paths.
        for workflow in WORKFLOWS:
            payloads = []
            for line in workflow.read_text().splitlines():
                prefix = "--parameters 'commands="
                if prefix in line and 'set -eu' in line and 'chatwoot-worker.service' in line:
                    payloads.append(json.loads(line.split(prefix, 1)[1].split("'", 1)[0]))
            for payload in payloads:
                commands = payload[1:]
                preamble = '''
count=0
fake_step() {
  count=$((count+1)); printf '%s\\n' "$*" >> "$STEP_LOG"
  [ "$count" != "$FAIL_STEP" ]
}
sudo() { fake_step "$@" || return $?; if [ "$1" = tee ]; then cat >/dev/null; fi; }
'''
                # In a pipeline sudo tee runs in a subshell, so count by shared log.
                preamble = preamble.replace('count=$((count+1));', 'count=$(wc -l < "$STEP_LOG"); count=$((count+1));')
                preamble = preamble.replace('[ "$count" != "$FAIL_STEP" ]\n}', '[ "$count" != "$FAIL_STEP" ] || return 77\n}')
                for fail_step in range(len(commands)+1):
                    log = self.directory / 'remote-steps'
                    log.write_text('')
                    result = subprocess.run(['/bin/bash', '-c', preamble + '\n' + '\n'.join(payload)],
                        env={**self.env, 'STEP_LOG': str(log), 'FAIL_STEP': str(fail_step)}, text=True,
                        capture_output=True, timeout=5)
                    with self.subTest(stack=workflow.name, commands=len(commands), fail_at=fail_step):
                        self.assertEqual(result.returncode == 0, fail_step == 0, result.stderr)
                        self.assertEqual(len(log.read_text().splitlines()), len(commands) if fail_step == 0 else fail_step)

    def test_all_run_blocks_and_nested_shells_parse_without_execution(self):
        for workflow in WORKFLOWS:
            lines = workflow.read_text().splitlines()
            for index, line in enumerate(lines):
                if line == '        run: |':
                    block = []
                    for item in lines[index+1:]:
                        if item and not item.startswith('          '):
                            break
                        block.append(item[10:] if item else '')
                    script = '\n'.join(block)
                    # GitHub evaluates this input expression before Bash starts.
                    script = script.replace("${{ github.event.inputs.green_instance_type || 't3.medium' }}", 't3.medium')
                    script = script.replace("${{ github.event.inputs.green_instance_type || 't3.small' }}", 't3.small')
                    result = subprocess.run(['/bin/bash', '-n'], input=script, env=self.env, text=True, capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
            source = workflow.read_text()
            userdata = source.split("          cat > \"$RUNNER_TEMP/green-user-data.sh\" <<'USERDATA'\n", 1)[1].split('          USERDATA\n', 1)[0]
            result = subprocess.run(['/bin/bash', '-n'], input='\n'.join(line[10:] for line in userdata.splitlines()),
                                    env=self.env, text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            nested = source.split('          cat > "$APP_DIR/deploy.sh" <<\'EOF\'\n', 1)[1].split('          EOF\n', 1)[0]
            result = subprocess.run(['/bin/bash', '-n'], input='\n'.join(line[10:] for line in nested.splitlines()),
                                    env=self.env, text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)

    STEP_ERRORS = {}

    def real_error(self, scenario):
        if scenario not in self.STEP_ERRORS:
            self.STEP_ERRORS[scenario] = real_check_stderr(scenario)
        return self.STEP_ERRORS[scenario]

    def call_index(self, state, predicate):
        return next(i for i, call in enumerate(state['calls'], 1) if predicate(call))

    def test_real_check_stderr_is_short_and_starts_with_the_sentinel(self):
        # SSM keeps only the first 8000 chars of stderr; Rails noise (10 KB in the fake) must go elsewhere.
        for scenario in (*CHECK_SCENARIOS, *HOST_SCENARIOS):
            with self.subTest(step=scenario):
                lines = self.real_error(scenario).splitlines()
                self.assertLess(len(self.real_error(scenario)), 500)
                verdict = ('instagram_coordination_preflight_failed' if scenario in CHECK_SCENARIOS
                           else 'instagram_coordination_preflight_host_failed')
                self.assertEqual(lines[:2], ['instagram_coordination_preflight_ran',
                                             f"{verdict} step={scenario.split(':')[0]}"])

    def test_green_coordination_failure_suspends_instagram_and_continues_the_deploy(self):
        # #1540: a check.sh that ran and failed suspends Instagram assisted on the green (same helper as recovery,
        # plus the marker), restarts what runs with it on, and the traffic/worker switch still happens.
        for workflow in WORKFLOWS:
            for name in ('Shift HTTPS listener to green', 'Switch Sidekiq workers to green'):
                for code, noise in [(code, '') for code in CHECK_SCENARIOS] + [('proxy_preflight_failed', 'sudo: unable to resolve host ip-10-0-0-1\n')]:
                    with self.subTest(stack=workflow.name, path=name, code=code, noise=bool(noise)):
                        # sudo may print before check.sh: the sentinel counts on any line.
                        result, state = self.execute(run_block(workflow.read_text(), name),
                                                     listener='tg-blue', running_workers=['i-blue'],
                                                     fail_coordination_instance='i-green',
                                                     coordination_error=noise + self.real_error(code))
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn(f'::warning::INSTAGRAM_ASSISTED_SUSPENDED step={code}\n',
                                      result.stdout)
                        self.assertEqual(state['markers'], {'i-green': f'INSTAGRAM_ASSISTED_SUSPENDED step={code}'})
                        self.assertEqual([node for node, _ in state['suspensions']], ['i-green'])
                        self.assertEqual([node for node, _ in state['web_restarts']], ['i-green'])
                        suspension = state['suspensions'][0][1]
                        restart = state['web_restarts'][0][1]
                        self.assertLess(state['coordination_checks'][0][1], suspension)
                        self.assertLess(suspension, restart)
                        if name == 'Shift HTTPS listener to green':
                            switch = self.call_index(state, lambda call: call[1] == 'modify-listener')
                            # Traffic only after the restarted green target is back in service.
                            self.assertEqual(len(state['green_in_service']), 1)
                            self.assertLess(restart, state['green_in_service'][0])
                            self.assertLess(state['green_in_service'][0], switch)
                            self.assertEqual(state['listener'], 'tg-green')
                            self.assert_pointers(state, 'tg-green', 'i-green')
                        else:
                            self.assertEqual(state['workers'], [['stop', 'i-blue'], ['start', 'i-green']])
                            self.assertEqual(state['running_workers'], ['i-green'])
                            start = self.call_index(state, lambda call: call[1] == 'send-command' and
                                'systemctl start chatwoot-worker.service' in call[call.index('--parameters')+1])
                            self.assertLess(restart, start)

    def test_green_coordination_failures_without_a_preflight_verdict_stay_fatal(self):
        sentinel = 'instagram_coordination_preflight_ran\n'
        cases = {
            **{f'status-{status}': {'coordination_status': status, 'coordination_error': self.real_error('tunnel_timeout')}
               for status in ('TimedOut', 'Cancelled', 'Cancelling', 'DeliveryTimedOut', 'ExecutionTimedOut',
                              'InProgress', 'Pending', 'Undeliverable', 'Terminated')},
            'failed-without-sentinel': {'coordination_error': 'sudo: /opt/chatwoot/igcoord/check.sh: command not found\n'},
            'failed-empty-stderr': {'coordination_error': ''},
            **{f'host-{code}': {'coordination_error': self.real_error(code)} for code in HOST_SCENARIOS},
            'verdict-without-sentinel': {'coordination_error': 'instagram_coordination_preflight_failed step=tunnel_timeout\n'},
            'truncated-before-code': {'coordination_error': sentinel + 'x' * 7900},
            'malformed-code': {'coordination_error': sentinel + 'instagram_coordination_preflight_failed step=10.0.0.1:6379\n'},
            'invocation-not-json': {'invocation_raw': 'not json'},
            'status-not-string': {'invocation_raw': '{"Status": null, "Output": "", "Error": ""}'},
            'error-not-string': {'invocation_raw': '{"Status": "Failed", "Output": "", "Error": null}'},
            'suspension-failed': {'coordination_error': self.real_error('proxy_preflight_failed'),
                                  'fail_suspension_instance': 'i-green'},
            'restart-failed': {'coordination_error': self.real_error('proxy_preflight_failed'),
                               'fail_restart_instance': 'i-green'},
        }
        for workflow in WORKFLOWS:
            for name in ('Shift HTTPS listener to green', 'Switch Sidekiq workers to green'):
                for case, failure in cases.items():
                    with self.subTest(stack=workflow.name, path=name, case=case):
                        # A check that never leaves Pending/InProgress is still fatal once the wait ends.
                        self.env['INSTAGRAM_CHECK_WAIT_SECONDS'] = '0'
                        self.addCleanup(self.env.pop, 'INSTAGRAM_CHECK_WAIT_SECONDS', None)
                        result, state = self.execute(run_block(workflow.read_text(), name),
                                                     listener='tg-blue', running_workers=['i-blue'],
                                                     fail_coordination_instance='i-green', **failure)
                        if case in ('status-InProgress', 'status-Pending'):
                            self.assertIn('instagram_preflight_status_unexpected', result.stderr)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertNotIn('::warning::', result.stdout)
                        self.assertNotIn('10.0.0.1', result.stdout + result.stderr)
                        if case.startswith('host-'):
                            self.assertIn(f"instagram_preflight_failed_without_verdict host_step={case[5:].split(':')[0]}",
                                          result.stderr)
                        if not case.startswith(('suspension', 'restart')):
                            self.assertNotIn('suspensions', state)
                            self.assertNotIn('INSTAGRAM_ASSISTED_SUSPENDED', result.stderr)
                        self.assertNotIn('markers', state if case != 'restart-failed' else {})
                        self.assertNotIn('green_in_service', state)
                        self.assertEqual(state['running_workers'], ['i-blue'])
                        self.assertEqual(state['workers'], [])
                        self.assertEqual(state['listener'], 'tg-blue')
                        self.assertEqual(state['writes'], [])
                        self.assertFalse(any(call[1] in ('modify-listener', 'terminate-instances', 'delete-target-group')
                                             for call in state['calls']))

    def test_green_coordination_success_keeps_instagram_and_reports_an_earlier_suspension(self):
        for workflow in WORKFLOWS:
            for name in ('Shift HTTPS listener to green', 'Switch Sidekiq workers to green'):
                for earlier in ('', 'proxy_preflight_failed'):
                    with self.subTest(stack=workflow.name, path=name, earlier=earlier):
                        markers = {'i-green': f'INSTAGRAM_ASSISTED_SUSPENDED step={earlier}'} if earlier else {}
                        result, state = self.execute(run_block(workflow.read_text(), name), listener='tg-blue',
                                                     running_workers=['i-blue'], markers=markers)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertNotIn('suspensions', state)
                        self.assertNotIn('web_restarts', state)
                        self.assertNotIn('INSTAGRAM_ASSISTED_SUSPENDED', result.stderr)
                        warning = (f'::warning::INSTAGRAM_ASSISTED_SUSPENDED step={earlier} '
                                   '(suspenso antes deste passo)')
                        self.assertEqual(warning in result.stdout, bool(earlier))
                        if not earlier:
                            self.assertNotIn('::warning::', result.stdout)
                        waited = 'green_in_service' in state
                        self.assertEqual(waited, bool(earlier) and name == 'Shift HTTPS listener to green')
                        if waited:
                            self.assertLess(state['green_in_service'][0],
                                            self.call_index(state, lambda call: call[1] == 'modify-listener'))

    def test_suspension_in_worker_step_is_reported_not_rechecked_by_listener_step(self):
        for workflow in WORKFLOWS:
            source = workflow.read_text()
            _, first = self.execute(run_block(source, 'Switch Sidekiq workers to green'), listener='tg-blue',
                                    running_workers=['i-blue'], fail_coordination_instance='i-green',
                                    coordination_error=self.real_error('coordination_ping_failed'))
            result, state = self.execute(run_block(source, 'Shift HTTPS listener to green'), listener='tg-blue',
                                         running_workers=['i-green'], markers=first['markers'],
                                         fail_coordination_instance='i-green')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('::warning::INSTAGRAM_ASSISTED_SUSPENDED step=coordination_ping_failed '
                          '(suspenso antes deste passo)', result.stdout)
            self.assertNotIn('suspensions', state)
            self.assertLess(state['green_in_service'][0],
                            self.call_index(state, lambda call: call[1] == 'modify-listener'))
            self.assertEqual(state['listener'], 'tg-green')

    def test_coordination_proof_precedes_every_traffic_shift(self):
        for workflow in WORKFLOWS:
            for name, instance in (('Shift HTTPS listener to green', 'i-green'),
                                   ('Restore previous target group', 'i-blue'),
                                   ('Cleanup failed green resources before traffic shift', 'i-blue')):
                result, state = self.execute(run_block(workflow.read_text(), name))
                self.assertEqual(result.returncode, 0, result.stderr)
                switch = next(i for i, call in enumerate(state['calls'], 1) if call[1] == 'modify-listener')
                proof = 'coordination_checks' if instance == 'i-green' else 'suspensions'
                self.assertTrue(any(node == instance and number < switch
                                    for node, number in state[proof]))

    def test_old_blue_fallback_and_unavailable_coordinator_restore_general_services(self):
        for workflow in WORKFLOWS:
            for name in ('Restore previous target group', 'Cleanup failed green resources before traffic shift'):
                for failure in ('missing_coordination_instance', 'fail_coordination_instance'):
                    with self.subTest(stack=workflow.name, path=name, scenario=failure):
                        result, state = self.execute(run_block(workflow.read_text(), name),
                            running_workers=['i-green'], **{failure: 'i-blue'},
                            outcomes={'synthetic': 'preserved'}, coordination_state={'epoch': 'unchanged'})
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(state['running_workers'], ['i-blue'])
                        self.assert_pointers(state, 'tg-blue', 'i-blue')
                        self.assertEqual(state['outcomes'], {'synthetic': 'preserved'})
                        self.assertEqual(state['coordination_state'], {'epoch': 'unchanged'})
                        self.assertEqual(state.get('coordination_checks', []), [])
                        suspension = state['suspensions'][0][1]
                        stop = next(i for i, call in enumerate(state['calls'], 1)
                                    if call[1] == 'send-command' and 'stop chatwoot-worker.service' in call[call.index('--parameters')+1])
                        self.assertLess(suspension, stop)

    def test_suspension_failure_preserves_last_online_worker_and_reports_error(self):
        for workflow in WORKFLOWS:
            for name in ('Restore previous target group', 'Cleanup failed green resources before traffic shift'):
                result, state = self.execute(run_block(workflow.read_text(), name),
                    running_workers=['i-green'], fail_suspension_instance='i-blue')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('instagram_recovery_suspension_failed', result.stderr)
                self.assertEqual(state['running_workers'], ['i-green'])
                self.assertEqual(state['workers'], [])
                self.assertEqual(state['writes'], [])
                self.assertEqual(state['listener'], 'tg-green')
                self.assertFalse(any(call[1] in ('modify-listener', 'terminate-instances', 'delete-target-group')
                                     for call in state['calls']))

    def test_stopped_target_suspension_failure_never_reports_rollback_success(self):
        for workflow in WORKFLOWS:
            result, state = self.execute(run_block(workflow.read_text(), 'Restore previous target group'),
                instance_state='stopped', boot_worker_enabled=True, running_workers=['i-green'],
                fail_suspension_instance='i-blue')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('instagram_recovery_suspension_failed', result.stderr)
            self.assertEqual(state['listener'], 'tg-green')
            self.assertEqual(state['writes'], [])
            self.assertTrue(all(len(event[2]) <= 1 for event in state['worker_timeline']))
            self.assertFalse(any(call[1] in ('modify-listener', 'delete-target-group', 'terminate-instances')
                                 for call in state['calls']))

    def test_suspension_helper_preserves_published_process_base_env_and_outcomes(self):
        helper = (ROOT / 'scripts/deploy/suspend-instagram-assisted.py').read_text().rstrip('\n')
        for old in (False, True):
            with self.subTest(old_blue=old):
                app = self.directory / ('old-app' if old else 'new-app')
                units = self.directory / ('old-units' if old else 'new-units')
                app.mkdir(); units.mkdir()
                (app / '.env').write_text('REDIS_URL=synthetic\nINSTAGRAM_TESTER_AUTOMATION_ENABLED=true\n')
                (app / 'instagram-tester.env').write_text('KEEP=synthetic\nINSTAGRAM_TESTER_AUTOMATION_ENABLED=true\n')
                (app / 'outcomes').write_text('preserve')
                (app / 'igcoord').mkdir()
                (app / 'igcoord/redis.env').write_text('REDIS_URL=coordinator\n')
                before = {file: file.read_bytes() for file in (app / '.env', app / 'outcomes', app / 'igcoord/redis.env')}
                published = {}
                for service in ('chatwoot-web.service', 'chatwoot-worker.service'):
                    overlay = '' if old else f' --env-file {app}/instagram-tester.env'
                    command = f'/usr/bin/docker run --rm --env-file {app}/.env{overlay} previous-image:sha bundle exec synthetic'
                    published[service] = command
                    (units / service).write_text(f'[Service]\nExecStart={command}\n')
                fake = self.directory / 'systemctl'
                fake.write_text('#!/bin/sh\ncat "$TEST_UNITS/$2"\n'); fake.chmod(0o700)
                script = helper.replace("Path('/opt/chatwoot')", f'Path({str(app)!r})').replace(
                    "Path('/etc/systemd/system')", f'Path({str(units)!r})')
                result = subprocess.run([sys.executable, '-c', script], capture_output=True, text=True,
                    env={**self.env, 'PATH': f'{self.directory}:{self.bin}:/usr/bin:/bin', 'TEST_UNITS': str(units)}, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((app / 'instagram-tester.env').read_text(),
                                 'KEEP=synthetic\nINSTAGRAM_TESTER_AUTOMATION_ENABLED=false\n')
                for file, contents in before.items():
                    self.assertEqual(file.read_bytes(), contents)
                for service, command in published.items():
                    self.assertEqual((units / service).read_text(), f'[Service]\nExecStart={command}\n')
                    if old:
                        override = (units / f'{service}.d/zz-instagram-recovery.conf').read_text()
                        self.assertIn(command.replace(f'--env-file {app}/.env',
                            f'--env-file {app}/.env --env-file {app}/instagram-tester.env'), override)
                    else:
                        self.assertFalse((units / f'{service}.d').exists())

    def test_invalid_published_worker_aborts_suspension_before_writes(self):
        app = self.directory / 'invalid-app'; app.mkdir()
        overlay = app / 'instagram-tester.env'
        overlay.write_text('INSTAGRAM_TESTER_AUTOMATION_ENABLED=true\n')
        fake = self.directory / 'systemctl'
        fake.write_text(f'#!/bin/sh\nif [ "$2" = chatwoot-web.service ]; then echo "ExecStart=/usr/bin/docker run --env-file {app}/.env previous-image:sha"; else echo "ExecStart=/bin/false"; fi\n')
        fake.chmod(0o700)
        helper = (ROOT / 'scripts/deploy/suspend-instagram-assisted.py').read_text().rstrip('\n').replace(
            "Path('/opt/chatwoot')", f'Path({str(app)!r})').replace(
            "Path('/etc/systemd/system')", f'Path({str(self.directory / "units")!r})')
        result = subprocess.run([sys.executable, '-c', helper], text=True, capture_output=True,
            env={**self.env, 'PATH': f'{self.directory}:{self.bin}:/usr/bin:/bin'}, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('instagram_recovery_published_command_missing:chatwoot-worker.service', result.stderr)
        self.assertEqual(overlay.read_text(), 'INSTAGRAM_TESTER_AUTOMATION_ENABLED=true\n')
        self.assertFalse((self.directory / 'units').exists())

    def test_all_application_containers_share_tunnel_env_and_ca_before_database_prepare(self):
        for workflow in WORKFLOWS:
            source = workflow.read_text()
            for line in source.splitlines():
                if 'docker run ' not in line:
                    continue
                with self.subTest(stack=workflow.name, command=line.strip()):
                    self.assertIn('--add-host ig-coord.internal:host-gateway', line)
                    self.assertIn('--add-host ig-proxy.internal:host-gateway', line)
                    self.assertIn('ca.crt:/run/igcoord/ca.crt:ro', line)
                    self.assertLess(line.index('instagram-tester.env'), line.index('igcoord/redis.env'))
            self.assertLess(source.index('"$APP_DIR/igcoord/check.sh"'), source.index('rails db:chatwoot_prepare'))
            self.assertEqual(source.count('Wants=instagram-coordination-tunnel.service'), 2)
            self.assertEqual(source.count('After=docker.service network-online.target instagram-coordination-tunnel.service'), 2)

    def test_previous_is_written_only_after_confirmed_green_and_never_on_failed_switch(self):
        for workflow in WORKFLOWS:
            script = run_block(workflow.read_text(), 'Shift HTTPS listener to green')
            parameters = {'current-tg': 'tg-blue', 'current-instance': 'i-blue',
                          'previous-tg': 'tg-older', 'previous-instance': 'i-older'}
            result, success = self.execute(script, listener='tg-blue', parameters=parameters)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_pointers(success, 'tg-green', 'i-green')
            calls = success['calls']
            switch = next(i for i, call in enumerate(calls) if call[1] == 'modify-listener')
            current = [i for i, call in enumerate(calls) if call[1] == 'put-parameter'
                       and call[call.index('--name')+1].startswith('current-')]
            previous = [i for i, call in enumerate(calls) if call[1] == 'put-parameter'
                        and call[call.index('--name')+1].startswith('previous-')]
            self.assertEqual([call[1] for call in calls[switch+1:min(current)]],
                             ['describe-listeners', 'describe-target-health'])
            self.assertEqual(len(current), 2)
            self.assertEqual(len(previous), 2)
            self.assertLess(max(current), min(previous))
            self.assertTrue(all(listener == 'tg-green' for _, _, listener in success['writes']))
            for number in range(switch+1, max(current)+2):
                for applied in (False, True) if number == switch+1 else (False,):
                    with self.subTest(stack=workflow.name, fail_at=number, response_lost=applied):
                        result, state = self.execute(script, listener='tg-blue', parameters=parameters.copy(),
                                                     fail_at=number, fail_after_apply=applied)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(state['parameters']['previous-tg'], 'tg-older')
                        self.assertEqual(state['parameters']['previous-instance'], 'i-older')
                        self.assertFalse(any(name.startswith('previous-') for name, _, _ in state['writes']))
                        markers = (self.directory / 'github-env').read_text()
                        self.assertNotIn('PREVIOUS_WRITE_ATTEMPTED=true', markers)
                        self.assertNotIn('TRAFFIC_SHIFT_DONE=true', markers)

    def test_cleanup_restarts_blue_worker_only_with_prior_intent(self):
        for workflow in WORKFLOWS:
            for marker in (None, 'false', 'true'):
                with self.subTest(stack=workflow.name, marker=marker):
                    self.env.pop('BLUE_WORKER_STOPPED', None)
                    if marker is not None:
                        self.env['BLUE_WORKER_STOPPED'] = marker
                    self.env['GREEN_WORKER_START_ATTEMPTED'] = 'false'
                    result, state = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'),
                        running_workers=[] if marker == 'true' else ['i-blue'])
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(state['workers'], [['start', 'i-blue']] if marker == 'true' else [])
                    self.assertEqual(state['running_workers'], ['i-blue'])
                    self.assert_pointers(state, 'tg-blue', 'i-blue')
                    self.assertIn('terminated_at', state)
        self.env['BLUE_WORKER_STOPPED'] = 'true'
        self.env['GREEN_WORKER_START_ATTEMPTED'] = 'true'

    def test_cancelled_cleanup_uses_durable_intent_after_interrupted_worker_switch(self):
        for workflow in WORKFLOWS:
            source = workflow.read_text()
            for name in ('Refresh AWS credentials for cleanup', 'Cleanup failed green resources before traffic shift'):
                header = source.split(f'      - name: {name}\n', 1)[1].split('        run:', 1)[0].split('      - name:', 1)[0]
                self.assertIn("if: (failure() || cancelled()) && env.TRAFFIC_SHIFT_DONE != 'true'", header)
            self.assertLess(source.index('      - name: Mark blue worker stop'),
                            source.index('      - name: Switch Sidekiq workers to green'))
            marker = source.split('      - name: Mark blue worker stop\n', 1)[1].splitlines()[0].removeprefix('        run: ')
            self.assertEqual(marker, 'echo "BLUE_WORKER_STOPPED=true" >> "$GITHUB_ENV"')
            switch = run_block(source, 'Switch Sidekiq workers to green')
            _, success = self.execute(switch, running_workers=['i-blue'])
            stop = next(i for i, call in enumerate(success['calls'], 1)
                        if call[1] == 'send-command' and 'stop chatwoot-worker.service' in call[call.index('--parameters')+1])
            start = next(i for i, call in enumerate(success['calls'], 1)
                         if call[1] == 'send-command' and 'start chatwoot-worker.service' in call[call.index('--parameters')+1])
            for number in (stop, stop+1, start, start+1):
                with self.subTest(stack=workflow.name, interrupted_at=number):
                    self.env.pop('BLUE_WORKER_STOPPED', None)
                    self.env.pop('GREEN_WORKER_START_ATTEMPTED', None)
                    result, interrupted = self.execute(marker+'\n'+switch, running_workers=['i-blue'],
                                                       fail_at=number, fail_after_apply=True)
                    self.assertEqual(result.returncode, 77, result.stderr)
                    markers = dict(line.split('=', 1) for line in (self.directory / 'github-env').read_text().splitlines())
                    self.assertEqual(markers['BLUE_WORKER_STOPPED'], 'true')
                    self.assertNotIn('TRAFFIC_SHIFT_DONE', markers)
                    self.env.update(markers)  # GitHub makes prior-step GITHUB_ENV durable for cancellation cleanup.
                    result, recovered = self.execute(run_block(source, 'Cleanup failed green resources before traffic shift'),
                                                      running_workers=interrupted['running_workers'])
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(recovered['running_workers'], ['i-blue'])
                    self.assertEqual(recovered['workers'][-1], ['start', 'i-blue'])
                    self.assertTrue(all(len(event[2]) <= 1 for event in recovered['worker_timeline']))
                    self.assert_pointers(recovered, 'tg-blue', 'i-blue')
        self.env['BLUE_WORKER_STOPPED'] = 'true'
        self.env['GREEN_WORKER_START_ATTEMPTED'] = 'true'

    def test_cleanup_running_deploy_tags_and_schedules_retirement_without_termination(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                result, state = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'),
                                             deploy_status='DEPLOY_RUNNING', running_workers=['i-green'])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(state['tags'], {'i-green': {'DeployCleanup': 'pending'}})
                self.assertTrue(state['retirement_scheduled'])
                self.assertNotIn('terminated_at', state)
                self.assertFalse(any(call[1] == 'terminate-instances' for call in state['calls']))
                self.assertEqual(state['running_workers'], ['i-blue'])
                self.assert_pointers(state, 'tg-blue', 'i-blue')
                calls = state['calls']
                tag = next(i for i, call in enumerate(calls) if call[1] == 'create-tags')
                retire = next(i for i, call in enumerate(calls) if call[1] == 'send-command'
                              and 'systemd-run --unit=green-retire' in call[call.index('--parameters')+1])
                self.assertLess(tag, retire)
                self.assertEqual(calls[retire+1][:2], ['ssm', 'get-command-invocation'])
                commands = state['commands']
                self.assertEqual([command['kind'] for command in commands.values()][-2:], ['deploy-status', 'retirement'])
                self.assertGreaterEqual(state['target_deleted_at'], state['target_drained_at'])

    def test_cleanup_retirement_failure_during_migration_preserves_instance_and_reports_error(self):
        for workflow in WORKFLOWS:
            for failure in ({'fail_operation': 'create-tags'}, {'fail_command_kind': 'retirement'},
                            {'fail_invocation_kind': 'retirement'},
                            *({'retirement_status': status} for status in ('Failed', 'Cancelled', 'TimedOut', 'InProgress'))):
                with self.subTest(stack=workflow.name, failure=failure):
                    result, state = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'),
                                                 deploy_status='DEPLOY_RUNNING', running_workers=['i-green'], **failure)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn('blue_green_deferred_shutdown_failed', result.stderr)
                    self.assertNotIn('terminated_at', state)
                    self.assertNotIn('retirement_scheduled', state)
                    self.assertFalse(any(call[1] == 'terminate-instances' for call in state['calls']))
                    self.assertEqual(state['running_workers'], ['i-blue'])
                    self.assert_pointers(state, 'tg-blue', 'i-blue')
                    if failure.get('retirement_status') == 'InProgress':
                        command_id = next(key for key, command in state['commands'].items() if command['kind'] == 'retirement')
                        self.assertEqual(sum(call[1] == 'get-command-invocation' and command_id in call for call in state['calls']), 6)

    def test_cleanup_idle_deploy_terminates_and_propagates_termination_failure(self):
        for workflow in WORKFLOWS:
            for fail in (False, True):
                with self.subTest(stack=workflow.name, termination_failed=fail):
                    result, state = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'),
                        deploy_status='DEPLOY_IDLE', **({'fail_operation': 'terminate-instances'} if fail else {}))
                    self.assertEqual(result.returncode, 77 if fail else 0, result.stderr)
                    self.assertEqual(state['calls'][-1][:2], ['ec2', 'terminate-instances'])
                    self.assertNotIn('tags', state)
                    self.assertNotIn('retirement_scheduled', state)
                    self.assertEqual('terminated_at' in state, not fail)
                    self.assert_pointers(state, 'tg-blue', 'i-blue')

    def test_remote_deploy_probe_and_retirement_commands_wait_for_migration_with_fakes(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                result, state = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'),
                                             deploy_status='DEPLOY_RUNNING')
                self.assertEqual(result.returncode, 0, result.stderr)
                commands = {command['kind']: command['payload'][0] for command in state['commands'].values()}
                marker = self.directory / 'deploy.running'
                self.env['MIGRATION_MARKER'] = str(marker)
                self.env['REMOTE_LOG'] = str(self.directory / 'retirement.log')
                marker.touch()
                probe = commands['deploy-status'].replace('/run/chatwoot-deploy.running', '"$MIGRATION_MARKER"')
                result, _ = self.execute(probe)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), 'DEPLOY_RUNNING')
                marker.unlink()
                result, _ = self.execute(probe)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), 'DEPLOY_IDLE')
                marker.touch()
                clock_fake = (self.bin / 'sleep').read_text()
                (self.bin / 'systemd-run').write_text('''#!/bin/sh
set -eu
[ "$1" = --unit=green-retire ]; [ "$2" = --no-block ]; [ "$3" = sh ]; [ "$4" = -c ]
printf 'scheduled\\n' >> "$REMOTE_LOG"
shift 2
"$@"
''')
                (self.bin / 'sleep').write_text('''#!/bin/sh
set -eu
[ "$1" = 5 ]; [ -e "$MIGRATION_MARKER" ]
printf 'migration-wait\\n' >> "$REMOTE_LOG"
rm "$MIGRATION_MARKER"
''')
                (self.bin / 'shutdown').write_text('''#!/bin/sh
set -eu
[ "$1" = -h ]; [ "$2" = now ]; [ ! -e "$MIGRATION_MARKER" ]
printf 'shutdown\\n' >> "$REMOTE_LOG"
''')
                retirement = commands['retirement'].replace('/run/chatwoot-deploy.running', str(marker))
                result, _ = self.execute(retirement)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(Path(self.env['REMOTE_LOG']).read_text().splitlines(),
                                 ['scheduled', 'migration-wait', 'shutdown'])
                # Restore the clock fake before exercising the other workflow.
                (self.bin / 'sleep').write_text(clock_fake)
                Path(self.env['REMOTE_LOG']).unlink()

    def test_cleanup_unknown_deploy_status_during_migration_must_preserve_instance(self):
        # Safety regression reproduced against the earlier workflow: an unavailable
        # status probe terminated green during migration. Unknown must never mean IDLE.
        for workflow in WORKFLOWS:
            for failure in ({'fail_command_kind': 'deploy-status'}, {'fail_invocation_kind': 'deploy-status'}):
                with self.subTest(stack=workflow.name, failure=failure):
                    result, state = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'),
                                                 deploy_status='DEPLOY_RUNNING', **failure)
                    self.assertFalse(any(call[1] == 'terminate-instances' for call in state['calls']),
                                     'active migration was terminated after the deploy status probe failed')
                    self.assertNotIn('terminated_at', state)
                    self.assertEqual(result.returncode, 1, 'unknown deploy status must not report successful cleanup')
                    self.assertIn('blue_green_deploy_status_unknown', result.stderr)
                    self.assert_pointers(state, 'tg-blue', 'i-blue')

    # #1350: build falho antes de a green receber a imagem.
    def before_image(self):
        """Ambiente da limpeza quando o deploy caiu antes do "Publish runtime image parameter"."""
        saved = {key: self.env.get(key) for key in ('GREEN_IMAGE_PUBLISHED', 'GREEN_TG_ARN',
                                                     'GREEN_WORKER_START_ATTEMPTED', 'BLUE_WORKER_STOPPED')}
        self.env.update({'GREEN_IMAGE_PUBLISHED': 'false', 'GREEN_TG_ARN': '',
                         'GREEN_WORKER_START_ATTEMPTED': 'false', 'BLUE_WORKER_STOPPED': 'false'})

        def restore():
            for key, value in saved.items():
                self.env[key] = value
        self.addCleanup(restore)
        # O tráfego nunca saiu da blue.
        return {'listener': 'tg-blue', 'running_workers': ['i-blue'],
                'parameters': {'current-tg': 'tg-blue', 'current-instance': 'i-blue',
                               'previous-tg': 'tg-older', 'previous-instance': 'i-older'}}

    def assert_blue_untouched(self, state):
        self.assertNotIn('i-blue', state.get('command_suspensions', {}).values())
        self.assertNotIn('i-blue', state.get('command_web_restarts', {}).values())
        self.assertFalse(any(call[1] == 'modify-listener' for call in state['calls']))
        self.assertEqual(state['writes'], [])

    def test_cleanup_after_freeze_abort_keeps_blue_untouched(self):
        # #1979: o deploy parou pelo congelamento logo antes do balanceador. A imagem já subiu e a green rodou o boot,
        # mas tráfego, worker e Instagram nunca saíram da blue.
        for workflow in WORKFLOWS:
            initial = self.before_image()
            self.env['GREEN_IMAGE_PUBLISHED'] = 'true'
            self.env['FREEZE_ABORTED'] = 'true'
            self.addCleanup(self.env.pop, 'FREEZE_ABORTED', None)
            script = run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift')
            with self.subTest(stack=workflow.name, scenario='boot-done'):
                result, state = self.execute(script, deploy_status='DEPLOY_IDLE', **initial)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_blue_untouched(state)
                self.assertEqual(state['terminated'], ['i-green'])
                self.assertEqual(state['running_workers'], ['i-blue'])
                self.assert_pointers(state, 'tg-blue', 'i-blue')
            with self.subTest(stack=workflow.name, scenario='listener-not-on-blue'):
                result, state = self.execute(script, deploy_status='DEPLOY_IDLE', **{**initial, 'listener': 'tg-green'})
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn('blue_green_destination_mismatch', result.stderr)
                self.assert_blue_untouched(state)
                self.assertNotIn('terminated', state)
            with self.subTest(stack=workflow.name, scenario='blue-worker-stopped'):
                # Sem o congelamento como causa única (worker da blue já parado), a recuperação completa continua.
                self.env['BLUE_WORKER_STOPPED'] = 'true'
                try:
                    result, state = self.execute(script, deploy_status='DEPLOY_IDLE', **initial)
                finally:
                    self.env['BLUE_WORKER_STOPPED'] = 'false'
                self.assertIn('i-blue', state.get('command_suspensions', {}).values())

    def test_freeze_abort_steps_mark_the_abort_for_cleanup(self):
        for workflow in WORKFLOWS:
            source = workflow.read_text()
            for name in ('Abort if production was frozen', 'Abort if production was frozen before traffic'):
                with self.subTest(stack=workflow.name, step=name):
                    block = run_block(source, name)
                    self.env['DESCONGELAR'] = 'false'
                    try:
                        result, state = self.execute(block, parameters={'deploy-freeze': 'on:1:1:pedido'})
                        self.assertEqual(result.returncode, 1, result.stderr)
                        self.assertIn('FREEZE_ABORTED=true', (self.directory / 'github-env').read_text())
                        result, state = self.execute(block, parameters={'deploy-freeze': 'on:1:1:pedido',
                                                                        'deploy-freeze-released': 'on:1:1:pedido'})
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual((self.directory / 'github-env').read_text(), '')
                        self.env['DESCONGELAR'] = 'true'
                        result, state = self.execute(block, parameters={'deploy-freeze': 'on:1:1:pedido'})
                        self.assertEqual(result.returncode, 0, result.stderr)
                    finally:
                        self.env.pop('DESCONGELAR', None)
        # O passo antes do tráfego fica entre a credencial renovada e o registro da green.
        for workflow in WORKFLOWS:
            source = workflow.read_text()
            with self.subTest(stack=workflow.name, check='order'):
                self.assertLess(source.index('      - name: Refresh AWS credentials before traffic steps'),
                                source.index('      - name: Abort if production was frozen before traffic'))
                self.assertLess(source.index('      - name: Abort if production was frozen before traffic'),
                                source.index('      - name: Register green target group'))

    def test_cleanup_without_image_terminates_green_even_when_blue_recovery_fails(self):
        for workflow in WORKFLOWS:
            initial = self.before_image()
            script = run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift')
            with self.subTest(stack=workflow.name, scenario='blue-ok'):
                result, state = self.execute(script, **initial)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(state['terminated'], ['i-green'])
                self.assertEqual(state['calls'][0][:2], ['ecr', 'describe-images'])
                # Sem imagem não há migration: nada de sondar o deploy.sh, marcar pending ou esperar drenagem.
                self.assertFalse(any(command['instance'] == 'i-green' for command in state.get('commands', {}).values()))
                self.assertNotIn('tags', state)
                self.assertFalse(any(event[0] == 'sleep' for event in state['events']))
                self.assert_pointers(state, 'tg-blue', 'i-blue')
                # #1979: a blue não foi tocada: nem suspensão, nem web reiniciado, nem listener ou ponteiro regravado.
                self.assert_blue_untouched(state)
            with self.subTest(stack=workflow.name, scenario='listener-unreadable'):
                result, state = self.execute(script, fail_operation='describe-listeners', **initial)
                # O erro original da conferência não é engolido pela terminação da green.
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn('não chegou a receber a imagem', result.stdout)
                self.assertEqual(state['terminated'], ['i-green'])
                self.assertEqual(state['calls'][-1][:2], ['ec2', 'terminate-instances'])
                self.assert_blue_untouched(state)
                self.assertEqual(state['running_workers'], ['i-blue'])
            with self.subTest(stack=workflow.name, scenario='listener-not-on-blue'):
                result, state = self.execute(script, **{**initial, 'listener': 'tg-green'})
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn('blue_green_destination_mismatch', result.stderr)
                self.assertEqual(state['terminated'], ['i-green'])
                self.assert_blue_untouched(state)
            with self.subTest(stack=workflow.name, scenario='blue-binding-missing'):
                original = self.env['BLUE_TG_ARN']
                self.env['BLUE_TG_ARN'] = ''
                try:
                    result, state = self.execute(script, **initial)
                finally:
                    self.env['BLUE_TG_ARN'] = original
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn('blue_green_recovery_destination_missing', result.stderr)
                self.assertEqual(state['terminated'], ['i-green'])
                self.assertEqual(state['writes'], [])

    def test_cleanup_without_image_reports_failed_termination(self):
        for workflow in WORKFLOWS:
            initial = self.before_image()
            script = run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift')
            for blue_failure in (False, True):
                with self.subTest(stack=workflow.name, blue_failure=blue_failure):
                    # #1979: com a blue intocada, a falha possível dela é o listener fora da blue.
                    extra = {'listener': 'tg-green'} if blue_failure else {}
                    result, state = self.execute(script, fail_operation='terminate-instances', **{**initial, **extra})
                    self.assertIn('blue_green_unused_green_termination_failed', result.stderr)
                    # Com falha na blue, sai com o erro dela; sem, a terminação falha o job. Nunca sucesso.
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertEqual('blue_green_destination_mismatch' in result.stderr, blue_failure)
                    self.assertNotIn('terminated', state)
                    self.assertEqual(state['calls'][-1][:2], ['ec2', 'terminate-instances'])

    def test_cleanup_with_image_or_unknown_ecr_keeps_migration_rule(self):
        # Imagem no ECR (build caiu depois do push) ou ECR ilegível: a green pode estar no deploy.sh (#972).
        for workflow in WORKFLOWS:
            initial = self.before_image()
            script = run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift')
            for image in ('present', 'unreadable'):
                with self.subTest(stack=workflow.name, image=image, scenario='migration-running'):
                    result, state = self.execute(script, image=image, deploy_status='DEPLOY_RUNNING', **initial)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(state['tags'], {'i-green': {'DeployCleanup': 'pending'}})
                    self.assertTrue(state['retirement_scheduled'])
                    self.assertNotIn('terminated', state)
                with self.subTest(stack=workflow.name, image=image, scenario='suspension-failed'):
                    result, state = self.execute(script, image=image, fail_suspension_instance='i-blue', **initial)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('instagram_recovery_suspension_failed', result.stderr)
                    self.assertNotIn('terminated', state)

    def test_cleanup_after_published_image_never_asks_ecr(self):
        for workflow in WORKFLOWS:
            initial = self.before_image()
            self.env['GREEN_IMAGE_PUBLISHED'] = 'true'
            result, state = self.execute(run_block(workflow.read_text(), 'Cleanup failed green resources before traffic shift'),
                                         **initial)
            with self.subTest(stack=workflow.name):
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(any(call[0] == 'ecr' for call in state['calls']))
                self.assertTrue(any(command['kind'] == 'deploy-status' for command in state['commands'].values()))
                self.assertEqual(state['terminated'], ['i-green'])

    def test_workflow_marks_image_published_only_after_build(self):
        for workflow in WORKFLOWS:
            source = workflow.read_text()
            with self.subTest(stack=workflow.name):
                self.assertIn('echo "GREEN_IMAGE_PUBLISHED=false"', run_block(source, 'Discover current infrastructure'))
                self.assertTrue(run_block(source, 'Publish runtime image parameter').splitlines()[2]
                                .startswith('echo "GREEN_IMAGE_PUBLISHED=true"'))
                self.assertLess(source.index('      - name: Build and push image'),
                                source.index('      - name: Publish runtime image parameter'))

    # Parte 1: o desligamento da blue saiu do job deploy.
    def shutdown(self, workflow, **changes):
        self.env.update({'OLD_PREVIOUS_INSTANCE_ID': 'i-older', 'OLD_PREVIOUS_TG_ARN': 'tg-older'})
        self.addCleanup(lambda: [self.env.pop(key, None) for key in ('OLD_PREVIOUS_INSTANCE_ID', 'OLD_PREVIOUS_TG_ARN')])
        state = {'instance_states': {'i-blue': 'running', 'i-older': 'stopped'},
                 'targets': {'tg-blue': 'i-blue', 'tg-green': 'i-green', 'tg-older': 'i-older'}}
        state.update(changes)
        return self.execute(run_block(workflow.read_text(), 'Stop blue instance and remove older rollback'), **state)

    def test_shutdown_job_runs_outside_deploy_lock_after_traffic_shift(self):
        for workflow in WORKFLOWS:
            stack = workflow.name.removeprefix('deploy-').removesuffix('-blue-green.yml')
            source = workflow.read_text()
            job = source.split('\n  desligar-blue:\n', 1)[1].split('\n  rollback:\n', 1)[0]
            with self.subTest(stack=stack):
                self.assertIn('    needs: deploy\n', job)
                self.assertIn("needs.deploy.result == 'success' && needs.deploy.outputs.traffic_shift_done == 'true'", job)
                self.assertIn(f'      group: desligar-blue-{stack}\n      cancel-in-progress: false\n', job)
                self.assertNotIn(f'group: deploy-{stack}-blue-green', job)
                self.assertIn('          sleep 300\n', job)
                # O job deploy não para mais a blue nem espera a janela.
                deploy = source.split('\n  deploy:\n', 1)[1].split('\n  desligar-blue:\n', 1)[0]
                self.assertNotIn('sleep 300', deploy)
                self.assertNotIn('stop-instances', deploy)
                hand_off = run_block(source, 'Hand off blue shutdown')
                for name in ('traffic_shift_done', 'listener_arn', 'blue_instance_id', 'blue_tg_arn', 'green_instance_id',
                             'green_tg_arn', 'old_previous_instance_id', 'old_previous_tg_arn'):
                    self.assertIn(f'echo "{name}=$', hand_off)
                    self.assertIn(f'      {name}: ${{{{ steps.hand-off.outputs.{name} }}}}\n', deploy)
                    if name != 'traffic_shift_done':  # este só entra no if: do job
                        self.assertIn(f'${{{{ needs.deploy.outputs.{name} }}}}', job)

    # #2032: repositório público. IDs e ARNs não passam pelo GITHUB_ENV (o runner os reimprime no cabeçalho de cada passo)
    # nem pelo env: do job desligar-blue; um arquivo carregado pelo BASH_ENV os entrega aos passos bash.
    def test_ids_and_arns_stay_out_of_step_headers(self):
        discovered = ('LB_ARN', 'LISTENER_ARN', 'VPC_ID', 'BLUE_TG_ARN', 'BLUE_INSTANCE_ID', 'OLD_PREVIOUS_INSTANCE_ID',
                      'OLD_PREVIOUS_TG_ARN', 'SUBNET_ID', 'SECURITY_GROUP_IDS', 'IAM_PROFILE_NAME', 'AMI_ID', 'ROOT_DEVICE_NAME')
        hand_off = {'LISTENER_ARN': 'listener-test', 'BLUE_INSTANCE_ID': 'i-blue', 'BLUE_TG_ARN': 'tg blue',
                    'GREEN_INSTANCE_ID': 'i-green', 'GREEN_TG_ARN': 'tg-green', 'OLD_PREVIOUS_INSTANCE_ID': '',
                    'OLD_PREVIOUS_TG_ARN': 'tg-older'}
        state_file = self.directory / 'deploy-estado.sh'
        for workflow in WORKFLOWS:
            source = workflow.read_text()
            job = source.split('\n  desligar-blue:\n', 1)[1].split('\n  rollback:\n', 1)[0]
            with self.subTest(stack=workflow.name):
                discover = run_block(source, 'Discover current infrastructure')
                for name in (*discovered, 'GREEN_INSTANCE_ID', 'GREEN_TG_ARN'):
                    self.assertNotIn(f'echo "{name}=', source)
                    self.assertNotIn(f'env.{name}', source)
                    self.assertNotIn(f'\n      {name}: ', job)  # env: de job, reimpresso em todo passo
                for name in discovered:
                    self.assertIn(f"printf 'export {name}=%q\\n'", discover)
                self.assertIn('echo "BASH_ENV=$deploy_state"', discover)
                self.assertIn("env.GREEN_INSTANCE_LAUNCHED == 'true'", source)
                # O hand-off entra uma vez só, no env: do passo que grava o arquivo.
                load = job.split('      - name: Load deploy hand-off\n', 1)[1].split('\n      - name: ', 1)[0]
                for name in hand_off:
                    self.assertEqual(job.count(f'{name}: ${{{{ needs.deploy.outputs.{name.lower()} }}}}'), 1, name)
                    self.assertIn(f'\n          {name}: ${{{{ needs.deploy.outputs.{name.lower()} }}}}', load)

                (self.directory / 'github-env').write_text('')
                subprocess.run(['/bin/bash', '-e', '-c', run_block(source, 'Load deploy hand-off')], check=True,
                               env={'PATH': '/usr/bin:/bin', 'RUNNER_TEMP': str(self.directory),
                                    'GITHUB_ENV': str(self.directory / 'github-env'), **hand_off})
                self.assertEqual((self.directory / 'github-env').read_text(), f'BASH_ENV={state_file}\n')
                self.assertEqual(state_file.stat().st_mode & 0o777, 0o600)
                # Um bash novo, como o de cada passo, lê de volta os mesmos valores, inclusive com espaço e vazio.
                loaded = subprocess.run(
                    ['/bin/bash', '-c', 'for n in "$@"; do printf "%s=%s\\n" "$n" "${!n-ausente}"; done', '_', *hand_off],
                    env={'PATH': '/usr/bin:/bin', 'BASH_ENV': str(state_file)}, capture_output=True, text=True, check=True)
                self.assertEqual(loaded.stdout, ''.join(f'{name}={value}\n' for name, value in hand_off.items()))
                state_file.unlink()

    def test_shutdown_stops_blue_and_retires_older_rollback(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                result, state = self.shutdown(workflow, parameters={
                    'current-tg': 'tg-green', 'current-instance': 'i-green',
                    'previous-tg': 'tg-blue', 'previous-instance': 'i-blue'})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(state['stopped'], ['i-blue'])
                self.assertEqual(state['waited_stopped'], ['i-blue'])
                self.assertEqual(state['terminated'], ['i-older'])
                self.assertEqual(state['deleted_target_groups'], ['tg-older'])
                self.assertEqual(state['writes'], [])
                self.assertFalse(any(call[1] == 'modify-listener' for call in state['calls']))

    def test_shutdown_keeps_blue_that_became_current_after_rollback(self):
        for workflow in WORKFLOWS:
            for pointer_only in (False, True):
                with self.subTest(stack=workflow.name, pointer_only=pointer_only):
                    # Rollback na janela: o listener (ou o ponteiro current) voltou para a blue.
                    result, state = self.shutdown(workflow, listener='tg-green' if pointer_only else 'tg-blue', parameters={
                        'current-tg': 'tg-blue', 'current-instance': 'i-blue',
                        'previous-tg': 'tg-blue', 'previous-instance': 'i-blue'})
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('voltou a ser a atual', result.stdout)
                    self.assertNotIn('stopped', state)
                    self.assertEqual(state['terminated'], ['i-older'])

    def test_shutdown_after_newer_deploy_tolerates_instances_already_handled(self):
        newer = {'listener': 'tg-next', 'targets': {'tg-blue': 'i-blue', 'tg-green': 'i-green', 'tg-next': 'i-next',
                                                     'tg-older': 'i-older'},
                 'parameters': {'current-tg': 'tg-next', 'current-instance': 'i-next',
                                'previous-tg': 'tg-green', 'previous-instance': 'i-green'}}
        for workflow in WORKFLOWS:
            for blue, older, stop_calls, waits, terminated in (
                    ('stopping', 'terminated', [], ['i-blue'], []),
                    ('stopped', 'shutting-down', [], [], []),
                    ('terminated', 'not-found', [], [], []),
                    ('not-found', 'stopped', [], [], ['i-older']),
                    ('running', 'running', ['i-blue'], ['i-blue'], ['i-older'])):
                with self.subTest(stack=workflow.name, blue=blue, older=older):
                    result, state = self.shutdown(workflow, instance_states={'i-blue': blue, 'i-older': older}, **newer)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(state.get('stopped', []), stop_calls)
                    self.assertEqual(state.get('waited_stopped', []), waits)
                    self.assertEqual(state.get('terminated', []), terminated)
                    # A atual e a previous de agora nunca são tocadas.
                    for call in state['calls']:
                        if call[1] in ('stop-instances', 'terminate-instances'):
                            self.assertNotIn(call[call.index('--instance-ids')+1], ('i-next', 'i-green'))

    def test_shutdown_never_retires_instance_or_target_group_in_use_now(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                # A "mais antiga" registrada virou a previous de agora: fica, com o target group dela.
                result, state = self.shutdown(workflow, instance_states={'i-blue': 'running', 'i-older': 'running'},
                    parameters={'current-tg': 'tg-green', 'current-instance': 'i-green',
                                'previous-tg': 'tg-older', 'previous-instance': 'i-older'})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('terminated', state)
                self.assertNotIn('deleted_target_groups', state)
                self.assertEqual(state['stopped'], ['i-blue'])

    def test_shutdown_unreadable_state_acts_on_nothing(self):
        for workflow in WORKFLOWS:
            for changes in ({'instance_states': {'i-blue': 'api-error', 'i-older': 'stopped'}},
                            {'fail_operation': 'describe-listeners'}, {'fail_operation': 'get-parameter'}):
                with self.subTest(stack=workflow.name, changes=changes):
                    result, state = self.shutdown(workflow, **changes)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(any(call[1] in ('stop-instances', 'terminate-instances', 'delete-target-group')
                                         for call in state['calls']))

    def test_rollback_waits_for_stopping_previous_before_boot(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                result, state = self.execute(run_block(workflow.read_text(), 'Restore previous target group'),
                                             instance_state='stopping', boot_worker_enabled=True, running_workers=['i-green'])
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = state['calls']
                wait = next(i for i, call in enumerate(calls) if call[:3] == ['ec2', 'wait', 'instance-stopped'])
                start = next(i for i, call in enumerate(calls) if call[1] == 'start-instances')
                self.assertLess(wait, start)
                self.assert_pointers(state, 'tg-blue', 'i-blue')

    def test_forgotten_green_warning_lists_only_old_unregistered_instances(self):
        (self.bin / 'date').write_text(f'''#!{sys.executable}
import sys
from datetime import datetime, timedelta, timezone
now = datetime(2026, 10, 12, 12, 0, tzinfo=timezone.utc)
assert sys.argv[1:2] == ['-u'] and sys.argv[2] == '-d' and sys.argv[4] == '+%s'
moment = now - timedelta(hours=2) if sys.argv[3] == '2 hours ago' else datetime.fromisoformat(sys.argv[3])
print(int(moment.timestamp()))
''')
        (self.bin / 'date').chmod(0o700)
        self.env['RUNNER_TEMP'] = str(self.directory)
        rows = [['i-forgotten', '2026-10-10T13:05:12+00:00', 'chatwoot-x-prod-ec2-green-1'],
                ['i-young', '2026-10-12T11:00:00+00:00', 'chatwoot-x-prod-ec2-green-2'],
                ['i-green', '2026-10-01T00:00:00+00:00', 'current'],
                ['i-blue', '2026-10-01T00:00:00+00:00', 'listener'],
                ['i-older', '2026-10-01T00:00:00+00:00', 'previous']]
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                result, state = self.execute(run_block(workflow.read_text(), 'Warn about forgotten green instances'),
                    running_greens=rows, parameters={'current-instance': 'i-green', 'previous-instance': 'i-older'})
                self.assertEqual(result.returncode, 0, result.stderr)
                warnings = [line for line in result.stdout.splitlines() if line.startswith('::warning::')]
                self.assertEqual(len(warnings), 1, result.stdout)
                self.assertNotIn('i-forgotten', warnings[0])
                self.assertIn('Green esquecida: Name=chatwoot-x-prod-ec2-green-1, LaunchTime=2026-10-10T13:05:12+00:00.',
                              warnings[0])
                mutations = ('stop-instances', 'terminate-instances', 'create-tags', 'put-parameter')
                self.assertFalse(any(call[1] in mutations for call in state['calls']))
                header = workflow.read_text().split('      - name: Warn about forgotten green instances\n', 1)[1]
                self.assertTrue(header.startswith('        continue-on-error: true\n'))

    # #2004: telemetria e diagnóstico do blue-green. Tudo aqui é leitura; nenhum passo novo pode decidir o deploy.
    TELEMETRY = ROOT / 'scripts/deploy/deploy-telemetry.py'
    SECRET = 'Ab3' * 13 + 'x'  # 40 caracteres, como uma chave real
    NEW_DEPLOY_STEPS = ('Collect green diagnostics', 'Upload green diagnostics')
    LOGS_ID = '0b1c2d3e-aaaa-4bbb-8ccc-1234567890ab'
    PII = ('+5511999999999', 'joao@x.com', 'Performing SendReplyJob', 'oi quero cotar')
    LOG_SOURCES = ('journalctl', 'cloud-init-output', 'docker logs', 'get-console-output', 'tail ')
    NEW_TEMPOS_STEPS = ('Summarize deploy phase durations', 'Upload deploy phase durations')

    def telemetry_env(self, jobs, gh_fails=False, ssm_online=True):
        """Fakes de aws/gh só para o diagnóstico: registram toda chamada e recusam qualquer escrita."""
        log = self.directory / 'telemetry-calls.jsonl'
        log.write_text('')
        (self.bin / 'python3').write_text(f'#!/bin/sh\nexec {sys.executable} "$@"\n')
        (self.bin / 'sleep').write_text('#!/bin/sh\nexit 0\n')
        (self.bin / 'gh').write_text(f'''#!{sys.executable}
import json, os, sys
with open(os.environ['TELEMETRY_LOG'], 'a') as stream:
    stream.write(json.dumps(['gh', sys.argv[1:]]) + '\\n')
if {gh_fails!r}:
    print('HTTP 502', file=sys.stderr)
    sys.exit(1)
print(json.dumps({{'jobs': {jobs!r}}}))
''')
        (self.bin / 'aws').write_text(f'''#!{sys.executable}
import json, os, sys
args = sys.argv[1:]
with open(os.environ['TELEMETRY_LOG'], 'a') as stream:
    stream.write(json.dumps(['aws', args]) + '\\n')
secret = {self.SECRET!r}
op = tuple(args[:2])
LOGS_ID = {self.LOGS_ID!r}
def query():
    return args[args.index('--query') + 1] if '--query' in args else ''
if op == ('ec2', 'describe-instances'):
    print('2026-10-21T10:00:00+00:00')
elif op == ('elbv2', 'describe-target-health'):
    arn = 'arn:aws:elasticloadbalancing:us-east-1:354307071110:targetgroup/cw-hub2-green-12/abc123def'
    full = {{'TargetHealthDescriptions': [{{'Target': {{'Id': 'i-green', 'Port': 3000}}, 'TargetGroupArn': arn,
        'TargetHealth': {{'State': 'unhealthy', 'Reason': 'Target.Timeout', 'Description': 'Request timed out'}}}}]}}
    if query():
        assert query() == ('TargetHealthDescriptions[].{{Port:Target.Port,State:TargetHealth.State,'
                           'Reason:TargetHealth.Reason,Description:TargetHealth.Description}}'), query()
        print(json.dumps([{{'Port': 3000, 'State': 'unhealthy', 'Reason': 'Target.Timeout',
                            'Description': 'Request timed out'}}]))
    else:
        print(json.dumps(full))
elif op == ('ec2', 'describe-instance-status'):
    print('An error occurred (UnauthorizedOperation) when calling the DescribeInstanceStatus operation: User: '
          'arn:aws:sts::354307071110:assumed-role/chatwoot-x-prod-deploy/GitHubActions is not authorized', file=sys.stderr)
    sys.exit(254)
elif op == ('ssm', 'describe-instance-information'):
    print('Online' if {ssm_online!r} else 'None')
elif op == ('ssm', 'send-command'):
    print(LOGS_ID if 'journalctl' in args[args.index('--parameters') + 1] else 'cmd-diag')
elif op == ('ssm', 'get-command-invocation'):
    if args[args.index('--command-id') + 1] == LOGS_ID:
        # Log de aplicação com dado de cliente: se alguém ler isto, o teste pega.
        print('I, [2026-10-21] Performing SendReplyJob with arguments: +5511999999999 joao@x.com')
        print('cloud-init: + /opt/chatwoot/deploy.sh oi quero cotar')
        sys.exit(0)
    if query() == 'Status':
        print('Success')
    else:
        print('cloud_init_fim_epoch 1792578600')
        print('== saude local')
        print('HTTP 502 em 0.01s')
        print('chatwoot-web   354307071110.dkr.ecr.us-east-1.amazonaws.com/repo:abc1234   MARCA-ESTRUTURAL-7 Up 3 minutes')
        print('SECRET_KEY_BASE=' + secret)
        print('+ 10:00:01 IMAGE_URI=354307071110.dkr.ecr.us-east-1.amazonaws.com/repo:' + secret)
        print('E, ERROR -- : Redis auth failed for redis://default:pw@cache:6379 key ' + secret)
else:
    print('unexpected_aws_call ' + ' '.join(args), file=sys.stderr)
    sys.exit(99)
''')
        for name in ('python3', 'sleep', 'gh', 'aws'):
            (self.bin / name).chmod(0o700)
        temp = Path(tempfile.mkdtemp(prefix='runner-temp-', dir=self.directory))
        for name in ('github-output', 'github-summary', 'github-env'):
            (self.directory / name).write_text('')
        return {**self.env, 'TELEMETRY_LOG': str(log), 'RUNNER_TEMP': str(temp),
                'GITHUB_OUTPUT': str(self.directory / 'github-output'),
                'GITHUB_STEP_SUMMARY': str(self.directory / 'github-summary'),
                'GITHUB_ENV': str(self.directory / 'github-env'),
                'GITHUB_REPOSITORY': 'autonom-ia2/chat', 'GITHUB_RUN_ID': '777', 'GITHUB_RUN_ATTEMPT': '1',
                'GH_TOKEN': 'synthetic', 'GREEN_INSTANCE_ID': 'i-green', 'GREEN_TG_ARN': 'tg-green',
                'BLUE_TG_ARN': 'tg-blue', 'JOB_STATUS': 'failure'}

    @staticmethod
    def deploy_job(steps):
        return [{'name': 'Deploy Green', 'started_at': '2026-10-21T10:00:00Z', 'completed_at': '2026-10-21T10:40:00Z',
                 'steps': [{'name': name, 'status': 'completed', 'conclusion': conclusion,
                            'started_at': start, 'completed_at': end} for name, conclusion, start, end in steps]}]

    def run_telemetry_step(self, workflow, env, step='Collect green diagnostics'):
        script = run_block(workflow.read_text(), step)
        result = subprocess.run(['/bin/bash', '-e', '-c', script], cwd=ROOT, env=env, text=True,
                                capture_output=True, timeout=30)
        calls = [json.loads(line) for line in Path(env['TELEMETRY_LOG']).read_text().splitlines()]
        return result, calls

    def collected_text(self, env):
        texts = [path.read_text() for path in sorted((Path(env['RUNNER_TEMP']) / 'deploy-diagnostico').glob('*'))]
        return texts, Path(env['GITHUB_STEP_SUMMARY']).read_text(), Path(env['GITHUB_OUTPUT']).read_text()

    def assert_read_only(self, calls):
        read_only = {('ec2', 'describe-instances'), ('ec2', 'describe-instance-status'),
                     ('elbv2', 'describe-target-health'), ('ssm', 'describe-instance-information'),
                     ('ssm', 'send-command'), ('ssm', 'get-command-invocation')}
        for tool, args in calls:
            if tool == 'aws':
                self.assertIn(tuple(args[:2]), read_only, args)
            else:
                self.assertEqual(args[0], 'api', args)
                self.assertNotIn('--method', args)
        for tool, args in calls:
            if tool == 'aws' and args[:2] == ['ssm', 'send-command']:
                self.assertEqual(args[args.index('--instance-ids') + 1], 'i-green')
                commands = json.loads(args[args.index('--parameters') + 1])['commands']
                for command in commands:
                    for forbidden in ('systemctl stop', 'systemctl start', 'systemctl restart', 'docker inspect',
                                      'docker exec', '/opt/chatwoot/.env', 'printenv', 'sudo', ' rm ', 'tee ', '>'):
                        self.assertNotIn(forbidden, command.replace('2>&1', '').replace('-o /dev/null', ''))
        # Repositório público: o workflow nunca lê a saída do comando de logs, e o comando que ele lê não tem log.
        for tool, args in calls:
            if tool == 'aws' and args[:2] == ['ssm', 'get-command-invocation']:
                self.assertNotEqual(args[args.index('--command-id') + 1], self.LOGS_ID)
            if tool == 'aws' and args[:2] == ['ssm', 'send-command']:
                commands = ' '.join(json.loads(args[args.index('--parameters') + 1])['commands'])
                if 'journalctl' not in commands:
                    for source in self.LOG_SOURCES:
                        self.assertNotIn(source, commands)

    def test_sanitize_removes_long_tokens_env_values_and_url_credentials(self):
        raw = '\n'.join([
            f'token: {self.SECRET}',
            f'SECRET_KEY_BASE={self.SECRET}',
            'export SMTP_PASSWORD=curta123',
            '  POSTGRES_PASSWORD=curta',
            '+ 10:00:01 IMAGE_URI=repo:abc OUTRO=1',
            'Redis auth failed for redis://default:pw@cache:6379/0',
            'HTTP 200 em 0.01s',
            'chatwoot-web   Up 3 minutes',
            '[   12.0] secret_key_base=curtinha status=500',
            'Authorization: Bearer abc.def',
            'aws_secret\twJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY fim',
            'conexao postgres://chatwoot:pa/ss@db:5432/prod',
            'docker pull 354307071110.dkr.ecr.us-east-1.amazonaws.com/chatwoot-autonomia-prod:abc1234 /var/log/cloud-init-output.log',
        ])
        result = subprocess.run([sys.executable, str(self.TELEMETRY), 'sanitize'], input=raw, text=True,
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(self.SECRET, result.stdout)
        for leaked in ('curta123', 'curta', 'repo:abc', 'OUTRO=1', 'default:pw', 'abc.def', 'EXAMPLEKEY', 'pa/ss'):
            self.assertNotIn(leaked, result.stdout)
        self.assertEqual(result.stdout.splitlines(), [
            'token: <REDACTED>',
            'SECRET_KEY_BASE=<REDACTED>',
            'export SMTP_PASSWORD=<REDACTED>',
            '  POSTGRES_PASSWORD=<REDACTED>',
            '+ 10:00:01 IMAGE_URI=<REDACTED> OUTRO=<REDACTED>',
            'Redis auth failed for redis://<REDACTED>@cache:6379/0',
            'HTTP 200 em 0.01s',
            'chatwoot-web   Up 3 minutes',
            '[   12.0] secret_key_base=<REDACTED> status=<REDACTED>',
            'Authorization: Bearer <REDACTED>',
            'aws_secret\t<REDACTED> fim',
            'conexao postgres://<REDACTED>@db:5432/prod',
            'docker pull chatwoot-autonomia-prod:abc1234 /var/log/cloud-init-output.log',
        ])

    def test_failed_critical_step_builds_sanitized_diagnostic_package(self):
        # Simula o 21/10: o waiter do Register estourou. O pacote sai completo, sanitizado e sem nenhuma escrita na AWS.
        jobs = self.deploy_job([
            ('Wait for green SSM and local health', 'success', '2026-10-21T10:20:00Z', '2026-10-21T10:25:00Z'),
            ('Register green target group', 'failure', '2026-10-21T10:26:00Z', '2026-10-21T10:36:00Z'),
        ])
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                env = self.telemetry_env(jobs)
                env['BLUE_WORKER_STOPPED'] = 'false'  # Register falha antes do "Mark blue worker stop"
                result, calls = self.run_telemetry_step(workflow, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_read_only(calls)
                files = sorted(path.name for path in (Path(env['RUNNER_TEMP']) / 'deploy-diagnostico').glob('*'))
                self.assertEqual(files, ['00-motivo.txt', '10-target-health-green.txt', '11-target-health-blue.txt',
                                         '20-ec2-status-checks.txt', '40-ssm-green.txt', '50-logs-no-ssm.txt'])
                texts, summary, output = self.collected_text(env)
                everything = '\n'.join(texts) + summary + output + result.stdout + result.stderr
                for leaked in (self.SECRET, 'curta', 'default:pw'):
                    self.assertNotIn(leaked, everything)
                package = '\n'.join(texts)
                self.assertIn('falhou: Register green target group', package)
                self.assertIn('Target.Timeout', package)
                # Permissão que falta (DescribeInstanceStatus) vira uma linha no pacote, não derruba o passo.
                self.assertIn('UnauthorizedOperation', package)
                self.assertIn('(falhou com status 254)', package)
                self.assertIn('SECRET_KEY_BASE=<REDACTED>', package)
                self.assertIn('HTTP 502 em 0.01s', package)
                self.assertIn('status da invocação: Success', package)
                self.assertIn(f'aws ssm list-command-invocations --command-id {self.LOGS_ID} --details', package)
                self.assertIn(f'aws ssm list-command-invocations --command-id {self.LOGS_ID} --details', summary)
                self.assertIn('### Diagnóstico da green\n', summary)
                self.assertEqual(output.splitlines(), ['green_launch_time=2026-10-21T10:00:00+00:00',
                                                       'green_boot_done=1792578600'])
                # Nada do que os passos existentes leem muda: GITHUB_ENV intocado.
                self.assertEqual(Path(env['GITHUB_ENV']).read_text(), '')


    def test_application_logs_never_reach_summary_artifact_or_job_log(self):
        # O repositório é público: Step Summary, log do job e artifact são abertos. Log do web/worker/cloud-init (que
        # pode ter telefone, e-mail, trecho de mensagem) fica no SSM; nada dele, nem do que a green respondeu, vai ao
        # log do job (nenhum echo ou ::warning:: repete saída coletada).
        jobs = self.deploy_job([
            ('Wait for green SSM and local health', 'failure', '2026-10-21T10:20:00Z', '2026-10-21T10:35:00Z')])
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                env = self.telemetry_env(jobs)
                env['BLUE_WORKER_STOPPED'] = 'false'
                result, calls = self.run_telemetry_step(workflow, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_read_only(calls)
                logs_sent = [args for tool, args in calls if tool == 'aws' and args[:2] == ['ssm', 'send-command']
                             and 'journalctl' in args[args.index('--parameters') + 1]]
                self.assertEqual(len(logs_sent), 1)
                texts, summary, output = self.collected_text(env)
                artifact = '\n'.join(texts)
                job_log = result.stdout + result.stderr
                for private in self.PII:
                    for where, text in (('artifact', artifact), ('summary', summary), ('job log', job_log),
                                        ('output', output)):
                        self.assertNotIn(private, text, where)
                # O que a green respondeu (estrutura) vai ao summary, nunca ao log do job.
                for collected in ('MARCA-ESTRUTURAL-7', 'Target.Timeout', 'HTTP 502', 'UnauthorizedOperation'):
                    self.assertIn(collected, summary)
                    self.assertNotIn(collected, job_log)
                for line in job_log.splitlines():
                    self.assertTrue(line.startswith(('::warning::Coletando diagnóstico da green: falhou: ',
                                                     'Passos críticos', 'Job falhou')), line)

    @staticmethod
    def has_account_id(text):
        digits = ''
        for char in text + ' ':
            if char.isdigit():
                digits += char
                continue
            if len(digits) == 12:
                return True
            digits = ''
        return False

    def test_no_account_id_or_arn_reaches_summary_or_artifact(self):
        # Repositório público: ARN e ID de conta (12 dígitos) não saem, nem do target health, nem do erro de permissão
        # (assumed-role), nem do registry ECR da imagem no docker ps.
        jobs = self.deploy_job([
            ('Register green target group', 'failure', '2026-10-21T10:26:00Z', '2026-10-21T10:36:00Z')])
        self.assertTrue(self.has_account_id('x 354307071110.dkr'))
        self.assertFalse(self.has_account_id('epoch 1792578600 i-0123456789abcdef0'))
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                env = self.telemetry_env(jobs)
                env['BLUE_WORKER_STOPPED'] = 'false'
                result, calls = self.run_telemetry_step(workflow, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                texts, summary, output = self.collected_text(env)
                public = '\n'.join(texts) + summary + output + result.stdout + result.stderr
                self.assertNotIn('arn:aws', public)
                self.assertFalse(self.has_account_id(public), public)
                self.assertNotIn('TargetGroupArn', public)
                self.assertIn('repo:abc1234', summary)
                self.assertIn('Target.Timeout', summary)
                self.assertIn('UnauthorizedOperation', summary)
        result = subprocess.run([sys.executable, str(self.TELEMETRY), 'sanitize'], text=True, capture_output=True,
                                input='"arn:aws:elasticloadbalancing:us-east-1:354307071110:targetgroup/cw-1/abc", conta 140023375763',
                                timeout=5)
        self.assertEqual(result.stdout, '"cw-1", conta <CONTA>')

    def test_shift_failure_with_sidekiq_on_green_does_not_wait_for_ssm(self):
        # Shift falhou: o worker da blue está parado e o Sidekiq roda na green. O comando de logs vai (sem espera); o
        # estrutural, que espera o SSM, fica de fora para não atrasar a limpeza que religa a blue.
        jobs = self.deploy_job([
            ('Shift HTTPS listener to green', 'failure', '2026-10-21T10:28:00Z', '2026-10-21T10:29:00Z')])
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                env = self.telemetry_env(jobs)
                env['BLUE_WORKER_STOPPED'] = 'true'
                result, calls = self.run_telemetry_step(workflow, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_read_only(calls)
                self.assertFalse(any(tool == 'aws' and args[:2] == ['ssm', 'get-command-invocation'] for tool, args in calls))
                sent = [args for tool, args in calls if tool == 'aws' and args[:2] == ['ssm', 'send-command']]
                self.assertEqual(len(sent), 1)
                self.assertIn('journalctl', sent[0][sent[0].index('--parameters') + 1])
                texts, summary, output = self.collected_text(env)
                self.assertIn('falhou: Shift HTTPS listener to green', texts[0])
                self.assertIn(f'--command-id {self.LOGS_ID}', summary)
                self.assertIn('green_boot_done=\n', output)

    def test_diagnostics_degrade_without_ssm_or_github_api(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                env = self.telemetry_env([], gh_fails=True, ssm_online=False)
                env['BLUE_WORKER_STOPPED'] = 'false'  # falha antes da troca de workers (ex.: green que não subiu)
                result, calls = self.run_telemetry_step(workflow, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_read_only(calls)
                self.assertFalse(any(args[:2] == ['ssm', 'send-command'] for tool, args in calls if tool == 'aws'))
                texts, summary, output = self.collected_text(env)
                self.assertIn('falhou: passo não identificado (API do GitHub indisponível)', texts[0])
                self.assertIn('SSM da green fora do ar', '\n'.join(texts))
                self.assertIn('green_boot_done=\n', output)
                self.assertEqual(Path(env['GITHUB_ENV']).read_text(), '')

    def test_slow_critical_step_collects_and_healthy_deploy_reads_only_boot_time(self):
        slow = self.deploy_job([
            ('Register green target group', 'success', '2026-10-21T10:26:00Z', '2026-10-21T10:33:30Z'),
            ('Shift HTTPS listener to green', 'success', '2026-10-21T10:34:00Z', '2026-10-21T10:34:40Z'),
        ])
        healthy = self.deploy_job([
            ('Wait for green SSM and local health', 'success', '2026-10-21T10:20:00Z', '2026-10-21T10:25:00Z'),
            ('Register green target group', 'success', '2026-10-21T10:26:00Z', '2026-10-21T10:27:30Z'),
            ('Shift HTTPS listener to green', 'success', '2026-10-21T10:28:00Z', '2026-10-21T10:28:40Z'),
        ])
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name, case='slow'):
                env = self.telemetry_env(slow)
                env['JOB_STATUS'] = 'success'
                result, calls = self.run_telemetry_step(workflow, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                texts, summary, output = self.collected_text(env)
                self.assertIn('demorou: Register green target group (7m30s, limite 5m00s)', texts[0])
            with self.subTest(stack=workflow.name, case='healthy'):
                env = self.telemetry_env(healthy)
                env['JOB_STATUS'] = 'success'
                result, calls = self.run_telemetry_step(workflow, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_read_only(calls)
                texts, summary, output = self.collected_text(env)
                self.assertEqual((texts, summary), ([], ''))
                sent = [json.loads(args[args.index('--parameters') + 1])['commands']
                        for tool, args in calls if tool == 'aws' and args[:2] == ['ssm', 'send-command']]
                self.assertEqual(sent, [['stat -c "cloud_init_fim_epoch %Y" /run/cloud-init/result.json']])
                self.assertIn('green_boot_done=1792578600', output)
            # Falha na troca de workers, com o worker da blue parado: a limpeza que o religa vem logo depois, então nada de
            # SSM antes dela, nem quando o Register demorou e nem quando a API do GitHub está fora.
            for register_end, gh_fails in (('10:27:30', False), ('10:33:30', False), ('10:27:30', True)):
                with self.subTest(stack=workflow.name, case='worker-switch-failed', register_end=register_end,
                                  gh_fails=gh_fails):
                    env = self.telemetry_env(self.deploy_job(
                        [('Register green target group', 'success', '2026-10-21T10:26:00Z', f'2026-10-21T{register_end}Z'),
                         ('Switch Sidekiq workers to green', 'failure', f'2026-10-21T{register_end}Z',
                          '2026-10-21T10:35:00Z')]), gh_fails=gh_fails)
                    env['BLUE_WORKER_STOPPED'] = 'true'
                    result, calls = self.run_telemetry_step(workflow, env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertFalse(any(tool == 'aws' and args[0] == 'ssm' for tool, args in calls))
                    texts, summary, output = self.collected_text(env)
                    self.assertEqual((texts, summary), ([], ''))
                    self.assertIn('green_boot_done=\n', output)

    def test_phase_table_and_json_for_every_deploy(self):
        jobs = self.deploy_job([
            ('Build and push image', 'success', '2026-10-21T10:01:00Z', '2026-10-21T10:19:00Z'),
            ('Wait for green SSM and local health', 'success', '2026-10-21T10:19:10Z', '2026-10-21T10:24:10Z'),
            ('Register green target group', 'failure', '2026-10-21T10:25:00Z', '2026-10-21T10:35:00Z'),
        ])
        for workflow in WORKFLOWS:
            stack = workflow.name.split('-')[1]
            for gh_fails in (False, True):
                with self.subTest(stack=stack, gh_fails=gh_fails):
                    env = self.telemetry_env(jobs, gh_fails=gh_fails)
                    env.update({'GREEN_LAUNCH_TIME': '2026-10-21T10:00:30+00:00', 'GREEN_BOOT_DONE': '1792578600'})
                    workflow_env = workflow.read_text().split('      - name: Summarize deploy phase durations\n', 1)[1]
                    self.assertIn(f'          DEPLOY_STACK: {stack}\n', workflow_env.split('        run: |', 1)[0])
                    env['DEPLOY_STACK'] = stack
                    result, calls = self.run_telemetry_step(workflow, env, 'Summarize deploy phase durations')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertFalse(any(tool == 'aws' for tool, _ in calls))
                    report = json.loads((Path(env['RUNNER_TEMP']) / 'deploy-tempos/tempos.json').read_text())
                    summary = Path(env['GITHUB_STEP_SUMMARY']).read_text()
                    self.assertEqual([row['fase'] for row in report['fases']], [
                        'Build da imagem', 'Boot da green', 'Saúde local da green', 'Registro no target group',
                        'Troca dos workers', 'Troca do listener', 'Desligamento da blue'])
                    self.assertEqual(report['stack'], stack)
                    self.assertEqual(report['fases'][1]['segundos'], 1770)  # 10:00:30 -> 10:30:00 (epoch)
                    self.assertIn(f'### Tempos do deploy ({stack})', summary)
                    self.assertIn('| Fase | Passo | Duração | Início (UTC) | Conclusão |', summary)
                    self.assertEqual(set(report), {'stack', 'run_id', 'run_attempt', 'sha', 'api_disponivel',
                                                   'deploy_total_segundos', 'fases'})
                    for row in report['fases']:
                        self.assertEqual(set(row), {'fase', 'passo', 'inicio', 'fim', 'segundos', 'conclusao'})
                    # O log do job (público) só leva o aviso fixo de API fora, nunca dado coletado.
                    self.assertIn(result.stdout, ('', '::warning::API do GitHub indisponível: a tabela de tempos sai sem os passos.\n'))
                    if gh_fails:
                        self.assertFalse(report['api_disponivel'])
                        self.assertEqual(report['fases'][0]['conclusao'], 'não rodou')
                    else:
                        self.assertEqual(report['fases'][0]['segundos'], 18 * 60)
                        self.assertEqual(report['fases'][3]['conclusao'], 'failure')
                        self.assertEqual(report['fases'][6]['conclusao'], 'não rodou')
                        self.assertIn('| Registro no target group | Register green target group | 10m00s | '
                                      '2026-10-21T10:25:00+00:00 | failure |', summary)

    def test_telemetry_steps_are_read_only_continue_on_error_and_keep_existing_outputs(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                source = workflow.read_text()
                deploy = source.split('\n  deploy:\n', 1)[1].split('\n  desligar-blue:\n', 1)[0]
                tempos = source.split('\n  tempos:\n', 1)[1].split('\n  congelar:\n', 1)[0]
                for job, steps in ((deploy, self.NEW_DEPLOY_STEPS), (tempos, self.NEW_TEMPOS_STEPS)):
                    for name in steps:
                        header = job.split(f'      - name: {name}\n', 1)[1].split('\n      - name: ', 1)[0]
                        self.assertIn('        continue-on-error: true\n', header, name)
                        self.assertNotIn('GITHUB_ENV', header, name)
                diagnostics = deploy.split('      - name: Collect green diagnostics\n', 1)[1].split('\n      - name: ', 1)[0]
                # Nunca no cancelamento (a limpeza precisa do tempo) e sempre antes da limpeza que termina a green.
                self.assertIn("        if: ${{ !cancelled() && env.GREEN_INSTANCE_LAUNCHED == 'true' }}\n", diagnostics)
                self.assertIn('        timeout-minutes: 4\n', diagnostics)
                order = [deploy.index(f'      - name: {name}\n') for name in (
                    'Refresh AWS credentials for cleanup', 'Collect green diagnostics',
                    'Cleanup failed green resources before traffic shift', 'Upload green diagnostics')]
                self.assertEqual(order, sorted(order))
                self.assertIn('        if: always()\n', deploy.split('      - name: Upload green diagnostics\n', 1)[1])
                # Saídas do job: as existentes seguem vindo do hand-off/unfreeze; as novas, só do diagnóstico.
                outputs = deploy.split('    outputs:\n', 1)[1].split('\n    steps:\n', 1)[0]
                mapping = {line.split(':', 1)[0].strip(): line.split(':', 1)[1].strip()
                           for line in outputs.splitlines() if line.strip() and not line.strip().startswith('#')}
                for key in ('traffic_shift_done', 'listener_arn', 'blue_instance_id', 'blue_tg_arn', 'green_instance_id',
                            'green_tg_arn', 'old_previous_instance_id', 'old_previous_tg_arn'):
                    self.assertEqual(mapping[key], f'${{{{ steps.hand-off.outputs.{key} }}}}')
                self.assertEqual(mapping['unfreeze_outcome'], '${{ steps.unfreeze.outcome }}')
                self.assertEqual(mapping['green_launch_time'], '${{ steps.diagnostico.outputs.green_launch_time }}')
                self.assertEqual(mapping['green_boot_done'], '${{ steps.diagnostico.outputs.green_boot_done }}')
                self.assertEqual(len(mapping), 11)
                # O job de tempos não fala com a AWS nem pede mais que leitura.
                self.assertNotIn('configure-aws-credentials', tempos)
                self.assertNotIn('aws ', tempos)
                self.assertIn('    permissions:\n      contents: read\n      actions: read\n    steps:\n', tempos)
                self.assertIn("    if: always() && (needs.deploy.result == 'success' || needs.deploy.result == 'failure')\n"
                              "    # Falha aqui (checkout, API) nunca pinta de vermelho um deploy que deu certo.\n"
                              "    continue-on-error: true\n", tempos)
        script = (ROOT / 'scripts/deploy/green-diagnostics.sh').read_text()
        self.assertNotIn('GITHUB_ENV', script)
        self.assertEqual(sorted({line.split('=', 1)[0].split('"')[-1] for line in script.splitlines()
                                 if 'GITHUB_OUTPUT' in line and line.strip().startswith('echo')}),
                         ['green_boot_done', 'green_launch_time'])


BOOT_FAKE = r'''
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
def log(entry):
    with open(os.environ['FAKE_LOG'], 'a') as stream:
        stream.write(json.dumps(entry) + '\n')
log([name, args])
if name == 'aws':
    if args[:2] == ['ecr', 'get-login-password']:
        print('synthetic-login')
    elif args[:2] == ['ssm', 'get-parameter'] and args[args.index('--name') + 1] == '/chatwoot/prod/instagram-tester-env':
        query = args[args.index('--query') + 1]
        print('SecureString' if query == 'Parameter.Type' else os.environ['FAKE_TESTER_ENV'], end='')
    else:
        sys.exit(99)
elif name == 'ss':
    if os.environ.get('FAKE_TUNNEL', 'up') == 'up':
        for port in (16381, 16380):
            print(f'LISTEN 0 128 172.17.0.1:{port} 0.0.0.0:* users:(("ssh",pid=7,fd=4))')
elif name == 'systemctl':
    if args[:2] == ['is-active', '--quiet'] and os.environ.get('FAKE_TUNNEL') == 'inactive':
        sys.exit(3)
elif name == 'docker':
    if args[0] == 'cp':
        target = Path(args[2])
        # Only the middle copy fails: the installer itself is already staged and must still not run.
        if os.environ.get('FAKE_FAIL') == 'docker-cp' and target.name == 'validate-coordination-env.py':
            sys.exit(77)
        target.write_text(os.environ['FAKE_INSTALLER'] if target.name == 'install-coordination-tunnel.sh' else 'synthetic\n')
    elif args[:3] == ['network', 'inspect', 'bridge']:
        if os.environ.get('FAKE_FAIL') == 'docker-network':
            sys.exit(1)
        print(os.environ.get('FAKE_GATEWAY', '172.17.0.1'))
    elif args[0] == 'run' and args[-1] == 'scripts/instagram_testers/runtime/coordination_preflight.rb':
        # Stand-in for Rails; coordination-runtime_test feeds the real Ruby output through check.sh.
        ruby = os.environ.get('FAKE_RUBY', 'ok')
        if ruby == 'silent':
            # Docker or Rails boot failed before the script: nothing from it.
            print('docker: Error response from daemon', file=sys.stderr)
            sys.exit(1)
        print('Rails boot noise ' * 600, file=sys.stderr)  # ~10 KB, beyond SSM's 8000-char stderr cut
        print('instagram_coordination_preflight_rails_started', file=sys.stderr)
        if ruby == 'ok':
            print('instagram_coordination_preflight_ok')
            sys.exit(0)
        if ruby == 'killed':
            sys.exit(137)  # the container was killed (OOM, docker stop) after the script started
        if ruby != 'crashed':
            print(f'instagram_coordination_preflight_failed step={ruby}', file=sys.stderr)
        sys.exit(1)
    elif args[0] == 'run':
        overlay = next(args[i + 1] for i, arg in enumerate(args) if arg == '--env-file' and args[i + 1].endswith('instagram-tester.env'))
        for path in (args[i + 1] for i, arg in enumerate(args) if arg == '--env-file'):
            assert Path(path).exists(), path
        log(['overlay-at-run', Path(overlay).read_text()])
        if os.environ.get('FAKE_FAIL') == 'docker-run':
            sys.exit(77)
    elif args[0] == 'create' and os.environ.get('FAKE_FAIL') == 'docker-create':
        sys.exit(77)
    elif args[0] == 'login':
        sys.stdin.read()  # like docker: drain the piped password, so `aws ... | docker login` has no broken pipe
    elif args[0] == 'pull' and os.environ.get('FAKE_FAIL') == 'docker-pull':
        sys.exit(77)
    elif args[0] not in ('login', 'pull', 'create', 'rm', 'image'):
        sys.exit(99)
else:
    sys.exit(99)
'''

# Every Instagram failure the real check.sh can report (suspends), and the fakes that produce it.
CHECK_SCENARIOS = {
    'tunnel_timeout': {'FAKE_TUNNEL': 'down'},
    'tunnel_inactive': {'FAKE_TUNNEL': 'inactive'},
    'coordination_ping_failed': {'FAKE_RUBY': 'coordination_ping_failed'},
    'proxy_configuration_invalid': {'FAKE_RUBY': 'proxy_configuration_invalid'},
    'proxy_preflight_failed': {'FAKE_RUBY': 'proxy_preflight_failed'},
    'rails_preflight_failed': {'FAKE_RUBY': 'crashed'},  # the script ran and died before classifying
}
# Host/Docker failures the real check.sh reports with its own verdict (fatal, never a suspension).
HOST_SCENARIOS = {
    'host_gateway_unavailable': {'FAKE_GATEWAY': 'not-an-ip'},
    'host_gateway_unavailable:docker': {'FAKE_FAIL': 'docker-network'},
    'host_docker_failed': {'FAKE_RUBY': 'silent'},
    'host_rails_killed': {'FAKE_RUBY': 'killed'},
}


def write_boot_fakes(directory):
    bin_dir = directory / 'bin'
    bin_dir.mkdir()
    for name in ('aws', 'docker', 'systemctl', 'ss'):
        (bin_dir / name).write_text(f'#!{sys.executable}\n{BOOT_FAKE}')
        (bin_dir / name).chmod(0o700)
    for name in ('sudo', 'ssh', 'sshd', 'curl', 'dnf', 'cloud-init', 'journalctl'):
        (bin_dir / name).write_text('#!/bin/sh\nexit 99\n')
        (bin_dir / name).chmod(0o700)
    return bin_dir


def real_check_script(app):
    """The real coordination-preflight.sh, pointed at a test app dir with a 1 s tunnel wait."""
    source = (ROOT / 'scripts/instagram_testers/runtime/coordination-preflight.sh').read_text()
    for old in ('APP_DIR=/opt/chatwoot', 'wait_seconds=60'):
        assert source.count(old) == 1, old
    return source.replace('APP_DIR=/opt/chatwoot', f'APP_DIR={app}').replace('wait_seconds=60', 'wait_seconds=1')


def real_check_stderr(scenario):
    """stderr of the real check.sh for one scenario: what SSM returns as StandardErrorContent."""
    with tempfile.TemporaryDirectory(prefix='real-check-') as name:
        directory = Path(name)
        app = directory / 'app'
        (app / 'igcoord').mkdir(parents=True)
        for path in ('runtime.env', '.env', 'instagram-tester.env', 'igcoord/redis.env', 'igcoord/ca.crt'):
            (app / path).write_text('IMAGE_URI=image:sha\n' if path == 'runtime.env' else '')
        check = directory / 'check.sh'
        check.write_text(real_check_script(app))
        env = {'PATH': f'{write_boot_fakes(directory)}:/usr/bin:/bin', 'FAKE_LOG': str(directory / 'log'),
               'TMPDIR': str(directory), **{**CHECK_SCENARIOS, **HOST_SCENARIOS}[scenario]}
        result = subprocess.run(['/bin/bash', str(check)], env=env, text=True, capture_output=True, timeout=30)
    assert result.returncode == 1, (scenario, result.returncode, result.stderr)
    return result.stderr


class GreenBootInstagramTest(unittest.TestCase):
    """#1540: deploy.sh from the green user data with the real check.sh, run with local fakes only."""

    TESTER_ENV = 'INSTAGRAM_TESTER_APP_NAME=synthetic\nINSTAGRAM_TESTER_AUTOMATION_ENABLED=true\n'

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='green-boot-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.app = self.directory / 'app'
        self.run_dir = self.directory / 'run'
        for path in (self.app, self.run_dir):
            path.mkdir()
        self.bin = write_boot_fakes(self.directory)
        (self.directory / 'check.sh').write_text(real_check_script(self.app))
        self.log = self.directory / 'commands.jsonl'

    def deploy_script(self, workflow):
        source = workflow.read_text()
        nested = source.split('          cat > "$APP_DIR/deploy.sh" <<\'EOF\'\n', 1)[1].split('          EOF\n', 1)[0]
        script = '\n'.join(line[10:] for line in nested.splitlines()) + '\n'
        replacements = (('APP_DIR="/opt/chatwoot"', f'APP_DIR="{self.app}"'),
                        ('mktemp -d /run/', f'mktemp -d {self.run_dir}/'),
                        # The publisher has its own coverage; it is not part of the coordination preflight.
                        ('\ninstall_instagram_tester_publisher\n', '\n: publisher-not-under-test\n'))
        for old, new in replacements:
            self.assertGreaterEqual(script.count(old), 1, old)
            script = script.replace(old, new)
        return script

    def boot(self, workflow, install_fails=False, fail='', start_worker='false', missing_runtime=False, **check_env):
        (self.app / '.env').write_text('REDIS_URL=synthetic\nINSTAGRAM_TESTER_AUTOMATION_ENABLED=true\n')
        (self.app / 'runtime.env').write_text(f'IMAGE_URI=image:sha\nAWS_REGION=us-east-1\nECR_REGISTRY=registry\n'
                                              f'START_WORKER_AFTER_DEPLOY={start_worker}\n')
        installer = ('#!/bin/bash\necho instagram_coordination_fetch_failed >&2\nexit 1\n' if install_fails else
                     f'#!/bin/bash\nset -eu\necho installer-ran >> "{self.directory}/installer.log"\n'
                     'install -d -m 700 "$3/igcoord"\n: > "$3/igcoord/redis.env"\n: > "$3/igcoord/ca.crt"\n'
                     f'install -m 700 "{self.directory}/check.sh" "$3/igcoord/check.sh"\n')
        if missing_runtime:
            # check.sh cannot even start (no runtime.env for it): not an Instagram verdict.
            installer += f'mv "$3/runtime.env" "{self.directory}/runtime.env.hidden"\n'
        self.log.write_text('')
        env = {'PATH': f'{self.bin}:/usr/bin:/bin', 'FAKE_LOG': str(self.log),
               'FAKE_TESTER_ENV': self.TESTER_ENV, 'FAKE_INSTALLER': installer,
               'FAKE_FAIL': fail, 'TMPDIR': str(self.directory), **check_env}
        script = self.directory / 'deploy.sh'
        script.write_text(self.deploy_script(workflow))
        return subprocess.run(['/bin/bash', str(script)], env=env, text=True, capture_output=True, timeout=60)

    def entries(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def systemctl(self):
        return [args for name, args in self.entries() if name == 'systemctl' and args[0] != 'is-active']

    def overlays_at_run(self):
        return [entry[1] for entry in self.entries() if entry[0] == 'overlay-at-run']

    def rails_preflight_ran(self):
        return any(name == 'docker' and args[0] == 'run' and args[-1].endswith('coordination_preflight.rb')
                   for name, args in self.entries())

    def reset(self):
        shutil.rmtree(self.app / 'igcoord', ignore_errors=True)
        (self.directory / 'installer.log').unlink(missing_ok=True)
        (self.app / 'instagram-assisted-suspended').unlink(missing_ok=True)

    def assert_suspended(self, result, step, start_worker):
        self.assertEqual(result.returncode, 0, result.stderr[-3000:])
        suspended = f'INSTAGRAM_ASSISTED_SUSPENDED step={step}'
        self.assertIn(suspended, result.stderr)
        self.assertEqual((self.app / 'instagram-assisted-suspended').read_text(), suspended + '\n')
        overlay = (self.app / 'instagram-tester.env').read_text()
        self.assertEqual(overlay, 'INSTAGRAM_TESTER_APP_NAME=synthetic\nINSTAGRAM_TESTER_AUTOMATION_ENABLED=false\n')
        self.assertEqual((self.app / 'instagram-tester.env').stat().st_mode & 0o777, 0o600)
        # Every container of this boot (prepare, SES preflight) already sees the suspension.
        self.assertEqual(self.overlays_at_run(), [overlay, overlay])
        self.assertIn(['restart', 'chatwoot-web.service'], self.systemctl())
        self.assertEqual(['restart', 'chatwoot-worker.service'] in self.systemctl(), start_worker == 'true')

    def test_each_failing_preflight_step_suspends_instagram_and_boot_completes(self):
        for workflow in WORKFLOWS:
            for code, check_env in CHECK_SCENARIOS.items():
                for start_worker in ('false', 'true'):
                    with self.subTest(stack=workflow.name, step=code, start_worker=start_worker):
                        self.reset()
                        result = self.boot(workflow, start_worker=start_worker, **check_env)
                        self.assert_suspended(result, code, start_worker)
                        self.assertEqual(self.rails_preflight_ran(), code not in ('tunnel_timeout', 'tunnel_inactive'))

    def test_tunnel_installer_failure_suspends_and_provides_container_files(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                self.reset()
                result = self.boot(workflow, install_fails=True)
                self.assert_suspended(result, 'tunnel_install_failed', 'false')
                self.assertIn('instagram_coordination_fetch_failed', result.stderr)
                self.assertEqual((self.app / 'igcoord/redis.env').read_text(), '')
                self.assertEqual((self.app / 'igcoord/ca.crt').read_text(), '')
                self.assertFalse((self.app / 'igcoord/check.sh').exists())
                self.assertFalse(self.rails_preflight_ran())

    def test_passing_preflight_keeps_instagram_unchanged(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                self.reset()
                result = self.boot(workflow)
                self.assertEqual(result.returncode, 0, result.stderr[-3000:])
                self.assertIn('instagram_coordination_preflight_ok', result.stdout)
                self.assertNotIn('INSTAGRAM_ASSISTED_SUSPENDED', result.stdout + result.stderr)
                self.assertFalse((self.app / 'instagram-assisted-suspended').exists())
                self.assertEqual((self.app / 'instagram-tester.env').read_text(), self.TESTER_ENV)
                self.assertEqual(self.overlays_at_run(), [self.TESTER_ENV, self.TESTER_ENV])
                self.assertTrue(self.rails_preflight_ran())
                self.assertIn(['restart', 'chatwoot-web.service'], self.systemctl())
                self.assertEqual((self.directory / 'installer.log').read_text().count('installer-ran'), 1)

    def test_redeploy_clears_a_previous_suspension(self):
        for workflow in WORKFLOWS:
            with self.subTest(stack=workflow.name):
                self.reset()
                self.assert_suspended(self.boot(workflow, FAKE_TUNNEL='down'), 'tunnel_timeout', 'false')
                result = self.boot(workflow)
                self.assertEqual(result.returncode, 0, result.stderr[-3000:])
                self.assertFalse((self.app / 'instagram-assisted-suspended').exists())
                self.assertEqual((self.app / 'instagram-tester.env').read_text(), self.TESTER_ENV)

    def test_non_instagram_boot_failures_stay_fatal(self):
        # Image copy, Docker, host and application failures abort the boot exactly as before #1540.
        cases = {'image-create': {'fail': 'docker-create'}, 'image-copy': {'fail': 'docker-cp'},
                 'docker-pull': {'fail': 'docker-pull'}, 'db-prepare': {'fail': 'docker-run'},
                 'check-without-runtime': {'missing_runtime': True},
                 **{f'check-{code}': dict(env) for code, env in HOST_SCENARIOS.items()}}
        for workflow in WORKFLOWS:
            for case, options in cases.items():
                with self.subTest(stack=workflow.name, case=case):
                    self.reset()
                    result = self.boot(workflow, **{key.removeprefix('FAKE_').lower() if key == 'FAKE_FAIL' else key: value
                                                    for key, value in options.items()})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('INSTAGRAM_ASSISTED_SUSPENDED', result.stdout + result.stderr)
                    self.assertFalse((self.app / 'instagram-assisted-suspended').exists())
                    self.assertEqual((self.app / 'instagram-tester.env').read_text(), self.TESTER_ENV)
                    self.assertNotIn(['restart', 'chatwoot-web.service'], self.systemctl())
                    if case in ('image-create', 'image-copy'):
                        self.assertFalse((self.directory / 'installer.log').exists())
                    if case.startswith('check-'):
                        self.assertIn('instagram_preflight_failed_without_verdict', result.stderr)
                    if case.startswith('check-host'):
                        self.assertIn(f"instagram_coordination_preflight_host_failed step={case[6:].split(':')[0]}",
                                      result.stderr)
                    (self.directory / 'runtime.env.hidden').unlink(missing_ok=True)

    def test_boot_and_ssm_share_the_same_verdict_parser(self):
        # The green and the runner cannot source one file; the parser must not drift between them.
        def body(text, indent):
            start = text.index(f'{indent}instagram_preflight_verdict() {{\n')
            end = text.index(f'\n{indent}}}\n', start)
            return [line[len(indent):] for line in text[start:end].splitlines()]
        runner = body(HELPER.read_text(), '')
        for workflow in WORKFLOWS:
            self.assertEqual(body(workflow.read_text(), ' ' * 10), runner, workflow.name)

    def test_green_user_data_fits_the_ec2_limit(self):
        for workflow in WORKFLOWS:
            source = workflow.read_text()
            userdata = source.split("          cat > \"$RUNNER_TEMP/green-user-data.sh\" <<'USERDATA'\n", 1)[1].split('          USERDATA\n', 1)[0]
            rendered = '\n'.join(line[10:] for line in userdata.splitlines()) + '\n'
            # EC2 rejects user data above 16 KB; leave room for the substituted image and registry.
            self.assertLess(len(rendered.encode()), 16384 - 512, workflow.name)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--fake-aws':
        fake_aws()
    else:
        unittest.main(verbosity=2)
