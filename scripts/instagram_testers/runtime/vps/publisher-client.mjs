import { createConnection } from 'node:net';
import { pathToFileURL } from 'node:url';
import { parseEnvelope, validateRequest } from '../operator-protocol.mjs';
import {
  abortable,
  decodeInput,
  MAX_OUTPUT_BYTES,
  publicationFailure,
  publisherSocketConfig,
  readBoundedInput,
  REQUEST_TIMEOUT_MS,
  sameIdentity,
  socketIdentity,
} from './publisher-socket.mjs';

function exchange(payload, config, identity, options, signal) {
  return new Promise((resolve, reject) => {
    let socket;
    let chunks = [];
    let bytes = 0;
    let sent = false;
    let settled = false;
    let onAbort;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      chunks = [];
      signal.removeEventListener('abort', onAbort);
      socket?.destroy();
      if (error) reject(publicationFailure());
      else resolve(value);
    };
    onAbort = () => finish(publicationFailure());
    signal.addEventListener('abort', onAbort, { once: true });
    if (signal.aborted) {
      onAbort();
      return;
    }
    try {
      socket = options.connectImpl({
        path: config.socket,
        allowHalfOpen: true,
      });
      socket.once('connect', async () => {
        try {
          const current = await socketIdentity(config, options);
          if (settled) return;
          if (
            !sameIdentity(identity.directory, current.directory) ||
            !sameIdentity(identity.socket, current.socket)
          )
            throw publicationFailure();
          sent = true;
          socket.end(JSON.stringify(payload));
        } catch {
          onAbort();
        }
      });
      socket.on('data', chunk => {
        if (settled) return;
        const buffer = Buffer.from(chunk);
        bytes += buffer.length;
        if (bytes > MAX_OUTPUT_BYTES) onAbort();
        else chunks.push(buffer);
      });
      socket.once('end', () => {
        if (settled) return;
        try {
          if (!sent) throw publicationFailure();
          const type =
            payload.operation === 'bootstrap' ? 'bootstrap' : payload.type;
          finish(null, parseEnvelope(decodeInput(chunks, bytes), type));
        } catch {
          onAbort();
        }
      });
      socket.once('error', onAbort);
      socket.once('close', onAbort);
    } catch {
      onAbort();
    }
  });
}

// The client uses no publisher configuration, credentials, subprocesses or TCP.
export async function runPublisherClient({
  stack,
  socketPath,
  input = process.stdin,
  uid = process.getuid(),
  gid = process.getgid(),
  lstatImpl,
  connectImpl = createConnection,
  signals = process,
  clock = globalThis,
} = {}) {
  const controller = new AbortController();
  const cancel = () => controller.abort();
  const timer = clock.setTimeout(cancel, REQUEST_TIMEOUT_MS);
  signals.once('SIGTERM', cancel);
  signals.once('SIGINT', cancel);
  try {
    const config = publisherSocketConfig(stack, socketPath);
    const payload = validateRequest(
      await readBoundedInput(input, { signal: controller.signal })
    );
    const options = { uid, gid, lstatImpl, connectImpl };
    const identity = await abortable(
      socketIdentity(config, options),
      controller.signal
    );
    return await exchange(
      payload,
      config,
      identity,
      options,
      controller.signal
    );
  } catch {
    input.destroy();
    throw publicationFailure();
  } finally {
    clock.clearTimeout(timer);
    signals.removeListener('SIGTERM', cancel);
    signals.removeListener('SIGINT', cancel);
  }
}

export async function main(args = process.argv.slice(2), env = process.env) {
  if (
    args.length !== 2 ||
    args[0] !== '--stack' ||
    !env.INSTAGRAM_TESTER_PUBLISHER_SOCKET
  )
    throw publicationFailure();
  const result = await runPublisherClient({
    stack: args[1],
    socketPath: env.INSTAGRAM_TESTER_PUBLISHER_SOCKET,
  });
  process.stdout.write(JSON.stringify(result));
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
