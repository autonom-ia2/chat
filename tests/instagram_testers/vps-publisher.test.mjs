/* eslint-disable no-await-in-loop, no-restricted-syntax -- Offline lifecycle cases drive ordered synthetic streams and clocks. */
/* eslint-disable max-classes-per-file -- Independent socket and clock mocks avoid any real I/O. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter, getEventListeners } from 'node:events';
import { readFile } from 'node:fs/promises';
import { PassThrough } from 'node:stream';
import {
  createPublisherBroker,
  publisherEnvelope,
} from '../../scripts/instagram_testers/runtime/vps/publisher-broker.mjs';
import {
  runPublisherClient,
  main as clientMain,
} from '../../scripts/instagram_testers/runtime/vps/publisher-client.mjs';
import {
  MAX_INPUT_BYTES,
  MAX_OUTPUT_BYTES,
  MAX_CONNECTIONS,
  REQUEST_TIMEOUT_MS,
  publisherSocketConfig,
  socketIdentity,
  abortable,
} from '../../scripts/instagram_testers/runtime/vps/publisher-socket.mjs';
import {
  parseEnvelope,
  validateRequest,
} from '../../scripts/instagram_testers/runtime/operator-protocol.mjs';

const version = '11111111-1111-4111-8111-111111111111';
const request = { type: 'session', operation: 'version' };
const operator = { type: 'operator', manager: null, request: null };
const bootstrap = {
  type: 'bootstrap',
  metadata: {
    INSTAGRAM_META_DEVELOPER_APP_ID: '1',
    INSTAGRAM_META_BUSINESS_ID: '2',
    INSTAGRAM_TESTER_APP_NAME: 'Aplicação sintética',
    INSTAGRAM_TESTER_ADMIN_USER_ID: '3',
    INSTAGRAM_TESTER_ROLES_DOC_ID: '4',
  },
  revision: 'a'.repeat(64),
  version,
};
const publish = {
  type: 'session',
  operation: 'publish',
  session: { cookies: [{ value: 'sintético' }] },
  expected_version: null,
  captured_at: 'synthetic',
  app_id: '1',
  business_id: '2',
  proxy_fingerprint: 'synthetic',
  roles_response: 'synthetic',
  configuration_revision: 'b'.repeat(64),
  roles_doc_id: '4',
};
const invitePermit = {
  type: 'browser_operation',
  operation: 'invite_permit',
  id: '22222222-2222-4222-8222-222222222222',
  request_id: '33333333-3333-4333-8333-333333333333',
  claim: '44444444-4444-4444-8444-444444444444',
  captured_at: '2026-10-08T12:00:00.000Z',
  target_id: '10004',
  username: 'placementseg',
  status: 'absent',
};
const invitePermitWrite = {
  type: 'browser_operation',
  operation: 'invite_permit',
  id: invitePermit.id,
  request_id: invitePermit.request_id,
  claim: invitePermit.claim,
  decision: 'write',
  status: 'absent',
};
const invalidUtf8 = Buffer.from(JSON.stringify(publish));
invalidUtf8[invalidUtf8.indexOf(Buffer.from('é'))] = 0xff;
const failure = { message: 'instagram_session_publication_failed' };
const flush = async () => {
  for (let index = 0; index < 40; index += 1) await Promise.resolve();
};

class Clock {
  time = 0;

  next = 0;

  timers = new Map();

  setTimeout(callback, ms) {
    this.next += 1;
    const id = this.next;
    this.timers.set(id, { callback, at: this.time + ms });
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
    await flush();
  }
}

// No real sockets, network, subprocesses, identities or credential files.
class Socket extends EventEmitter {
  destroyed = false;

  readableEnded = false;

  writableEnded = false;

  writes = [];

  end(value) {
    this.writableEnded = true;
    if (value !== undefined) this.writes.push(value);
    queueMicrotask(() => {
      if (!this.peer || this.destroyed || this.peer.destroyed) return;
      if (value !== undefined) this.peer.emit('data', Buffer.from(value));
      this.peer.readableEnded = true;
      this.peer.emit('end');
      if (this.peer.writableEnded) this.destroy();
    });
  }

  destroy() {
    if (this.destroyed) return;
    this.destroyed = true;
    this.emit('close');
    this.peer?.destroy();
  }

  receive(value, eof = true) {
    this.emit('data', Buffer.isBuffer(value) ? value : Buffer.from(value));
    if (eof) {
      this.readableEnded = true;
      this.emit('end');
    }
  }
}

function stat(kind, mode, ino) {
  return {
    uid: 200,
    gid: 300,
    dev: 1,
    ino,
    mode,
    isDirectory: () => kind === 'directory',
    isSocket: () => kind === 'socket',
    isSymbolicLink: () => kind === 'symlink',
  };
}

function files(stack = 'hub2you', existing = false) {
  const config = publisherSocketConfig(stack);
  const state = {
    directory: stat('directory', 0o710, 10),
    socket: existing ? stat('socket', 0o660, 20) : null,
    calls: [],
    chmods: [],
    async lstatImpl(path) {
      state.calls.push(path);
      const value = path === config.directory ? state.directory : state.socket;
      assert.ok([config.directory, config.socket].includes(path));
      if (!value)
        throw Object.assign(new Error('synthetic absent'), { code: 'ENOENT' });
      return { ...value };
    },
    async chmodImpl(path, mode) {
      assert.equal(path, config.socket);
      state.chmods.push([path, mode]);
      state.socket.mode = mode;
    },
  };
  return state;
}

function serverFactory(state, hooks = {}) {
  return (options, handler) => {
    assert.deepEqual(options, { allowHalfOpen: true });
    const server = new EventEmitter();
    server.paths = [];
    server.closes = 0;
    server.accept = socket => handler(socket);
    server.listen = (path, callback) => {
      server.paths.push(path);
      hooks.beforeListen?.(server);
      if (hooks.bindError) {
        queueMicrotask(() =>
          server.emit('error', new Error('synthetic bind failure'))
        );
        return;
      }
      state.socket = stat('socket', 0o770, 20);
      queueMicrotask(() => {
        hooks.onListen?.(server);
        callback();
      });
    };
    server.close = callback => {
      server.closes += 1;
      queueMicrotask(callback);
    };
    hooks.created?.(server);
    return server;
  };
}

async function brokerFixture(t, changes = {}) {
  const stack = changes.stack || 'hub2you';
  const state = changes.files || files(stack);
  const clock = new Clock();
  const signals = new EventEmitter();
  const calls = [];
  const options = {
    stack,
    uid: 200,
    gid: 300,
    env: { SYNTHETIC: 'publisher-only' },
    lstatImpl: state.lstatImpl,
    chmodImpl: state.chmodImpl,
    createServerImpl: serverFactory(state),
    clock,
    signals,
    runPublisherImpl: async (payload, opts) => {
      const call = { payload, ...opts, cancellations: 0 };
      calls.push(call);
      opts.signals.on('SIGTERM', () => {
        call.cancellations += 1;
      });
      return version;
    },
    ...changes,
  };
  const broker = await createPublisherBroker(options);
  t.after(() => broker.close());
  return { ...broker, state, clock, signals, calls, options };
}

test('warm-channel prewarm failure closes its candidate and server listeners', async () => {
  const state = files();
  const signals = new EventEmitter();
  let server;
  let serverCloses = 0;
  let candidateCloses = 0;
  const baseServerFactory = serverFactory(state);
  const createServerImpl = (options, handler) => {
    server = baseServerFactory(options, handler);
    const close = server.close.bind(server);
    server.close = callback => {
      serverCloses += 1;
      close(callback);
    };
    return server;
  };

  await assert.rejects(
    createPublisherBroker({
      stack: 'hub2you',
      uid: 200,
      gid: 300,
      env: { SYNTHETIC: 'publisher-only' },
      lstatImpl: state.lstatImpl,
      chmodImpl: state.chmodImpl,
      createServerImpl,
      signals,
      warmChannel: true,
      channelFactory: async () => ({
        send: async () => {
          throw new Error('synthetic prewarm failure');
        },
        close: async () => {
          candidateCloses += 1;
        },
      }),
    }),
    failure
  );

  assert.equal(candidateCloses, 1);
  assert.equal(serverCloses, 1);
  assert.equal(server.closes, 1);
  assert.equal(signals.listenerCount('SIGTERM'), 0);
  assert.equal(signals.listenerCount('SIGINT'), 0);
});

function clientFixture(changes = {}) {
  const state = changes.files || files(changes.stack || 'hub2you', true);
  const clock = new Clock();
  const signals = new EventEmitter();
  const input = new Socket();
  const sockets = [];
  const connections = [];
  const options = {
    stack: 'hub2you',
    uid: 100,
    gid: 300,
    lstatImpl: state.lstatImpl,
    input,
    signals,
    clock,
    connectImpl: config => {
      connections.push(config);
      const socket = new Socket();
      sockets.push(socket);
      socket.end = value => {
        socket.writes.push(value);
        queueMicrotask(() =>
          socket.receive(JSON.stringify({ type: 'session', version }))
        );
      };
      queueMicrotask(() => socket.emit('connect'));
      return socket;
    },
    ...changes,
  };
  const start = (value = request) => {
    const promise = runPublisherClient(options);
    input.receive(
      typeof value === 'object' && !Buffer.isBuffer(value)
        ? JSON.stringify(value)
        : value
    );
    return promise;
  };
  return { state, clock, signals, input, sockets, connections, options, start };
}

test('fixed socket configuration isolates stacks and rejects alternate transports/paths', () => {
  assert.notEqual(
    publisherSocketConfig('hub2you').socket,
    publisherSocketConfig('autonomia').socket
  );
  for (const stack of [
    undefined,
    'other',
    '__proto__',
    {},
    'hub2you/../autonomia',
  ])
    assert.throws(() => publisherSocketConfig(stack), failure);
  for (const path of [
    '127.0.0.1:80',
    'https://synthetic',
    '/tmp/publisher.sock',
    '/run/instagram-publisher-autonomia/publisher.sock',
  ])
    assert.throws(() => publisherSocketConfig('hub2you', path), failure);
});

test('identity accepts exact permissions, publisher ownership and browser group', async () => {
  const state = files('hub2you', true);
  const identity = await socketIdentity(publisherSocketConfig('hub2you'), {
    uid: 100,
    gid: 300,
    lstatImpl: state.lstatImpl,
  });
  assert.equal(identity.socket.uid, 200);
  await socketIdentity(publisherSocketConfig('hub2you'), {
    role: 'broker',
    uid: 200,
    gid: 300,
    lstatImpl: state.lstatImpl,
  });
});

for (const [label, change] of [
  [
    'parent symlink',
    s => {
      s.directory = stat('symlink', 0o710, 10);
    },
  ],
  [
    'parent regular file',
    s => {
      s.directory = stat('file', 0o710, 10);
    },
  ],
  [
    'parent mode',
    s => {
      s.directory.mode = 0o750;
    },
  ],
  [
    'parent group writable',
    s => {
      s.directory.mode = 0o730;
    },
  ],
  [
    'parent special bits',
    s => {
      s.directory.mode = 0o2710;
    },
  ],
  [
    'parent gid',
    s => {
      s.directory.gid = 301;
    },
  ],
  [
    'parent root',
    s => {
      s.directory.uid = 0;
      s.socket.uid = 0;
    },
  ],
  [
    'browser owns parent',
    s => {
      s.directory.uid = 100;
      s.socket.uid = 100;
    },
  ],
  [
    'socket symlink',
    s => {
      s.socket = stat('symlink', 0o660, 20);
    },
  ],
  [
    'socket regular file',
    s => {
      s.socket = stat('file', 0o660, 20);
    },
  ],
  [
    'socket mode',
    s => {
      s.socket.mode = 0o666;
    },
  ],
  [
    'socket special bits',
    s => {
      s.socket.mode = 0o1660;
    },
  ],
  [
    'socket gid',
    s => {
      s.socket.gid = 301;
    },
  ],
  [
    'socket owner mismatch',
    s => {
      s.socket.uid = 201;
    },
  ],
  [
    'missing socket',
    s => {
      s.socket = null;
    },
  ],
]) {
  test(`client refuses ${label} before connecting`, async () => {
    const f = clientFixture();
    change(f.state);
    await assert.rejects(f.start(), failure);
    assert.equal(f.connections.length, 0);
    assert.equal(f.clock.timers.size, 0);
  });
}

test('broker refuses root, foreign publisher uid, gid and insecure directory before binding', async () => {
  for (const changes of [{ uid: 0 }, { uid: 201 }, { gid: 301 }]) {
    const state = files();
    await assert.rejects(
      createPublisherBroker({
        stack: 'hub2you',
        ...changes,
        uid: changes.uid ?? 200,
        gid: changes.gid ?? 300,
        lstatImpl: state.lstatImpl,
        createServerImpl: () => assert.fail('must not bind'),
      }),
      failure
    );
  }
  const state = files();
  state.directory.mode = 0o770;
  await assert.rejects(
    createPublisherBroker({
      stack: 'hub2you',
      uid: 200,
      gid: 300,
      lstatImpl: state.lstatImpl,
      createServerImpl: () => assert.fail('must not bind'),
    }),
    failure
  );
});

test('broker never overwrites any preexisting socket/file/symlink', async () => {
  for (const kind of ['socket', 'file', 'symlink']) {
    const state = files('hub2you', true);
    state.socket = stat(kind, 0o660, 20);
    await assert.rejects(
      createPublisherBroker({
        stack: 'hub2you',
        uid: 200,
        gid: 300,
        lstatImpl: state.lstatImpl,
        createServerImpl: () => assert.fail('must not bind'),
        chmodImpl: () => assert.fail('must not chmod'),
      }),
      failure
    );
    assert.equal(state.socket.isSymbolicLink(), kind === 'symlink');
  }
});

test('broker startup filesystem errors fail closed instead of treating them as absence', async () => {
  const state = files();
  await assert.rejects(
    createPublisherBroker({
      stack: 'hub2you',
      uid: 200,
      gid: 300,
      lstatImpl: async path => {
        if (path.endsWith('.sock'))
          throw Object.assign(new Error('private'), { code: 'EACCES' });
        return state.directory;
      },
      createServerImpl: () => assert.fail('must not bind'),
    }),
    failure
  );
});

test('broker binds only AF_UNIX, sets 0660 and removes service listeners on close', async t => {
  const f = await brokerFixture(t);
  assert.deepEqual(f.server.paths, [
    '/run/instagram-publisher-hub2you/publisher.sock',
  ]);
  assert.deepEqual(f.state.chmods, [[f.server.paths[0], 0o660]]);
  await Promise.all([f.close(), f.close()]);
  assert.equal(f.server.closes, 1);
  assert.equal(f.signals.listenerCount('SIGTERM'), 0);
  assert.equal(f.signals.listenerCount('SIGINT'), 0);
});

test('bind failure and socket permission failure close server without exposing details', async () => {
  for (const reason of ['bind', 'chmod', 'identity']) {
    const state = files();
    const signals = new EventEmitter();
    let server;
    await assert.rejects(
      createPublisherBroker({
        stack: 'hub2you',
        uid: 200,
        gid: 300,
        lstatImpl: state.lstatImpl,
        signals,
        createServerImpl: serverFactory(state, {
          created: value => {
            server = value;
          },
          bindError: reason === 'bind',
        }),
        chmodImpl: async (...args) => {
          if (reason === 'chmod') throw new Error('private filesystem path');
          await state.chmodImpl(...args);
          if (reason === 'identity') state.socket.uid = 201;
        },
      }),
      failure
    );
    assert.equal(server.closes, 1);
    assert.equal(signals.listenerCount('SIGTERM'), 0);
  }
});

test('startup detects parent inode replacement after binding', async () => {
  const state = files();
  await assert.rejects(
    createPublisherBroker({
      stack: 'hub2you',
      uid: 200,
      gid: 300,
      lstatImpl: state.lstatImpl,
      createServerImpl: serverFactory(state, {
        onListen: () => {
          state.directory.ino += 1;
        },
      }),
      chmodImpl: state.chmodImpl,
      signals: new EventEmitter(),
    }),
    failure
  );
});

test('service signal during bind cannot leave a late listener alive', async () => {
  const state = files();
  const signals = new EventEmitter();
  let server;
  await assert.rejects(
    createPublisherBroker({
      stack: 'hub2you',
      uid: 200,
      gid: 300,
      lstatImpl: state.lstatImpl,
      chmodImpl: state.chmodImpl,
      signals,
      createServerImpl: serverFactory(state, {
        created: s => {
          server = s;
        },
        beforeListen: () => signals.emit('SIGTERM'),
      }),
    }),
    failure
  );
  assert.equal(server.closes, 1);
  assert.equal(signals.listenerCount('SIGTERM'), 0);
});

test('connections during startup validation are refused without any publisher work', async () => {
  const state = files();
  let calls = 0;
  let server;
  const socket = new Socket();
  const broker = await createPublisherBroker({
    stack: 'hub2you',
    uid: 200,
    gid: 300,
    lstatImpl: state.lstatImpl,
    createServerImpl: serverFactory(state, {
      created: value => {
        server = value;
      },
    }),
    chmodImpl: async (...args) => {
      server.accept(socket);
      socket.receive(JSON.stringify(request));
      await state.chmodImpl(...args);
    },
    runPublisherImpl: async () => {
      calls += 1;
      return version;
    },
    signals: new EventEmitter(),
  });
  await flush();
  assert.equal(socket.destroyed, true);
  assert.equal(calls, 0);
  await broker.close();
});

test('broker waits for EOF and validates complete JSON before publishing once', async t => {
  const f = await brokerFixture(t);
  const socket = new Socket();
  f.server.accept(socket);
  socket.receive('{"type":"session",', false);
  await flush();
  assert.equal(f.calls.length, 0);
  socket.receive('"operation":"version"}');
  await flush();
  assert.equal(f.calls.length, 1);
  assert.deepEqual(f.calls[0].payload, request);
  assert.equal(f.calls[0].stack, 'hub2you');
  assert.equal(f.calls[0].env, f.options.env);
  assert.notEqual(f.calls[0].signals, f.signals);
  assert.deepEqual(parseEnvelope(socket.writes[0], 'session'), {
    type: 'session',
    version,
  });
  socket.emit('end');
  await flush();
  assert.equal(f.calls.length, 1);
});

test('all existing request operations and envelope variants remain compatible', async t => {
  const cases = [
    [request, version],
    [{ ...request }, null],
    [publish, version],
    [{ ...publish, request_id: version, expected_version: version }, version],
    [{ type: 'session', operation: 'bootstrap' }, bootstrap],
    [{ type: 'operator', operation: 'operator_read' }, operator],
    [{ type: 'operator', operation: 'operator_claim', id: version }, operator],
    [
      {
        type: 'operator',
        operation: 'operator_complete',
        id: version,
        state: 'failed',
      },
      operator,
    ],
    [
      {
        type: 'operator',
        operation: 'manager_heartbeat',
        state: 'healthy',
        control_available: false,
      },
      operator,
    ],
    [
      {
        type: 'operator',
        operation: 'manager_heartbeat',
        state: 'operator_required',
        control_available: true,
        request_id: version,
      },
      operator,
    ],
  ];
  for (const [payload, result] of cases) {
    const f = await brokerFixture(t, { runPublisherImpl: async () => result });
    const socket = new Socket();
    f.server.accept(socket);
    socket.receive(JSON.stringify(payload));
    await flush();
    assert.equal(socket.writes.length, 1);
    assert.equal(validateRequest(payload), payload);
    assert.deepEqual(
      parseEnvelope(socket.writes[0]),
      result === version || result === null
        ? { type: 'session', version: result }
        : result
    );
    await f.close();
  }
});

test('warm channel transports one invite_permit frame and never replays a lost response', async t => {
  let inviteCalls = 0;
  const channelFrames = [];
  const channel = {
    send: async payload => {
      if (payload.operation === 'bootstrap') return { type: 'bootstrap' };
      assert.deepEqual(payload, invitePermit);
      inviteCalls += 1;
      channelFrames.push(payload);
      if (inviteCalls === 1) return invitePermitWrite;
      throw new Error('synthetic_lost_invite_response');
    },
    close: async () => {},
  };
  const f = await brokerFixture(t, {
    warmChannel: true,
    channelFactory: async () => channel,
  });
  const first = new Socket();
  f.server.accept(first);
  first.receive(JSON.stringify(invitePermit));
  await flush();
  assert.deepEqual(
    parseEnvelope(first.writes[0], 'browser_operation'),
    invitePermitWrite
  );

  const second = new Socket();
  f.server.accept(second);
  second.receive(JSON.stringify(invitePermit));
  await flush();
  assert.equal(inviteCalls, 2);
  assert.equal(channelFrames.length, 2);
  assert.equal(second.destroyed, true);
  assert.deepEqual(second.writes, []);
});

for (const [label, value] of [
  ['malformed JSON', '{'],
  ['empty input', ''],
  ['two documents', '{}{}'],
  ['array', '[]'],
  ['null', 'null'],
  ['unknown type', '{"type":"other"}'],
  ['wrong operation', JSON.stringify({ ...request, operation: 'shell' })],
  ['extra key', JSON.stringify({ ...request, command: 'synthetic' })],
  [
    'wrong bool',
    JSON.stringify({
      type: 'operator',
      operation: 'manager_heartbeat',
      state: 'healthy',
      control_available: 'false',
    }),
  ],
  [
    'invalid id',
    JSON.stringify({ type: 'operator', operation: 'operator_claim', id: 1 }),
  ],
  ['invalid session', JSON.stringify({ ...publish, session: [] })],
  [
    'missing revision',
    JSON.stringify({ ...publish, configuration_revision: null }),
  ],
  ['invalid UTF8', Buffer.from([0xff])],
  ['UTF8 corruption inside otherwise valid JSON', invalidUtf8],
  ['BOM JSON', Buffer.from('\uFEFF' + JSON.stringify(request))],
]) {
  test(`both request boundaries reject ${label} without publisher/connect`, async t => {
    const f = await brokerFixture(t);
    const socket = new Socket();
    f.server.accept(socket);
    socket.receive(value);
    await flush();
    assert.equal(f.calls.length, 0);
    assert.equal(socket.destroyed, true);
    assert.deepEqual(socket.writes, []);
    const client = clientFixture();
    await assert.rejects(client.start(value), failure);
    assert.equal(client.connections.length, 0);
  });
}

test('input limit counts raw bytes cumulatively and accepts exactly 2MiB', async t => {
  const prefix = JSON.stringify(request);
  const exact = Buffer.from(
    prefix + ' '.repeat(MAX_INPUT_BYTES - Buffer.byteLength(prefix))
  );
  const f = await brokerFixture(t);
  const socket = new Socket();
  f.server.accept(socket);
  socket.receive(exact.subarray(0, 1024), false);
  socket.receive(exact.subarray(1024));
  await flush();
  assert.equal(f.calls.length, 1);
  assert.deepEqual(await clientFixture().start(exact), {
    type: 'session',
    version,
  });
  const overflow = new Socket();
  f.server.accept(overflow);
  overflow.receive(exact, false);
  overflow.receive(Buffer.from(' '), false);
  await flush();
  assert.equal(overflow.destroyed, true);
  assert.equal(f.calls.length, 1);
  const client = clientFixture();
  await assert.rejects(
    client.start(Buffer.concat([exact, Buffer.from(' ')])),
    failure
  );
  assert.equal(client.connections.length, 0);
});

test('UTF8 split inside a multibyte character survives intact at broker boundary', async t => {
  const f = await brokerFixture(t);
  const bytes = Buffer.from(JSON.stringify(publish));
  const index = bytes.indexOf(Buffer.from('é'));
  const socket = new Socket();
  f.server.accept(socket);
  socket.receive(bytes.subarray(0, index + 1), false);
  socket.receive(bytes.subarray(index + 1));
  await flush();
  assert.deepEqual(f.calls[0].payload, publish);
});

test('broker capacity includes incomplete input and response flushing; fifth is refused', async t => {
  const f = await brokerFixture(t);
  const sockets = Array.from(
    { length: MAX_CONNECTIONS + 1 },
    () => new Socket()
  );
  sockets.forEach(socket => f.server.accept(socket));
  assert.equal(sockets[4].destroyed, true);
  sockets[0].receive(JSON.stringify(request));
  await flush();
  const whileFlushing = new Socket();
  f.server.accept(whileFlushing);
  assert.equal(whileFlushing.destroyed, true);
  sockets[0].destroy();
  const fresh = new Socket();
  f.server.accept(fresh);
  fresh.receive(JSON.stringify(request));
  await flush();
  assert.equal(f.calls.length, 2);
});

test('warm channel serializes three requests, cancels the middle one and preserves FIFO', async t => {
  let releaseFirst;
  let channelClosed = 0;
  const channelFrames = [];
  const channel = {
    send: async payload => {
      channelFrames.push(payload);
      if (payload.operation === 'bootstrap') return { type: 'bootstrap' };
      if (payload.operation === 'version') {
        await new Promise(resolve => {
          releaseFirst = resolve;
        });
        return version;
      }
      assert.deepEqual(payload, {
        type: 'operator',
        operation: 'operator_read',
      });
      return operator;
    },
    close: async () => {
      channelClosed += 1;
    },
  };
  const f = await brokerFixture(t, {
    warmChannel: true,
    channelFactory: async () => channel,
  });
  const first = new Socket();
  const second = new Socket();
  const third = new Socket();
  f.server.accept(first);
  f.server.accept(second);
  f.server.accept(third);
  first.receive(JSON.stringify(request));
  second.receive(JSON.stringify({ type: 'session', operation: 'bootstrap' }));
  third.receive(
    JSON.stringify({ type: 'operator', operation: 'operator_read' })
  );
  await flush();

  assert.equal(typeof releaseFirst, 'function');
  assert.deepEqual(
    channelFrames.map(payload => payload.operation),
    ['bootstrap', 'version']
  );
  second.destroy();
  await flush();
  releaseFirst();
  await flush();

  assert.deepEqual(
    channelFrames.map(payload => payload.operation),
    ['bootstrap', 'version', 'operator_read']
  );
  assert.deepEqual(parseEnvelope(first.writes[0], 'session'), {
    type: 'session',
    version,
  });
  assert.deepEqual(parseEnvelope(third.writes[0], 'operator'), operator);
  assert.equal(second.destroyed, true);
  assert.deepEqual(second.writes, []);
  assert.equal(channelClosed, 0);
});

test('warm channel reports CURRENT rotation for a queued frame and opens a fresh channel', async t => {
  let releaseFirst;
  let generation = 0;
  let channelNumber = 0;
  const channelFrames = [];
  const channels = [];
  const channelFactory = async () => {
    channelNumber += 1;
    const number = channelNumber;
    const ownGeneration = generation;
    const channel = {
      send: async payload => {
        channelFrames.push({ channel: number, payload });
        if (payload.operation === 'bootstrap') return { type: 'bootstrap' };
        if (payload.operation === 'version') {
          await new Promise(resolve => {
            releaseFirst = resolve;
          });
          generation = 1;
          return version;
        }
        if (ownGeneration !== generation) throw new Error('current_rotated');
        return operator;
      },
      close: async () => {},
    };
    channels.push(channel);
    return channel;
  };
  const f = await brokerFixture(t, { warmChannel: true, channelFactory });
  const first = new Socket();
  const second = new Socket();
  const third = new Socket();
  f.server.accept(first);
  f.server.accept(second);
  f.server.accept(third);
  first.receive(JSON.stringify(request));
  second.receive(
    JSON.stringify({ type: 'operator', operation: 'operator_read' })
  );
  third.receive(
    JSON.stringify({ type: 'operator', operation: 'operator_read' })
  );
  await flush();
  assert.equal(typeof releaseFirst, 'function');
  releaseFirst();
  await flush();

  assert.equal(channels.length, 2);
  assert.deepEqual(
    channelFrames.map(frame => [frame.channel, frame.payload.operation]),
    [
      [1, 'bootstrap'],
      [1, 'version'],
      [1, 'operator_read'],
      [2, 'bootstrap'],
      [2, 'operator_read'],
    ]
  );
  assert.deepEqual(parseEnvelope(first.writes[0], 'session'), {
    type: 'session',
    version,
  });
  assert.equal(second.destroyed, true);
  assert.deepEqual(second.writes, []);
  assert.deepEqual(parseEnvelope(third.writes[0], 'operator'), operator);
});

test('warm channel EOF closes the old channel and the next queued request uses a new one without replay', async t => {
  let channelNumber = 0;
  const channelFrames = [];
  const channelFactory = async () => {
    channelNumber += 1;
    const number = channelNumber;
    return {
      send: async payload => {
        channelFrames.push({ channel: number, payload });
        if (payload.operation === 'bootstrap') return { type: 'bootstrap' };
        if (number === 1) throw new Error('synthetic_ssh_eof');
        return operator;
      },
      close: async () => {},
    };
  };
  const f = await brokerFixture(t, { warmChannel: true, channelFactory });
  const first = new Socket();
  const second = new Socket();
  f.server.accept(first);
  f.server.accept(second);
  first.receive(JSON.stringify(request));
  second.receive(
    JSON.stringify({ type: 'operator', operation: 'operator_read' })
  );
  await flush();

  assert.equal(first.destroyed, true);
  assert.deepEqual(first.writes, []);
  assert.equal(channelNumber, 2);
  assert.deepEqual(
    channelFrames.map(frame => [frame.channel, frame.payload.operation]),
    [
      [1, 'bootstrap'],
      [1, 'version'],
      [2, 'bootstrap'],
      [2, 'operator_read'],
    ]
  );
  assert.deepEqual(parseEnvelope(second.writes[0], 'operator'), operator);
});

test('closing a warm broker cancels the active frame and releases queued requests', async t => {
  let releaseCount = 0;
  const channelFrames = [];
  const channel = {
    send: async (payload, { signals }) => {
      channelFrames.push(payload);
      if (payload.operation === 'bootstrap') return { type: 'bootstrap' };
      return new Promise((_resolve, reject) => {
        signals.once('SIGTERM', () => {
          releaseCount += 1;
          reject(new Error('synthetic_shutdown'));
        });
      });
    },
    close: async () => {},
  };
  const f = await brokerFixture(t, {
    warmChannel: true,
    channelFactory: async () => channel,
  });
  const first = new Socket();
  const second = new Socket();
  f.server.accept(first);
  f.server.accept(second);
  first.receive(JSON.stringify(request));
  second.receive(
    JSON.stringify({ type: 'operator', operation: 'operator_read' })
  );
  await flush();
  const closing = f.close();
  await closing;

  assert.equal(releaseCount, 1);
  assert.deepEqual(
    channelFrames.map(payload => payload.operation),
    ['bootstrap', 'version']
  );
  assert.equal(first.destroyed, true);
  assert.equal(second.destroyed, true);
  assert.equal(f.server.closes, 1);
  assert.equal(f.signals.listenerCount('SIGTERM'), 0);
  assert.equal(f.signals.listenerCount('SIGINT'), 0);
});

test('30s budget starts at admission, does not reset for data and includes publisher work', async t => {
  let cancellations = 0;
  const f = await brokerFixture(t, {
    runPublisherImpl: (_payload, opts) => {
      opts.signals.on('SIGTERM', () => {
        cancellations += 1;
      });
      return new Promise(() => {});
    },
  });
  const socket = new Socket();
  f.server.accept(socket);
  socket.receive('{', false);
  await f.clock.advance(REQUEST_TIMEOUT_MS - 1);
  assert.equal(socket.destroyed, false);
  socket.receive('"type":"session","operation":"version"}');
  await flush();
  await f.clock.advance(1);
  assert.equal(socket.destroyed, true);
  assert.equal(cancellations, 1);
  assert.equal(f.clock.timers.size, 0);
});

test('incomplete input timeout and input stream error never invoke publisher', async t => {
  const f = await brokerFixture(t);
  const a = new Socket();
  const b = new Socket();
  f.server.accept(a);
  f.server.accept(b);
  a.receive('{', false);
  b.emit('error', new Error('private stream error'));
  await f.clock.advance(REQUEST_TIMEOUT_MS);
  assert.equal(a.destroyed, true);
  assert.equal(b.destroyed, true);
  assert.equal(f.calls.length, 0);
});

test('timeout includes blocked response flushing without canceling a completed publisher', async t => {
  const f = await brokerFixture(t);
  const socket = new Socket();
  f.server.accept(socket);
  socket.receive(JSON.stringify(request));
  await flush();
  assert.equal(socket.writes.length, 1);
  await f.clock.advance(REQUEST_TIMEOUT_MS);
  assert.equal(socket.destroyed, true);
  assert.equal(f.calls[0].cancellations, 0);
});

test('client loss cancels only its publisher and suppresses late success/rejection', async t => {
  const pending = [];
  const f = await brokerFixture(t, {
    runPublisherImpl: (_payload, opts) => {
      const call = { signals: opts.signals, cancellations: 0 };
      opts.signals.on('SIGTERM', () => {
        call.cancellations += 1;
      });
      pending.push(call);
      return new Promise((resolve, reject) => {
        call.resolve = resolve;
        call.reject = reject;
      });
    },
  });
  const sockets = Array.from({ length: 3 }, () => new Socket());
  for (const socket of sockets) {
    f.server.accept(socket);
    socket.receive(JSON.stringify(request));
  }
  await flush();
  sockets[0].destroy();
  sockets[1].emit('error', new Error('private'));
  pending[0].resolve(version);
  pending[1].reject(new Error('late private failure'));
  pending[2].resolve(version);
  await flush();
  assert.deepEqual(
    pending.map(call => call.cancellations),
    [1, 1, 0]
  );
  assert.deepEqual(
    sockets.map(socket => socket.writes.length),
    [0, 0, 1]
  );
  assert.notEqual(pending[0].signals, pending[1].signals);
});

for (const signal of ['SIGTERM', 'SIGINT']) {
  test(`${signal} cancels active requests once, closes incomplete sockets and refuses admission`, async t => {
    const pending = [];
    const f = await brokerFixture(t, {
      runPublisherImpl: (_payload, opts) =>
        new Promise(resolve => {
          const call = { count: 0, resolve };
          pending.push(call);
          opts.signals.on('SIGTERM', () => {
            call.count += 1;
          });
        }),
    });
    const sockets = [new Socket(), new Socket(), new Socket()];
    sockets.forEach(socket => f.server.accept(socket));
    sockets[0].receive(JSON.stringify(request));
    sockets[1].receive(JSON.stringify(request));
    await flush();
    f.signals.emit(signal);
    f.signals.emit(signal);
    await f.close();
    const denied = new Socket();
    f.server.accept(denied);
    pending.forEach(call => call.resolve(version));
    await flush();
    assert.deepEqual(
      pending.map(call => call.count),
      [1, 1]
    );
    assert.ok([...sockets, denied].every(socket => socket.destroyed));
    assert.ok(sockets.every(socket => socket.writes.length === 0));
    assert.equal(f.clock.timers.size, 0);
  });
}

test('publisher failure is never retried and cannot expose exception/payload', async t => {
  let calls = 0;
  const f = await brokerFixture(t, {
    runPublisherImpl: async () => {
      calls += 1;
      throw new Error('private synthetic payload');
    },
  });
  const socket = new Socket();
  f.server.accept(socket);
  socket.receive(JSON.stringify(publish));
  await flush();
  assert.equal(calls, 1);
  assert.equal(socket.destroyed, true);
  assert.deepEqual(socket.writes, []);
});

test('publisher malformed, mismatched and oversized envelopes fail without output', async t => {
  for (const [payload, result] of [
    [request, undefined],
    [request, 42],
    [request, 'not-uuid'],
    [
      { type: 'operator', operation: 'operator_read' },
      { ...operator, extra: 'private' },
    ],
    [
      { type: 'operator', operation: 'operator_read' },
      { type: 'session', version },
    ],
    [
      { type: 'session', operation: 'bootstrap' },
      { ...bootstrap, revision: 'bad' },
    ],
    [
      { type: 'operator', operation: 'operator_read' },
      { ...operator, extra: 'x'.repeat(MAX_OUTPUT_BYTES) },
    ],
  ]) {
    const f = await brokerFixture(t, { runPublisherImpl: async () => result });
    const socket = new Socket();
    f.server.accept(socket);
    socket.receive(JSON.stringify(payload));
    await flush();
    assert.equal(socket.destroyed, true);
    assert.deepEqual(socket.writes, []);
    await f.close();
  }
  assert.throws(() => publisherEnvelope(request, 'x'.repeat(MAX_OUTPUT_BYTES)));
});

test('client exchanges existing session request over fixed path with half-open semantics', async () => {
  const f = clientFixture();
  assert.deepEqual(await f.start(), { type: 'session', version });
  assert.deepEqual(f.connections, [
    {
      path: '/run/instagram-publisher-hub2you/publisher.sock',
      allowHalfOpen: true,
    },
  ]);
  assert.deepEqual(JSON.parse(f.sockets[0].writes[0]), request);
  assert.equal(f.sockets[0].destroyed, true);
  assert.equal(f.clock.timers.size, 0);
  assert.equal(f.signals.listenerCount('SIGTERM'), 0);
});

test('full mocked broker/client exchange works for both stacks and all envelope types', async t => {
  for (const stack of ['hub2you', 'autonomia']) {
    for (const [payload, result] of [
      [request, version],
      [{ ...request, operation: 'bootstrap' }, bootstrap],
      [{ type: 'operator', operation: 'operator_read' }, operator],
    ]) {
      const f = await brokerFixture(t, {
        stack,
        runPublisherImpl: async () => result,
      });
      const client = clientFixture({
        stack,
        files: f.state,
        connectImpl: config => {
          assert.equal(config.path, publisherSocketConfig(stack).socket);
          const a = new Socket();
          const b = new Socket();
          a.peer = b;
          b.peer = a;
          f.server.accept(b);
          queueMicrotask(() => a.emit('connect'));
          return a;
        },
      });
      assert.deepEqual(
        await client.start(payload),
        typeof result === 'string' ? { type: 'session', version } : result
      );
      assert.equal(f.clock.timers.size, 0);
      await f.close();
    }
  }
});

test('client identity race rejects replaced socket or parent before sending any payload', async () => {
  for (const field of ['socket', 'directory']) {
    const f = clientFixture();
    const socket = new Socket();
    f.options.connectImpl = () => {
      f.state[field].ino += 1;
      queueMicrotask(() => socket.emit('connect'));
      return socket;
    };
    await assert.rejects(f.start(), failure);
    assert.deepEqual(socket.writes, []);
    assert.equal(socket.destroyed, true);
  }
});

test('client connect errors, early close and write failure are static and clean up', async () => {
  for (const reason of ['throw', 'error', 'close', 'write']) {
    const f = clientFixture();
    const socket = new Socket();
    f.options.connectImpl = () => {
      if (reason === 'throw') throw new Error('private');
      if (reason === 'write')
        socket.end = () => {
          throw new Error('private write');
        };
      queueMicrotask(() =>
        socket.emit(
          reason === 'write' ? 'connect' : reason,
          new Error('private')
        )
      );
      return socket;
    };
    await assert.rejects(f.start(), failure);
    assert.equal(f.clock.timers.size, 0);
    if (reason !== 'throw') assert.equal(socket.destroyed, true);
  }
});

test('client rejects malformed/mismatched/extra/oversized/invalid-UTF8 response and premature EOF', async () => {
  for (const response of [
    '{',
    '',
    '{}{}',
    JSON.stringify(operator),
    JSON.stringify({ type: 'session', version, extra: 'private' }),
    Buffer.alloc(MAX_OUTPUT_BYTES + 1),
    Buffer.from([0xff]),
  ]) {
    const f = clientFixture();
    f.options.connectImpl = () => {
      const socket = new Socket();
      socket.end = () => queueMicrotask(() => socket.receive(response));
      queueMicrotask(() => socket.emit('connect'));
      return socket;
    };
    await assert.rejects(f.start(), failure);
  }
  const f = clientFixture();
  f.options.connectImpl = () => {
    const socket = new Socket();
    queueMicrotask(() =>
      socket.receive(JSON.stringify({ type: 'session', version }))
    );
    return socket;
  };
  await assert.rejects(f.start(), failure);
});

test('parseEnvelope retains its existing stricter 1024-byte envelope limit', () => {
  const valid = JSON.stringify({ type: 'session', version });
  assert.deepEqual(
    parseEnvelope(valid + ' '.repeat(1024 - valid.length), 'session'),
    { type: 'session', version }
  );
  assert.throws(() =>
    parseEnvelope(valid + ' '.repeat(1025 - valid.length), 'session')
  );
});

test('client response byte limit is cumulative and never waits for EOF after overflow', async () => {
  const f = clientFixture();
  const socket = new Socket();
  f.options.connectImpl = () => {
    socket.end = () => {
      socket.receive(Buffer.alloc(MAX_OUTPUT_BYTES), false);
      socket.receive(Buffer.from('x'), false);
    };
    queueMicrotask(() => socket.emit('connect'));
    return socket;
  };
  await assert.rejects(f.start(), failure);
  assert.equal(socket.destroyed, true);
});

test('client total deadline includes stdin, connecting, response and stalled filesystem checks', async () => {
  for (const phase of ['stdin', 'connect', 'response', 'filesystem']) {
    const f = clientFixture();
    const socket = new Socket();
    f.options.connectImpl = () => {
      if (phase === 'response') queueMicrotask(() => socket.emit('connect'));
      return socket;
    };
    if (phase === 'filesystem')
      f.options.lstatImpl = () => new Promise(() => {});
    const promise =
      phase === 'stdin' ? runPublisherClient(f.options) : f.start();
    const rejected = assert.rejects(promise, failure);
    await flush();
    await f.clock.advance(REQUEST_TIMEOUT_MS);
    await rejected;
    assert.equal(f.input.destroyed, true);
    assert.equal(f.clock.timers.size, 0);
    if (['connect', 'response'].includes(phase))
      assert.equal(socket.destroyed, true);
  }
});

test('client cancellation during post-connect identity check prevents late payload send', async () => {
  const f = clientFixture();
  let release;
  const socket = new Socket();
  f.options.connectImpl = () => {
    queueMicrotask(() => socket.emit('connect'));
    return socket;
  };
  let checks = 0;
  f.options.lstatImpl = async path => {
    checks += 1;
    if (checks === 3)
      await new Promise(resolve => {
        release = resolve;
      });
    return f.state.lstatImpl(path);
  };
  const promise = f.start();
  const rejected = assert.rejects(promise, failure);
  await flush();
  assert.equal(typeof release, 'function');
  f.signals.emit('SIGTERM');
  release();
  await rejected;
  await flush();
  assert.deepEqual(socket.writes, []);
  assert.equal(socket.destroyed, true);
});

test('client SIGINT during stdin and stream error release listeners without connecting', async () => {
  for (const reason of ['signal', 'error', 'close']) {
    const f = clientFixture();
    const promise = runPublisherClient(f.options);
    const rejected = assert.rejects(promise, failure);
    if (reason === 'signal') f.signals.emit('SIGINT');
    else f.input.emit(reason, new Error('private'));
    await rejected;
    assert.equal(f.connections.length, 0);
    assert.equal(f.input.listenerCount('data'), 0);
    assert.equal(f.signals.listenerCount('SIGINT'), 0);
  }
});

test('simultaneous timeout, service stop, disconnect and publisher rejection settle once', async t => {
  let reject;
  let cancellations = 0;
  const f = await brokerFixture(t, {
    runPublisherImpl: (_payload, opts) =>
      new Promise((_resolve, fail) => {
        reject = fail;
        opts.signals.on('SIGTERM', () => {
          cancellations += 1;
        });
      }),
  });
  const socket = new Socket();
  f.server.accept(socket);
  socket.receive(JSON.stringify(request));
  await flush();
  const tick = f.clock.advance(REQUEST_TIMEOUT_MS);
  f.signals.emit('SIGTERM');
  socket.destroy();
  reject(new Error('private late error'));
  await tick;
  await f.close();
  assert.equal(cancellations, 1);
  assert.deepEqual(socket.writes, []);
  assert.equal(f.server.closes, 1);
});

test('client EOF success wins late service signal/close without duplicate result', async () => {
  const f = clientFixture();
  const promise = f.start();
  await flush();
  f.signals.emit('SIGTERM');
  await f.clock.advance(REQUEST_TIMEOUT_MS);
  assert.deepEqual(await promise, { type: 'session', version });
  assert.equal(f.clock.timers.size, 0);
});

test('CLI rejects invalid args/missing or foreign socket without reading stdin', async () => {
  await assert.rejects(clientMain(['--stack', 'hub2you'], {}), failure);
  await assert.rejects(
    clientMain(['--stack', 'hub2you', 'extra'], {
      INSTAGRAM_TESTER_PUBLISHER_SOCKET: '/synthetic',
    }),
    failure
  );
  await assert.rejects(
    clientMain(['--stack', 'autonomia'], {
      INSTAGRAM_TESTER_PUBLISHER_SOCKET:
        '/run/instagram-publisher-hub2you/publisher.sock',
    }),
    failure
  );
});

test('client source has no publisher implementation, key/profile lookup or subprocess imports', async () => {
  const source = await readFile(
    new URL(
      '../../scripts/instagram_testers/runtime/vps/publisher-client.mjs',
      import.meta.url
    ),
    'utf8'
  );
  [
    'publisher-tunnel',
    'child_process',
    'AWS_',
    'SSH_KEY',
    'readFile',
    'createServer',
    'exec(',
  ].forEach(forbidden => assert.equal(source.includes(forbidden), false));
  assert.equal(source.includes('INSTAGRAM_TESTER_PUBLISHER_SOCKET'), true);
});

test('real Node stream mocks preserve stdin EOF and UTF8 without network', async () => {
  const f = clientFixture();
  const input = new PassThrough();
  const promise = runPublisherClient({ ...f.options, input });
  const bytes = Buffer.from(JSON.stringify(publish));
  const at = bytes.indexOf(Buffer.from('é'));
  input.write(bytes.subarray(0, at + 1));
  await flush();
  assert.equal(f.connections.length, 0);
  input.end(bytes.subarray(at + 1));
  assert.deepEqual(await promise, { type: 'session', version });
  assert.deepEqual(JSON.parse(f.sockets[0].writes[0]), publish);
});

test('abort race removes listeners on cancellation, success, failure and pre-aborted signal', async () => {
  for (const reason of ['abort', 'resolve', 'reject', 'pre-aborted']) {
    const controller = new AbortController();
    let resolve;
    let reject;
    const pending = new Promise((ok, fail) => {
      resolve = ok;
      reject = fail;
    });
    if (reason === 'pre-aborted') controller.abort();
    const promise = abortable(pending, controller.signal);
    if (reason === 'resolve') {
      resolve('success');
      assert.equal(await promise, 'success');
    } else {
      const rejected = assert.rejects(promise, failure);
      if (reason === 'reject') reject(new Error('private failure'));
      else controller.abort();
      await rejected;
    }
    assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
    resolve('late success');
    await flush();
  }
});

test('one request timeout leaves a later admitted request running', async t => {
  const calls = [];
  const f = await brokerFixture(t, {
    runPublisherImpl: (_payload, opts) =>
      new Promise(resolve => {
        const call = { count: 0, resolve };
        calls.push(call);
        opts.signals.once('SIGTERM', () => {
          call.count += 1;
        });
      }),
  });
  const first = new Socket();
  f.server.accept(first);
  first.receive(JSON.stringify(request));
  await flush();
  await f.clock.advance(10_000);
  const second = new Socket();
  f.server.accept(second);
  second.receive(JSON.stringify(request));
  await flush();
  await f.clock.advance(20_000);
  assert.deepEqual(
    calls.map(call => call.count),
    [1, 0]
  );
  assert.equal(second.destroyed, false);
  calls[0].resolve(version);
  calls[1].resolve(version);
  await flush();
  assert.deepEqual(first.writes, []);
  assert.equal(second.writes.length, 1);
});

test('client deadline carries time spent on stdin into response and ignores trickling bytes', async () => {
  const f = clientFixture();
  const socket = new Socket();
  f.options.connectImpl = () => {
    queueMicrotask(() => socket.emit('connect'));
    return socket;
  };
  const promise = runPublisherClient(f.options);
  const rejected = assert.rejects(promise, failure);
  f.input.receive('{', false);
  await f.clock.advance(20_000);
  f.input.receive('"type":"session","operation":"version"}');
  await flush();
  assert.equal(socket.writes.length, 1);
  socket.receive('{', false);
  await f.clock.advance(9999);
  assert.equal(socket.destroyed, false);
  socket.receive('"type":', false);
  await f.clock.advance(1);
  await rejected;
  assert.equal(socket.destroyed, true);
});

test('runtime server error cancels owned requests and closes admission', async t => {
  let count = 0;
  const f = await brokerFixture(t, {
    runPublisherImpl: (_payload, opts) => {
      opts.signals.on('SIGTERM', () => {
        count += 1;
      });
      return new Promise(() => {});
    },
  });
  const socket = new Socket();
  f.server.accept(socket);
  socket.receive(JSON.stringify(request));
  await flush();
  f.server.emit('error', new Error('private server failure'));
  await f.close();
  assert.equal(count, 1);
  assert.equal(socket.destroyed, true);
  assert.equal(f.server.closes, 1);
});
