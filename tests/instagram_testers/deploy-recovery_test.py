"""Offline Bash recovery tests. Every infrastructure command is a local fake.

Only selected run blocks/functions are executed, never user-data/bootstrap.
Absolute publisher executables are replaced with fakes before Bash runs.
AWS fakes return API envelopes and apply only the workflow's exact projections.
"""
import json
import os
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
        **dict.fromkeys(('describe-instances', 'start-instances', 'terminate-instances', 'create-tags'), 'ec2'),
    }
    expected_service = ({'command-executed': 'ssm', 'instance-running': 'ec2',
                         'target-deregistered': 'elbv2'}[args[2]] if operation == 'wait' else expected_services[operation])
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
            payload = json.loads(parameters.removeprefix('commands='))
            assert payload[0] == 'set -eu'
            command_kind = 'service'
        else:
            parameters = json.loads(parameters)
            assert set(parameters) == {'commands'}
            payload = parameters['commands']
            assert len(payload) == 1 and isinstance(payload[0], str)
            if payload[0] == 'if [ -e /run/chatwoot-deploy.running ]; then echo DEPLOY_RUNNING; else echo DEPLOY_IDLE; fi':
                command_kind = 'deploy-status'
            else:
                assert payload[0] == ('systemd-run --unit=green-retire --no-block sh -c '
                                      '"while [ -e /run/chatwoot-deploy.running ]; do sleep 5; done; shutdown -h now"')
                command_kind = 'retirement'
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
    elif operation == 'describe-instances':
        envelope = {'Reservations': [{'Instances': [{'State': {'Name': state.get('instance_state', 'running')}}]}]}
        assert arg('--query') == 'Reservations[0].Instances[0].State.Name'
        result = envelope['Reservations'][0]['Instances'][0]['State']['Name']
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
        if any('start chatwoot-worker.service' in item for item in payload):
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
        assert args[2] in ('command-executed', 'instance-running', 'target-deregistered')
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
            'LISTENER_ARN': 'listener-test', 'ALB_NAME': 'lb-test',
            'BLUE_TG_ARN': 'tg-blue', 'BLUE_INSTANCE_ID': 'i-blue',
            'GREEN_TG_ARN': 'tg-green', 'GREEN_INSTANCE_ID': 'i-green',
            'GREEN_WORKER_START_ATTEMPTED': 'true',
            'BLUE_WORKER_STOPPED': 'true',  # Existing recovery cases follow the worker-stop intent step.
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
                        tolerant_probe = (name == 'Cleanup failed green resources before traffic shift' and
                            (args[1] == 'get-command-invocation' or
                             (args[1] == 'send-command' and args[args.index('--parameters')+1].startswith('{'))))
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

    def test_coordination_failure_cannot_shift_traffic_or_remove_resources(self):
        for workflow in WORKFLOWS:
            for name, instance in (('Shift HTTPS listener to green', 'i-green'),
                                   ('Switch Sidekiq workers to green', 'i-green'),
                                   ):
                initial = 'tg-blue' if instance == 'i-green' else 'tg-green'
                with self.subTest(stack=workflow.name, path=name):
                    result, state = self.execute(run_block(workflow.read_text(), name),
                                                 listener=initial, running_workers=['i-blue'],
                                                 fail_coordination_instance=instance)
                    self.assertEqual(result.returncode, 78, result.stderr)
                    self.assertEqual(state['running_workers'], ['i-blue'])
                    self.assertEqual(state['workers'], [])
                    self.assertEqual(state['listener'], initial)
                    self.assertEqual(state['writes'], [])
                    self.assertFalse(any(call[1] in ('modify-listener', 'terminate-instances', 'delete-target-group')
                                         for call in state['calls']))
                    self.assertFalse(any(action[0] == 'start' for action in state['workers']))

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
                self.assertIn('instagram_recovery_suspension_failed:i-blue', result.stderr)
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
            self.assertIn('instagram_recovery_suspension_failed:i-blue', result.stderr)
            self.assertEqual(state['listener'], 'tg-green')
            self.assertEqual(state['writes'], [])
            self.assertTrue(all(len(event[2]) <= 1 for event in state['worker_timeline']))
            self.assertFalse(any(call[1] in ('modify-listener', 'delete-target-group', 'terminate-instances')
                                 for call in state['calls']))

    def test_suspension_helper_preserves_published_process_base_env_and_outcomes(self):
        helper = (ROOT / 'scripts/deploy/suspend-instagram-assisted.py').read_text()
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
        helper = (ROOT / 'scripts/deploy/suspend-instagram-assisted.py').read_text().replace(
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


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--fake-aws':
        fake_aws()
    else:
        unittest.main(verbosity=2)
