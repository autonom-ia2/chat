/* eslint-disable no-await-in-loop, no-continue -- Explicit operator requests are processed sequentially. */
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { isMainModule } from './entrypoint.mjs';
import {
  publisher,
  deadlineScope,
  pause,
  observerConfiguration,
} from '../session-manager.mjs';
import { parseEnvelope } from './operator-protocol.mjs';

const POLL_MS = 30000;
const TRANSPORT_MS = 30000;
const LEASE_MARGIN_MS = 5000;
const MIN_RENEW_WAIT_MS = 1000;
const REQUEST_BUDGET_MS = 3600000;
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
      if (signal.aborted) done(143);
      else if (error) reject(new Error('operator_runtime_failed'));
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
    const scope = deadlineScope(signal, clock, TRANSPORT_MS, now);
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
  const supervise = request => {
    const budget = Date.parse(request.created_at) + REQUEST_BUDGET_MS - now();
    if (budget <= 0) throw new Error('operator_runtime_failed');
    const scope = deadlineScope(shutdown.signal, clock, budget, now);
    const children = new AbortController();
    const stopChildren = () => children.abort(scope.signal.reason);
    scope.signal.addEventListener('abort', stopChildren, { once: true });
    let expiry;
    let expiresAt;
    let renewing;
    let succeeded = false;
    const confirm = status => {
      if (succeeded) return;
      scope.signal.throwIfAborted();
      const current = status.request;
      if (current?.id !== request.id)
        throw new Error('operator_runtime_failed');
      if (current.state === 'succeeded') {
        succeeded = true; // Only the publisher can produce this receipt. Never replay publication.
        clock.clearTimeout(expiry);
        children.abort();
        return;
      }
      expiresAt = Math.min(
        Date.parse(current.expires_at),
        Date.parse(request.created_at) + REQUEST_BUDGET_MS
      );
      const remaining = expiresAt - now();
      if (current.state !== 'running' || remaining <= 0)
        throw new Error('operator_runtime_failed');
      clock.clearTimeout(expiry);
      expiry = clock.setTimeout(() => scope.close(), remaining);
    };
    const reconcile = async () =>
      confirm(await send({ operation: 'operator_read' }, scope.signal));
    const heartbeat = async () => {
      try {
        confirm(
          await send(
            {
              operation: 'manager_heartbeat',
              state: 'operator_required',
              control_available: false,
              request_id: request.id,
            },
            scope.signal
          )
        );
      } catch {
        if (succeeded) return;
        scope.signal.throwIfAborted();
        // A lost reply can hide a renewal or a real publication. Only a read can resolve it.
        await reconcile();
      }
    };
    return {
      scope,
      confirm,
      reconcile,
      get succeeded() {
        return succeeded;
      },
      start: async () => {
        await heartbeat();
        renewing = (async () => {
          while (!scope.signal.aborted && !succeeded) {
            const wait = Math.max(
              MIN_RENEW_WAIT_MS,
              Math.min(
                POLL_MS,
                expiresAt - now() - 2 * TRANSPORT_MS - LEASE_MARGIN_MS
              )
            );
            await pause(wait, scope.signal, clock);
            if (scope.signal.aborted || succeeded) break;
            await heartbeat();
          }
        })().catch(() => {
          // Closing a completed supervision also cancels its pending pause.
          if (!succeeded && !scope.signal.aborted) scope.close();
        });
      },
      child: async (script, childEnv) => {
        scope.signal.throwIfAborted();
        let code;
        try {
          // Await process drainage even when the lease or a real success cancels it.
          code = await child(script, childEnv, children.signal);
        } catch (error) {
          if (!succeeded || !children.signal.aborted) throw error;
        }
        if (succeeded) return 0;
        scope.signal.throwIfAborted();
        return code;
      },
      close: async () => {
        scope.close();
        clock.clearTimeout(expiry);
        await renewing;
        scope.signal.removeEventListener('abort', stopChildren);
      },
    };
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
      const lease = supervise(request);
      try {
        try {
          lease.confirm(
            await send(
              { operation: 'operator_claim', id: activeId },
              lease.scope.signal
            )
          );
        } catch {
          lease.scope.signal.throwIfAborted();
          await lease.reconcile();
        }
        if (lease.succeeded) {
          activeId = undefined;
          return;
        }
        await lease.start();
        if (lease.succeeded) {
          activeId = undefined;
          return;
        }
        const scope = deadlineScope(
          lease.scope.signal,
          clock,
          TRANSPORT_MS,
          now
        );
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
        const browserEnv = { ...env, ...bootstrap.metadata };
        delete browserEnv.INSTAGRAM_TESTER_RECONNECT_REQUEST_ID;
        if (env.INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE) {
          browserEnv.INSTAGRAM_TESTER_OPERATOR_REQUEST_ID = activeId;
          browserEnv.INSTAGRAM_TESTER_OPERATOR_REQUEST_DEADLINE = String(
            Math.floor(Date.parse(request.created_at) / 1000) + 3600
          );
        }
        let code = lease.succeeded ? 0 : await lease.child(BROWSER, browserEnv);
        if (shutdown.signal.aborted && !lease.succeeded) break;
        if (code === 0 && !lease.succeeded)
          code = await lease.child(MANAGER, {
            ...browserEnv,
            INSTAGRAM_TESTER_RECONNECT_REQUEST_ID: activeId,
          });
        if (shutdown.signal.aborted && !lease.succeeded) break;
        if (!lease.succeeded) await lease.reconcile();
        if (lease.succeeded) {
          activeId = undefined;
          return;
        }
        await send(
          {
            operation: 'operator_complete',
            id: activeId,
            state: code === 2 ? 'operator_required' : 'failed',
          },
          lease.scope.signal
        );
        activeId = undefined;
      } catch {
        if (lease.succeeded) {
          activeId = undefined;
          return;
        }
        if (shutdown.signal.aborted) break;
        throw new Error('operator_runtime_failed');
      } finally {
        await lease.close();
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

if (isMainModule(import.meta.url)) {
  runWaiter().catch(() => {
    process.stderr.write('instagram_operator_waiter_failed\n');
    process.exitCode = 1;
  });
}
