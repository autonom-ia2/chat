/* eslint-disable max-classes-per-file -- Transport fakes model separate stream interfaces. */

import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import {
  createPublisherChannel,
  PUBLISHER_CHANNEL_COMMAND,
} from '../../scripts/instagram_testers/runtime/publisher-channel.mjs';
import { publisherSshArguments } from '../../scripts/instagram_testers/runtime/publisher-tunnel.mjs';
import { createPublisherBroker } from '../../scripts/instagram_testers/runtime/vps/publisher-broker.mjs';

const INSTANCE = 'i-0123456789abcdef0';
const ENV = {
  INSTAGRAM_TESTER_AUTONOMIA_INSTANCE_ID: INSTANCE,
  INSTAGRAM_TESTER_PUBLISHER_SSH_KEY: '/tmp/synthetic-publisher-key',
};
const BOOTSTRAP = JSON.stringify({
  type: 'bootstrap',
  metadata: {
    INSTAGRAM_META_DEVELOPER_APP_ID: '10001',
    INSTAGRAM_META_BUSINESS_ID: '10002',
    INSTAGRAM_TESTER_APP_NAME: 'Synthetic App',
    INSTAGRAM_TESTER_ADMIN_USER_ID: '10003',
    INSTAGRAM_TESTER_ROLES_DOC_ID: '10004',
  },
  revision: 'a'.repeat(64),
  version: null,
});

class FakeStream extends EventEmitter {
  constructor(writeImpl = () => {}) {
    super();
    this.writeImpl = writeImpl;
  }

  write(value, callback) {
    this.writeImpl(String(value));
    callback?.();
    return true;
  }
}

class FakeChild extends EventEmitter {
  constructor(writeImpl = () => {}) {
    super();
    this.stdin = new FakeStream(writeImpl);
    this.stdout = new EventEmitter();
    this.stderr = new EventEmitter();
    this.stdout.resume = () => {};
    this.stderr.resume = () => {};
    this.exitCode = null;
  }

  kill() {
    if (this.exitCode !== null) return;
    this.exitCode = 0;
    this.emit('close', 0);
  }
}

class FakeServer extends EventEmitter {
  // eslint-disable-next-line class-methods-use-this
  listen(_socketPath, callback) {
    callback();
  }

  // eslint-disable-next-line class-methods-use-this
  close(callback) {
    callback();
  }
}

function testFiles() {
  return {
    mkdtemp: async () => '/tmp/instagram-channel-test',
    writeFile: async () => {},
    chmod: async () => {},
    rm: async () => {},
  };
}

function channelFactory({
  current = [INSTANCE],
  response = () => BOOTSTRAP,
  respond = true,
  writeError = false,
  afterFrame = () => {},
} = {}) {
  const currentReads = [];
  let readerClosed = false;
  let readerFactories = 0;
  const sshFrames = [];
  let ssh;
  const run = async (_command, args) => {
    if (args.includes('get-caller-identity')) return '140023375763\n';
    throw new Error('unexpected_aws_command');
  };
  const spawnImpl = command => {
    if (command === 'aws') return new FakeChild();
    ssh = new FakeChild(frame => {
      if (writeError) throw new Error('synthetic_write_failure');
      const payload = JSON.parse(frame);
      sshFrames.push(payload);
      afterFrame();
      if (respond)
        queueMicrotask(() => {
          if (ssh.exitCode === null)
            ssh.stdout.emit('data', Buffer.from(`${response(payload)}\n`));
        });
    });
    return ssh;
  };
  return {
    currentReads,
    sshFrames,
    get ssh() {
      return ssh;
    },
    options: {
      stack: 'autonomia',
      env: ENV,
      run,
      currentReaderFactory: async () => {
        readerFactories += 1;
        return {
          read: async () => {
            const value = current.shift() || INSTANCE;
            currentReads.push(value);
            return value;
          },
          close: () => {
            readerClosed = true;
          },
        };
      },
      spawnImpl,
      freePortFn: async () => 2222,
      waitForPortFn: async () => true,
      hostKeyFn: async () => 'ssh-ed25519 AAAA synthetic',
      files: testFiles(),
    },
    get readerClosed() {
      return readerClosed;
    },
    get readerFactories() {
      return readerFactories;
    },
  };
}

test('keeps one SSH channel and verifies CURRENT before every frame', async () => {
  const fake = channelFactory({ current: [INSTANCE, INSTANCE, INSTANCE] });
  const channel = await createPublisherChannel(fake.options);

  await channel.send({ type: 'session', operation: 'bootstrap' });
  await channel.send({ type: 'session', operation: 'bootstrap' });

  assert.equal(fake.currentReads.length, 3);
  assert.equal(fake.readerFactories, 1);
  assert.equal(fake.sshFrames.length, 2);
  assert.deepEqual(fake.sshFrames[0], {
    type: 'session',
    operation: 'bootstrap',
  });
  await channel.close();
  assert.equal(fake.readerClosed, true);
});

test('closes the channel when CURRENT rotates before a frame', async () => {
  const fake = channelFactory({ current: [INSTANCE, 'i-0fedcba9876543210'] });
  const channel = await createPublisherChannel(fake.options);

  await assert.rejects(
    channel.send({ type: 'session', operation: 'bootstrap' }),
    /instagram_session_publication_failed/
  );
  assert.equal(fake.sshFrames.length, 0);
  await assert.rejects(
    channel.send({ type: 'session', operation: 'bootstrap' }),
    /instagram_session_publication_failed/
  );
});

test('closes on malformed output and never exposes a stale response', async () => {
  const fake = channelFactory({
    current: [INSTANCE, INSTANCE],
    response: () => '{"type":"malformed"}',
  });
  const channel = await createPublisherChannel(fake.options);

  await assert.rejects(
    channel.send({ type: 'session', operation: 'bootstrap' }),
    /instagram_session_publication_failed/
  );
  await assert.rejects(
    channel.send({ type: 'session', operation: 'bootstrap' }),
    /instagram_session_publication_failed/
  );
});

test('closes when a response exceeds the bounded output frame before parsing', async () => {
  const fake = channelFactory({
    current: [INSTANCE, INSTANCE],
    response: () => 'x'.repeat(2049),
  });
  const channel = await createPublisherChannel(fake.options);

  await assert.rejects(
    channel.send({ type: 'session', operation: 'bootstrap' }),
    /instagram_session_publication_failed/
  );
  await assert.rejects(
    channel.send({ type: 'session', operation: 'bootstrap' }),
    /instagram_session_publication_failed/
  );
});

test('consumes the pending response when the SSH write fails and never retries', async () => {
  const fake = channelFactory({ current: [INSTANCE], writeError: true });
  const channel = await createPublisherChannel(fake.options);

  await assert.rejects(
    channel.send({ type: 'session', operation: 'bootstrap' }),
    /instagram_session_publication_failed/
  );
  assert.equal(fake.sshFrames.length, 0);
  await assert.rejects(
    channel.send({ type: 'session', operation: 'bootstrap' }),
    /instagram_session_publication_failed/
  );
});

test('consumes the pending response on child EOF and never retries a closed channel', async () => {
  const fake = channelFactory({ current: [INSTANCE], respond: false });
  const channel = await createPublisherChannel(fake.options);
  const pending = channel.send({ type: 'session', operation: 'bootstrap' });
  queueMicrotask(() => fake.ssh.emit('close', 1));

  await assert.rejects(pending, /instagram_session_publication_failed/);
  assert.equal(fake.sshFrames.length, 1);
  await assert.rejects(
    channel.send({ type: 'session', operation: 'bootstrap' }),
    /instagram_session_publication_failed/
  );
});

test('consumes the pending response on request cancellation', async () => {
  const signals = new EventEmitter();
  const fake = channelFactory({
    current: [INSTANCE],
    respond: false,
    afterFrame: () => signals.emit('SIGTERM'),
  });
  const channel = await createPublisherChannel(fake.options);
  const pending = channel.send(
    { type: 'session', operation: 'bootstrap' },
    { signals }
  );

  await assert.rejects(pending, /instagram_session_publication_failed/);
  assert.equal(fake.sshFrames.length, 1);
});

test('only permits the fixed SSH channel command', () => {
  const config = { sshKey: '/tmp/synthetic-key' };
  const oneShot = publisherSshArguments(config, 2222, '/tmp/known_hosts');
  const channel = publisherSshArguments(
    config,
    2222,
    '/tmp/known_hosts',
    PUBLISHER_CHANNEL_COMMAND
  );

  assert.equal(oneShot.at(-1), 'chatwoot_publisher@127.0.0.1');
  assert.equal(channel.at(-1), PUBLISHER_CHANNEL_COMMAND);
  assert.throws(() =>
    publisherSshArguments(config, 2222, '/tmp/known_hosts', 'arbitrary-command')
  );
});

test('prewarms a broker channel with a bootstrap before accepting sockets', async () => {
  const directory = {
    dev: 1,
    ino: 2,
    uid: 501,
    gid: 20,
    mode: 0o40710,
    isDirectory: () => true,
    isSymbolicLink: () => false,
  };
  const socket = {
    dev: 1,
    ino: 3,
    uid: 501,
    gid: 20,
    mode: 0o140660,
    isSocket: () => true,
    isSymbolicLink: () => false,
  };
  let socketLookups = 0;
  const lstatImpl = async path => {
    if (path.endsWith('/publisher.sock')) {
      socketLookups += 1;
      if (socketLookups === 1) {
        const error = new Error('missing');
        error.code = 'ENOENT';
        throw error;
      }
      return socket;
    }
    return directory;
  };
  const sent = [];
  let closed = false;
  const brokerChannelFactory = async () => ({
    send: async payload => {
      sent.push(payload);
      return { type: 'bootstrap' };
    },
    close: async () => {
      closed = true;
    },
  });
  const broker = await createPublisherBroker({
    stack: 'autonomia',
    socketPath: '/run/instagram-publisher-autonomia/publisher.sock',
    uid: 501,
    gid: 20,
    lstatImpl,
    chmodImpl: async () => {},
    createServerImpl: () => new FakeServer(),
    channelFactory: brokerChannelFactory,
    warmChannel: true,
    env: {},
    signals: new EventEmitter(),
  });

  assert.deepEqual(sent, [{ type: 'session', operation: 'bootstrap' }]);
  await broker.close();
  assert.equal(closed, true);
});
