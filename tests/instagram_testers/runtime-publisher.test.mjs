import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import {
  STACKS,
  hostKeyViaSsm,
  knownHostsLine,
  parsePublisherOutput,
  PUBLISH_BUDGET_MS,
  publisherSshArguments,
  runPublisher,
  runtimeConfig,
  startSessionArguments,
  verifyAwsAccount,
} from '../../scripts/instagram_testers/runtime/publisher-tunnel.mjs';

const runtimeDir = fileURLToPath(
  new URL('../../scripts/instagram_testers/runtime/', import.meta.url)
);
const baseEnv = {
  INSTAGRAM_TESTER_HUB2YOU_INSTANCE_ID: 'i-0a588ad747022bb9c',
  INSTAGRAM_TESTER_AUTONOMIA_INSTANCE_ID: 'i-0123456789abcdef0',
  INSTAGRAM_TESTER_PUBLISHER_SSH_KEY:
    '/Users/operator/.ssh/instagram-publisher',
};
const canary = 'cookie=xs=synthetic-token; password=never-log';
const version = '11111111-1111-4111-8111-111111111111';

function fakeChild({ stdin = false } = {}) {
  const child = new EventEmitter();
  child.pid = 0;
  child.killed = false;
  child.kill = () => {
    child.killed = true;
    return true;
  };
  child.stdout = new EventEmitter();
  child.stdout.resume = () => {};
  child.stderr = new EventEmitter();
  child.stderr.resume = () => {};
  if (stdin) {
    child.stdin = new EventEmitter();
    child.stdin.end = () => {
      process.nextTick(() => child.stdin.emit('error', new Error('EPIPE')));
    };
  }
  return child;
}

function syntheticRun(
  account = '354307071110',
  instance = 'i-0a588ad747022bb9c'
) {
  return async (_command, args) => {
    if (args.includes('get-caller-identity')) return `${account}\n`;
    if (args.includes('get-parameter')) return `${instance}\n`;
    throw new Error('unexpected synthetic AWS operation');
  };
}

test('pins each publisher profile to the expected AWS account and rejects missing instance/key', () => {
  assert.deepEqual(
    Object.fromEntries(
      Object.entries(STACKS).map(([name, config]) => [
        name,
        [config.accountId, config.awsProfile],
      ])
    ),
    {
      hub2you: ['354307071110', 'hub2you'],
      autonomia: ['140023375763', 'financial'],
    }
  );
  assert.equal(
    runtimeConfig('hub2you', baseEnv).instanceId,
    'i-0a588ad747022bb9c'
  );
  assert.equal(
    runtimeConfig('hub2you', {
      INSTAGRAM_TESTER_PUBLISHER_SSH_KEY:
        baseEnv.INSTAGRAM_TESTER_PUBLISHER_SSH_KEY,
    }).instanceId,
    undefined
  );
  assert.throws(
    () => runtimeConfig('hub2you', {}),
    /instagram_session_publication_failed/
  );
});

test('SSM forwarding and SSH argv never contain the JSON payload', () => {
  const config = runtimeConfig('hub2you', baseEnv);
  const startArgs = startSessionArguments(config, 49152);
  const sshArgs = publisherSshArguments(config, 49152, '/tmp/known_hosts');
  assert.equal(startArgs.includes(canary), false);
  assert.equal(sshArgs.includes(canary), false);
  assert.equal(sshArgs.at(-1), 'chatwoot_publisher@127.0.0.1');
  assert.equal(sshArgs.includes('bundle'), false);
  assert.equal(
    startArgs.includes('AWS-StartPortForwardingSessionToRemoteHost'),
    true
  );
  assert.equal(startArgs.includes(config.instanceId), true);
});

test('SSH is pinned to a temporary SSM-derived host key and cannot fall back to trust-on-first-use', () => {
  const line = knownHostsLine(
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData== operator@host',
    49152
  );
  assert.equal(
    line,
    '[127.0.0.1]:49152 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData==\n'
  );
  const args = publisherSshArguments(
    runtimeConfig('hub2you', baseEnv),
    49152,
    '/tmp/known_hosts'
  );
  assert.equal(args.includes('StrictHostKeyChecking=yes'), true);
  assert.equal(args.includes('GlobalKnownHostsFile=/dev/null'), true);
  assert.equal(args.includes('UserKnownHostsFile=/tmp/known_hosts'), true);
  assert.throws(
    () => knownHostsLine('not-a-public-key', 49152),
    /instagram_session_publication_failed/
  );
});

test('publisher output accepts only an opaque version result', () => {
  assert.equal(parsePublisherOutput(JSON.stringify({ version })), version);
  assert.equal(parsePublisherOutput(JSON.stringify({ version: null })), null);
  [
    `${JSON.stringify({ version })}\nlog=${canary}`,
    JSON.stringify({ version, session: canary }),
    JSON.stringify({ error: canary }),
    'not-json',
  ].forEach(invalid => {
    assert.throws(
      () => parsePublisherOutput(invalid),
      /instagram_session_publication_failed/
    );
  });
});

test('account verification is exact and does not expose AWS output', async () => {
  const calls = [];
  const config = runtimeConfig('hub2you', baseEnv);
  await verifyAwsAccount(config, {
    run: async (_command, args) => {
      calls.push(args);
      return '354307071110\n';
    },
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].includes(canary), false);
  await assert.rejects(
    verifyAwsAccount(config, {
      run: async () => '140023375763\n',
    }),
    /instagram_session_publication_failed/
  );
});

test('host key retrieval uses only fixed SSM commands and no SSH-side probing', async () => {
  const config = runtimeConfig('hub2you', baseEnv);
  const calls = [];
  const output = await hostKeyViaSsm(config, {
    run: async (_command, args) => {
      calls.push(args);
      if (args.includes('send-command')) return 'command-12345678\n';
      if (args.includes('list-command-invocations') && calls.length === 2)
        return 'null';
      return JSON.stringify({
        Status: 'Success',
        Output:
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData== host\n',
      });
    },
    sleep: async () => {},
  });
  assert.match(output, /^ssh-ed25519 /);
  assert.equal(calls.length, 3);
  assert.equal(
    calls[0].some(value =>
      value.includes('/usr/bin/cat /etc/ssh/ssh_host_ed25519_key.pub')
    ),
    true
  );
  assert.equal(calls[0].includes(canary), false);
  assert.equal(calls[1].includes('list-command-invocations'), true);
  assert.equal(calls[1].includes('--details'), true);
});

test('runPublisher checks the current blue-green pointer before sending stdin', async () => {
  const config = runtimeConfig('hub2you', baseEnv);
  const calls = [];
  await assert.rejects(
    runPublisher(
      { operation: 'publish', session: canary },
      {
        stack: 'hub2you',
        env: baseEnv,
        run: async (_command, args) => {
          calls.push(args);
          if (args.includes('get-caller-identity'))
            return `${config.accountId}\n`;
          return 'i-old-blue-instance\n';
        },
        freePortFn: async () => 49152,
      }
    ),
    /instagram_session_publication_failed/
  );
  assert.equal(calls.length, 2);
  assert.equal(calls[1].includes(config.currentInstanceParameter), true);
});

test('runPublisher targets the current pointer when no override is configured', async () => {
  const env = {
    INSTAGRAM_TESTER_PUBLISHER_SSH_KEY:
      baseEnv.INSTAGRAM_TESTER_PUBLISHER_SSH_KEY,
  };
  const tunnel = fakeChild();
  let startArgs;
  await assert.rejects(
    runPublisher(
      { operation: 'publish', session: canary },
      {
        stack: 'hub2you',
        env,
        budgetMs: 15,
        run: syntheticRun(),
        freePortFn: async () => 49152,
        waitForPortFn: () => new Promise(() => {}),
        spawnImpl: (command, args) => {
          if (command === 'aws') startArgs = args;
          return tunnel;
        },
      }
    ),
    /instagram_session_publication_failed/
  );
  assert.equal(startArgs.includes('i-0a588ad747022bb9c'), true);
});

test('runPublisher enforces a sub-30s deadline and kills a detached SSM tunnel', async () => {
  const tunnel = fakeChild();
  const spawned = [];
  const started = Date.now();
  await assert.rejects(
    runPublisher(
      { operation: 'publish', session: canary },
      {
        stack: 'hub2you',
        env: baseEnv,
        budgetMs: 15,
        run: syntheticRun(),
        freePortFn: async () => 49152,
        waitForPortFn: () => new Promise(() => {}),
        spawnImpl: command => {
          spawned.push(command);
          return tunnel;
        },
      }
    ),
    /instagram_session_publication_failed/
  );
  assert.equal(PUBLISH_BUDGET_MS < 30000, true);
  assert.deepEqual(spawned, ['aws']);
  assert.equal(tunnel.killed, true);
  assert.equal(Date.now() - started < 1000, true);
});

test('runPublisher converts SSH stdin EPIPE to a static failure and cleans both children', async () => {
  const tunnel = fakeChild();
  const ssh = fakeChild({ stdin: true });
  const spawned = [];
  await assert.rejects(
    runPublisher(
      { operation: 'publish', session: canary },
      {
        stack: 'hub2you',
        env: baseEnv,
        budgetMs: 500,
        run: syntheticRun(),
        freePortFn: async () => 49152,
        waitForPortFn: async () => true,
        hostKeyFn: async () =>
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData== host\n',
        spawnImpl: command => {
          spawned.push(command);
          return command === 'aws' ? tunnel : ssh;
        },
      }
    ),
    /instagram_session_publication_failed/
  );
  assert.deepEqual(spawned, ['aws', 'ssh']);
  assert.equal(ssh.killed, true);
  assert.equal(tunnel.killed, true);
});

test('forced remote command is root-only, narrow, and emits only the publisher result', async () => {
  const source = await readFile(`${runtimeDir}/forced-publisher.sh`, 'utf8');
  assert.match(
    source,
    /\/usr\/bin\/docker exec -i chatwoot-web bundle exec rails runner scripts\/instagram_testers\/session_publisher\.rb/
  );
  assert.match(source, /SSH_ORIGINAL_COMMAND/);
  assert.match(source, /id -u/);
  assert.match(source, /SUDO_USER-.*chatwoot_publisher/);
  assert.doesNotMatch(source, /docker (run|compose|cp|exec [^\n]*\$)/);
  assert.doesNotMatch(source, /\beval\b/);
  assert.match(source, /instagram_publisher_transport_failed/);
});

test('forced wrapper rejects untrusted SSH commands before touching Docker', () => {
  const wrapper = `${runtimeDir}/forced-publisher.sh`;
  const base = {
    ...process.env,
    SUDO_USER: 'chatwoot_publisher',
  };
  const nonRoot = spawnSync(wrapper, [], {
    env: base,
    encoding: 'utf8',
  });
  assert.equal(nonRoot.status, 2);
  assert.equal(nonRoot.stdout, '');
  assert.equal(nonRoot.stderr, 'instagram_publisher_transport_failed\n');

  const originalCommand = spawnSync(wrapper, [], {
    env: {
      ...base,
      SSH_ORIGINAL_COMMAND: 'docker exec chatwoot-web sh',
    },
    encoding: 'utf8',
  });
  assert.equal(originalCommand.status, 2);
  assert.equal(originalCommand.stdout, '');
  assert.equal(
    originalCommand.stderr,
    'instagram_publisher_transport_failed\n'
  );
});

test('remote installer uses an executable shell, no docker group, and a validated no-argument sudo rule', async () => {
  const source = await readFile(
    `${runtimeDir}/install-remote-publisher.sh`,
    'utf8'
  );
  assert.match(source, /publisher_user='chatwoot_publisher'/);
  assert.match(source, /--shell \/bin\/sh/);
  assert.match(source, /actual_shell=.*print \$7/);
  assert.match(source, /actual_shell.*\/bin\/sh/);
  assert.match(source, /publisher_groups=.*id -nG/);
  assert.match(source, /docker/);
  assert.match(source, /sudo/);
  assert.match(source, /wheel/);
  assert.match(source, /root/);
  assert.match(source, /admin/);
  assert.doesNotMatch(source, /\/sbin\/nologin|usermod|group docker/);
  assert.match(
    source,
    /command=\\"\/usr\/bin\/sudo -n \$publisher_command\\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty/
  );
  assert.match(source, /IFS= read -r public_key/);
  assert.match(source, /\[ "\$#" -eq 0 \]/);
  const sudoersLine = source
    .split('\n')
    .find(line => line.includes('NOPASSWD:'));
  assert.ok(sudoersLine);
  assert.equal(sudoersLine.includes(String.raw`$publisher_command \"\"`), true);
  assert.equal(sudoersLine.includes('*'), false);
  assert.match(source, /\/usr\/sbin\/visudo -cf/);
  assert.match(source, /install -d -o root -g root -m 0755 "\$publisher_home"/);
  assert.match(source, /chown root:root "\$publisher_home"/);
  assert.doesNotMatch(
    source,
    /authorized_keys.*\$\(.*password|PRIVATE_KEY|SECRET/
  );
});

test('LaunchAgent maps manager operator_required exit 2 to clean exit and keeps crash restart', async () => {
  const wrapper = await readFile(
    `${runtimeDir}/manager-launchagent-wrapper.sh`,
    'utf8'
  );
  const plist = await readFile(
    `${runtimeDir}/com.autonomia.instagram-tester-manager.plist`,
    'utf8'
  );
  assert.match(wrapper, /status.*\$\?/);
  assert.match(wrapper, /\[ "\$status" -eq 2 \]/);
  assert.match(wrapper, /instagram_manager_operator_required/);
  assert.match(plist, /<key>RunAtLoad<\/key>\s*<true\/>/);
  assert.match(plist, /<key>SuccessfulExit<\/key>\s*<false\/>/);
  assert.match(plist, /instagram-tester-manager\.err/);
  assert.match(plist, /Application Support\/InstagramTester\/profile/);
  assert.doesNotMatch(plist, /INSTAGRAM_TESTER_SESSION_JSON/);
});
