import { EventEmitter } from 'node:events';
import { chmod, lstat } from 'node:fs/promises';
import { createServer } from 'node:net';
import { isMainModule } from '../entrypoint.mjs';
import { parseEnvelope, validateRequest } from '../operator-protocol.mjs';
import { runPublisher } from '../publisher-tunnel.mjs';
import { createPublisherChannel } from '../publisher-channel.mjs';
import {
  MAX_CONNECTIONS,
  MAX_OUTPUT_BYTES,
  publicationFailure,
  publisherSocketConfig,
  readBoundedInput,
  REQUEST_TIMEOUT_MS,
  sameIdentity,
  socketIdentity,
} from './publisher-socket.mjs';

export function publisherEnvelope(payload, result) {
  const type = payload.operation === 'bootstrap' ? 'bootstrap' : payload.type;
  const output = JSON.stringify(
    type === 'session' ? { type, version: result } : result
  );
  if (
    typeof output !== 'string' ||
    Buffer.byteLength(output) > MAX_OUTPUT_BYTES
  )
    throw publicationFailure();
  parseEnvelope(output, type);
  return output;
}

export async function createPublisherBroker({
  stack,
  socketPath,
  env = process.env,
  uid = process.getuid(),
  gid = process.getgid(),
  lstatImpl = lstat,
  chmodImpl = chmod,
  createServerImpl = createServer,
  runPublisherImpl = runPublisher,
  channelFactory = createPublisherChannel,
  warmChannel = false,
  prewarmChannel = true,
  signals = process,
  clock = globalThis,
} = {}) {
  const config = publisherSocketConfig(stack, socketPath);
  const identityOptions = { role: 'broker', uid, gid, lstatImpl };
  const initial = await socketIdentity(config, {
    ...identityOptions,
    directoryOnly: true,
  });
  try {
    await lstatImpl(config.socket);
    throw publicationFailure();
  } catch (error) {
    if (error.code !== 'ENOENT') throw publicationFailure();
  }

  const active = new Map();
  let channel;
  let channelPromise;
  let channelQueue = Promise.resolve();
  let stopping = false;
  let ready = false;
  let closing;
  let bindingDone;
  const binding = new Promise(resolve => {
    bindingDone = resolve;
  });

  const closeChannel = async candidate => {
    if (!candidate) return;
    if (channel === candidate) {
      channel = null;
      channelPromise = null;
    }
    await candidate.close().catch(() => {});
  };

  const openChannel = () => {
    if (channelPromise) return channelPromise;
    const pending = (async () => {
      const candidate = await channelFactory({ stack, env, signals, clock });
      try {
        if (stopping) throw publicationFailure();
        if (prewarmChannel) {
          const bootstrap = await candidate.send({
            type: 'session',
            operation: 'bootstrap',
          }, { signals });
          if (bootstrap?.type !== 'bootstrap') throw publicationFailure();
        }
        channel = candidate;
        return candidate;
      } catch {
        await candidate.close().catch(() => {});
        throw publicationFailure();
      }
    })();
    channelPromise = pending;
    pending.catch(() => {
      if (channelPromise === pending) channelPromise = null;
    });
    return pending;
  };

  const runWarmChannel = async (payload, requestSignals) => {
    let cancelled = false;
    const cancel = () => {
      cancelled = true;
    };
    requestSignals.once('SIGTERM', cancel);
    requestSignals.once('SIGINT', cancel);
    const previous = channelQueue;
    let release;
    channelQueue = new Promise(resolve => {
      release = resolve;
    });
    try {
      await previous;
      if (cancelled) throw publicationFailure();
      const candidate = await openChannel();
      try {
        return await candidate.send(payload, { signals: requestSignals });
      } catch {
        await closeChannel(candidate);
        throw publicationFailure();
      }
    } finally {
      requestSignals.removeListener('SIGTERM', cancel);
      requestSignals.removeListener('SIGINT', cancel);
      release();
    }
  };
  const server = createServerImpl({ allowHalfOpen: true }, socket => {
    // Count sockets while reading AND while flushing a response.
    if (!ready || stopping || active.size >= MAX_CONNECTIONS) {
      socket.on('error', () => {});
      socket.destroy();
      return;
    }
    const controller = new AbortController();
    const requestSignals = new EventEmitter();
    let closed = false;
    let publishing = false;
    let timer;
    const terminate = () => {
      if (closed) return;
      closed = true;
      clock.clearTimeout(timer);
      active.delete(socket);
      controller.abort();
      if (publishing) requestSignals.emit('SIGTERM');
      socket.destroy();
    };
    timer = clock.setTimeout(terminate, REQUEST_TIMEOUT_MS);
    active.set(socket, terminate);
    socket.on('error', terminate);
    socket.once('close', terminate);
    readBoundedInput(socket, { signal: controller.signal }).then(
      async payload => {
        try {
          if (closed) return;
          validateRequest(payload);
          publishing = true;
          const result = warmChannel
            ? await runWarmChannel(payload, requestSignals)
            : await runPublisherImpl(payload, {
                stack,
                env,
                signals: requestSignals,
              });
          publishing = false;
          if (closed) return;
          socket.end(publisherEnvelope(payload, result));
        } catch {
          terminate();
        }
      },
      terminate
    );
  });

  let onSignal;
  const close = () => {
    if (closing) return closing;
    stopping = true;
    active.forEach(terminate => terminate());
    signals.removeListener('SIGTERM', onSignal);
    signals.removeListener('SIGINT', onSignal);
    closing = binding.then(async () => {
      await closeChannel(channel);
      await channelPromise?.catch(() => {});
      await new Promise(resolve => {
        server.close(() => resolve());
      });
    });
    return closing;
  };
  onSignal = () => {
    close();
  };
  signals.once('SIGTERM', onSignal);
  signals.once('SIGINT', onSignal);
  server.on('error', onSignal);
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(config.socket, () => {
        server.removeListener('error', reject);
        resolve();
      });
    }).finally(bindingDone);
    if (stopping) throw publicationFailure();
    // The parent is not writable by the browser group. Never unlink a path here.
    await chmodImpl(config.socket, 0o660);
    const bound = await socketIdentity(config, identityOptions);
    if (stopping || !sameIdentity(initial.directory, bound.directory))
      throw publicationFailure();
    if (warmChannel) await openChannel();
    ready = true;
    return { server, close };
  } catch {
    await close();
    throw publicationFailure();
  }
}

export async function main(env = process.env) {
  if (!env.INSTAGRAM_TESTER_PUBLISHER_SOCKET) throw publicationFailure();
  return createPublisherBroker({
    stack: env.INSTAGRAM_TESTER_RUNTIME_STACK,
    socketPath: env.INSTAGRAM_TESTER_PUBLISHER_SOCKET,
    env,
    warmChannel: true,
  });
}

if (isMainModule(import.meta.url)) {
  main().catch(() => {
    process.stderr.write('instagram_session_publication_failed\n');
    process.exitCode = 2;
  });
}
