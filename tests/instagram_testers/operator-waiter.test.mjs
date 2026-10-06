/* eslint-disable no-await-in-loop, no-restricted-syntax -- Deterministic offline lease scenarios advance one timer at a time. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import {
  runWaiter,
  runtimeChild,
} from '../../scripts/instagram_testers/runtime/operator-waiter.mjs';
import { validateRequest } from '../../scripts/instagram_testers/runtime/operator-protocol.mjs';

const ID = '11111111-1111-4111-8111-111111111111';
const OTHER_ID = '22222222-2222-4222-8222-222222222222';
const START = Date.parse('2026-10-06T10:00:00.000Z');
const flush = () =>
  new Promise(done => {
    setImmediate(done);
  });
const bootstrap = {
  type: 'bootstrap',
  metadata: {
    INSTAGRAM_META_DEVELOPER_APP_ID: '10001',
    INSTAGRAM_META_BUSINESS_ID: '10002',
    INSTAGRAM_TESTER_APP_NAME: 'Synthetic App',
    INSTAGRAM_TESTER_ADMIN_USER_ID: '12345',
    INSTAGRAM_TESTER_ROLES_DOC_ID: '10003',
  },
  revision: 'a'.repeat(64),
  version: null,
};
const env = {
  INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON: '["synthetic"]',
  INSTAGRAM_TESTER_PROXY_HOST: '127.0.0.1',
  INSTAGRAM_TESTER_PROXY_PORT: '9100',
  INSTAGRAM_TESTER_PROXY_AUTH_MODE: 'ip',
  INSTAGRAM_TESTER_PROXY_IDENTITY: '93.184.216.34:8080',
};

function harness() {
  let time = START;
  let next = 0;
  const timers = new Map();
  const clock = {
    setTimeout: (fn, delay) => {
      next += 1;
      timers.set(next, { fn, at: time + delay });
      return next;
    },
    clearTimeout: key => timers.delete(key),
  };
  const signals = new EventEmitter();
  const h = {
    timers,
    signals,
    calls: [],
    children: [],
    result: undefined,
    now: () => time,
    current: {
      id: ID,
      action: 'reconnect',
      state: 'queued',
      actor_id: 42,
      created_at: new Date(START).toISOString(),
      updated_at: new Date(START).toISOString(),
      expires_at: new Date(START + 3600000).toISOString(),
    },
    advance: async ms => {
      const target = time + ms;
      await flush();
      while (timers.size) {
        const [key, timer] = [...timers.entries()].sort(
          (a, b) => a[1].at - b[1].at
        )[0];
        if (timer.at > target) break;
        time = timer.at;
        timers.delete(key);
        timer.fn();
        await flush();
      }
      time = target;
      await flush();
    },
    start: async () => {
      h.running = runWaiter(env, h.dependencies).then(
        () => {
          h.result = 'done';
        },
        error => {
          h.result = error.message;
        }
      );
      await flush();
    },
    finish: async () => {
      h.current = { ...h.current, state: 'succeeded' };
      h.children.at(-1).finish(0);
      await h.running;
      assert.equal(h.result, 'done');
      assert.equal(timers.size, 0);
      assert.equal(signals.listenerCount('SIGTERM'), 0);
      assert.equal(signals.listenerCount('SIGINT'), 0);
    },
  };
  h.reply = payload => ({
    type: 'operator',
    manager: {
      state: payload.state || 'operator_required',
      control_available: payload.control_available ?? false,
      observed_at: new Date(time).toISOString(),
    },
    request: h.current && { ...h.current },
  });
  h.publish = async (_command, payload) => {
    validateRequest(payload);
    if (payload.operation === 'bootstrap') return bootstrap;
    if (
      payload.operation === 'operator_claim' ||
      (payload.operation === 'manager_heartbeat' && payload.request_id)
    ) {
      if (
        h.current?.id !== (payload.id || payload.request_id) ||
        h.current.state !== (payload.id ? 'queued' : 'running') ||
        Date.parse(h.current.expires_at) <= time
      )
        throw new Error('synthetic revoked');
      h.current = {
        ...h.current,
        state: 'running',
        expires_at: new Date(
          Math.min(time + 90000, Date.parse(h.current.created_at) + 3600000)
        ).toISOString(),
        updated_at: new Date(time).toISOString(),
      };
    }
    if (payload.operation === 'operator_complete') {
      if (h.current?.id !== payload.id || h.current.state !== 'running')
        throw new Error('synthetic not running');
      h.current = { ...h.current, state: payload.state };
    }
    return h.reply(payload);
  };
  h.dependencies = {
    clock,
    now: h.now,
    signals,
    stderr: { write: value => assert.fail(value) },
    publish: (...args) => {
      h.calls.push({ ...args[1], at: time - START, signal: args[2].signal });
      return h.publish(...args);
    },
    child: (script, childEnv, signal) =>
      new Promise((done, reject) => {
        const entry = { script, env: childEnv, signal, at: time - START };
        const stop = () => {
          entry.cancelled = true;
          const drain = () => {
            entry.drained = true;
            if (h.childAbortError) reject(new Error('synthetic cancelled'));
            else done(143);
          };
          if (h.childDrainMs) clock.setTimeout(drain, h.childDrainMs);
          else drain();
        };
        entry.finish = code => {
          signal.removeEventListener('abort', stop);
          entry.drained = true;
          done(code);
        };
        signal.addEventListener('abort', stop, { once: true });
        h.children.push(entry);
      }),
  };
  return h;
}

test('one supervision spans claim, bootstrap, browser and manager without restarting its pause', async () => {
  const h = harness();
  const publish = h.publish;
  h.publish = async (...args) => {
    if (args[1].operation === 'bootstrap')
      await new Promise(done => {
        h.dependencies.clock.setTimeout(done, 20000);
      });
    return publish(...args);
  };
  await h.start();
  assert.equal(h.children.length, 0);
  await h.advance(20000);
  assert.equal(h.children[0].at, 20000);
  await h.advance(9000);
  h.children[0].finish(0);
  await flush();
  assert.equal(h.children[1].at, 29000);
  assert.equal(h.children[1].signal, h.children[0].signal);
  await h.advance(1000);
  assert.deepEqual(
    h.calls.filter(call => call.request_id).map(call => call.at),
    [0, 25000]
  );
  await h.finish();
  assert.equal(h.children.length, 2);
  assert.equal(
    h.children.some(child => child.cancelled),
    false
  );
});

for (const latency of [20000, 25000]) {
  test(`a ${latency}ms running reply leaves heartbeat, read and margin before confirmed expiry`, async () => {
    const h = harness();
    const publish = h.publish;
    h.publish = async (...args) => {
      const payload = args[1];
      if (payload.request_id && h.now() > START) return new Promise(() => {});
      if (payload.operation === 'operator_read') {
        await new Promise(done => {
          h.dependencies.clock.setTimeout(done, 29999);
        });
        h.current = { ...h.current, state: 'succeeded' };
        return h.reply(payload);
      }
      const reply = await publish(...args);
      if (payload.request_id)
        await new Promise(done => {
          h.dependencies.clock.setTimeout(done, latency);
        });
      return reply;
    };
    await h.start();
    await h.advance(latency);
    assert.equal(h.children.length, 1);
    assert.equal(Date.parse(h.current.expires_at), START + 90000);
    await h.advance(55000 - latency);
    const renewalAt = latency === 25000 ? 26000 : 25000;
    await h.advance(renewalAt - 25000);
    assert.deepEqual(
      h.calls.filter(call => call.request_id).map(call => call.at),
      [0, renewalAt]
    );
    assert.equal(
      h.calls.find(call => call.operation === 'operator_read').at,
      renewalAt + 30000
    );
    await h.advance(29999);
    await h.running;
    assert.equal(h.result, 'done');
    assert.equal(h.children[0].cancelled, true);
    assert.equal(h.children.length, 1);
    assert.equal(
      h.calls.some(call => call.operation === 'operator_complete'),
      false
    );
    assert.equal(h.timers.size, 0);
  });
}

for (const lostClaim of [false, true]) {
  test(`lost ${lostClaim ? 'claim' : 'heartbeat'} response reconciles confirmed running lease`, async () => {
    const h = harness();
    const publish = h.publish;
    h.publish = async (...args) => {
      const reply = await publish(...args);
      if (
        (lostClaim && args[1].operation === 'operator_claim') ||
        (!lostClaim && args[1].request_id && h.now() === START + 25000)
      )
        throw new Error('synthetic lost reply after write');
      return reply;
    };
    await h.start();
    await h.advance(25000);
    assert.equal(h.children[0].signal.aborted, false);
    assert.equal(
      h.calls.filter(call => call.operation === 'operator_read').length,
      1
    );
    assert.equal(
      h.calls.filter(call => call.operation === 'operator_claim').length,
      1
    );
    await h.advance(59000);
    assert.equal(h.children[0].signal.aborted, false);
    h.children[0].finish(0);
    await flush();
    await h.finish();
    assert.equal(h.children.length, 2);
    assert.equal(
      h.calls.some(call => call.operation === 'publish'),
      false
    );
  });
}

for (const state of [
  'queued',
  'failed',
  'operator_required',
  'missing',
  'other-running',
  'other-succeeded',
  'expired',
]) {
  test(`uncertain heartbeat cancels on reconciliation with ${state}`, async () => {
    const h = harness();
    const publish = h.publish;
    h.publish = async (...args) => {
      if (args[1].request_id && h.now() === START + 25000) {
        let currentState = state;
        if (['expired', 'other-running'].includes(state))
          currentState = 'running';
        if (state === 'other-succeeded') currentState = 'succeeded';
        h.current =
          state === 'missing'
            ? null
            : {
                ...h.current,
                id: state.startsWith('other-') ? OTHER_ID : ID,
                state: currentState,
                expires_at: new Date(
                  state === 'expired' ? h.now() : h.now() + 90000
                ).toISOString(),
              };
        throw new Error('synthetic uncertain heartbeat');
      }
      return publish(...args);
    };
    await h.start();
    await h.advance(25000);
    await h.running;
    assert.equal(h.result, 'operator_runtime_failed');
    assert.equal(h.children[0].cancelled, true);
    assert.equal(h.children.length, 1);
    assert.equal(h.timers.size, 0);
    assert.equal(
      h.calls.filter(call => call.operation === 'operator_read').length,
      1
    );
  });
}

test('valid heartbeat envelope with a changed ID is reconciled and cancels the manager', async () => {
  const h = harness();
  const publish = h.publish;
  h.publish = async (...args) => {
    if (args[1].request_id && h.now() === START + 25000) {
      h.current = { ...h.current, id: OTHER_ID };
      return h.reply(args[1]);
    }
    return publish(...args);
  };
  await h.start();
  h.children[0].finish(0);
  await flush();
  await h.advance(25000);
  await h.running;
  assert.equal(h.result, 'operator_runtime_failed');
  assert.equal(h.children[1].cancelled, true);
  assert.equal(h.current.id, OTHER_ID);
  assert.equal(
    h.calls.filter(call => call.operation === 'operator_read').length,
    1
  );
});

test('failed heartbeat and stalled reconciliation cannot extend the last confirmed expiration', async () => {
  const h = harness();
  const publish = h.publish;
  h.publish = async (...args) => {
    if (args[1].request_id && h.now() > START) {
      // Heartbeat and read exhaust their budgets at t=55 and t=85, before the t=90 expiry.
      return new Promise(() => {});
    }
    if (args[1].operation === 'operator_read') return new Promise(() => {});
    return publish(...args);
  };
  await h.start();
  await h.advance(84999);
  assert.equal(h.children[0].signal.aborted, false);
  await h.advance(1);
  await h.running;
  assert.equal(h.result, 'operator_runtime_failed');
  assert.equal(h.children[0].cancelled, true);
  assert.equal(Date.parse(h.current.expires_at), START + 90000);
  assert.equal(h.timers.size, 0);
});

test('running reconciliation preserves its actual expiration, without a local renewal', async () => {
  const h = harness();
  const publish = h.publish;
  h.publish = async (...args) => {
    if (args[1].request_id && h.now() > START) {
      if (h.now() === START + 25000)
        throw new Error('synthetic heartbeat not applied');
      return new Promise(() => {});
    }
    if (args[1].operation === 'operator_read' && h.now() > START + 25000) {
      await new Promise(done => {
        h.dependencies.clock.setTimeout(done, 29000);
      });
      return h.reply(args[1]);
    }
    return publish(...args);
  };
  await h.start();
  await h.advance(25000);
  assert.equal(h.children[0].signal.aborted, false);
  await h.advance(64999);
  assert.equal(h.children[0].signal.aborted, false);
  await h.advance(1);
  await h.running;
  assert.equal(h.children[0].cancelled, true);
  assert.equal(h.result, 'operator_runtime_failed');
  assert.equal(h.timers.size, 0);
});

test('same-ID succeeded receipt after lost heartbeat prevents publication replay at transition', async () => {
  const h = harness();
  const publish = h.publish;
  h.publish = async (...args) => {
    if (args[1].request_id && h.now() === START + 25000) {
      h.current = { ...h.current, state: 'succeeded' };
      throw new Error('synthetic reply lost after real success');
    }
    return publish(...args);
  };
  await h.start();
  await h.advance(25000);
  await h.running;
  assert.equal(h.result, 'done');
  assert.equal(h.children[0].cancelled, true);
  assert.equal(h.timers.size, 0);
  assert.equal(h.children.length, 1);
  assert.equal(
    h.calls.some(call => call.operation === 'operator_complete'),
    false
  );
});

for (const abortError of [false, true]) {
  test(`real success stops a stalled manager and awaits drainage, with abort rejection=${abortError}`, async () => {
    const h = harness();
    h.childDrainMs = 28000;
    h.childAbortError = abortError;
    await h.start();
    h.children[0].finish(0);
    await flush();
    h.current = { ...h.current, state: 'succeeded' };
    await h.advance(25000);
    assert.equal(h.children[1].cancelled, true);
    assert.equal(h.children[1].drained, undefined);
    assert.equal(h.result, undefined);
    if (abortError) h.signals.emit('SIGTERM');
    await h.advance(27999);
    assert.equal(h.result, undefined);
    await h.advance(1);
    await h.running;
    assert.equal(h.result, 'done');
    assert.equal(h.children[1].drained, true);
    assert.equal(h.children.length, 2);
    assert.equal(
      h.calls.some(call => call.operation === 'operator_complete'),
      false
    );
    assert.equal(h.calls.filter(call => call.request_id).length, 2);
    assert.equal(h.timers.size, 0);
  });
}

test('late running read after a real succeeded receipt cannot restore expiry or lose success', async () => {
  const h = harness();
  const publish = h.publish;
  let reads = 0;
  h.publish = async (...args) => {
    const payload = args[1];
    if (payload.request_id && h.now() > START) {
      await new Promise(done => {
        h.dependencies.clock.setTimeout(done, 5000);
      });
      throw new Error('synthetic heartbeat lost after success');
    }
    if (payload.operation === 'operator_read') {
      reads += 1;
      if (reads === 1) {
        const reply = h.reply(payload);
        reply.request.expires_at = new Date(START + 40000).toISOString();
        await new Promise(done => {
          h.dependencies.clock.setTimeout(done, 20000);
        });
        return reply;
      }
      h.current = { ...h.current, state: 'succeeded' };
      return h.reply(payload);
    }
    return publish(...args);
  };
  await h.start();
  h.children[0].finish(0);
  await flush();
  await h.advance(25000);
  h.children[1].finish(1);
  await flush();
  await h.advance(5000);
  assert.equal(h.current.state, 'succeeded');
  assert.equal(h.result, undefined);
  await h.advance(15000);
  await h.running;
  assert.equal(h.result, 'done');
  assert.equal(reads, 2);
  assert.equal(h.children.length, 2);
  assert.equal(
    h.calls.some(call => call.operation === 'operator_complete'),
    false
  );
  assert.equal(h.timers.size, 0);
});

test('late running heartbeat after succeeded read cannot trigger completion or another manager', async () => {
  const h = harness();
  const publish = h.publish;
  h.publish = async (...args) => {
    const payload = args[1];
    if (payload.request_id && h.now() > START) {
      const reply = h.reply(payload);
      await new Promise(done => {
        h.dependencies.clock.setTimeout(done, 20000);
      });
      return reply;
    }
    if (payload.operation === 'operator_read') {
      await new Promise(done => {
        h.dependencies.clock.setTimeout(done, 5000);
      });
      h.current = { ...h.current, state: 'succeeded' };
      return h.reply(payload);
    }
    return publish(...args);
  };
  await h.start();
  h.children[0].finish(0);
  await flush();
  await h.advance(25000);
  h.children[1].finish(1);
  await flush();
  await h.advance(5000);
  await h.running;
  assert.equal(h.result, 'done');
  await h.advance(15000);
  assert.equal(h.result, 'done');
  assert.equal(h.current.state, 'succeeded');
  assert.equal(
    h.children.every(child => child.drained),
    true
  );
  assert.equal(h.children.length, 2);
  assert.equal(
    h.calls.some(call => call.operation === 'operator_complete'),
    false
  );
  assert.equal(h.timers.size, 0);
});

test('real success while manager runs is accepted even if its exit status was lost', async () => {
  const h = harness();
  await h.start();
  h.children[0].finish(0);
  await flush();
  h.current = { ...h.current, state: 'succeeded' };
  h.children[1].finish(1);
  await h.running;
  assert.equal(h.result, 'done');
  assert.equal(h.children.length, 2);
  assert.equal(
    h.calls.some(call => call.operation === 'operator_complete'),
    false
  );
  assert.equal(h.timers.size, 0);
});

for (const phase of ['claim', 'bootstrap', 'browser', 'manager', 'reconcile']) {
  test(`shutdown during ${phase} is normal cancellation with bounded cleanup`, async () => {
    const h = harness();
    const publish = h.publish;
    let pendingSignal;
    h.publish = async (...args) => {
      if (
        (phase === 'claim' && args[1].operation === 'operator_claim') ||
        (phase === 'bootstrap' && args[1].operation === 'bootstrap') ||
        (phase === 'reconcile' && args[1].operation === 'operator_read')
      ) {
        if (phase === 'claim') await publish(...args);
        pendingSignal = args[2].signal;
        return new Promise(() => {});
      }
      if (phase === 'reconcile' && args[1].request_id && h.now() > START)
        throw new Error('synthetic lost response');
      return publish(...args);
    };
    await h.start();
    if (phase === 'manager') {
      h.children[0].finish(0);
      await flush();
    }
    if (phase === 'reconcile') await h.advance(25000);
    h.signals.emit('SIGTERM');
    await h.running;
    assert.equal(h.result, 'done');
    assert.equal(h.current.state, 'failed');
    assert.equal(h.timers.size, 0);
    assert.equal(h.signals.listenerCount('SIGTERM'), 0);
    assert.equal(h.signals.listenerCount('SIGINT'), 0);
    if (pendingSignal) assert.equal(pendingSignal.aborted, true);
    assert.equal(
      h.children.every(
        child =>
          child.cancelled || (child === h.children[0] && phase === 'manager')
      ),
      true
    );
    const complete = h.calls.filter(
      call => call.operation === 'operator_complete'
    );
    assert.equal(complete.length, 1);
    assert.equal(complete[0].signal.aborted, true); // Its own completed transport, independent of shutdown.
  });
}

test('confirmed lease expiration cancels a pending bootstrap before any child starts', async () => {
  const h = harness();
  const publish = h.publish;
  let bootstrapSignal;
  h.publish = async (...args) => {
    if (args[1].operation === 'bootstrap') {
      bootstrapSignal = args[2].signal;
      return new Promise(() => {});
    }
    if (
      args[1].request_id &&
      h.calls.filter(call => call.request_id).length > 1
    )
      return new Promise(() => {});
    const reply = await publish(...args);
    if (args[1].operation === 'operator_claim' || args[1].request_id) {
      h.current.expires_at = new Date(START + 1000).toISOString();
      return h.reply(args[1]);
    }
    return reply;
  };
  await h.start();
  await h.advance(999);
  assert.equal(bootstrapSignal.aborted, false);
  await h.advance(1);
  await h.running;
  assert.equal(bootstrapSignal.aborted, true);
  assert.equal(h.result, 'operator_runtime_failed');
  assert.equal(h.children.length, 0);
  assert.equal(h.timers.size, 0);
});

for (const atRequestDeadline of [false, true]) {
  test(`expiry during heartbeat cancels and drains before a late renewal, request deadline=${atRequestDeadline}`, async () => {
    const h = harness();
    const expiration = START + 10000;
    if (atRequestDeadline) {
      h.current.created_at = new Date(expiration - 3600000).toISOString();
      h.current.expires_at = new Date(expiration).toISOString();
    }
    const publish = h.publish;
    let heartbeatSignal;
    h.publish = async (...args) => {
      const payload = args[1];
      if (
        payload.request_id &&
        h.calls.filter(call => call.request_id).length > 1
      ) {
        heartbeatSignal = args[2].signal;
        const reply = h.reply(payload);
        reply.request.expires_at = new Date(h.now() + 90000).toISOString();
        await new Promise(done => {
          h.dependencies.clock.setTimeout(done, 20000);
        });
        return reply;
      }
      const reply = await publish(...args);
      if (payload.operation === 'operator_claim' || payload.request_id) {
        h.current.expires_at = new Date(expiration).toISOString();
        return h.reply(payload);
      }
      return reply;
    };
    h.childDrainMs = 2000;
    await h.start();
    await h.advance(9999);
    assert.equal(heartbeatSignal.aborted, false);
    assert.equal(h.children[0].cancelled, undefined);
    await h.advance(1);
    assert.equal(heartbeatSignal.aborted, true);
    assert.equal(h.children[0].cancelled, true);
    assert.equal(h.result, undefined);
    assert.equal(
      h.calls.some(call => call.operation === 'operator_complete'),
      false
    );
    await h.advance(2000);
    await h.running;
    assert.equal(h.result, 'operator_runtime_failed');
    assert.equal(h.children[0].drained, true);
    await h.advance(9000); // The late reply cannot restart supervision or a manager.
    assert.equal(h.result, 'operator_runtime_failed');
    assert.equal(h.children.length, 1);
    assert.equal(
      h.calls.filter(call => call.operation === 'operator_claim').length,
      1
    );
    assert.equal(h.timers.size, 0);
  });
}

test('shutdown waits for child drainage before completing the claimed request', async () => {
  const h = harness();
  h.childDrainMs = 28000;
  await h.start();
  h.signals.emit('SIGTERM');
  await flush();
  assert.equal(h.children[0].cancelled, true);
  assert.equal(
    h.calls.some(call => call.operation === 'operator_complete'),
    false
  );
  await h.advance(27999);
  assert.equal(h.result, undefined);
  await h.advance(1);
  await h.running;
  assert.equal(h.result, 'done');
  assert.equal(h.children[0].drained, true);
  assert.equal(h.current.state, 'failed');
  assert.equal(h.timers.size, 0);
});

test('shutdown cleanup is independent and ends after its own transport deadline', async () => {
  const h = harness();
  const publish = h.publish;
  let cleanupSignal;
  h.publish = async (...args) => {
    if (args[1].operation === 'operator_complete') {
      cleanupSignal = args[2].signal;
      return new Promise(() => {});
    }
    return publish(...args);
  };
  await h.start();
  h.signals.emit('SIGTERM');
  await flush();
  assert.equal(h.children[0].cancelled, true);
  assert.equal(cleanupSignal.aborted, false);
  await h.advance(29999);
  assert.equal(h.result, undefined);
  await h.advance(1);
  await h.running;
  assert.equal(cleanupSignal.aborted, true);
  assert.equal(h.result, 'done');
  assert.equal(h.timers.size, 0);
  assert.equal(h.signals.listenerCount('SIGTERM'), 0);
});

for (const childEvent of ['exit', 'error']) {
  test(`runtime ${childEvent} after cancellation returns 143 without reporting a process failure`, async () => {
    const child = new EventEmitter();
    const h = harness();
    const controller = new AbortController();
    child.kill = () => {};
    const running = runtimeChild('synthetic', {}, controller.signal, {
      spawnImpl: () => child,
      clock: h.dependencies.clock,
    });
    controller.abort();
    child.emit(
      childEvent,
      childEvent === 'error' ? new Error('synthetic stopped') : null
    );
    assert.equal(await running, 143);
    assert.equal(h.timers.size, 0);
  });
}
