/* eslint-disable no-await-in-loop, no-continue -- Explicit operator requests are processed sequentially. */
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import {
  publisher,
  deadlineScope,
  pause,
  observerConfiguration,
} from '../session-manager.mjs';
import { parseEnvelope } from './operator-protocol.mjs';

const POLL_MS = 30000;
const BROWSER = fileURLToPath(
  new URL('../session-browser.mjs', import.meta.url)
);
const MANAGER = fileURLToPath(
  new URL('../session-manager.mjs', import.meta.url)
);

export function runtimeChild(
  script,
  env,
  signal,
  { spawnImpl = spawn, clock = globalThis } = {}
) {
  return new Promise((done, reject) => {
    if (signal.aborted) {
      done(143);
      return;
    }
    const child = spawnImpl(process.execPath, [script], {
      shell: false,
      env,
      stdio: 'ignore',
      detached: true,
    });
    let settled = false;
    let timer;
    let stop;
    const finish = (error, code) => {
      if (settled) return;
      settled = true;
      clock.clearTimeout(timer);
      signal.removeEventListener('abort', stop);
      if (error) reject(new Error('operator_runtime_failed'));
      else done(code);
    };
    const kill = type => {
      try {
        if (child.pid) process.kill(-child.pid, type);
        else child.kill(type);
      } catch {
        child.kill(type);
      }
    };
    stop = () => {
      kill('SIGTERM');
      timer = clock.setTimeout(() => {
        kill('SIGKILL');
        finish(null, 143);
      }, 28000);
    };
    signal.addEventListener('abort', stop, { once: true });
    child.once('error', () => finish(true));
    child.once('exit', code => finish(null, code ?? 1));
    if (signal.aborted) stop();
  });
}

export async function runWaiter(
  env = process.env,
  {
    publish = publisher,
    child = runtimeChild,
    signals = process,
    sleep = pause,
    clock = globalThis,
    stderr = process.stderr,
    now = Date.now,
  } = {}
) {
  const command = JSON.parse(
    env.INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON || 'null'
  );
  const shutdown = new AbortController();
  const stop = () => shutdown.abort(new Error('operator_stopped'));
  signals.once('SIGTERM', stop);
  signals.once('SIGINT', stop);
  let activeId;
  let offline = false;
  const send = async (payload, signal = shutdown.signal) => {
    const scope = deadlineScope(signal, clock);
    try {
      const result = parseEnvelope(
        JSON.stringify(
          await scope.wait(
            publish(
              command,
              { type: 'operator', ...payload },
              { signal: scope.signal, clock }
            )
          )
        ),
        'operator'
      );
      if (
        payload.operation === 'manager_heartbeat' &&
        (result.manager?.state !== payload.state ||
          result.manager.control_available !== payload.control_available)
      )
        throw new Error('publication_failed');
      return result;
    } finally {
      scope.close();
    }
  };
  const trackedChild = async (script, childEnv, request) => {
    const budget = Date.parse(request.created_at) + 3600000 - now();
    if (budget <= 0) throw new Error('operator_runtime_failed');
    const scope = deadlineScope(shutdown.signal, clock, budget);
    let renewing = true;
    const renew = (async () => {
      while (!scope.signal.aborted && renewing) {
        await pause(POLL_MS, scope.signal, clock);
        if (scope.signal.aborted || !renewing) break;
        try {
          await send(
            {
              operation: 'manager_heartbeat',
              state: 'operator_required',
              control_available: false,
              request_id: activeId,
            },
            scope.signal
          );
        } catch {
          // A successful publication ends the lease; distinguish its receipt from a lost lease.
          const status = await send(
            { operation: 'operator_read' },
            scope.signal
          );
          if (
            status.request?.id === activeId &&
            status.request.state === 'succeeded'
          )
            break;
          throw new Error('operator_runtime_failed');
        }
      }
    })().catch(() => {
      scope.close();
    });
    try {
      return await scope.wait(child(script, childEnv, scope.signal));
    } finally {
      renewing = false;
      scope.close();
      await renew;
    }
  };
  try {
    while (!shutdown.signal.aborted) {
      let status;
      try {
        status = await send({
          operation: 'manager_heartbeat',
          state: 'operator_required',
          control_available: true,
        });
        offline = false;
      } catch {
        if (shutdown.signal.aborted) break;
        if (!offline)
          stderr.write(
            'instagram_control_offline: start/check the dedicated waiter transport on its runtime host; no browser was opened and no recovery is confirmed.\n'
          );
        offline = true;
        await sleep(POLL_MS, shutdown.signal, clock).catch(() => {});
        continue;
      }
      if (status.request?.state !== 'queued') {
        await sleep(POLL_MS, shutdown.signal, clock).catch(() => {});
        continue;
      }
      const request = status.request;
      activeId = request.id; // Set before claim: its transport response can be lost after a real claim.
      try {
        const claimed = await send({
          operation: 'operator_claim',
          id: activeId,
        });
        if (
          claimed.request?.id !== activeId ||
          claimed.request.state !== 'running'
        )
          throw new Error('publication_failed');
        await send({
          operation: 'manager_heartbeat',
          state: 'operator_required',
          control_available: false,
          request_id: activeId,
        });
        const scope = deadlineScope(shutdown.signal, clock);
        let bootstrap;
        try {
          bootstrap = parseEnvelope(
            JSON.stringify(
              await scope.wait(
                publish(
                  command,
                  { type: 'session', operation: 'bootstrap' },
                  { signal: scope.signal, clock }
                )
              )
            ),
            'bootstrap'
          );
        } finally {
          scope.close();
        }
        observerConfiguration(env, bootstrap); // Validate proxy without changing its authentication policy.
        // Bootstrap can consume a transport budget. Renew before starting the human browser.
        await send({
          operation: 'manager_heartbeat',
          state: 'operator_required',
          control_available: false,
          request_id: activeId,
        });
        const browserEnv = { ...env, ...bootstrap.metadata };
        delete browserEnv.INSTAGRAM_TESTER_RECONNECT_REQUEST_ID;
        let code = await trackedChild(BROWSER, browserEnv, request);
        if (shutdown.signal.aborted) break;
        if (code === 0)
          code = await trackedChild(
            MANAGER,
            { ...browserEnv, INSTAGRAM_TESTER_RECONNECT_REQUEST_ID: activeId },
            request
          );
        if (shutdown.signal.aborted) break;
        const current = await send({ operation: 'operator_read' });
        if (
          current.request?.id === activeId &&
          current.request.state === 'succeeded' &&
          code === 0
        ) {
          activeId = undefined;
          return;
        }
        await send({
          operation: 'operator_complete',
          id: activeId,
          state: code === 2 ? 'operator_required' : 'failed',
        });
        activeId = undefined;
      } catch {
        if (shutdown.signal.aborted) break;
        throw new Error('operator_runtime_failed');
      }
    }
  } finally {
    if (activeId) {
      // Independent bounded cleanup even after cancellation. If offline, the 90s claim lease still expires.
      await send(
        { operation: 'operator_complete', id: activeId, state: 'failed' },
        null
      ).catch(() => {});
    }
    signals.removeListener('SIGTERM', stop);
    signals.removeListener('SIGINT', stop);
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  runWaiter().catch(() => {
    process.stderr.write('instagram_operator_waiter_failed\n');
    process.exitCode = 1;
  });
}
