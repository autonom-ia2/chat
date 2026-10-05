import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { EventEmitter, once } from 'node:events';
import fsPromises from 'node:fs/promises';
import {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  symlink,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { createRequire, syncBuiltinESMExports } from 'node:module';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { Duplex, Readable } from 'node:stream';
import test from 'node:test';
import {
  createGateway,
  readAsset,
  socketIdentity,
} from '../../scripts/instagram_testers/runtime/vps/gateway.mjs';
import {
  configFromEnv,
  createAuth,
  MAX_NONCES,
  MAX_SESSIONS,
  readPrivateJson,
} from '../../scripts/instagram_testers/runtime/vps/gateway-auth.mjs';

const require = createRequire(
  new URL(
    '../../scripts/instagram_testers/runtime/vps/gateway.mjs',
    import.meta.url
  )
);
const { SignJWT } = await import(require.resolve('jose'));
const WebSocket = require('ws');
const KEY = Buffer.alloc(32, 0x42); // Synthetic key, never environment credentials.
const nativeLstat = fsPromises.lstat;

class MemorySocket extends Duplex {
  // eslint-disable-next-line no-underscore-dangle, class-methods-use-this -- Duplex requires this hook name; reads are pushed by the peer.
  _read() {}

  // eslint-disable-next-line no-underscore-dangle -- Duplex requires this hook name for the in-memory transport.
  _write(data, _, callback) {
    this.peer.push(Buffer.from(data));
    callback();
  }

  // eslint-disable-next-line no-underscore-dangle -- Duplex requires this hook name for the in-memory transport.
  _final(callback) {
    this.peer.push(null);
    callback();
  }

  // eslint-disable-next-line no-underscore-dangle -- Duplex requires this hook name for the in-memory transport.
  _destroy(error, callback) {
    if (!this.peer.destroyed) this.peer.destroy();
    callback(error);
  }

  setTimeout() {
    return this;
  }

  setNoDelay() {
    return this;
  }
}

async function fixture(t, { marker = true, wire = false } = {}) {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), 'ig-gateway-test-'))
  );
  const stateDir = path.join(root, 'gateway');
  await mkdir(stateDir, { mode: 0o700 });
  const config = {
    stack: 'hub2you',
    base: new URL('https://gateway.example/hub2you/'),
    issuer: 'https://rails.example',
    key: KEY,
    gatewayUid: 2101,
    gatewayGid: 2201,
    browserUid: 2102,
    viewerGid: 2202,
    runtimeDir: path.join(root, 'runtime'),
    stateDir,
    requestFile: path.join(root, 'runtime/browser-request.json'),
    vncSocket: path.join(root, 'runtime/vnc.sock'),
    port: 0,
  };
  await mkdir(config.runtimeDir, { mode: 0o710 });
  await chmod(config.runtimeDir, 0o710);
  const metadata = new Map();
  const projectStat = (filename, info) => {
    const privateState =
      filename === stateDir || filename.startsWith(`${stateDir}/`);
    info.uid = privateState ? 2101 : 2102;
    info.gid = privateState ? 2201 : 2202;
    Object.assign(info, metadata.get(filename));
    return info;
  };
  const fs = {
    ...fsPromises,
    lstat: async filename =>
      projectStat(filename, await fsPromises.lstat(filename)),
    open: async (...args) => {
      const handle = await fsPromises.open(...args);
      return new Proxy(handle, {
        get(target, key) {
          if (key === 'stat')
            return async () => projectStat(args[0], await target.stat());
          const value = target[key];
          return typeof value === 'function' ? value.bind(target) : value;
        },
      });
    },
  };
  let time = 1900000000;
  const now = () => time;
  const requestId = randomUUID();
  const deadline = time + 3600;
  const markerValue = { request_id: requestId, deadline };
  const setMarker = async value => {
    await writeFile(config.requestFile, JSON.stringify(value), { mode: 0o640 });
    await chmod(config.requestFile, 0o640);
  };
  if (marker) await setMarker(markerValue);
  const claims = {
    iss: config.issuer,
    aud: 'instagram-operator-browser:hub2you',
    sub: '17',
    jti: randomUUID(),
    iat: time,
    exp: time + 60,
    request_id: requestId,
    deadline,
    stack: config.stack,
  };
  const sign = (
    changes = {},
    header = { alg: 'HS256', typ: 'JWT' },
    key = KEY
  ) =>
    new SignJWT({ ...claims, ...changes }).setProtectedHeader(header).sign(key);
  const virtualSockets = new Set();
  const clients = new Set();
  t.mock.method(fsPromises, 'lstat', async (...args) => {
    const info = await nativeLstat(...args);
    if (virtualSockets.has(args[0]) && !info.isSymbolicLink()) {
      info.isSocket = () => true;
      info.isFile = () => false;
    }
    return info;
  });
  t.mock.method(net, 'createConnection', options => {
    assert.deepEqual(options, { path: config.vncSocket });
    const stream = new Duplex({
      read() {},
      write(data, _, callback) {
        this.push(data);
        callback();
      },
    });
    clients.add(stream);
    stream.on('close', () => clients.delete(stream));
    setImmediate(() => {
      stream.emit('connect');
      stream.push(Buffer.from('synthetic-vnc'));
    });
    return stream;
  });
  if (!wire)
    t.mock.method(
      WebSocket.WebSocketServer.prototype,
      'handleUpgrade',
      (request, socket, head, callback) => {
        const client = socket.client;
        const serverWs = new EventEmitter();
        serverWs.readyState = WebSocket.OPEN;
        serverWs.bufferedAmount = 0;
        serverWs.send = (data, options, done) => {
          queueMicrotask(() =>
            client.emit('message', Buffer.from(data), options.binary)
          );
          done();
        };
        serverWs.terminate = () => {
          if (serverWs.readyState === WebSocket.CLOSED) return;
          serverWs.readyState = WebSocket.CLOSED;
          queueMicrotask(() => {
            serverWs.emit('close');
            client.emit('close');
          });
        };
        client.send = data =>
          serverWs.emit('message', data, typeof data !== 'string');
        client.terminate = serverWs.terminate;
        client.close = client.terminate;
        callback(serverWs);
        queueMicrotask(() => client.emit('open'));
      }
    );
  syncBuiltinESMExports();
  const gateway = await createGateway(config, { now, pollMs: 10, fs });
  const headers = { host: config.base.host, 'x-forwarded-proto': 'https' };
  function incoming(target, method, extra, body = '', peer = '127.0.0.1') {
    const req = Readable.from([Buffer.from(body)]);
    req.url = target;
    req.method = method;
    req.headers = { ...headers };
    // eslint-disable-next-line no-restricted-syntax -- Node supports native iteration; preserve ordered side effects.
    for (const [key, value] of Object.entries(extra))
      req.headers[key.toLowerCase()] = value;
    req.headersDistinct = Object.fromEntries(
      Object.entries(req.headers).map(([key, value]) => [
        key,
        Array.isArray(value) ? value : [value],
      ])
    );
    req.socket = { remoteAddress: peer };
    return req;
  }
  const request = (target, { method = 'GET', extra = {}, body, peer } = {}) =>
    new Promise(resolve => {
      const req = incoming(target, method, extra, body, peer);
      const response = {
        statusCode: 200,
        headers: {},
        setHeader(key, value) {
          this.headers[key.toLowerCase()] =
            key.toLowerCase() === 'set-cookie' ? [value] : value;
        },
        end(value) {
          resolve({
            status: this.statusCode,
            headers: this.headers,
            body: value.toString(),
          });
        },
      };
      gateway.server.emit('request', req, response);
    });
  const grant = async (ticket, extra, body) => {
    const value = ticket ?? (await sign());
    return request('/hub2you/grant', {
      method: 'POST',
      extra: {
        Origin: config.issuer,
        'Content-Type': 'application/x-www-form-urlencoded',
        ...extra,
      },
      body: body ?? new URLSearchParams({ ticket: value }).toString(),
    });
  };
  const cookie = response => response.headers['set-cookie'][0].split(';')[0];
  const ws = (sessionCookie, extra = {}, target = '/hub2you/ws') => {
    if (wire) {
      const client = new WebSocket(null, undefined, { autoPong: true });
      // eslint-disable-next-line no-underscore-dangle -- ws internals select client framing without opening a network socket.
      client._isServer = false;
      // eslint-disable-next-line no-underscore-dangle -- ws requires initialized buffering state for the in-memory client.
      client._bufferedAmount = 0;
      const clientSocket = new MemorySocket();
      const serverSocket = new MemorySocket();
      clientSocket.peer = serverSocket;
      serverSocket.peer = clientSocket;
      clientSocket.on('error', () => {});
      serverSocket.on('error', () => {});
      client.on('error', () => {});
      const terminate = client.terminate.bind(client);
      client.terminate = () =>
        client.readyState === WebSocket.CONNECTING
          ? clientSocket.destroy()
          : terminate();
      let handshakeHeaders = Buffer.alloc(0);
      const handshake = chunk => {
        handshakeHeaders = Buffer.concat([handshakeHeaders, chunk]);
        const boundary = handshakeHeaders.indexOf('\r\n\r\n');
        if (boundary < 0) return;
        clientSocket.removeListener('data', handshake);
        const statusCode = Number(handshakeHeaders.toString().split(' ')[1]);
        if (statusCode !== 101) {
          client.emit('unexpected-response', null, { statusCode, resume() {} });
          return;
        }
        client.setSocket(
          clientSocket,
          handshakeHeaders.subarray(boundary + 4),
          {
            maxPayload: 65536,
          }
        );
      };
      clientSocket.on('data', handshake);
      const upgradeRequest = incoming(target, 'GET', {
        Origin: config.base.origin,
        Cookie: sessionCookie,
        Upgrade: 'websocket',
        Connection: 'Upgrade',
        'Sec-WebSocket-Version': '13',
        'Sec-WebSocket-Key': Buffer.alloc(16, 0x21).toString('base64'),
        ...extra,
      });
      queueMicrotask(() =>
        gateway.server.emit(
          'upgrade',
          upgradeRequest,
          serverSocket,
          Buffer.alloc(0)
        )
      );
      return client;
    }
    const client = new EventEmitter();
    client.terminate = () => {};
    const socket = new EventEmitter();
    socket.client = client;
    socket.destroy = () => {
      socket.destroyed = true;
      client.emit('close');
    };
    socket.end = data => {
      client.emit('unexpected-response', null, {
        statusCode: Number(data.split(' ')[1]),
        resume() {},
      });
      socket.destroy();
    };
    queueMicrotask(() =>
      gateway.server.emit(
        'upgrade',
        incoming(target, 'GET', {
          Origin: config.base.origin,
          Cookie: sessionCookie,
          ...extra,
        }),
        socket,
        Buffer.alloc(0)
      )
    );
    return client;
  };
  async function vnc() {
    await writeFile(config.vncSocket, '', { mode: 0o660 });
    await chmod(config.vncSocket, 0o660);
    virtualSockets.add(config.vncSocket);
    return { clients };
  }
  t.after(async () => {
    await gateway.close();
    // eslint-disable-next-line no-restricted-syntax -- Node supports native iteration; preserve ordered side effects.
    for (const client of clients) client.destroy();
    t.mock.restoreAll();
    syncBuiltinESMExports();
    await rm(root, { recursive: true, force: true });
  });
  return {
    root,
    fs,
    metadata,
    config,
    claims,
    sign,
    gateway,
    request,
    grant,
    cookie,
    ws,
    vnc,
    now,
    setMarker,
    markerValue,
    advance: seconds => {
      time += seconds;
    },
  };
}

async function deniedWs(ws) {
  return new Promise((resolve, reject) => {
    ws.on('error', () => {});
    ws.on('open', () => {
      ws.terminate();
      reject(new Error('Unexpected WebSocket admission'));
    });
    ws.on('unexpected-response', (_, response) => {
      response.resume();
      ws.terminate();
      resolve(response.statusCode);
    });
  });
}

test('configuration requires stack-specific paths, isolated identities and canonical HTTPS/key', async () => {
  const env = {
    INSTAGRAM_TESTER_RUNTIME_STACK: 'hub2you',
    INSTAGRAM_TESTER_OPERATOR_BROWSER_URL: 'https://gateway.example/hub2you/',
    INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY: '42'.repeat(32),
    INSTAGRAM_TESTER_OPERATOR_ISSUER: 'https://rails.example',
    INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE:
      '/run/instagram-hub2you/browser-request.json',
    INSTAGRAM_TESTER_VNC_SOCKET: '/run/instagram-hub2you/vnc.sock',
    INSTAGRAM_TESTER_GATEWAY_PORT: '18441',
    INSTAGRAM_TESTER_GATEWAY_STATE_DIR:
      '/var/lib/instagram-gateway-hub2you/gateway',
  };
  const overrides = new Map();
  const options = {
    uid: 2101,
    gid: 2201,
    groups: [2201, 2202],
    fs: {
      lstat: async filename => {
        const gateway = filename.startsWith('/var/lib/instagram-gateway-');
        const browser = filename.startsWith('/var/lib/instagram-') && !gateway;
        const runtime = filename.startsWith('/run/instagram-');
        let uid = 0;
        let gid = 0;
        let mode = 0o755;
        if (gateway) {
          uid = 2101;
          gid = 2201;
          mode = 0o700;
        }
        if (browser) {
          uid = 2102;
          gid = 2203;
          mode = 0o700;
        }
        if (runtime) {
          uid = 2102;
          gid = 2202;
          mode = 0o710;
        }
        return {
          uid,
          gid,
          mode,
          isDirectory: () => true,
          ...overrides.get(filename),
        };
      },
    },
  };
  const parsed = await configFromEnv(env, options);
  assert.deepEqual(parsed.key, KEY);
  assert.equal(parsed.browserUid, 2102);
  assert.equal(parsed.viewerGid, 2202);
  assert.equal(parsed.gatewayUid, 2101);
  // eslint-disable-next-line no-restricted-syntax -- Node supports native iteration; preserve ordered side effects.
  for (const [key, value] of [
    ['INSTAGRAM_TESTER_RUNTIME_STACK', 'other'],
    [
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL',
      'http://gateway.example/hub2you/',
    ],
    [
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL',
      'https://user@gateway.example/hub2you/',
    ],
    [
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL',
      'https://gateway.example/hub2you/?ticket=x',
    ],
    [
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL',
      'https://gateway.example/autonomia/',
    ],
    ['INSTAGRAM_TESTER_OPERATOR_ISSUER', 'https://rails.example/'],
    ['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY', 'g'.repeat(64)],
    ['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY', '42'.repeat(31)],
    ['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY', 'a'.repeat(65)],
    [
      'INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE',
      '/run/instagram-autonomia/browser-request.json',
    ],
    ['INSTAGRAM_TESTER_VNC_SOCKET', '127.0.0.1:5900'],
    ['INSTAGRAM_TESTER_GATEWAY_PORT', '18442'],
    ['INSTAGRAM_TESTER_GATEWAY_STATE_DIR', '/tmp/shared'],
  ]) {
    // eslint-disable-next-line no-await-in-loop -- Invalid environments are checked one at a time.
    await assert.rejects(configFromEnv({ ...env, [key]: value }, options), key);
  }
  const autonomia = Object.fromEntries(
    Object.entries(env).map(([key, value]) => [
      key,
      value.replaceAll('hub2you', 'autonomia').replaceAll('18441', '18442'),
    ])
  );
  assert.equal((await configFromEnv(autonomia, options)).stack, 'autonomia');
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Test each configuration failure independently. */
  for (const changes of [
    { uid: 2102 },
    { uid: 0 },
    { gid: 2202 },
    { gid: 2203 },
    { groups: [2201] },
    { groups: [2201, 2202, 2203] },
  ])
    await assert.rejects(configFromEnv(env, { ...options, ...changes }));
  for (const [filename, changes] of [
    ['/var/lib', { uid: 2102 }],
    ['/run', { mode: 0o777 }],
    ['/var', { isDirectory: () => false }],
    ['/var/lib/instagram-hub2you', { uid: 2101 }],
    ['/var/lib/instagram-hub2you', { mode: 0o755 }],
    ['/var/lib/instagram-gateway-hub2you', { uid: 2102 }],
    ['/var/lib/instagram-gateway-hub2you', { gid: 2202 }],
    ['/var/lib/instagram-gateway-hub2you/gateway', { mode: 0o710 }],
    ['/run/instagram-hub2you', { uid: 2101 }],
    ['/run/instagram-hub2you', { gid: 2203 }],
    ['/run/instagram-hub2you', { mode: 0o700 }],
    ['/run/instagram-hub2you', { isDirectory: () => false }],
  ]) {
    overrides.set(filename, changes);
    await assert.rejects(configFromEnv(env, options));
    overrides.clear();
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
});

test('valid POST returns an opaque Strict cookie and all resources require authentication', async t => {
  const f = await fixture(t);
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const resource of [
    'console/',
    'status',
    'assets/console.js',
    'assets/novnc/core/rfb.js',
    'ws',
  ]) {
    assert.equal(
      (await f.request(`/hub2you/${resource}`)).status,
      401,
      resource
    );
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  const ticket = await f.sign();
  const response = await f.grant(ticket);
  assert.equal(response.status, 200);
  assert.ok(
    response.headers['set-cookie'][0].startsWith('__Secure-ig-hub2you=')
  );
  // eslint-disable-next-line no-restricted-syntax -- Node supports native iteration; preserve ordered side effects.
  for (const attribute of [
    'Secure',
    'HttpOnly',
    'SameSite=Strict',
    'Path=/hub2you/',
    'Max-Age=900',
  ]) {
    assert.ok(response.headers['set-cookie'][0].includes(attribute));
  }
  assert.ok(response.body.includes('./assets/enter.js'));
  assert.equal(response.body.includes(ticket), false);
  assert.equal(response.headers['cache-control'], 'no-store');
  assert.equal(response.headers['referrer-policy'], 'no-referrer');
  const extra = { Cookie: f.cookie(response), Origin: f.config.base.origin };
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const resource of [
    'console/',
    'status',
    'assets/console.js',
    'assets/enter.js',
    'assets/novnc/core/rfb.js',
    'assets/novnc/vendor/pako/lib/zlib/inflate.js',
  ]) {
    const asset = await f.request(`/hub2you/${resource}`, { extra });
    assert.equal(asset.status, 200, resource);
    assert.equal(asset.headers['cache-control'], 'no-store');
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  const nonces = await readdir(f.config.stateDir);
  assert.equal(nonces.length, 1);
  const filename = path.join(f.config.stateDir, nonces[0]);
  // eslint-disable-next-line no-bitwise -- POSIX permission bits require masking.
  assert.equal((await lstat(filename)).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(await readFile(filename)), {
    stack: 'hub2you',
    jti: f.claims.jti,
    exp: f.claims.exp,
  });
});

test('boundary denies foreign/missing grant Origin, forged Host, HTTP forwarding, bearer and ambiguous form', async t => {
  const f = await fixture(t);
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const extra of [
    { Origin: 'https://rails.example.evil' },
    { Origin: '' },
    { Origin: 'null' },
    { Origin: undefined },
    { Host: 'evil.example', 'X-Forwarded-Host': 'gateway.example' },
    { 'X-Forwarded-Proto': 'http' },
    { Authorization: 'Bearer synthetic' },
  ]) {
    if (extra.Origin === undefined && Object.hasOwn(extra, 'Origin')) {
      const response = await f.request('/hub2you/grant', {
        method: 'POST',
        extra: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'ticket=x',
      });
      assert.equal(response.status, 403);
    } else assert.equal((await f.grant(await f.sign(), extra)).status, 403);
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  const ticket = await f.sign();
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const body of [
    `ticket=${ticket}&ticket=${ticket}`,
    `ticket=${ticket}&extra=x`,
    'ticket=',
    'other=x',
  ]) {
    assert.equal((await f.grant(ticket, {}, body)).status, 403);
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  assert.equal(
    (await f.grant(ticket, { 'Content-Type': 'application/json' }, '{}'))
      .status,
    415
  );
  assert.equal(
    (await f.grant(ticket, {}, `ticket=${'x'.repeat(4096)}`)).status,
    413
  );
  assert.equal(
    (await f.grant(ticket, { 'Content-Length': '4097' }, '')).status,
    413
  );
  const accepted = await f.grant(ticket);
  const extra = { Cookie: f.cookie(accepted) };
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const target of [
    '/hub2you/status?ticket=x',
    '/autonomia/status',
    '/hub2you/assets/../console.js',
    '/hub2you/assets/%2e%2e/console.js',
    '/hub2you/assets/novnc/package.json',
    '/hub2you/assets/novnc/docs/API.md',
  ]) {
    assert.notEqual((await f.request(target, { extra })).status, 200, target);
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  assert.equal(
    (
      await f.request('/hub2you/status', {
        extra: { ...extra, Origin: 'https://evil.example' },
      })
    ).status,
    403
  );
  assert.equal(
    (
      await f.request('/hub2you/status', {
        extra: {
          ...extra,
          Origin: [f.config.base.origin, f.config.base.origin],
        },
      })
    ).status,
    403
  );
  assert.equal(
    (
      await f.request('/hub2you/status', {
        extra: { ...extra, 'Sec-Fetch-Site': 'cross-site' },
      })
    ).status,
    403
  );
  assert.equal(
    (await f.request('/hub2you/status', { extra, peer: '192.0.2.1' })).status,
    403
  );
  assert.equal(
    (
      await f.request('/hub2you/status', {
        extra: { ...extra, Cookie: `${extra.Cookie}; ${extra.Cookie}` },
      })
    ).status,
    401
  );
});

test('strict JWT signature, algorithm, header, claims, types, lifetime and stack', async t => {
  const f = await fixture(t);
  const cases = [
    { iss: 'https://evil.example' },
    { aud: ['instagram-operator-browser:hub2you'] },
    { aud: 'instagram-operator-browser:autonomia' },
    { sub: 17 },
    { sub: '0' },
    { sub: '1x' },
    { jti: 'not-a-uuid' },
    { request_id: 'not-a-uuid' },
    { stack: 'autonomia' },
    { extra: 'claim' },
    { iat: f.now() + 1 },
    { iat: f.now() + 0.5 },
    { exp: f.now() + 61 },
    { exp: String(f.now() + 60) },
    { iat: f.now() - 60, exp: f.now() },
    { deadline: f.now() },
    { deadline: f.now() + 3601 },
    { deadline: String(f.claims.deadline) },
    { deadline: f.claims.deadline - 1 },
  ];
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const changes of cases)
    assert.notEqual(
      (await f.grant(await f.sign(changes))).status,
      200,
      JSON.stringify(changes)
    );
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const header of [
    { alg: 'HS384', typ: 'JWT' },
    { alg: 'HS256', typ: 'jwt' },
    { alg: 'HS256' },
    { alg: 'HS256', typ: 'JWT', kid: 'x' },
  ]) {
    assert.notEqual((await f.grant(await f.sign({}, header))).status, 200);
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  assert.equal(
    (await f.grant(await f.sign({}, undefined, Buffer.alloc(32, 0x43)))).status,
    403
  );
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const claim of Object.keys(f.claims)) {
    const missing = { ...f.claims };
    delete missing[claim];
    const ticket = await new SignJWT(missing)
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .sign(KEY);
    assert.notEqual((await f.grant(ticket)).status, 200, claim);
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  assert.deepEqual(await readdir(f.config.stateDir), []);
});

test('nonce admission is exclusive across simultaneous grants and gateway restart', async t => {
  const f = await fixture(t);
  const ticket = await f.sign();
  const responses = await Promise.all([f.grant(ticket), f.grant(ticket)]);
  assert.deepEqual(
    responses.map(response => response.status).sort(),
    [200, 403]
  );
  const accepted = responses.find(response => response.status === 200);
  await f.gateway.close();
  const restarted = await createAuth(f.config, f.now, f.fs);
  await assert.rejects(restarted.grant(ticket));
  assert.throws(() =>
    restarted.sessionId({ cookie: '__Secure-ig-autonomia=synthetic' })
  );
  await assert.rejects(restarted.validate(f.cookie(accepted).split('=')[1]));
});

test('nonce cleanup preserves unrelated, unsafe and foreign entries and requires private state identity', async t => {
  const f = await fixture(t);
  const auth = await createAuth(f.config, f.now, f.fs);
  const expired = randomUUID();
  const foreign = randomUUID();
  const linked = randomUUID();
  await writeFile(
    path.join(f.config.stateDir, `nonce-${expired}.json`),
    JSON.stringify({ jti: expired, stack: 'hub2you', exp: f.now() }),
    { mode: 0o600 }
  );
  await writeFile(
    path.join(f.config.stateDir, `nonce-${foreign}.json`),
    JSON.stringify({ jti: foreign, stack: 'autonomia', exp: f.now() }),
    { mode: 0o600 }
  );
  const unrelated = path.join(f.root, 'unrelated');
  await writeFile(unrelated, 'keep');
  await writeFile(path.join(f.config.stateDir, 'other.json'), 'keep');
  await symlink(
    unrelated,
    path.join(f.config.stateDir, `nonce-${linked}.json`)
  );
  assert.equal(await auth.pruneNonces(), 2);
  assert.equal(await readFile(unrelated, 'utf8'), 'keep');
  assert.equal(
    await readFile(path.join(f.config.stateDir, 'other.json'), 'utf8'),
    'keep'
  );
  await chmod(f.config.stateDir, 0o755);
  await assert.rejects(auth.grant(await f.sign()));
  await assert.rejects(createAuth(f.config, undefined, f.fs));
  await chmod(f.config.stateDir, 0o700);
  await assert.rejects(
    createAuth(
      { ...f.config, gatewayUid: f.config.gatewayUid + 1 },
      undefined,
      f.fs
    )
  );
  const original = `${f.config.stateDir}-original`;
  await rename(f.config.stateDir, original);
  await mkdir(f.config.stateDir, { mode: 0o700 });
  await assert.rejects(auth.grant(await f.sign()));
  assert.deepEqual(await readdir(f.config.stateDir), []);
});

test('sessions and nonces have fixed capacity and expired sessions release capacity', async t => {
  const f = await fixture(t);
  const auth = await createAuth(f.config, f.now, f.fs);
  /* eslint-disable no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (let index = 0; index < MAX_SESSIONS; index += 1)
    await auth.grant(await f.sign({ jti: randomUUID() }));
  /* eslint-enable no-await-in-loop */
  await assert.rejects(
    auth.grant(await f.sign({ jti: randomUUID() })),
    error => error.status === 503
  );
  f.advance(901);
  await auth.grant(
    await f.sign({ jti: randomUUID(), iat: f.now(), exp: f.now() + 60 })
  );
  assert.equal(auth.sessions.size, 1);
  assert.equal((await readdir(f.config.stateDir)).length, 1);
  await Promise.all(
    Array.from({ length: MAX_NONCES - 1 }, async () => {
      const jti = randomUUID();
      await writeFile(
        path.join(f.config.stateDir, `nonce-${jti}.json`),
        JSON.stringify({ stack: 'hub2you', jti, exp: f.now() + 60 }),
        { mode: 0o600 }
      );
    })
  );
  await assert.rejects(
    auth.grant(
      await f.sign({ jti: randomUUID(), iat: f.now(), exp: f.now() + 60 })
    ),
    error => error.status === 503
  );
});

test('session waits for marker, binds its identity and expires at the earlier deadline', async t => {
  const f = await fixture(t, { marker: false });
  const granted = await f.grant();
  const extra = { Cookie: f.cookie(granted) };
  assert.deepEqual(
    JSON.parse((await f.request('/hub2you/status', { extra })).body),
    { state: 'waiting' }
  );
  assert.equal(await deniedWs(f.ws(extra.Cookie)), 409);
  await f.setMarker(f.markerValue);
  assert.deepEqual(
    JSON.parse((await f.request('/hub2you/status', { extra })).body),
    { state: 'ready' }
  );
  await f.setMarker({ ...f.markerValue, request_id: randomUUID() });
  assert.equal((await f.request('/hub2you/status', { extra })).status, 401);
  await f.setMarker(f.markerValue);
  assert.equal((await f.request('/hub2you/status', { extra })).status, 401);
  f.advance(3500);
  const fresh = await f.grant(
    await f.sign({ jti: randomUUID(), iat: f.now(), exp: f.now() + 60 })
  );
  assert.ok(fresh.headers['set-cookie'][0].includes('Max-Age=100'));
  f.advance(100);
  assert.equal(
    (await f.request('/hub2you/status', { extra: { Cookie: f.cookie(fresh) } }))
      .status,
    401
  );
});

test('WebSocket bridges only AF_UNIX binary data, excludes concurrent connections and permits session reconnection', async t => {
  const f = await fixture(t);
  await f.vnc();
  const cookie = f.cookie(await f.grant());
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const [extra, target] of [
    [{ Origin: 'https://evil.example' }, '/hub2you/ws'],
    [{ Origin: '' }, '/hub2you/ws'],
    [{ Host: 'evil.example' }, '/hub2you/ws'],
    [{}, '/hub2you/ws?ticket=x'],
    [{ Cookie: '' }, '/hub2you/ws'],
  ])
    assert.notEqual(await deniedWs(f.ws(cookie, extra, target)), 101);
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  const ws = f.ws(cookie);
  const greeting = once(ws, 'message');
  await once(ws, 'open');
  assert.equal((await greeting)[0].toString(), 'synthetic-vnc');
  assert.equal(await deniedWs(f.ws(cookie)), 409);
  const reply = once(ws, 'message');
  ws.send(Buffer.from('synthetic-keys'));
  assert.equal((await reply)[0].toString(), 'synthetic-keys');
  ws.close();
  await once(ws, 'close');
  const reconnected = f.ws(cookie);
  const nextGreeting = once(reconnected, 'message');
  await once(reconnected, 'open');
  await nextGreeting;
  const closed = once(reconnected, 'close');
  await unlink(f.config.requestFile);
  await closed;
  assert.equal(
    (await f.request('/hub2you/status', { extra: { Cookie: cookie } })).status,
    401
  );
});

test('open websocket stops on deadline, session expiry and changed marker', async t => {
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const reason of ['deadline', 'session', 'changed']) {
    await t.test(reason, async child => {
      const f = await fixture(child);
      await f.vnc();
      const ws = f.ws(f.cookie(await f.grant()));
      const greeting = once(ws, 'message');
      await once(ws, 'open');
      await greeting;
      const closed = once(ws, 'close');
      if (reason === 'changed')
        await f.setMarker({
          ...f.markerValue,
          deadline: f.markerValue.deadline - 1,
        });
      else f.advance(reason === 'deadline' ? 3600 : 900);
      await closed;
    });
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
});

test('VNC endpoint requires browser UID, viewer GID, mode 0660 and trusted runtime', async t => {
  const f = await fixture(t);
  const cookie = f.cookie(await f.grant());
  await writeFile(f.config.vncSocket, 'not a socket', { mode: 0o600 });
  assert.equal(await deniedWs(f.ws(cookie)), 403);
  await unlink(f.config.vncSocket);
  const mock = await f.vnc();
  await chmod(f.config.vncSocket, 0o600);
  assert.equal(await deniedWs(f.ws(cookie)), 403);
  assert.equal(mock.clients.size, 0);
  await chmod(f.config.vncSocket, 0o660);
  await assert.rejects(
    socketIdentity({ ...f.config, browserUid: f.config.browserUid + 1 }, f.fs)
  );
  await assert.rejects(
    socketIdentity({ ...f.config, viewerGid: f.config.viewerGid + 1 }, f.fs)
  );
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Check the endpoint's metadata, separately from its parent. */
  for (const changes of [{ uid: 2101 }, { gid: 2201 }, { mode: 0o2660 }]) {
    f.metadata.set(f.config.vncSocket, changes);
    await assert.rejects(socketIdentity(f.config, f.fs));
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  f.metadata.clear();
  const realSocket = f.config.vncSocket;
  f.config.vncSocket = path.join(f.config.runtimeDir, 'linked.sock');
  await symlink(realSocket, f.config.vncSocket);
  assert.equal(await deniedWs(f.ws(cookie)), 403);
});

test('own assets refuse symlinks without serving files outside the fixed asset root', async t => {
  const f = await fixture(t);
  const cookie = f.cookie(await f.grant());
  await writeFile(path.join(f.root, 'outside.js'), 'must not be served');
  const assets = path.join(f.root, 'assets');
  await mkdir(assets);
  await writeFile(path.join(assets, 'safe.js'), 'safe');
  await symlink(
    path.join(f.root, 'outside.js'),
    path.join(assets, 'linked.js')
  );
  await symlink(f.root, path.join(assets, 'linked-dir'));
  assert.equal((await readAsset(assets, 'safe.js')).toString(), 'safe');
  await assert.rejects(readAsset(assets, 'linked.js'));
  await assert.rejects(readAsset(assets, 'linked-dir/outside.js'));
  await assert.rejects(readAsset(assets, '../outside.js'));
  assert.equal(
    (
      await f.request('/hub2you/assets/not-allowed.js', {
        extra: { Cookie: cookie },
      })
    ).status,
    404
  );
  assert.equal(
    (
      await f.request('/hub2you/assets/novnc/core/../../../gateway-auth.mjs', {
        extra: { Cookie: cookie },
      })
    ).status,
    403
  );
});

test('real ws handshake and masked frames work over in-memory sockets; text and oversized frames are closed', async t => {
  const f = await fixture(t, { wire: true });
  await f.vnc();
  const cookie = f.cookie(await f.grant());
  assert.equal(
    await deniedWs(f.ws(cookie, { Origin: 'https://evil.example' })),
    403
  );
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Cases share fixture state and must finish in order. */
  for (const payload of [
    Buffer.from('binary-keys'),
    'text-is-not-vnc',
    Buffer.alloc(65537),
  ]) {
    const ws = f.ws(cookie);
    const greeting = once(ws, 'message');
    await once(ws, 'open');
    assert.equal((await greeting)[0].toString(), 'synthetic-vnc');
    if (Buffer.isBuffer(payload) && payload.length < 65536) {
      const echoed = once(ws, 'message');
      ws.send(payload);
      assert.deepEqual((await echoed)[0], payload);
      ws.close();
      await once(ws, 'close');
    } else {
      const closed = new Promise(resolve => {
        ws.once('close', resolve);
      });
      ws.send(payload);
      await closed;
    }
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
});

test('same UID and shared primary group are refused even for direct auth fixtures', async t => {
  const f = await fixture(t);
  await assert.rejects(
    createAuth({ ...f.config, browserUid: f.config.gatewayUid }, f.now, f.fs)
  );
  await assert.rejects(
    createAuth({ ...f.config, viewerGid: f.config.gatewayGid }, f.now, f.fs)
  );
});

test('marker and nonce cannot substitute each other by owner, group or mode', async t => {
  const f = await fixture(t);
  const nonce = path.join(f.config.stateDir, `nonce-${randomUUID()}.json`);
  await writeFile(nonce, '{}', { mode: 0o600 });
  const nonceOwner = { uid: 2101, gid: 2201, mode: 0o600 };
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Exercise each ownership/mode failure independently. */
  for (const changes of [
    { uid: 2101 },
    { gid: 2201 },
    { mode: 0o600 },
    { mode: 0o2640 },
    { nlink: 3 },
  ]) {
    f.metadata.set(f.config.requestFile, changes);
    assert.equal(
      (await f.grant(await f.sign({ jti: randomUUID() }))).status,
      401
    );
  }
  f.metadata.clear();
  for (const changes of [
    { uid: 2102 },
    { gid: 2202 },
    { mode: 0o640 },
    { nlink: 2 },
  ]) {
    f.metadata.set(nonce, changes);
    await assert.rejects(readPrivateJson(nonce, nonceOwner, 1024, f.fs));
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
  f.metadata.clear();
  assert.equal((await f.grant()).status, 200);
});

test('JSON reader rechecks inode, owner, group and mode on the opened descriptor and after reading', async t => {
  const f = await fixture(t);
  const owner = { uid: 2102, gid: 2202, mode: 0o640, marker: true };
  /* eslint-disable no-restricted-syntax, no-await-in-loop -- Test changes at each descriptor check independently. */
  for (const afterRead of [false, true]) {
    for (const changes of [
      { uid: 2101 },
      { gid: 2201 },
      { mode: 0o600 },
      { ino: -1 },
      { nlink: 3 },
    ]) {
      const fs = {
        ...f.fs,
        open: async (...args) => {
          const handle = await f.fs.open(...args);
          let calls = 0;
          return new Proxy(handle, {
            get(target, key) {
              if (key === 'stat')
                return async () => {
                  const info = await target.stat();
                  calls += 1;
                  return calls === (afterRead ? 2 : 1)
                    ? Object.assign(info, changes)
                    : info;
                };
              const value = target[key];
              return typeof value === 'function' ? value.bind(target) : value;
            },
          });
        },
      };
      await assert.rejects(
        readPrivateJson(f.config.requestFile, owner, 1024, fs)
      );
    }
  }
  /* eslint-enable no-restricted-syntax, no-await-in-loop */
});

test('runtime inode and permissions stay bound throughout a session', async t => {
  const f = await fixture(t, { marker: false });
  const auth = await createAuth(f.config, f.now, f.fs);
  const { id } = await auth.grant(await f.sign());
  f.metadata.set(f.config.runtimeDir, { mode: 0o700 });
  await assert.rejects(auth.validate(id));
  f.metadata.clear();
  const next = await auth.grant(await f.sign({ jti: randomUUID() }));
  await rename(f.config.runtimeDir, `${f.config.runtimeDir}-old`);
  await mkdir(f.config.runtimeDir);
  await chmod(f.config.runtimeDir, 0o710);
  await assert.rejects(auth.validate(next.id));
});

test('missing runtime never becomes the permitted waiting-for-marker state', async t => {
  const f = await fixture(t, { marker: false });
  const auth = await createAuth(f.config, f.now, f.fs);
  const { id } = await auth.grant(await f.sign());
  await rm(f.config.runtimeDir, { recursive: true });
  await assert.rejects(auth.validate(id));
  await assert.rejects(auth.grant(await f.sign({ jti: randomUUID() })));
});

test('nonce cannot be replayed when filesystem work crosses ticket expiry', async t => {
  const f = await fixture(t);
  const auth = await createAuth(f.config, f.now, f.fs);
  const ticket = await f.sign();
  await auth.grant(ticket);
  f.advance(59);
  const read = f.fs.readdir;
  t.mock.method(f.fs, 'readdir', async directory => {
    f.advance(1);
    return read(directory);
  });
  await assert.rejects(auth.grant(ticket));
  assert.equal(auth.sessions.size, 1);
  assert.ok(
    (await readdir(f.config.stateDir)).includes(`nonce-${f.claims.jti}.json`)
  );
});

test('new ticket expiring during admission never produces a session', async t => {
  const f = await fixture(t);
  const auth = await createAuth(f.config, f.now, f.fs);
  const ticket = await f.sign();
  const read = f.fs.readdir;
  t.mock.method(f.fs, 'readdir', async directory => {
    f.advance(60);
    return read(directory);
  });
  await assert.rejects(auth.grant(ticket));
  assert.equal(auth.sessions.size, 0);
});
