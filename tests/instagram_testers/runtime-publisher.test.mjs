/* eslint-disable no-await-in-loop, no-restricted-syntax -- Synthetic cancellation and supervisor cases serialize local lifecycle checks. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { EventEmitter, once } from 'node:events';
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

const syntheticFiles = {
  mkdtemp: async () => '/synthetic/publisher',
  writeFile: async () => {},
  chmod: async () => {},
  rm: async () => {},
};

class PublisherClock {
  constructor() {
    this.time = 0;
    this.timers = new Map();
    this.next = 0;
  }

  setTimeout(callback, ms) {
    this.next += 1;
    const id = this.next;
    this.timers.set(id, { at: this.time + ms, callback });
    return id;
  }

  clearTimeout(id) {
    this.timers.delete(id);
  }

  async advance(ms) {
    this.time += ms;
    for (const [id, timer] of this.timers) {
      if (timer.at <= this.time) {
        this.timers.delete(id);
        timer.callback();
      }
    }
    for (let index = 0; index < 20; index += 1) await Promise.resolve();
  }
}

async function flushPublisher() {
  for (let index = 0; index < 30; index += 1) await Promise.resolve();
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
  assert.equal(
    parsePublisherOutput(JSON.stringify({ type: 'session', version })),
    version
  );
  assert.equal(
    parsePublisherOutput(JSON.stringify({ type: 'session', version: null })),
    null
  );
  assert.throws(
    () =>
      parsePublisherOutput(
        JSON.stringify({ type: 'session', version: 'opaque-generation:2' })
      ),
    /publication_failed/
  );
  [
    `${JSON.stringify({ type: 'session', version })}\nlog=${canary}`,
    JSON.stringify({ version, session: canary }),
    JSON.stringify({ error: canary }),
    'not-json',
  ].forEach(invalid => {
    assert.throws(() => parsePublisherOutput(invalid), /publication_failed/);
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
  let elapsed = 0;
  const output = await hostKeyViaSsm(config, {
    run: async (_command, args) => {
      calls.push(args);
      if (args.includes('send-command')) return 'command-12345678\n';
      const envelope = {
        CommandInvocations:
          calls.length === 2
            ? []
            : [
                {
                  Status: 'Success',
                  CommandPlugins: [
                    {
                      Output:
                        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData== host\n',
                    },
                  ],
                },
              ],
      };
      const query = args[args.indexOf('--query') + 1];
      assert.equal(
        query.slice(query.indexOf('].') + 2),
        '{Status:Status,Output:CommandPlugins[0].Output}'
      );
      const invocation = envelope[query.split('[0]')[0]]?.[0];
      return JSON.stringify(
        invocation
          ? {
              Status: invocation.Status,
              Output: invocation.CommandPlugins[0].Output,
            }
          : null
      );
    },
    deadline: 100,
    now: () => elapsed,
    sleep: async () => {
      elapsed += 25;
    },
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
      { type: 'session', operation: 'version' },
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
  const clock = new PublisherClock();
  const rejected = assert.rejects(
    runPublisher(
      { type: 'session', operation: 'version' },
      {
        stack: 'hub2you',
        env,
        budgetMs: 100,
        clock,
        now: () => clock.time,
        signals: new EventEmitter(),
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
  await flushPublisher();
  await clock.advance(100);
  await rejected;
  assert.equal(startArgs.includes('i-0a588ad747022bb9c'), true);
});

test('runPublisher enforces a sub-30s deadline and kills a detached SSM tunnel', async () => {
  const tunnel = fakeChild();
  const spawned = [];
  const clock = new PublisherClock();
  const rejected = assert.rejects(
    runPublisher(
      { type: 'session', operation: 'version' },
      {
        stack: 'hub2you',
        env: baseEnv,
        budgetMs: 100,
        clock,
        now: () => clock.time,
        signals: new EventEmitter(),
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
  await flushPublisher();
  await clock.advance(100);
  await rejected;
  assert.equal(PUBLISH_BUDGET_MS < 30000, true);
  assert.deepEqual(spawned, ['aws']);
  assert.equal(tunnel.killed, true);
  assert.equal(clock.timers.size, 0);
});

test('runPublisher converts SSH stdin EPIPE to a static failure and cleans both children', async () => {
  const tunnel = fakeChild();
  const ssh = fakeChild({ stdin: true });
  const spawned = [];
  await assert.rejects(
    runPublisher(
      { type: 'session', operation: 'version' },
      {
        stack: 'hub2you',
        env: baseEnv,
        budgetMs: 500,
        files: syntheticFiles,
        signals: new EventEmitter(),
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
    SSH_ORIGINAL_COMMAND: 'synthetic-rejected-command',
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

test('synthetic Node forwarder sees EOF with ignored stdin, and pipe stays alive until cleanup', async () => {
  const program =
    'process.stdin.resume(); process.stdin.on("end", () => process.exit(0)); console.log("READY");';
  const ignored = spawn(process.execPath, ['-e', program], {
    stdio: ['ignore', 'ignore', 'ignore'],
    env: {},
  });
  assert.deepEqual(await once(ignored, 'exit'), [0, null]);
  let tunnel;
  let exited;
  try {
    const result = await runPublisher(
      { type: 'session', operation: 'version' },
      {
        stack: 'hub2you',
        env: baseEnv,
        run: syntheticRun(),
        files: syntheticFiles,
        signals: new EventEmitter(),
        freePortFn: async () => 49152,
        stopProcessFn: child => child?.kill('SIGTERM'),
        spawnImpl: (command, _args, options) => {
          if (command === 'aws') {
            assert.equal(options.stdio[0], 'pipe');
            tunnel = spawn(process.execPath, ['-e', program], {
              ...options,
              env: {},
            });
            exited = once(tunnel, 'exit');
            return tunnel;
          }
          assert.equal(command, 'ssh');
          assert.equal(tunnel.exitCode, null);
          assert.equal(tunnel.stdin.writableEnded, false);
          assert.equal(tunnel.stdin.destroyed, false);
          const child = fakeChild();
          child.stdin = new EventEmitter();
          child.stdin.end = () =>
            queueMicrotask(() => {
              child.stdout.emit(
                'data',
                JSON.stringify({ type: 'session', version })
              );
              child.emit('exit', 0);
              child.emit('close', 0);
            });
          return child;
        },
        waitForPortFn: async () => {
          await once(tunnel.stdout, 'data');
          return true;
        },
        hostKeyFn: async () => {
          assert.equal(tunnel.stdin.destroyed, false);
          return 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData== host';
        },
      }
    );
    assert.equal(result, version);
    await exited;
    assert.equal(tunnel.killed, true);
    assert.equal(tunnel.stdin.destroyed, true);
  } finally {
    tunnel?.kill('SIGTERM');
    if (exited) await exited;
  }
});

for (const stage of ['port', 'host-key', 'ssh', 'cleanup']) {
  for (const cancellation of ['deadline', 'SIGTERM']) {
    test(`${cancellation} bounds publisher ${stage} and discards stale completion`, async () => {
      const clock = new PublisherClock();
      const signals = new EventEmitter();
      const tunnel = fakeChild();
      const ssh = fakeChild();
      ssh.stdin = new EventEmitter();
      ssh.stdin.end = () => {
        if (stage === 'cleanup')
          queueMicrotask(() => {
            ssh.stdout.emit(
              'data',
              JSON.stringify({ type: 'session', version })
            );
            ssh.emit('exit', 0);
            ssh.emit('close', 0);
          });
      };
      let completeStage;
      const pending = new Promise(resolvePending => {
        completeStage = resolvePending;
      });
      const children = [];
      const result = runPublisher(
        { type: 'session', operation: 'version' },
        {
          stack: 'hub2you',
          env: baseEnv,
          run: syntheticRun(),
          clock,
          signals,
          now: () => clock.time,
          budgetMs: 100,
          files: {
            ...syntheticFiles,
            rm: stage === 'cleanup' ? () => pending : syntheticFiles.rm,
          },
          freePortFn: async () => 49152,
          waitForPortFn: stage === 'port' ? () => pending : async () => true,
          hostKeyFn:
            stage === 'host-key'
              ? () => pending
              : async () =>
                  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData== host',
          spawnImpl: command => {
            children.push(command);
            return command === 'aws' ? tunnel : ssh;
          },
        }
      );
      // Attach handlers before advancing the clock to observe all rejections.
      const settled = result.then(
        value => ({ value }),
        error => ({ error })
      );
      await flushPublisher();
      if (cancellation === 'deadline') await clock.advance(100);
      else signals.emit('SIGTERM');
      const outcome = await settled;
      if (stage === 'cleanup') {
        // The SSH result already exists, but cleanup must still be bounded.
        assert.equal(outcome.value, version);
      } else
        assert.equal(
          outcome.error?.message,
          'instagram_session_publication_failed'
        );
      assert.equal(tunnel.killed, true);
      if (stage === 'ssh') assert.equal(ssh.killed, true);
      const count = children.length;
      completeStage(
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData== host'
      );
      ssh.stdout.emit('data', JSON.stringify({ type: 'session', version }));
      ssh.emit('exit', 0);
      ssh.emit('close', 0);
      await flushPublisher();
      assert.equal(children.length, count);
      assert.equal(signals.listenerCount('SIGTERM'), 0);
      assert.equal(clock.timers.size, 0);
    });
  }
}

test('LaunchAgent wrapper treats synthetic operator and operational exit codes differently', async () => {
  const source = await readFile(
    `${runtimeDir}/manager-launchagent-wrapper.sh`,
    'utf8'
  );
  const command =
    '/usr/local/bin/node /ABSOLUTE/PATH/TO/scripts/instagram_testers/session-manager.mjs';
  assert.equal(source.includes(command), true);
  for (const [code, expected] of [
    [0, 0],
    [1, 1],
    [2, 0],
    [3, 1],
  ]) {
    const script = source
      .replace(
        command,
        '[ "$synthetic_resumed" = yes ] && exit 0; synthetic_resumed=yes; "$SYNTHETIC_NODE" -e "process.exit(Number(process.argv[1]))" "$SYNTHETIC_STATUS"'
      )
      .replace(
        '/usr/local/bin/node /ABSOLUTE/PATH/TO/scripts/instagram_testers/runtime/operator-waiter.mjs',
        '"$SYNTHETIC_NODE" -e "process.exit(0)"'
      );
    const result = spawnSync('/bin/sh', ['-c', script], {
      encoding: 'utf8',
      env: { SYNTHETIC_NODE: process.execPath, SYNTHETIC_STATUS: String(code) },
    });
    assert.equal(result.status, expected);
    assert.equal(result.stdout, '');
    let expectedStderr = '';
    if (code === 2) expectedStderr = 'instagram_manager_operator_required\n';
    else if (expected === 1) expectedStderr = 'instagram_manager_failed\n';
    assert.equal(result.stderr, expectedStderr);
  }
});

for (const exitFirst of [false, true]) {
  test(`transport waits for close and preserves split 781-byte UTF8 bootstrap; exitFirst=${exitFirst}`, async () => {
    const bootstrap = {
      type: 'bootstrap',
      metadata: {
        INSTAGRAM_META_DEVELOPER_APP_ID: '1',
        INSTAGRAM_META_BUSINESS_ID: '1',
        INSTAGRAM_TESTER_APP_NAME: '😀'.repeat(120),
        INSTAGRAM_TESTER_ADMIN_USER_ID: '1',
        INSTAGRAM_TESTER_ROLES_DOC_ID: '1',
      },
      revision: 'a'.repeat(64),
      version: null,
    };
    const bytes = Buffer.from(JSON.stringify(bootstrap));
    assert.equal(bytes.length, 781);
    const split = bytes.indexOf(Buffer.from('😀')) + 1;
    const result = await runPublisher(
      { type: 'session', operation: 'bootstrap' },
      {
        stack: 'hub2you',
        env: baseEnv,
        run: syntheticRun(),
        files: syntheticFiles,
        signals: new EventEmitter(),
        freePortFn: async () => 49152,
        waitForPortFn: async () => true,
        hostKeyFn: async () =>
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData== host',
        spawnImpl: command => {
          const child = fakeChild();
          if (command === 'ssh') {
            child.stdin = new EventEmitter();
            child.stdin.end = () =>
              queueMicrotask(() => {
                if (exitFirst) child.emit('exit', 0);
                child.stdout.emit('data', bytes.subarray(0, split));
                child.stdout.emit('data', bytes.subarray(split));
                if (!exitFirst) child.emit('exit', 0);
                child.emit('close', 0);
              });
          }
          return child;
        },
      }
    );
    assert.deepEqual(result, bootstrap);
  });
}

test('metadata writer locks in sorted name order even when caller supplies reversed keys; no database', async () => {
  const { stdout, status, stderr } = spawnSync(
    '/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby',
    [
      '-e',
      `
    module Instagram; module Automation; end; module Testers; module Validation
      def self.id?(value); value.is_a?(String) && value.match?(/\\A[0-9]{1,40}\\z/); end
    end; end; end
    class String; def present?; !empty?; end; end
    class InstallationConfig
      WRITES = []
      Record = Struct.new(:name, :value) do
        def new_record?; false; end
        def save!; InstallationConfig::WRITES << name; end
      end
      def self.transaction; yield; end
      def self.find_or_initialize_by(name:); Record.new(name); end
    end
    load 'app/services/instagram/automation/metadata.rb'
    klass = Instagram::Automation::Metadata
    submitted = klass::KEYS.reverse.to_h { |key| [key, key == klass::APP_NAME_KEY ? 'Synthetic App' : '1'] }
    klass.new.update!(submitted)
    abort 'unsorted locks' unless InstallationConfig::WRITES == klass::KEYS.sort
    puts 'sorted writer: OK'
  `,
    ],
    { encoding: 'utf8' }
  );
  assert.equal(status, 0, stderr);
  assert.equal(stdout.trim(), 'sorted writer: OK');
});

for (const failure of ['overflow', 'error', 'stdin-error', 'nonzero']) {
  test(`transport rejects ${failure} after exit and ignores a late valid close`, async () => {
    let ssh;
    const result = runPublisher(
      { type: 'session', operation: 'version' },
      {
        stack: 'hub2you',
        env: baseEnv,
        run: syntheticRun(),
        files: syntheticFiles,
        signals: new EventEmitter(),
        freePortFn: async () => 49152,
        waitForPortFn: async () => true,
        hostKeyFn: async () =>
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData== host',
        spawnImpl: command => {
          const child = fakeChild();
          if (command === 'ssh') {
            ssh = child;
            child.stdin = new EventEmitter();
            child.stdin.end = () =>
              queueMicrotask(() => {
                child.emit('exit', 0);
                if (failure === 'overflow') {
                  child.stdout.emit('data', Buffer.alloc(1024, 32));
                  child.stdout.emit('data', Buffer.alloc(1025, 32));
                }
                if (failure === 'error')
                  child.emit('error', new Error('synthetic'));
                if (failure === 'stdin-error')
                  child.stdin.emit('error', new Error('synthetic'));
                child.stdout.emit(
                  'data',
                  Buffer.from(JSON.stringify({ type: 'session', version }))
                );
                child.emit('close', failure === 'nonzero' ? 1 : 0);
              });
          }
          return child;
        },
      }
    );
    await assert.rejects(result, /instagram_session_publication_failed/);
    if (failure === 'overflow' || failure === 'stdin-error')
      assert.equal(ssh.killed, true);
  });
}
