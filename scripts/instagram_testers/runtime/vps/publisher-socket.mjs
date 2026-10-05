import { lstat } from 'node:fs/promises';

export const MAX_INPUT_BYTES = 2 * 1024 * 1024;
export const MAX_OUTPUT_BYTES = 2048;
export const REQUEST_TIMEOUT_MS = 30_000;
export const MAX_CONNECTIONS = 4;
export const publicationFailure = () =>
  new Error('instagram_session_publication_failed');

export function publisherSocketConfig(stack, socketPath) {
  if (!['hub2you', 'autonomia'].includes(stack)) throw publicationFailure();
  const directory = `/run/instagram-publisher-${stack}`;
  const socket = `${directory}/publisher.sock`;
  if (socketPath !== undefined && socketPath !== socket)
    throw publicationFailure();
  return Object.freeze({ stack, directory, socket });
}

export function sameIdentity(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

export async function socketIdentity(
  config,
  {
    role = 'client',
    uid = process.getuid(),
    gid = process.getgid(),
    lstatImpl = lstat,
    directoryOnly = false,
  } = {}
) {
  try {
    const fixed = publisherSocketConfig(config.stack, config.socket);
    if (
      config.directory !== fixed.directory ||
      !['client', 'broker'].includes(role)
    )
      throw publicationFailure();
    const directory = await lstatImpl(fixed.directory);
    // eslint-disable-next-line no-bitwise -- Require exact POSIX permissions, including no special bits.
    const directoryMode = directory.mode & 0o7777;
    if (
      directory.isSymbolicLink() ||
      !directory.isDirectory() ||
      directoryMode !== 0o710 ||
      directory.gid !== gid ||
      directory.uid === 0 ||
      (role === 'broker'
        ? uid === 0 || directory.uid !== uid
        : directory.uid === uid)
    )
      throw publicationFailure();
    if (directoryOnly) return { directory };
    const socket = await lstatImpl(fixed.socket);
    // eslint-disable-next-line no-bitwise -- Require exact POSIX socket permissions.
    const socketMode = socket.mode & 0o7777;
    if (
      socket.isSymbolicLink() ||
      !socket.isSocket() ||
      socketMode !== 0o660 ||
      socket.gid !== gid ||
      socket.uid !== directory.uid
    )
      throw publicationFailure();
    return { directory, socket };
  } catch {
    throw publicationFailure();
  }
}

export function decodeInput(chunks, bytes) {
  return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(
    Buffer.concat(chunks, bytes)
  );
}

export function abortable(promise, signal) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let abort;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      signal.removeEventListener('abort', abort);
      if (error) reject(publicationFailure());
      else resolve(value);
    };
    abort = () => finish(publicationFailure());
    signal.addEventListener('abort', abort, { once: true });
    Promise.resolve(promise).then(
      value => finish(null, value),
      () => finish(publicationFailure())
    );
    if (signal.aborted) abort();
  });
}

export function readBoundedInput(input, { signal } = {}) {
  return new Promise((resolve, reject) => {
    let chunks = [];
    let bytes = 0;
    let settled = false;
    let onData;
    let onEnd;
    let onError;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      input.removeListener('data', onData);
      input.removeListener('end', onEnd);
      input.removeListener('error', onError);
      input.removeListener('close', onError);
      signal?.removeEventListener('abort', onError);
      chunks = [];
      if (error) reject(publicationFailure());
      else resolve(value);
    };
    onError = () => finish(publicationFailure());
    onData = chunk => {
      const buffer = Buffer.from(chunk);
      bytes += buffer.length;
      if (bytes > MAX_INPUT_BYTES) onError();
      else chunks.push(buffer);
    };
    onEnd = () => {
      try {
        finish(null, JSON.parse(decodeInput(chunks, bytes)));
      } catch {
        onError();
      }
    };
    input.on('data', onData);
    input.once('end', onEnd);
    input.once('error', onError);
    input.once('close', onError);
    signal?.addEventListener('abort', onError, { once: true });
    if (signal?.aborted || input.destroyed || input.readableEnded) onError();
  });
}
