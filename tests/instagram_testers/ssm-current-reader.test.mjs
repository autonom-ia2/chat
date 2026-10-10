/* eslint-disable max-classes-per-file -- Reader fakes model SDK client variants. */

import assert from 'node:assert/strict';
import test from 'node:test';
import { createSsmCurrentReader } from '../../scripts/instagram_testers/runtime/vps/ssm-current-reader.mjs';

const CONFIG = {
  region: 'us-east-1',
  awsProfile: 'hub2you',
  currentInstanceParameter: '/chatwoot/prod/blue-green/current-instance-id',
};

class FakeCommand {
  constructor(input) {
    this.input = input;
  }
}

class FakeClient {
  constructor(config, responses = []) {
    this.config = config;
    this.responses = responses;
    this.calls = [];
    this.destroyed = 0;
  }

  async send(command, options) {
    this.calls.push({ command, options });
    const response = this.responses.shift();
    if (response instanceof Error) throw response;
    return { Parameter: { Value: response } };
  }

  destroy() {
    this.destroyed += 1;
  }
}

async function readerWith(responses) {
  let client;
  const reader = await createSsmCurrentReader(CONFIG, {
    clientFactory: class extends FakeClient {
      constructor(config) {
        super(config, responses);
        client = this;
      }
    },
    commandFactory: FakeCommand,
  });
  return { reader, client };
}

test('rejects an already-aborted signal without sending or retrying', async () => {
  const { reader, client } = await readerWith(['i-0123456789abcdef0']);
  const controller = new AbortController();
  controller.abort();

  await assert.rejects(
    reader.read({ signal: controller.signal }),
    /instagram_session_publication_failed/
  );
  assert.equal(client.calls.length, 0);
  reader.close();
});

test('rejects when the signal aborts during the provider call', async () => {
  const controller = new AbortController();
  let client;
  const reader = await createSsmCurrentReader(CONFIG, {
    clientFactory: class extends FakeClient {
      constructor(config) {
        super(config, ['i-0123456789abcdef0']);
        client = this;
      }

      async send(command, options) {
        controller.abort();
        return super.send(command, options);
      }
    },
    commandFactory: FakeCommand,
  });

  await assert.rejects(
    reader.read({ signal: controller.signal }),
    /instagram_session_publication_failed/
  );
  assert.equal(client.calls.length, 1);
  reader.close();
});

test('closes and rejects a provider call still in flight', async () => {
  let client;
  const reader = await createSsmCurrentReader(CONFIG, {
    clientFactory: class {
      constructor(config) {
        this.config = config;
        this.calls = [];
        this.abortSignal = null;
        this.destroyed = 0;
        client = this;
      }

      send(command, options) {
        this.calls.push(command);
        this.abortSignal = options.abortSignal;
        return new Promise(() => {});
      }

      destroy() {
        this.destroyed += 1;
      }
    },
    commandFactory: FakeCommand,
  });
  const pending = reader.read();
  queueMicrotask(() => reader.close());

  await assert.rejects(pending, /instagram_session_publication_failed/);
  assert.equal(client.calls.length, 1);
  assert.equal(client.abortSignal.aborted, true);
  assert.equal(client.destroyed, 1);
});

test('returns each fresh CURRENT value, including a rotation', async () => {
  const { reader, client } = await readerWith([
    'i-0123456789abcdef0',
    'i-0fedcba9876543210',
  ]);

  assert.equal(await reader.read(), 'i-0123456789abcdef0');
  assert.equal(await reader.read(), 'i-0fedcba9876543210');
  assert.equal(client.calls.length, 2);
  assert.deepEqual(
    client.calls.map(call => call.command.input),
    [
      { Name: CONFIG.currentInstanceParameter },
      { Name: CONFIG.currentInstanceParameter },
    ]
  );
  reader.close();
});

test('makes three fresh reads and surfaces a provider error without retry', async () => {
  const { reader, client } = await readerWith([
    'i-0123456789abcdef0',
    'i-0123456789abcdef0',
    'i-0123456789abcdef0',
    new Error('synthetic_provider_failure'),
  ]);

  await reader.read();
  await reader.read();
  await reader.read();
  await assert.rejects(reader.read(), /instagram_session_publication_failed/);
  assert.equal(client.calls.length, 4);
  assert.equal(client.config.maxAttempts, 1);
  reader.close();
  assert.equal(client.destroyed, 1);
});
