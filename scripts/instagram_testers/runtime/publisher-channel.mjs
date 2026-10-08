/* eslint-disable no-await-in-loop, no-restricted-syntax -- The channel and its AWS health checks are intentionally sequential. */

import { spawn } from 'node:child_process';
import { chmod, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  commandRunner,
  freePort,
  hostKeyViaSsm,
  knownHostsLine,
  parsePublisherOutput,
  PUBLISH_BUDGET_MS,
  PUBLISHER_CHANNEL_COMMAND,
  publisherSshArguments,
  runtimeConfig,
  startSessionArguments,
  verifyAwsAccount,
  waitForPort,
} from './publisher-tunnel.mjs';
import { validateRequest } from './operator-protocol.mjs';

export { PUBLISHER_CHANNEL_COMMAND };
export const MAX_CHANNEL_INPUT_BYTES = 2 * 1024 * 1024;
export const MAX_CHANNEL_OUTPUT_BYTES = 2048;

const staticFailure = () => new Error('instagram_session_publication_failed');

async function defaultCurrentReaderFactory(config) {
  const { createSsmCurrentReader } = await import(
    './vps/ssm-current-reader.mjs'
  );
  return createSsmCurrentReader(config);
}

function stopProcess(child, group = false) {
  if (!child) return;
  try {
    if (group && child.pid && child.exitCode === null)
      process.kill(-child.pid, 'SIGTERM');
    else child.kill();
  } catch {
    try {
      child.kill();
    } catch {
      // The child already exited.
    }
  }
}

function delay(milliseconds) {
  return new Promise(resolve => {
    setTimeout(resolve, milliseconds);
  });
}

function abortable(promise, signal) {
  if (!signal) return promise;
  return new Promise((resolve, reject) => {
    let settled = false;
    let onAbort;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      signal.removeEventListener('abort', onAbort);
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

function frameController(signals, clock, budgetMs) {
  const controller = new AbortController();
  const cancel = () => controller.abort();
  let timer = clock.setTimeout(cancel, budgetMs);
  signals?.once('SIGTERM', cancel);
  signals?.once('SIGINT', cancel);
  return {
    signal: controller.signal,
    clear() {
      clock.clearTimeout(timer);
      timer = null;
      signals?.removeListener('SIGTERM', cancel);
      signals?.removeListener('SIGINT', cancel);
    },
  };
}

function writeFrame(stream, frame, signal) {
  const output = `${JSON.stringify(frame)}\n`;
  if (Buffer.byteLength(output) > MAX_CHANNEL_INPUT_BYTES)
    return Promise.reject(staticFailure());
  return new Promise((resolve, reject) => {
    let settled = false;
    let onAbort;
    let onError;
    let onClose;
    let onDrain;
    const finish = error => {
      if (settled) return;
      settled = true;
      signal?.removeEventListener('abort', onAbort);
      stream.removeListener('error', onError);
      stream.removeListener('close', onClose);
      stream.removeListener('drain', onDrain);
      if (error) reject(staticFailure());
      else resolve();
    };
    onError = () => finish(staticFailure());
    onClose = () => finish(staticFailure());
    onDrain = () => finish();
    onAbort = () => finish(staticFailure());
    stream.once('error', onError);
    stream.once('close', onClose);
    signal?.addEventListener('abort', onAbort, { once: true });
    if (signal?.aborted) {
      onAbort();
      return;
    }
    try {
      const drained = stream.write(output, error => {
        if (error) onError();
        else finish();
      });
      if (!drained) stream.once('drain', onDrain);
    } catch {
      onError();
    }
  });
}

export async function createPublisherChannel({
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
  currentReaderFactory = defaultCurrentReaderFactory,
} = {}) {
  if (!Number.isInteger(budgetMs) || budgetMs <= 0 || budgetMs >= 30000)
    throw staticFailure();
  const config = runtimeConfig(stack, env);
  const lifecycle = new AbortController();
  const deadline = now() + budgetMs;
  let activeTunnel;
  let activeSsh;
  let scratch;
  let closed = false;
  let closing;
  let frameActive = false;
  let frameWaiter;
  let outputBuffer = Buffer.alloc(0);
  let currentReaderPromise;

  const stopChildren = () => {
    lifecycle.abort();
    stopProcessFn(activeSsh);
    stopProcessFn(activeTunnel, true);
  };
  const remaining = () => {
    if (lifecycle.signal.aborted || closed) throw staticFailure();
    const value = deadline - now();
    if (value <= 0) {
      stopChildren();
      throw staticFailure();
    }
    return value;
  };
  const close = () => {
    if (closing) return closing;
    closed = true;
    lifecycle.abort();
    frameWaiter?.reject(staticFailure());
    frameWaiter = null;
    stopChildren();
    closing = (async () => {
      await currentReaderPromise
        ?.then(reader => reader?.close?.())
        .catch(() => {});
      if (scratch)
        await files
          .rm(scratch, { recursive: true, force: true })
          .catch(() => {});
      outputBuffer = Buffer.alloc(0);
    })();
    return closing;
  };
  const failChannel = () => {
    close().catch(() => {});
  };

  try {
    currentReaderPromise = Promise.resolve()
      .then(() => currentReaderFactory(config, { env }))
      .then(reader => {
        if (!reader || typeof reader.read !== 'function') throw staticFailure();
        return reader;
      });
    const metadata = [
      abortable(
        Promise.resolve().then(() =>
          verifyAwsAccount(config, {
            run,
            signal: lifecycle.signal,
            timeoutMs: remaining(),
          })
        ),
        lifecycle.signal
      ),
      abortable(
        Promise.resolve().then(async () => {
          const reader = await currentReaderPromise;
          const currentInstanceId = await reader.read({
            signal: lifecycle.signal,
            timeoutMs: remaining(),
          });
          if (config.instanceId) {
            if (currentInstanceId !== config.instanceId) throw staticFailure();
          }
          return currentInstanceId;
        }),
        lifecycle.signal
      ),
    ];
    let currentInstanceId;
    try {
      [, currentInstanceId] = await Promise.all(metadata);
    } catch {
      stopChildren();
      await Promise.allSettled(metadata);
      throw staticFailure();
    }
    const targetConfig = Object.freeze({
      ...config,
      instanceId: currentInstanceId,
    });
    const port = await abortable(freePortFn(), lifecycle.signal);
    remaining();
    activeTunnel = spawnImpl('aws', startSessionArguments(targetConfig, port), {
      shell: false,
      detached: true,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    activeTunnel.once('error', failChannel);
    activeTunnel.once('close', failChannel);
    activeTunnel.stdout?.resume();
    activeTunnel.stderr?.resume();

    const readiness = [
      abortable(
        Promise.resolve().then(() =>
          waitForPortFn(port, {
            timeoutMs: remaining(),
            deadline,
            sleep,
            signal: lifecycle.signal,
            now,
          })
        ),
        lifecycle.signal
      ),
      abortable(
        Promise.resolve().then(() =>
          hostKeyFn(targetConfig, {
            run,
            sleep,
            signal: lifecycle.signal,
            deadline,
            now,
          })
        ),
        lifecycle.signal
      ),
    ];
    let rawKey;
    try {
      [, rawKey] = await Promise.all(readiness);
    } catch {
      stopChildren();
      await Promise.allSettled(readiness);
      throw staticFailure();
    }
    remaining();
    scratch = await abortable(
      files.mkdtemp(join(tmpdir(), 'instagram-publisher-channel-')),
      lifecycle.signal
    );
    const knownHostsPath = join(scratch, 'known_hosts');
    await abortable(
      files.writeFile(knownHostsPath, knownHostsLine(rawKey, port), {
        mode: 0o600,
      }),
      lifecycle.signal
    );
    await abortable(files.chmod(knownHostsPath, 0o600), lifecycle.signal);

    activeSsh = spawnImpl(
      'ssh',
      publisherSshArguments(
        targetConfig,
        port,
        knownHostsPath,
        PUBLISHER_CHANNEL_COMMAND
      ),
      { shell: false, stdio: ['pipe', 'pipe', 'ignore'] }
    );
    activeSsh.once('error', failChannel);
    activeSsh.once('close', failChannel);
    activeSsh.stdout?.on('data', chunk => {
      if (closed) return;
      outputBuffer = Buffer.concat([outputBuffer, Buffer.from(chunk)]);
      if (outputBuffer.length > MAX_CHANNEL_OUTPUT_BYTES + 1) {
        failChannel();
        return;
      }
      while (!closed) {
        const newline = outputBuffer.indexOf(0x0a);
        if (newline < 0) break;
        const line = outputBuffer.subarray(0, newline);
        outputBuffer = outputBuffer.subarray(newline + 1);
        if (!line.length || line.length > MAX_CHANNEL_OUTPUT_BYTES) {
          failChannel();
          return;
        }
        if (!frameWaiter) {
          failChannel();
          return;
        }
        const waiter = frameWaiter;
        frameWaiter = null;
        waiter.resolve(
          line[line.length - 1] === 0x0d ? line.subarray(0, -1) : line
        );
      }
    });

    const readFrame = signal =>
      new Promise((resolve, reject) => {
        if (closed || frameWaiter) {
          reject(staticFailure());
          return;
        }
        let onAbort;
        frameWaiter = {
          resolve: value => {
            signal?.removeEventListener('abort', onAbort);
            resolve(value);
          },
          reject: error => {
            signal?.removeEventListener('abort', onAbort);
            reject(error);
          },
        };
        onAbort = () => {
          if (frameWaiter) {
            frameWaiter = null;
            reject(staticFailure());
          }
          close().catch(() => {});
        };
        signal?.addEventListener('abort', onAbort, { once: true });
        if (signal?.aborted) onAbort();
      });

    const send = async (
      payload,
      { signals: requestSignals = signals } = {}
    ) => {
      validateRequest(payload);
      if (closed || frameActive) throw staticFailure();
      frameActive = true;
      const frame = frameController(requestSignals, clock, budgetMs);
      const frameDeadline = now() + budgetMs;
      try {
        const reader = await currentReaderPromise;
        const current = await reader.read({
          signal: frame.signal,
          timeoutMs: Math.max(1, frameDeadline - now()),
        });
        if (current !== targetConfig.instanceId) throw staticFailure();
        const response = readFrame(frame.signal);
        const [, raw] = await Promise.all([
          writeFrame(activeSsh.stdin, payload, frame.signal),
          response,
        ]);
        const output = Buffer.from(raw).toString('utf8');
        return parsePublisherOutput(
          output,
          payload.operation === 'bootstrap' ? 'bootstrap' : payload.type
        );
      } catch {
        await close();
        throw staticFailure();
      } finally {
        frame.clear();
        frameActive = false;
      }
    };

    return Object.freeze({ close, send });
  } catch {
    await close();
    throw staticFailure();
  }
}
