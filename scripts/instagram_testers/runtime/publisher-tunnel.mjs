/* eslint-disable no-await-in-loop, no-restricted-syntax -- The SSM session and its health checks are intentionally sequential. */

import { spawn } from 'node:child_process';
import { parseEnvelope, validateRequest } from './operator-protocol.mjs';
import { createServer, createConnection } from 'node:net';
import { chmod, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const INSTANCE_ID = /^i-[0-9a-f]{8,17}$/;
const PRIVATE_PATH = /^(\/[^\0\r\n]+)$/;
const PUBLIC_KEY_TYPE =
  /^(ssh-ed25519|ecdsa-sha2-nistp256|rsa-sha2-512|rsa-sha2-256)$/;
const PUBLIC_KEY_DATA = /^[A-Za-z0-9+/]+={0,2}$/;
const MAX_OUTPUT_BYTES = 2048;
const HOST_KEY_DOCUMENT = 'ChatwootInstagramPublisherHostKey';
export const PUBLISH_BUDGET_MS = 25_000;

function delay(milliseconds) {
  return new Promise(resolve => {
    setTimeout(resolve, milliseconds);
  });
}

export const STACKS = Object.freeze({
  hub2you: Object.freeze({
    accountId: '354307071110',
    awsProfile: 'hub2you',
    region: 'us-east-1',
    instanceEnv: 'INSTAGRAM_TESTER_HUB2YOU_INSTANCE_ID',
    currentInstanceParameter: '/chatwoot/prod/blue-green/current-instance-id',
  }),
  autonomia: Object.freeze({
    accountId: '140023375763',
    awsProfile: 'financial',
    region: 'us-east-1',
    instanceEnv: 'INSTAGRAM_TESTER_AUTONOMIA_INSTANCE_ID',
    currentInstanceParameter: '/chatwoot/prod/blue-green/current-instance-id',
  }),
});

const staticFailure = () => new Error('instagram_session_publication_failed');

function requireSafe(value, condition = true) {
  if (condition === true ? !value : !condition) throw staticFailure();
  return value;
}

function stopProcess(child, group = false) {
  if (!child) return;
  try {
    if (group && child.pid && child.exitCode === null)
      process.kill(-child.pid, 'SIGTERM');
    else child.kill();
  } catch {
    child.kill();
  }
}

function awsArgs(config, args) {
  return [
    '--profile',
    config.awsProfile,
    '--region',
    config.region,
    '--no-cli-pager',
    ...args,
  ];
}

export function runtimeConfig(stack, env = process.env) {
  const profile = STACKS[stack];
  requireSafe(profile, typeof profile === 'object');
  const instanceId = env[profile.instanceEnv];
  const sshKey = env.INSTAGRAM_TESTER_PUBLISHER_SSH_KEY;
  requireSafe(instanceId === undefined || INSTANCE_ID.test(instanceId));
  requireSafe(sshKey, PRIVATE_PATH.test(sshKey));
  const hostKeyDocument =
    env.INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT || 'AWS-RunShellScript';
  requireSafe(
    ['AWS-RunShellScript', HOST_KEY_DOCUMENT].includes(hostKeyDocument)
  );
  return Object.freeze({
    ...profile,
    stack,
    instanceId,
    sshKey,
    hostKeyDocument,
  });
}

export function startSessionArguments(config, localPort) {
  requireSafe(config && INSTANCE_ID.test(config.instanceId));
  requireSafe(
    Number.isInteger(localPort) && localPort >= 1024 && localPort <= 65535
  );
  return awsArgs(config, [
    'ssm',
    'start-session',
    '--target',
    config.instanceId,
    '--document-name',
    'AWS-StartPortForwardingSession',
    '--parameters',
    `portNumber=["22"],localPortNumber=["${localPort}"]`,
  ]);
}

export function publisherSshArguments(config, localPort, knownHostsPath) {
  requireSafe(config && PRIVATE_PATH.test(config.sshKey));
  requireSafe(
    Number.isInteger(localPort) && localPort >= 1024 && localPort <= 65535
  );
  requireSafe(
    typeof knownHostsPath === 'string' && PRIVATE_PATH.test(knownHostsPath)
  );
  return [
    '-T',
    '-o',
    'BatchMode=yes',
    '-o',
    'RequestTTY=no',
    '-o',
    'StrictHostKeyChecking=yes',
    '-o',
    `UserKnownHostsFile=${knownHostsPath}`,
    '-o',
    'GlobalKnownHostsFile=/dev/null',
    '-o',
    'VerifyHostKeyDNS=no',
    '-o',
    'UpdateHostkeys=no',
    '-o',
    'IdentitiesOnly=yes',
    '-o',
    'IdentityAgent=none',
    '-o',
    'ClearAllForwardings=yes',
    '-o',
    'ControlMaster=no',
    '-o',
    'LogLevel=ERROR',
    '-i',
    config.sshKey,
    '-p',
    String(localPort),
    'chatwoot_publisher@127.0.0.1',
  ];
}

export function parsePublisherOutput(output, type) {
  const result = parseEnvelope(output, type);
  return result.type === 'session' ? result.version : result;
}

export function knownHostsLine(publicKey, localPort) {
  requireSafe(typeof publicKey === 'string');
  requireSafe(
    Number.isInteger(localPort) && localPort >= 1024 && localPort <= 65535
  );
  const parts = publicKey.trim().split(/\s+/);
  requireSafe(
    parts.length >= 2 &&
      PUBLIC_KEY_TYPE.test(parts[0]) &&
      PUBLIC_KEY_DATA.test(parts[1])
  );
  return `[127.0.0.1]:${localPort} ${parts[0]} ${parts[1]}\n`;
}

export function commandRunner(
  command,
  args,
  { input = '', timeoutMs = 30000, spawnImpl = spawn, signal } = {}
) {
  requireSafe(command === 'aws');
  requireSafe(
    Array.isArray(args) &&
      args.every(value => typeof value === 'string' && !/[\0\r\n]/.test(value))
  );
  return new Promise((resolve, reject) => {
    const chunks = [];
    let outputBytes = 0;
    let settled = false;
    let timer;
    let onAbort;
    const child = spawnImpl(command, args, {
      shell: false,
      stdio: ['pipe', 'pipe', 'ignore'],
    });
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (onAbort) signal?.removeEventListener('abort', onAbort);
      if (error) reject(staticFailure());
      else resolve(value);
    };
    onAbort = () => {
      child.kill();
      finish(staticFailure());
    };
    signal?.addEventListener('abort', onAbort, { once: true });
    if (signal?.aborted) {
      onAbort();
      return;
    }
    timer = setTimeout(() => {
      child.kill();
      finish(staticFailure());
    }, timeoutMs);
    child.stdout?.on('data', chunk => {
      if (settled) return;
      const buffer = Buffer.from(chunk);
      outputBytes += buffer.length;
      if (outputBytes > MAX_OUTPUT_BYTES * 4) {
        child.kill();
        finish(staticFailure());
        return;
      }
      chunks.push(buffer);
    });
    child.once('error', () => finish(staticFailure()));
    child.once('close', code => {
      if (code !== 0) finish(staticFailure());
      else finish(null, Buffer.concat(chunks, outputBytes).toString('utf8'));
    });
    child.stdin?.end(input);
  });
}

export async function verifyAwsAccount(
  config,
  { run = commandRunner, signal, timeoutMs } = {}
) {
  const account = (
    await run(
      'aws',
      awsArgs(config, [
        'sts',
        'get-caller-identity',
        '--query',
        'Account',
        '--output',
        'text',
      ]),
      { signal, timeoutMs }
    )
  ).trim();
  requireSafe(account === config.accountId);
  return true;
}

export async function currentInstanceViaSsm(
  config,
  { run = commandRunner, signal, timeoutMs } = {}
) {
  const instanceId = (
    await run(
      'aws',
      awsArgs(config, [
        'ssm',
        'get-parameter',
        '--name',
        config.currentInstanceParameter,
        '--query',
        'Parameter.Value',
        '--output',
        'text',
      ]),
      { signal, timeoutMs }
    )
  ).trim();
  requireSafe(INSTANCE_ID.test(instanceId));
  return instanceId;
}

export async function hostKeyViaSsm(
  config,
  { run = commandRunner, sleep = delay, signal, deadline, now = Date.now } = {}
) {
  const runAws = args =>
    run('aws', args, {
      signal,
      timeoutMs: deadline ? Math.max(1, deadline - now()) : undefined,
    });
  const commandId = (
    await runAws(
      awsArgs(config, [
        'ssm',
        'send-command',
        '--instance-ids',
        config.instanceId,
        '--document-name',
        config.hostKeyDocument || 'AWS-RunShellScript',
        ...(config.hostKeyDocument === HOST_KEY_DOCUMENT
          ? []
          : [
              '--parameters',
              'commands=["/usr/bin/cat /etc/ssh/ssh_host_ed25519_key.pub"]',
            ]),
        '--query',
        'Command.CommandId',
        '--output',
        'text',
      ])
    )
  ).trim();
  requireSafe(/^[A-Za-z0-9-]{8,128}$/.test(commandId));

  const pollingDeadline = deadline || now() + 30000;
  while (now() < pollingDeadline) {
    if (signal?.aborted) throw staticFailure();
    const raw = await runAws(
      awsArgs(config, [
        'ssm',
        'list-command-invocations',
        '--command-id',
        commandId,
        '--details',
        '--query',
        'CommandInvocations[0].{Status:Status,Output:CommandPlugins[0].Output}',
        '--output',
        'json',
      ])
    );
    let response;
    try {
      response = JSON.parse(raw);
    } catch {
      throw staticFailure();
    }
    if (response?.Status === 'Success') return response.Output || '';
    if (
      response?.Status != null &&
      ['Failed', 'Cancelled', 'TimedOut', 'Cancelling'].includes(
        response.Status
      )
    )
      throw staticFailure();
    await sleep(Math.min(500, Math.max(1, pollingDeadline - now())));
  }
  throw staticFailure();
}

export function freePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once('error', () => reject(staticFailure()));
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = address && typeof address === 'object' ? address.port : null;
      server.close(error => {
        if (error || !port) reject(staticFailure());
        else resolve(port);
      });
    });
  });
}

export async function waitForPort(
  port,
  { timeoutMs = 30000, sleep = delay, signal, deadline, now = Date.now } = {}
) {
  const pollingDeadline = deadline || now() + timeoutMs;
  while (now() < pollingDeadline) {
    if (signal?.aborted) throw staticFailure();
    const connected = await new Promise(resolve => {
      const socket = createConnection({ host: '127.0.0.1', port });
      const abort = () => {
        socket.destroy();
        resolve(false);
      };
      socket.once('connect', () => {
        signal?.removeEventListener('abort', abort);
        socket.destroy();
        resolve(true);
      });
      socket.once('error', () => {
        signal?.removeEventListener('abort', abort);
        socket.destroy();
        resolve(false);
      });
      signal?.addEventListener('abort', abort, { once: true });
    });
    if (signal?.aborted) throw staticFailure();
    if (connected) return true;
    await sleep(Math.min(100, Math.max(1, pollingDeadline - now())));
  }
  throw staticFailure();
}

function abortable(promise, signal) {
  if (!signal) return promise;
  return new Promise((resolve, reject) => {
    let settled = false;
    let onAbort;
    const cleanup = () => {
      if (onAbort) signal.removeEventListener('abort', onAbort);
    };
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      cleanup();
      if (error) reject(staticFailure());
      else resolve(value);
    };
    onAbort = () => finish(staticFailure());
    signal.addEventListener('abort', onAbort, { once: true });
    Promise.resolve(promise).then(
      value => finish(null, value),
      error => finish(error)
    );
    if (signal.aborted) onAbort();
  });
}

export async function runPublisher(
  payload,
  {
    stack,
    env = process.env,
    spawnImpl = spawn,
    run = commandRunner,
    sleep = delay,
    budgetMs = PUBLISH_BUDGET_MS,
    now = Date.now,
    freePortFn = freePort,
    waitForPortFn = waitForPort,
    hostKeyFn = hostKeyViaSsm,
    signals = process,
    clock = globalThis,
    stopProcessFn = stopProcess,
    files = { mkdtemp, writeFile, chmod, rm },
  } = {}
) {
  validateRequest(payload);
  requireSafe(Number.isInteger(budgetMs) && budgetMs > 0 && budgetMs < 30000);
  const config = runtimeConfig(stack, env);
  const deadline = now() + budgetMs;
  const controller = new AbortController();
  let activeTunnel;
  let activeSsh;
  const stopChildren = () => {
    controller.abort();
    stopProcessFn(activeSsh);
    stopProcessFn(activeTunnel, true);
  };
  const onSignal = () => stopChildren();
  const remaining = () => {
    if (controller.signal.aborted) throw staticFailure();
    const value = deadline - now();
    if (value <= 0) {
      stopChildren();
      throw staticFailure();
    }
    return value;
  };
  const budgetTimer = clock.setTimeout(stopChildren, budgetMs);
  signals.once('SIGTERM', onSignal);
  signals.once('SIGINT', onSignal);
  try {
    await abortable(
      verifyAwsAccount(config, {
        run,
        signal: controller.signal,
        timeoutMs: remaining(),
      }),
      controller.signal
    );
    const currentInstanceId = await abortable(
      currentInstanceViaSsm(config, {
        run,
        signal: controller.signal,
        timeoutMs: remaining(),
      }),
      controller.signal
    );
    if (config.instanceId) requireSafe(currentInstanceId === config.instanceId);
    const targetConfig = Object.freeze({
      ...config,
      instanceId: currentInstanceId,
    });
    const port = await abortable(freePortFn(), controller.signal);
    remaining();
    activeTunnel = spawnImpl('aws', startSessionArguments(targetConfig, port), {
      shell: false,
      detached: true,
      // Keep stdin alive until cleanup; EOF can close the forwarder.
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    activeTunnel.once('error', () => {});
    activeTunnel.stdout?.resume();
    activeTunnel.stderr?.resume();
    await abortable(
      waitForPortFn(port, {
        timeoutMs: remaining(),
        deadline,
        sleep,
        signal: controller.signal,
        now,
      }),
      controller.signal
    );
    const rawKey = await abortable(
      hostKeyFn(targetConfig, {
        run,
        sleep,
        signal: controller.signal,
        deadline,
        now,
      }),
      controller.signal
    );
    const scratch = await abortable(
      files.mkdtemp(join(tmpdir(), 'instagram-publisher-')),
      controller.signal
    );
    const knownHostsPath = join(scratch, 'known_hosts');
    try {
      await abortable(
        files.writeFile(knownHostsPath, knownHostsLine(rawKey, port), {
          mode: 0o600,
        }),
        controller.signal
      );
      await abortable(files.chmod(knownHostsPath, 0o600), controller.signal);
      return await abortable(
        new Promise((resolve, reject) => {
          const chunks = [];
          let outputBytes = 0;
          let settled = false;
          let timer;
          let onStdinError;
          remaining();
          const child = spawnImpl(
            'ssh',
            publisherSshArguments(targetConfig, port, knownHostsPath),
            {
              shell: false,
              stdio: ['pipe', 'pipe', 'ignore'],
            }
          );
          activeSsh = child;
          let onAbort;
          const finish = (error, value) => {
            if (settled) return;
            settled = true;
            clock.clearTimeout(timer);
            if (onAbort)
              controller.signal.removeEventListener('abort', onAbort);
            child.stdin?.removeListener('error', onStdinError);
            if (activeSsh === child) activeSsh = null;
            if (error) reject(staticFailure());
            else resolve(value);
          };
          onStdinError = () => {
            stopProcessFn(child);
            finish(staticFailure());
          };
          onAbort = () => {
            stopProcessFn(child);
            finish(staticFailure());
          };
          controller.signal.addEventListener('abort', onAbort, { once: true });
          timer = clock.setTimeout(() => {
            child.kill();
            finish(staticFailure());
          }, remaining());
          child.stdout?.on('data', chunk => {
            if (settled) return;
            const buffer = Buffer.from(chunk);
            outputBytes += buffer.length;
            if (outputBytes > MAX_OUTPUT_BYTES) {
              child.kill();
              finish(staticFailure());
              return;
            }
            chunks.push(buffer);
          });
          child.once('error', () => finish(staticFailure()));
          child.stdin?.on('error', onStdinError);
          child.once('close', code => {
            if (code !== 0) finish(staticFailure());
            else {
              try {
                finish(
                  null,
                  parsePublisherOutput(
                    Buffer.concat(chunks, outputBytes).toString('utf8'),
                    payload.operation === 'bootstrap'
                      ? 'bootstrap'
                      : payload.type
                  )
                );
              } catch {
                finish(staticFailure());
              }
            }
          });
          child.stdin?.end(JSON.stringify(payload));
        }),
        controller.signal
      );
    } finally {
      await abortable(
        files.rm(scratch, { recursive: true, force: true }),
        controller.signal
      ).catch(() => {});
    }
  } finally {
    clock.clearTimeout(budgetTimer);
    signals.removeListener('SIGTERM', onSignal);
    signals.removeListener('SIGINT', onSignal);
    stopProcessFn(activeSsh);
    stopProcessFn(activeTunnel, true);
  }
}

async function readInput() {
  let input = '';
  for await (const chunk of process.stdin) {
    input += chunk;
    if (Buffer.byteLength(input) > 2 * 1024 * 1024) throw staticFailure();
  }
  try {
    return JSON.parse(input);
  } catch {
    throw staticFailure();
  }
}

function stackFromArgs(args) {
  requireSafe(
    args.length === 2 && args[0] === '--stack' && Object.hasOwn(STACKS, args[1])
  );
  return args[1];
}

export async function main(args = process.argv.slice(2), env = process.env) {
  const stack = stackFromArgs(args);
  const payload = await readInput();
  const result = await runPublisher(payload, { stack, env });
  process.stdout.write(
    JSON.stringify(
      payload.type === 'session' && payload.operation !== 'bootstrap'
        ? { type: 'session', version: result }
        : result
    )
  );
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  main().catch(() => {
    process.stderr.write('instagram_session_publication_failed\n');
    process.exitCode = 2;
  });
}
