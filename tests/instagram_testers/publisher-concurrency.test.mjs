/* eslint-disable no-await-in-loop, no-restricted-syntax -- Drive synthetic lifecycle events with one deterministic clock. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter, getEventListeners } from 'node:events';
import {
  commandRunner,
  hostKeyViaSsm,
  PUBLISH_BUDGET_MS,
  runPublisher,
} from '../../scripts/instagram_testers/runtime/publisher-tunnel.mjs';

const request = { type: 'session', operation: 'version' };
const hostKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISyntheticHostKeyData==';
const failure = { message: 'instagram_session_publication_failed' };
const instance = 'i-0123456789abcdef0';
const env = {
  INSTAGRAM_TESTER_PUBLISHER_SSH_KEY: '/synthetic/key',
  INSTAGRAM_TESTER_HUB2YOU_INSTANCE_ID: instance,
};
const flush = async () => {
  for (let index = 0; index < 60; index += 1) await Promise.resolve();
};

class Clock {
  time = 0;

  next = 0;

  timers = new Map();

  setTimeout(callback, ms) {
    this.next += 1;
    const id = this.next;
    this.timers.set(id, { at: this.time + ms, callback });
    return id;
  }

  clearTimeout(id) {
    this.timers.delete(id);
  }

  async advanceTo(target) {
    assert.ok(target >= this.time);
    await flush();
    for (;;) {
      const next = [...this.timers].sort((a, b) => a[1].at - b[1].at)[0];
      if (!next || next[1].at > target) break;
      const [id, timer] = next;
      this.time = timer.at;
      this.timers.delete(id);
      timer.callback();
      await flush();
    }
    this.time = target;
    await flush();
  }
}

// Every command, child, listener and file is a mock; no socket or external service.
function fixture({
  stsMs = 2300,
  currentMs = 2400,
  listenerMs = 4000,
  sendMs = 1500,
  pollMs = 4000,
  sshMs = 500,
  failAt,
  account = '354307071110',
  current = instance,
  key = hostKey,
  overrides = {},
  payload = request,
} = {}) {
  const clock = new Clock();
  const signals = new EventEmitter();
  const events = [];
  const operations = [];
  const branches = [];
  const children = [];
  const record = name => events.push({ name, at: clock.time });
  const operation = (name, ms, value, options) => {
    record(`${name}:start`);
    operations.push({ name, at: clock.time, options });
    return new Promise((resolve, reject) => {
      let timer;
      const abort = () => {
        clock.clearTimeout(timer);
        options.signal.removeEventListener('abort', abort);
        record(`${name}:abort`);
        reject(new Error('synthetic cancellation'));
      };
      options.signal.addEventListener('abort', abort, { once: true });
      if (options.signal.aborted) {
        abort();
        return;
      }
      if (ms === null) return;
      timer = clock.setTimeout(() => {
        options.signal.removeEventListener('abort', abort);
        record(`${name}:done`);
        if (failAt === name) reject(new Error('synthetic branch failure'));
        else resolve(value);
      }, ms);
    });
  };
  const files = {
    mkdtemp: async () => {
      record('scratch');
      return '/synthetic/scratch';
    },
    writeFile: async (path, value, options) => {
      record('known_hosts');
      assert.equal(path, '/synthetic/scratch/known_hosts');
      assert.equal(value, `[127.0.0.1]:49152 ${hostKey}\n`);
      assert.deepEqual(options, { mode: 0o600 });
    },
    chmod: async (path, mode) => {
      record('chmod');
      assert.equal(path, '/synthetic/scratch/known_hosts');
      assert.equal(mode, 0o600);
    },
    rm: async (path, options) => {
      record('rm');
      assert.equal(path, '/synthetic/scratch');
      assert.deepEqual(options, { recursive: true, force: true });
    },
  };
  const options = {
    stack: 'hub2you',
    env,
    clock,
    now: () => clock.time,
    signals,
    files,
    run: (_command, args, commandOptions) => {
      assert.equal(_command, 'aws');
      if (args.includes('get-caller-identity'))
        return operation('sts', stsMs, account, commandOptions);
      if (args.includes('get-parameter'))
        return operation('current', currentMs, current, commandOptions);
      if (args.includes('send-command')) {
        assert.ok(args.includes(instance));
        return operation('send', sendMs, 'command-12345678', commandOptions);
      }
      if (args.includes('list-command-invocations'))
        return operation(
          'poll',
          pollMs,
          JSON.stringify({ Status: 'Success', Output: key }),
          commandOptions
        );
      throw new Error('unexpected synthetic command');
    },
    freePortFn: async () => {
      record('free-port');
      return 49152;
    },
    waitForPortFn: (port, listenerOptions) => {
      assert.equal(port, 49152);
      branches.push({ name: 'listener', options: listenerOptions });
      return operation('listener', listenerMs, true, listenerOptions);
    },
    hostKeyFn: (target, hostOptions) => {
      branches.push({ name: 'hostkey', options: hostOptions });
      return hostKeyViaSsm(target, hostOptions);
    },
    sleep: () => {
      throw new Error('unexpected retry in synthetic success path');
    },
    spawnImpl: (command, args, childOptions) => {
      record(command);
      const child = new EventEmitter();
      let closeTimer;
      child.killed = false;
      child.pid = 0;
      child.kill = () => {
        child.killed = true;
        clock.clearTimeout(closeTimer);
      };
      child.stdout = new EventEmitter();
      child.stdout.resume = () => {};
      child.stderr = new EventEmitter();
      child.stderr.resume = () => {};
      child.stdin = new EventEmitter();
      child.stdin.end = input => {
        assert.equal(command, 'ssh');
        assert.deepEqual(JSON.parse(input), payload);
        if (sshMs === null) return;
        closeTimer = clock.setTimeout(() => {
          record('ssh:close');
          child.stdout.emit(
            'data',
            JSON.stringify({ type: 'session', version: null })
          );
          child.emit('close', 0);
        }, sshMs);
      };
      if (command === 'aws') {
        assert.ok(args.includes('start-session'));
        assert.equal(childOptions.detached, true);
        assert.equal(childOptions.stdio[0], 'pipe');
      } else {
        assert.equal(command, 'ssh');
        assert.ok(args.includes('StrictHostKeyChecking=yes'));
        assert.ok(
          args.includes('UserKnownHostsFile=/synthetic/scratch/known_hosts')
        );
      }
      children.push({ command, child });
      return child;
    },
    stopProcessFn: (child, group) => {
      if (!child) return;
      const { command } = children.find(item => item.child === child);
      if (command === 'aws') assert.equal(group, true);
      record(`${command}:stop`);
      child.kill();
    },
    ...overrides,
  };
  let outcome;
  const result = runPublisher(payload, options);
  const settled = result.then(
    value => {
      outcome = { value, at: clock.time };
      return outcome;
    },
    error => {
      outcome = { error, at: clock.time };
      return outcome;
    }
  );
  return {
    clock,
    signals,
    events,
    operations,
    branches,
    children,
    result,
    settled,
    record,
    options,
    outcome: () => outcome,
  };
}

const timeOf = (f, name) => f.events.find(event => event.name === name)?.at;
const clean = f => {
  assert.equal(f.clock.timers.size, 0);
  assert.equal(f.signals.listenerCount('SIGTERM'), 0);
  assert.equal(f.signals.listenerCount('SIGINT'), 0);
  if (f.children.length)
    assert.equal(
      f.children.find(item => item.command === 'aws')?.child.killed,
      true
    );
  for (const { options } of f.operations)
    assert.equal(getEventListeners(options.signal, 'abort').length, 0);
};

test('synthetic supplied timings overlap hostkey with listener; STS/CURRENT overlap before operations', async t => {
  const f = fixture();
  await f.clock.advanceTo(2399);
  assert.equal(timeOf(f, 'sts:done'), 2300);
  assert.equal(timeOf(f, 'current:start'), 0);
  assert.equal(timeOf(f, 'aws'), undefined);
  await f.clock.advanceTo(2400);
  assert.equal(timeOf(f, 'current:done'), 2400);
  assert.equal(timeOf(f, 'aws'), 2400);
  assert.equal(timeOf(f, 'listener:start'), 2400);
  assert.equal(timeOf(f, 'send:start'), 2400);
  await f.clock.advanceTo(6400);
  assert.equal(timeOf(f, 'listener:done'), 6400);
  assert.equal(timeOf(f, 'poll:done'), undefined);
  assert.equal(timeOf(f, 'scratch'), undefined);
  assert.equal(timeOf(f, 'ssh'), undefined);
  await f.clock.advanceTo(7900);
  assert.equal(timeOf(f, 'poll:done'), 7900);
  assert.equal(timeOf(f, 'known_hosts'), 7900);
  assert.equal(timeOf(f, 'ssh'), 7900);
  const sharedSignal = f.operations[0].options.signal;
  for (const op of f.operations) {
    assert.equal(op.options.signal, sharedSignal);
    assert.equal(op.options.timeoutMs, 25000 - op.at);
    if (op.name === 'listener') assert.equal(op.options.deadline, 25000);
  }
  assert.deepEqual(
    f.branches.map(branch => branch.name),
    ['listener', 'hostkey']
  );
  for (const { options } of f.branches) {
    assert.equal(options.signal, sharedSignal);
    assert.equal(options.deadline, 25000);
    assert.equal(options.now, f.options.now);
    assert.equal(options.sleep, f.options.sleep);
  }
  await f.clock.advanceTo(8400);
  assert.deepEqual(await f.settled, { value: null, at: 8400 });
  assert.equal(timeOf(f, 'rm'), 8400);
  clean(f);
  t.diagnostic(`SYNTHETIC ONLY ${JSON.stringify(f.events)}`);
});

test('hostkey first still cannot create known_hosts or SSH before listener proof', async () => {
  const f = fixture({ listenerMs: 5500, pollMs: 2500 });
  await f.clock.advanceTo(6400);
  assert.equal(timeOf(f, 'poll:done'), 6400);
  assert.equal(timeOf(f, 'listener:done'), undefined);
  assert.equal(timeOf(f, 'scratch'), undefined);
  assert.equal(timeOf(f, 'ssh'), undefined);
  await f.clock.advanceTo(7900);
  assert.equal(timeOf(f, 'ssh'), 7900);
  await f.clock.advanceTo(8400);
  assert.deepEqual(await f.settled, { value: null, at: 8400 });
  clean(f);
});

for (const branch of ['listener', 'send', 'poll']) {
  test(`${branch} failure immediately cancels sibling and stops tunnel without SSH`, async () => {
    const f = fixture({
      listenerMs: branch === 'listener' ? 500 : null,
      sendMs: branch === 'send' ? 500 : 200,
      pollMs: branch === 'poll' ? 300 : null,
      failAt: branch,
    });
    await f.clock.advanceTo(2900);
    const outcome = await f.settled;
    assert.equal(outcome.error.message, failure.message);
    assert.equal(outcome.at, 2900);
    const sibling = branch === 'listener' ? 'poll' : 'listener';
    assert.equal(timeOf(f, `${sibling}:abort`), 2900);
    assert.equal(timeOf(f, 'aws:stop'), 2900);
    assert.equal(timeOf(f, 'scratch'), undefined);
    assert.equal(timeOf(f, 'ssh'), undefined);
    clean(f);
  });
}

for (const branch of ['listener', 'hostkey']) {
  test(`${branch} synchronous throw consumes sibling late rejection under strict mode`, async () => {
    let failSibling;
    let siblingSignal;
    let siblingAbort = false;
    const throws = () => {
      throw new Error('synthetic synchronous failure');
    };
    const pending = (_target, options) => {
      siblingSignal = options.signal;
      options.signal.addEventListener(
        'abort',
        () => {
          siblingAbort = true;
        },
        { once: true }
      );
      return new Promise((_resolve, reject) => {
        failSibling = reject;
      });
    };
    const f = fixture({
      overrides: {
        waitForPortFn: branch === 'listener' ? throws : pending,
        hostKeyFn: branch === 'hostkey' ? throws : pending,
      },
    });
    await f.clock.advanceTo(2400);
    assert.equal((await f.settled).error.message, failure.message);
    assert.equal(siblingSignal.aborted, true);
    assert.equal(siblingAbort, true);
    assert.equal(timeOf(f, 'ssh'), undefined);
    failSibling(new Error('synthetic late rejection after publisher returned'));
    await flush();
    await new Promise(resolve => {
      setImmediate(resolve);
    });
    clean(f);
  });
}

test('default 25s deadline cancels both pending branches and ignores late completions', async () => {
  assert.equal(PUBLISH_BUDGET_MS, 25000);
  const completions = [];
  const branchOptions = [];
  const pending = (_target, options) => {
    branchOptions.push(options);
    return new Promise(resolve => {
      completions.push(resolve);
    });
  };
  const f = fixture({
    overrides: { waitForPortFn: pending, hostKeyFn: pending },
  });
  await f.clock.advanceTo(2400);
  assert.equal(branchOptions.length, 2);
  assert.equal(branchOptions[0].signal, branchOptions[1].signal);
  for (const options of branchOptions) assert.equal(options.deadline, 25000);
  await f.clock.advanceTo(24999);
  assert.equal(f.outcome(), undefined);
  await f.clock.advanceTo(25000);
  assert.equal((await f.settled).error.message, failure.message);
  assert.equal(f.outcome().at, 25000);
  assert.equal(branchOptions[0].signal.aborted, true);
  completions[0](true);
  completions[1](hostKey);
  await flush();
  assert.equal(timeOf(f, 'scratch'), undefined);
  assert.equal(timeOf(f, 'ssh'), undefined);
  clean(f);
});

test('25s remains total budget including SSH close; timeout cleans scratch and children', async () => {
  const f = fixture({ sshMs: 18000 });
  await f.clock.advanceTo(24999);
  assert.equal(timeOf(f, 'ssh'), 7900);
  assert.equal(f.outcome(), undefined);
  await f.clock.advanceTo(25000);
  assert.equal((await f.settled).error.message, failure.message);
  assert.equal(f.outcome().at, 25000);
  assert.equal(timeOf(f, 'ssh:close'), undefined);
  assert.equal(timeOf(f, 'rm'), 25000);
  assert.equal(
    f.children.find(item => item.command === 'ssh').child.killed,
    true
  );
  clean(f);
});

for (const signal of ['SIGTERM', 'SIGINT']) {
  test(`${signal} cancels both readiness branches and releases listeners/timers`, async () => {
    const f = fixture({ listenerMs: null, sendMs: null });
    await f.clock.advanceTo(2400);
    f.signals.emit(signal);
    assert.equal((await f.settled).error.message, failure.message);
    assert.equal(timeOf(f, 'listener:abort'), 2400);
    assert.equal(timeOf(f, 'send:abort'), 2400);
    assert.equal(timeOf(f, 'ssh'), undefined);
    clean(f);
  });
}

test('account mismatch cancels overlapping CURRENT before any operational work', async () => {
  const f = fixture({ account: '140023375763' });
  await f.clock.advanceTo(2300);
  assert.equal((await f.settled).error.message, failure.message);
  assert.equal(timeOf(f, 'current:start'), 0);
  assert.equal(timeOf(f, 'aws'), undefined);
  assert.equal(timeOf(f, 'current:abort'), 2300);
  assert.equal(timeOf(f, 'send:start'), undefined);
  assert.equal(timeOf(f, 'free-port'), undefined);
  assert.equal(timeOf(f, 'scratch'), undefined);
  assert.equal(timeOf(f, 'ssh'), undefined);
  assert.equal(f.clock.timers.size, 0);
  assert.equal(f.signals.listenerCount('SIGTERM'), 0);
});

test('valid but different CURRENT still blocks tunnel and both readiness branches', async () => {
  const f = fixture({ current: 'i-0a588ad747022bb9c' });
  await f.clock.advanceTo(2400);
  assert.equal((await f.settled).error.message, failure.message);
  assert.equal(timeOf(f, 'aws'), undefined);
  assert.equal(timeOf(f, 'listener:start'), undefined);
  assert.equal(timeOf(f, 'send:start'), undefined);
  assert.equal(timeOf(f, 'free-port'), undefined);
  assert.equal(timeOf(f, 'scratch'), undefined);
  assert.equal(timeOf(f, 'ssh'), undefined);
  assert.equal(f.clock.timers.size, 0);
  assert.equal(f.signals.listenerCount('SIGTERM'), 0);
});

test('validateRequest rejects an extra field before any command, timer or child', async () => {
  const f = fixture({ payload: { ...request, extra: true } });
  assert.equal((await f.settled).error.message, 'publication_failed');
  assert.deepEqual(f.events, []);
  assert.equal(f.clock.timers.size, 0);
  assert.equal(f.signals.listenerCount('SIGTERM'), 0);
});

test('invalid hostkey remains fail-closed and removes scratch without spawning SSH', async () => {
  const f = fixture({ key: 'invalid synthetic key' });
  await f.clock.advanceTo(7900);
  assert.equal((await f.settled).error.message, failure.message);
  assert.equal(timeOf(f, 'listener:done'), 6400);
  assert.equal(timeOf(f, 'scratch'), 7900);
  assert.equal(timeOf(f, 'known_hosts'), undefined);
  assert.equal(timeOf(f, 'ssh'), undefined);
  assert.equal(timeOf(f, 'rm'), 7900);
  clean(f);
});

const noOperationalWork = f => {
  for (const name of [
    'free-port',
    'aws',
    'listener:start',
    'send:start',
    'poll:start',
    'scratch',
    'known_hosts',
    'chmod',
    'ssh',
    'rm',
  ])
    assert.equal(timeOf(f, name), undefined, name);
  assert.deepEqual(f.children, []);
  assert.deepEqual(f.branches, []);
};

for (const first of ['sts', 'current']) {
  test(`${first} metadata success first waits for the other validation before operations`, async t => {
    const f = fixture({
      stsMs: first === 'sts' ? 1000 : 8000,
      currentMs: first === 'current' ? 1000 : 8000,
    });
    await f.clock.advanceTo(7999);
    assert.equal(timeOf(f, 'sts:start'), 0);
    assert.equal(timeOf(f, 'current:start'), 0);
    assert.equal(timeOf(f, `${first}:done`), 1000);
    noOperationalWork(f);
    const reads = f.operations;
    assert.equal(reads.length, 2);
    assert.equal(reads[0].options.signal, reads[1].options.signal);
    for (const read of reads) assert.equal(read.options.timeoutMs, 25000);
    await f.clock.advanceTo(8000);
    assert.equal(timeOf(f, 'free-port'), 8000);
    assert.equal(timeOf(f, 'aws'), 8000);
    await f.clock.advanceTo(14000);
    assert.deepEqual(await f.settled, { value: null, at: 14000 });
    clean(f);
    t.diagnostic(`SYNTHETIC METADATA BARRIER ${JSON.stringify(f.events)}`);
  });
}

for (const branch of ['sts', 'current']) {
  for (const rejection of ['throw', 'reject']) {
    test(`${branch} metadata ${rejection} aborts sibling and consumes its late rejection`, async () => {
      let rejectSibling;
      const seen = [];
      const f = fixture({
        overrides: {
          run: (command, args, options) => {
            assert.equal(command, 'aws');
            assert.ok(args.includes('--profile'));
            assert.ok(args.includes('hub2you'));
            const name = args.includes('get-caller-identity')
              ? 'sts'
              : 'current';
            seen.push({ name, options });
            if (name === branch) {
              if (rejection === 'throw')
                throw new Error('synthetic synchronous read failure');
              return Promise.reject(new Error('synthetic rejected read'));
            }
            return new Promise((_resolve, reject) => {
              rejectSibling = reject;
            });
          },
        },
      });
      await flush();
      assert.equal((await f.settled).error.message, failure.message);
      assert.deepEqual(
        seen.map(read => read.name),
        ['sts', 'current']
      );
      assert.equal(seen[0].options.signal, seen[1].options.signal);
      assert.equal(seen[0].options.signal.aborted, true);
      for (const read of seen) assert.equal(read.options.timeoutMs, 25000);
      noOperationalWork(f);
      rejectSibling(new Error('synthetic late sibling rejection'));
      await flush();
      await new Promise(resolve => {
        setImmediate(resolve);
      });
      clean(f);
    });
  }
  test(`${branch} delayed read failure cancels the other pending metadata read`, async () => {
    const f = fixture({
      stsMs: branch === 'sts' ? 1200 : null,
      currentMs: branch === 'current' ? 1200 : null,
      failAt: branch,
    });
    await f.clock.advanceTo(1199);
    noOperationalWork(f);
    assert.equal(f.outcome(), undefined);
    await f.clock.advanceTo(1200);
    assert.equal((await f.settled).error.message, failure.message);
    assert.equal(
      timeOf(f, `${branch === 'sts' ? 'current' : 'sts'}:abort`),
      1200
    );
    noOperationalWork(f);
    clean(f);
  });
}

for (const current of ['invalid-instance', 'i-0a588ad747022bb9c']) {
  test(`invalid CURRENT ${current} cancels pending account validation without operations`, async () => {
    const f = fixture({ stsMs: null, currentMs: 1000, current });
    await f.clock.advanceTo(1000);
    assert.equal((await f.settled).error.message, failure.message);
    assert.equal(timeOf(f, 'sts:abort'), 1000);
    noOperationalWork(f);
    clean(f);
  });
}

test('account mismatch after valid CURRENT still forbids every operational action', async () => {
  const f = fixture({ stsMs: 8000, currentMs: 1000, account: '140023375763' });
  await f.clock.advanceTo(7999);
  assert.equal(timeOf(f, 'current:done'), 1000);
  noOperationalWork(f);
  await f.clock.advanceTo(8000);
  assert.equal((await f.settled).error.message, failure.message);
  noOperationalWork(f);
  clean(f);
});

for (const completed of ['neither', 'sts', 'current']) {
  test(`metadata 25s deadline with ${completed} completed kills remaining reads`, async () => {
    const f = fixture({
      stsMs: completed === 'sts' ? 1000 : null,
      currentMs: completed === 'current' ? 1000 : null,
    });
    await f.clock.advanceTo(24999);
    assert.equal(f.outcome(), undefined);
    noOperationalWork(f);
    await f.clock.advanceTo(25000);
    assert.equal((await f.settled).error.message, failure.message);
    assert.equal(f.outcome().at, 25000);
    for (const read of f.operations)
      assert.equal(read.options.signal.aborted, true);
    noOperationalWork(f);
    clean(f);
  });
  for (const signal of ['SIGTERM', 'SIGINT']) {
    test(`${signal} during metadata with ${completed} completed cancels remaining reads`, async () => {
      const f = fixture({
        stsMs: completed === 'sts' ? 1000 : null,
        currentMs: completed === 'current' ? 1000 : null,
      });
      await f.clock.advanceTo(1500);
      f.signals.emit(signal);
      assert.equal((await f.settled).error.message, failure.message);
      assert.equal(f.outcome().at, 1500);
      for (const read of f.operations)
        assert.equal(read.options.signal.aborted, true);
      noOperationalWork(f);
      clean(f);
    });
  }
}

test('metadata deadline observes late success and rejection without restarting operations', async () => {
  const completions = [];
  const f = fixture({
    overrides: {
      run: (_command, _args, options) =>
        new Promise((resolve, reject) => {
          completions.push({ resolve, reject, options });
        }),
    },
  });
  await f.clock.advanceTo(25000);
  assert.equal((await f.settled).error.message, failure.message);
  assert.equal(completions.length, 2);
  completions[0].resolve('354307071110');
  completions[1].reject(new Error('synthetic late rejection after deadline'));
  await flush();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  noOperationalWork(f);
  clean(f);
});

for (const cancellation of [
  'sts',
  'current',
  'sts-throw',
  'current-throw',
  'deadline',
  'SIGTERM',
  'SIGINT',
]) {
  test(`real commandRunner with mocked AWS children leaves no live child on metadata ${cancellation}`, async () => {
    const awsChildren = [];
    let f;
    f = fixture({
      overrides: {
        run: (command, args, options) =>
          commandRunner(command, args, {
            ...options,
            spawnImpl: (childCommand, childArgs, childOptions) => {
              assert.equal(childCommand, 'aws');
              assert.equal(childOptions.shell, false);
              assert.deepEqual(childArgs.slice(0, 5), [
                '--profile',
                'hub2you',
                '--region',
                'us-east-1',
                '--no-cli-pager',
              ]);
              assert.ok(
                childArgs.includes('get-caller-identity') ||
                  childArgs.includes('get-parameter')
              );
              const name = childArgs.includes('get-caller-identity')
                ? 'sts'
                : 'current';
              if (cancellation === `${name}-throw`)
                throw new Error('synthetic synchronous AWS spawn failure');
              const child = new EventEmitter();
              child.stdout = new EventEmitter();
              child.stdin = { end: () => {} };
              child.live = true;
              child.kills = 0;
              child.kill = () => {
                child.live = false;
                child.kills += 1;
              };
              if (cancellation === name)
                f.clock.setTimeout(() => {
                  child.live = false;
                  child.emit('close', 1);
                }, 1200);
              awsChildren.push({ name, child, options });
              return child;
            },
          }),
      },
    });
    await f.clock.advanceTo(cancellation === 'deadline' ? 25000 : 1200);
    if (cancellation.startsWith('SIG')) f.signals.emit(cancellation);
    assert.equal((await f.settled).error.message, failure.message);
    assert.equal(awsChildren.length, cancellation.endsWith('-throw') ? 1 : 2);
    for (const { name, child, options } of awsChildren) {
      assert.equal(child.live, false);
      assert.equal(child.kills, cancellation === name ? 0 : 1);
      assert.equal(options.signal.aborted, true);
      assert.equal(getEventListeners(options.signal, 'abort').length, 0);
      child.emit('close', 1);
      child.emit('error', new Error('synthetic late child error'));
    }
    await flush();
    noOperationalWork(f);
    clean(f);
  });
}

test('slow metadata does not reset the 25s deadline for readiness', async () => {
  const f = fixture({ stsMs: 24000, currentMs: 23000 });
  await f.clock.advanceTo(23999);
  noOperationalWork(f);
  await f.clock.advanceTo(24000);
  assert.equal(timeOf(f, 'aws'), 24000);
  const listener = f.operations.find(op => op.name === 'listener');
  assert.equal(listener.options.deadline, 25000);
  assert.equal(listener.options.timeoutMs, 1000);
  const send = f.operations.find(op => op.name === 'send');
  assert.equal(send.options.timeoutMs, 1000);
  await f.clock.advanceTo(25000);
  assert.equal((await f.settled).error.message, failure.message);
  assert.equal(f.outcome().at, 25000);
  assert.equal(timeOf(f, 'listener:abort'), 25000);
  assert.equal(timeOf(f, 'send:abort'), 25000);
  assert.equal(timeOf(f, 'scratch'), undefined);
  assert.equal(timeOf(f, 'ssh'), undefined);
  clean(f);
});
