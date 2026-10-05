import http from 'node:http';
import net from 'node:net';
import { constants } from 'node:fs';
import filesystem, { lstat, open, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isMainModule } from '../entrypoint.mjs';
import { WebSocket, WebSocketServer } from 'ws';
import {
  configFromEnv,
  createAuth,
  reject,
  sameIdentity,
  runtimeDirectory,
} from './gateway-auth.mjs';

const MAX_POST = 4096;
const MAX_BUFFER = 1024 * 1024;
const ASSET_CHARS =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_./';
const OWN_ASSETS = new Map([
  ['console.js', 'text/javascript; charset=utf-8'],
  ['enter.js', 'text/javascript; charset=utf-8'],
]);
const WEB_ROOT = fileURLToPath(new URL('./web/', import.meta.url));

function securityHeaders(response, origin) {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  response.setHeader(
    'Permissions-Policy',
    'clipboard-read=(), clipboard-write=(), camera=(), microphone=(), display-capture=()'
  );
  // noVNC sets its own display dimensions/styles. All executable code remains external.
  response.setHeader(
    'Content-Security-Policy',
    `default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; img-src 'self' data: blob:; connect-src ${origin.replace('https:', 'wss:')} ${origin}; base-uri 'none'; frame-ancestors 'none'; form-action 'none'`
  );
}

function requestBoundary(request, config, origin, requiredOrigin = false) {
  const duplicate = ['host', 'origin', 'cookie', 'x-forwarded-proto'].some(
    name => (request.headersDistinct[name]?.length || 0) > 1
  );
  if (
    duplicate ||
    request.socket.remoteAddress !== '127.0.0.1' ||
    request.headers.host !== config.base.host ||
    request.headers['x-forwarded-proto'] !== 'https' ||
    (requiredOrigin && request.headers.origin !== origin) ||
    (request.headers.origin !== undefined &&
      request.headers.origin !== origin) ||
    (!requiredOrigin &&
      request.headers['sec-fetch-site'] !== undefined &&
      !['same-origin', 'none'].includes(request.headers['sec-fetch-site'])) ||
    request.headers.authorization !== undefined
  )
    throw reject();
  // Compare the raw target before URL normalization can erase traversal segments.
  const target = request.url;
  if (
    !target.startsWith(`/${config.stack}/`) ||
    target.includes('?') ||
    target.includes('#') ||
    ![...target].every(char => ASSET_CHARS.includes(char)) ||
    target.split('/').some(part => part === '.' || part === '..')
  )
    throw reject();
  return target;
}

export async function readAsset(root, relative) {
  const parts = relative.split('/');
  let filename = root;
  /* eslint-disable no-await-in-loop -- Filesystem/session checks must complete sequentially. */
  for (let index = 0; index < parts.length; index += 1) {
    if (!parts[index] || ['.', '..'].includes(parts[index])) throw reject(404);
    filename = path.join(filename, parts[index]);
    const info = await lstat(filename);
    if (
      info.isSymbolicLink() ||
      (index < parts.length - 1 ? !info.isDirectory() : !info.isFile())
    )
      throw reject(404);
  }
  /* eslint-enable no-await-in-loop */
  const handle = await open(
    filename,
    // eslint-disable-next-line no-bitwise -- POSIX open flags require bitwise composition.
    constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK
  );
  try {
    const info = await handle.stat();
    if (!info.isFile() || info.size > 2 * MAX_BUFFER) throw reject(404);
    return await handle.readFile();
  } finally {
    await handle.close();
  }
}

async function postTicket(request) {
  if (request.headers['content-type'] !== 'application/x-www-form-urlencoded')
    throw reject(415);
  const length = request.headers['content-length'];
  if (
    length !== undefined &&
    (!Number.isSafeInteger(Number(length)) || Number(length) > MAX_POST)
  )
    throw reject(413);
  const chunks = [];
  let bytes = 0;
  // eslint-disable-next-line no-restricted-syntax -- Consume the Node request stream sequentially to enforce the byte limit.
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > MAX_POST) throw reject(413);
    chunks.push(chunk);
  }
  const form = new URLSearchParams(Buffer.concat(chunks).toString('utf8'));
  const entries = [...form.entries()];
  if (entries.length !== 1 || entries[0][0] !== 'ticket' || !entries[0][1])
    throw reject();
  return entries[0][1];
}

export async function socketIdentity(config, fs = filesystem) {
  if (path.dirname(config.vncSocket) !== config.runtimeDir) throw reject();
  const parent = await runtimeDirectory(config, fs);
  const info = await fs.lstat(config.vncSocket);
  if (
    !info.isSocket() ||
    info.uid !== config.browserUid ||
    info.gid !== config.viewerGid ||
    // eslint-disable-next-line no-bitwise -- POSIX permission bits require masking.
    (info.mode & 0o7777) !== 0o660
  )
    throw reject();
  if (!sameIdentity(parent, await runtimeDirectory(config, fs))) throw reject();
  return info;
}

export async function createGateway(
  config,
  { now, pollMs = 1000, fs = filesystem } = {}
) {
  const auth = await createAuth(config, now, fs);
  // Resolve the installed dependency once; requests can select only files inside this fixed tree.
  const novncRoot = await realpath(
    path.dirname(
      path.dirname(fileURLToPath(import.meta.resolve('@novnc/novnc')))
    )
  );
  const webRoot = await realpath(WEB_ROOT);
  const prefix = `/${config.stack}/`;
  const connections = new Set();
  const websocket = new WebSocketServer({
    noServer: true,
    maxPayload: 65536,
    perMessageDeflate: false,
  });
  const server = http.createServer(
    { maxHeaderSize: 8192, requestTimeout: 5000, headersTimeout: 5000 },
    (request, response) => {
      securityHeaders(response, config.base.origin);
      (async () => {
        const granting =
          request.method === 'POST' && request.url === `${prefix}grant`;
        const target = requestBoundary(
          request,
          config,
          granting ? config.issuer : config.base.origin,
          granting
        );
        if (granting) {
          const { cookie } = await auth.grant(await postTicket(request));
          response.setHeader('Set-Cookie', cookie);
          response.setHeader('Content-Type', 'text/html; charset=utf-8');
          // A page on this origin establishes Strict-cookie context before navigating to console.
          response.end(await readAsset(webRoot, 'enter.html'));
          return;
        }
        const { ready } = await auth.validate(auth.sessionId(request.headers));
        if (request.method !== 'GET') throw reject(405);
        if (target === `${prefix}status`) {
          response.setHeader('Content-Type', 'application/json; charset=utf-8');
          response.end(JSON.stringify({ state: ready ? 'ready' : 'waiting' }));
        } else if (target === `${prefix}console/`) {
          response.setHeader('Content-Type', 'text/html; charset=utf-8');
          response.end(await readAsset(webRoot, 'console.html'));
        } else if (target.startsWith(`${prefix}assets/`)) {
          const asset = target.slice(`${prefix}assets/`.length);
          let root = webRoot;
          let relative = asset;
          let type = OWN_ASSETS.get(asset);
          if (asset.startsWith('novnc/')) {
            root = novncRoot;
            relative = asset.slice('novnc/'.length);
            if (
              !['core', 'vendor'].includes(relative.split('/')[0]) ||
              !relative.endsWith('.js')
            )
              throw reject(404);
            type = 'text/javascript; charset=utf-8';
          }
          if (!type) throw reject(404);
          const body = await readAsset(root, relative);
          response.setHeader('Content-Type', type);
          response.end(body);
        } else throw reject(404);
      })().catch(error => {
        response.statusCode = error.status || 403;
        response.end('instagram_gateway_denied');
      });
    }
  );
  server.maxConnections = 128;
  server.keepAliveTimeout = 5000;

  server.on('upgrade', (request, socket, head) => {
    socket.on('error', () => {});
    (async () => {
      if (
        request.method !== 'GET' ||
        requestBoundary(request, config, config.base.origin, true) !==
          `${prefix}ws`
      )
        throw reject();
      const id = auth.sessionId(request.headers);
      const { session } = await auth.validate(id, true);
      if (session.connection) throw reject(409);
      // Reserve before any asynchronous socket validation to exclude racing upgrades.
      session.connection = { terminate: () => socket.destroy() };
      let upgraded = false;
      try {
        const identity = await socketIdentity(config, fs);
        await auth.validate(id, true);
        websocket.handleUpgrade(request, socket, head, ws => {
          upgraded = true;
          session.connection = ws;
          connections.add(ws);
          const vnc = net.createConnection({ path: config.vncSocket });
          let connected = false;
          let stopped = false;
          let pendingBytes = 0;
          let messages = Promise.resolve();
          const stop = () => {
            if (stopped) return;
            stopped = true;
            vnc.destroy();
            ws.terminate();
          };
          vnc.pause();
          vnc.on('connect', async () => {
            try {
              if (!sameIdentity(identity, await socketIdentity(config, fs)))
                throw reject();
              await auth.validate(id, true);
              connected = true;
              vnc.resume();
            } catch {
              stop();
            }
          });
          vnc.on('data', data => {
            vnc.pause();
            (async () => {
              await auth.validate(id, true);
              if (
                ws.readyState !== WebSocket.OPEN ||
                ws.bufferedAmount > MAX_BUFFER
              )
                throw reject();
              ws.send(data, { binary: true }, error => {
                if (error) stop();
                else if (!stopped) vnc.resume();
              });
            })().catch(stop);
          });
          ws.on('message', (data, binary) => {
            pendingBytes += data.length;
            if (!binary || pendingBytes > MAX_BUFFER) {
              stop();
              return;
            }
            messages = messages
              .then(async () => {
                await auth.validate(id, true);
                if (!connected || stopped || vnc.writableLength > MAX_BUFFER)
                  throw reject();
                await new Promise((resolve, rejectWrite) => {
                  vnc.write(data, error =>
                    error ? rejectWrite(error) : resolve()
                  );
                });
                pendingBytes -= data.length;
              })
              .catch(stop);
          });
          ws.on('error', stop);
          ws.on('close', () => {
            stop();
            connections.delete(ws);
            if (session.connection === ws) session.connection = null;
          });
          vnc.on('error', stop);
          vnc.on('close', stop);
        });
      } finally {
        if (!upgraded && session.connection) session.connection = null;
      }
    })().catch(error => {
      if (!socket.destroyed)
        socket.end(
          `HTTP/1.1 ${error.status || 403} Denied\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`
        );
    });
  });

  let polling = false;
  const timer = setInterval(async () => {
    if (polling) return;
    polling = true;
    try {
      /* eslint-disable no-restricted-syntax, no-await-in-loop -- Filesystem/session checks must complete sequentially. */
      for (const id of auth.sessions.keys()) {
        try {
          await auth.validate(id);
        } catch {
          /* validate revokes invalid sessions */
        }
      }
      /* eslint-enable no-restricted-syntax, no-await-in-loop */
    } finally {
      polling = false;
    }
  }, pollMs);
  timer.unref();
  return {
    server,
    async close() {
      clearInterval(timer);
      // eslint-disable-next-line no-restricted-syntax -- Node supports native iteration; preserve ordered side effects.
      for (const ws of connections) ws.terminate();
      // eslint-disable-next-line no-restricted-syntax -- Node supports native iteration; preserve ordered side effects.
      for (const id of auth.sessions.keys()) auth.revoke(id);
      await new Promise(resolve => {
        websocket.close(resolve);
      });
      server.closeAllConnections();
      if (server.listening)
        await new Promise(resolve => {
          server.close(resolve);
        });
    },
  };
}

if (isMainModule(import.meta.url)) {
  try {
    const config = await configFromEnv();
    const gateway = await createGateway(config);
    gateway.server.on('error', () => {
      process.stderr.write('instagram_gateway_failed\n');
      process.exit(1);
    });
    gateway.server.listen(config.port, '127.0.0.1');
    // eslint-disable-next-line no-restricted-syntax -- Node supports native iteration; preserve ordered side effects.
    for (const signal of ['SIGTERM', 'SIGINT'])
      process.once(signal, async () => {
        await gateway.close();
      });
  } catch {
    process.stderr.write('instagram_gateway_failed\n');
    process.exitCode = 1;
  }
}
