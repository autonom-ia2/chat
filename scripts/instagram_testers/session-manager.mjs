/* eslint-disable no-await-in-loop, no-restricted-syntax -- Node operational steps and refresh cycles must run sequentially. */
/* eslint-disable no-bitwise, no-control-regex -- Check filesystem permission bits and reject control characters at the process boundary. */
import { mkdir, lstat, open, unlink } from 'node:fs/promises';
import { resolve, dirname, isAbsolute, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { isMainModule } from './runtime/entrypoint.mjs';
import {
  executeBrowserOperation,
  createWarmMetaPage,
  acceptFreshRolesResponse,
} from './browser-operations.mjs';
import {
  parseEnvelope,
  validateRequest,
} from './runtime/operator-protocol.mjs';
import {
  configuration,
  proxyConfiguration,
  observedSession,
  loadingQueryFields,
  rolesQueryFields,
  safeBrowserLocation,
  validateRolesResponse,
} from './session-observer.mjs';

const CYCLE_BUDGET_MS = 30000;
const REFRESH_INTERVAL_MS = 900000;
const BROWSER_OPERATION_POLL_MS = 250;
const BROWSER_OPERATION_BUDGET_MS = 120000;
// Mirrors Rails BrowserOperationStore::CLAIM_TTL (120 s). Rails starts its
// claim window after it receives the claim, so the VPS window is never longer.
const CLAIM_WINDOW_MS = 120000;
// One completion publish (CYCLE_BUDGET_MS) plus 5 s of margin, which also
// absorbs small clock skew against the request's absolute deadline.
const COMPLETION_RESERVE_MS = 35000;

function writeBrowserOperationDiagnostic(stderr, diagnostic) {
  try {
    stderr.write(`${JSON.stringify(diagnostic)}\n`);
  } catch {
    // Diagnostics must not change the operation's terminal observation.
  }
}

export function cancellable(promise, signal) {
  return new Promise((done, reject) => {
    const abort = () => {
      signal.removeEventListener('abort', abort);
      reject(signal.reason);
    };
    signal.addEventListener('abort', abort, { once: true });
    Promise.resolve(promise).then(
      value => {
        signal.removeEventListener('abort', abort);
        if (signal.aborted) reject(signal.reason);
        else done(value);
      },
      error => {
        signal.removeEventListener('abort', abort);
        reject(error);
      }
    );
    if (signal.aborted) abort();
  });
}

export function pause(ms, signal, clock = globalThis) {
  let timer;
  return cancellable(
    new Promise(done => {
      timer = clock.setTimeout(done, ms);
    }),
    signal
  ).finally(() => clock.clearTimeout(timer));
}

// Reuse one deadline/cancellation primitive for setup, cycles, waiter transport and cleanup.
export function deadlineScope(
  signal,
  clock = globalThis,
  budgetMs = CYCLE_BUDGET_MS,
  now = Date.now
) {
  const deadline = now() + budgetMs;
  const controller = new AbortController();
  const cancel = () =>
    controller.abort(signal?.reason || new Error('operation_cancelled'));
  signal?.addEventListener('abort', cancel, { once: true });
  if (signal?.aborted) cancel();
  const timer = clock.setTimeout(
    () => controller.abort(new Error('operation_timeout')),
    budgetMs
  );
  return {
    signal: controller.signal,
    remaining: () => Math.max(1, deadline - now()),
    wait: promise => cancellable(promise, controller.signal),
    close: () => {
      controller.abort(new Error('operation_finished'));
      clock.clearTimeout(timer);
      signal?.removeEventListener('abort', cancel);
    },
  };
}

export function observerConfiguration(env, bootstrap) {
  const value = parseEnvelope(JSON.stringify(bootstrap), 'bootstrap');
  // Only the proxy/runtime settings come from local ENV; canonical IDs overwrite stale IDs.
  return configuration({ ...env, ...value.metadata });
}

export function chromiumSandbox(env) {
  const value = env.INSTAGRAM_TESTER_CHROMIUM_SANDBOX;
  if (value !== undefined && !['true', 'false'].includes(value))
    throw new Error('browser_runtime_required');
  if (env.INSTAGRAM_TESTER_RUNTIME_MODE === 'vps' && value !== 'true')
    throw new Error('browser_runtime_required');
  return value === 'true';
}

export function managerCycleBudget(env) {
  const mode = env.INSTAGRAM_TESTER_RUNTIME_MODE;
  if (mode === 'vps') return 120000;
  if (mode !== undefined && mode !== '')
    throw new Error('browser_runtime_required');
  return CYCLE_BUDGET_MS;
}

export function browserEnvironment(env) {
  // Browser children do not need Rails/AWS/proxy secrets or protocol tracing.
  const keys = [
    'PATH',
    'HOME',
    'TMPDIR',
    'TEMP',
    'TMP',
    'DISPLAY',
    'XAUTHORITY',
    'WAYLAND_DISPLAY',
    'XDG_RUNTIME_DIR',
    'LANG',
  ];
  return Object.fromEntries(
    keys.filter(key => env[key] !== undefined).map(key => [key, env[key]])
  );
}

export async function privateProfile(path) {
  if (!path || !isAbsolute(path)) throw new Error('private_profile_required');
  const target = resolve(path);
  const ancestors = [];
  for (
    let current = target;
    current !== dirname(current);
    current = dirname(current)
  )
    ancestors.unshift(current);
  for (const current of ancestors) {
    try {
      const info = await lstat(current);
      if (info.isSymbolicLink() || !info.isDirectory())
        throw new Error('private_profile_required');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      await mkdir(current, { mode: 0o700 });
    }
    try {
      await lstat(join(current, '.git'));
      throw new Error('private_profile_required');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  const info = await lstat(target);
  if (info.uid !== process.getuid() || (info.mode & 0o077) !== 0)
    throw new Error('private_profile_required');
  return target;
}

export function publisher(
  command,
  payload,
  { signal, spawnImpl = spawn, clock = globalThis } = {}
) {
  validateRequest(payload);
  return new Promise((done, reject) => {
    if (
      !Array.isArray(command) ||
      !command.length ||
      !command.every(
        value =>
          typeof value === 'string' &&
          value.length &&
          !['\0', '\r', '\n'].some(character => value.includes(character))
      )
    ) {
      reject(new Error('publisher_required'));
      return;
    }
    if (signal?.aborted) {
      reject(signal.reason);
      return;
    }
    // Captured fields travel only through stdin. Cancellation reaches the
    // transport child, which closes its own SSM/SSH children on SIGTERM.
    const child = spawnImpl(command[0], command.slice(1), {
      stdio: ['pipe', 'pipe', 'ignore'],
      shell: false,
    });
    const chunks = [];
    let outputBytes = 0;
    let settled = false;
    let timer;
    let abort;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clock.clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      if (error) reject(error);
      else done(value);
    };
    abort = () => {
      child.kill('SIGTERM');
      finish(signal?.reason || new Error('publication_failed'));
    };
    signal?.addEventListener('abort', abort, { once: true });
    timer = clock.setTimeout(abort, CYCLE_BUDGET_MS);
    child.stdout.on('data', chunk => {
      if (settled) return;
      const buffer = Buffer.from(chunk);
      outputBytes += buffer.length;
      if (outputBytes > 1024) {
        child.kill('SIGTERM');
        finish(new Error('publication_failed'));
        return;
      }
      chunks.push(buffer);
    });
    child.once('error', () => finish(new Error('publication_failed')));
    child.stdin.on('error', () => {
      child.kill('SIGTERM');
      finish(new Error('publication_failed'));
    });
    child.once('close', code => {
      try {
        if (code !== 0) throw new Error();
        const result = parseEnvelope(
          Buffer.concat(chunks, outputBytes).toString('utf8'),
          payload.operation === 'bootstrap' ? 'bootstrap' : payload.type
        );
        finish(null, result.type === 'session' ? result.version : result);
      } catch {
        finish(new Error('publication_failed'));
      }
    });
    child.stdin.end(JSON.stringify(payload));
  });
}

export function isAllowedBrowserRequest({
  url: requestUrl,
  method,
  body = '',
  config,
}) {
  let url;
  try {
    url = new URL(requestUrl);
  } catch {
    return false;
  }
  const trusted =
    url.protocol === 'https:' &&
    ['facebook.com', 'fbcdn.net'].some(
      host => url.hostname === host || url.hostname.endsWith(`.${host}`)
    );
  if (!trusted || url.pathname.includes('/roles/add/')) return false;
  if (method === 'GET' || method === 'HEAD') return true;
  if (
    method !== 'POST' ||
    url.origin !== 'https://developers.facebook.com' ||
    url.pathname !== '/api/graphql/' ||
    url.search !== '' ||
    url.hash !== ''
  )
    return false;
  try {
    return (
      rolesQueryFields(body, config) !== null ||
      loadingQueryFields(body, config) !== null
    );
  } catch {
    return false;
  }
}

export async function handleBrowserRoute(route, config, stderr) {
  try {
    const request = route.request();
    if (
      !isAllowedBrowserRequest({
        url: request.url(),
        method: request.method(),
        body: request.postData() || '',
        config,
      })
    ) {
      await route.abort();
    } else {
      await route.continue();
    }
  } catch (error) {
    // Playwright has already completed these routes; a second abort cannot help.
    // For other failures, close the request instead of permitting it.
    if (!error.message?.includes('Route is already handled'))
      await route.abort().catch(() => {});
    writeBrowserOperationDiagnostic(stderr, {
      event: 'instagram_browser_route_failed',
    });
  }
}

export async function run(
  env = process.env,
  {
    publish = publisher,
    loadRuntime = path => import(pathToFileURL(path)),
    signals = process,
    clock = globalThis,
    now = Date.now,
    stdout = process.stdout,
    stderr = process.stderr,
    files = { privateProfile, open, unlink },
    executeOperation = executeBrowserOperation,
  } = {}
) {
  let config;
  const proxy = proxyConfiguration(env);
  const cycleBudget = managerCycleBudget(env);
  const browserOperationsEnabled =
    env.INSTAGRAM_TESTER_RUNTIME_MODE === 'vps' &&
    env.INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED === 'true';
  // 13 minutes asleep + a bounded 2-minute cycle fits the backend's 16-minute heartbeat TTL.
  // Legacy runtimes retain the original 15-minute pause and 30-second cycle.
  const refreshInterval =
    env.INSTAGRAM_TESTER_RUNTIME_MODE === 'vps' ? 780000 : REFRESH_INTERVAL_MS;
  const command = JSON.parse(
    env.INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON || 'null'
  );
  let lockPath;
  let lock;
  let context;
  let warmMetaPage = null;
  let unhealthy = null;
  const operatorState = { required: false };
  const reconnect = { id: env.INSTAGRAM_TESTER_RECONNECT_REQUEST_ID };
  const shutdown = new AbortController();
  const stop = () => shutdown.abort(new Error('manager_stopped'));
  signals.once('SIGTERM', stop);
  signals.once('SIGINT', stop);
  const setup = deadlineScope(shutdown.signal, clock, CYCLE_BUDGET_MS, now);
  try {
    const profile = await setup.wait(
      files.privateProfile(env.INSTAGRAM_TESTER_BROWSER_PROFILE)
    );
    lockPath = join(profile, '.instagram-manager.lock');
    lock = await setup.wait(files.open(lockPath, 'wx', 0o600));
    if (
      !env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE ||
      !isAbsolute(env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE)
    )
      throw new Error('browser_runtime_required');
    delete process.env.DEBUG;
    delete process.env.PWDEBUG;
    const runtime = await setup.wait(
      loadRuntime(env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE)
    );
    context = await setup.wait(
      runtime.chromium
        .launchPersistentContext(profile, {
          channel: 'chrome',
          headless: true,
          chromiumSandbox: chromiumSandbox(env),
          timeout: setup.remaining(),
          env: browserEnvironment(env),
          proxy: {
            server: `http://${proxy.host}:${Number(proxy.port)}`,
          },
          acceptDownloads: false,
          serviceWorkers: 'block',
          ignoreHTTPSErrors: false,
        })
        .then(value => {
          if (setup.signal.aborted) {
            value.close().catch(() => {});
            throw new Error('operation_cancelled');
          }
          return value;
        })
    );
    const page = context.pages()[0] || (await setup.wait(context.newPage()));
    for (const other of context.pages())
      if (other !== page) await setup.wait(other.close());
    context.on('page', other => {
      other.close().catch(() => {});
    });
    // The default guard stays in place; the operation executor permits only
    // its reviewed natural typeahead request on the primary page.
    await setup.wait(
      context.route('**/*', route => handleBrowserRoute(route, config, stderr))
    );
    setup.close();
    while (!shutdown.signal.aborted) {
      warmMetaPage?.dispose();
      warmMetaPage = null;
      const cycle = deadlineScope(shutdown.signal, clock, cycleBudget);
      const wait = cycle.wait;
      const send = payload => {
        cycle.signal.throwIfAborted();
        return wait(publish(command, payload, { signal: cycle.signal, clock }));
      };
      let publication = null;
      let warmObservation = null;
      let accepting = true;
      let observe;
      try {
        // Version is part of the recoverable cycle and is opaque to this client.
        const bootstrap = await send({
          type: 'session',
          operation: 'bootstrap',
        });
        const cycleConfig = observerConfiguration(env, bootstrap);
        config = cycleConfig;
        const expectedVersion = bootstrap.version;
        const capturedAt = new Date(now()).toISOString();
        let operatorStop;
        const requireOperator = () => {
          if (!operatorStop) {
            operatorState.required = true;
            operatorStop = (async () => {
              await send({
                type: 'operator',
                operation: 'manager_heartbeat',
                state: 'operator_required',
                control_available: false,
              }).catch(() => {});
              throw new Error('operator_required');
            })();
          }
          return operatorStop;
        };
        observe = response => {
          if (
            !accepting ||
            cycle.signal.aborted ||
            publication ||
            response.url() !== 'https://developers.facebook.com/api/graphql/'
          )
            return;
          const request = response.request();
          if (
            request.url() !== 'https://developers.facebook.com/api/graphql/' ||
            request.method() !== 'POST'
          )
            return;
          // Loading responses must never reserve the slot for a roles capture.
          try {
            if (!rolesQueryFields(request.postData() || '', cycleConfig))
              return;
          } catch {
            return;
          }
          publication = (async () => {
            const headers = await wait(request.allHeaders());
            cycle.signal.throwIfAborted();
            const session = observedSession(
              {
                url: request.url(),
                method: request.method(),
                headers,
                body: request.postData(),
              },
              cycleConfig
            );
            if (!session) {
              publication = null;
              return false;
            }
            if ([401, 403].includes(response.status())) await requireOperator();
            if (response.status() !== 200)
              throw new Error('session_update_rejected');
            const rolesResponse = await wait(response.text());
            cycle.signal.throwIfAborted();
            validateRolesResponse(rolesResponse);
            if (!safeBrowserLocation(page.url(), cycleConfig))
              await requireOperator();
            await send({
              type: 'session',
              operation: 'publish',
              ...(reconnect.id ? { request_id: reconnect.id } : {}),
              session,
              expected_version: expectedVersion,
              configuration_revision: bootstrap.revision,
              roles_doc_id: cycleConfig.docId,
              captured_at: capturedAt,
              app_id: cycleConfig.appId,
              business_id: cycleConfig.businessId,
              proxy_fingerprint: cycleConfig.proxyFingerprint,
              roles_response: rolesResponse,
            });
            warmObservation = {
              page,
              configuration: cycleConfig,
              request,
              response,
              body: rolesResponse,
              source: 'manager_refresh',
            };
            reconnect.id = undefined;
            return true;
          })();
          publication.catch(() => {});
        };
        page.on('response', observe);
        const navigation = await wait(
          page.goto(cycleConfig.rolesUrl, {
            waitUntil: 'domcontentloaded',
            timeout: CYCLE_BUDGET_MS,
          })
        );
        if (
          !safeBrowserLocation(page.url(), cycleConfig) ||
          [401, 403].includes(navigation?.status())
        )
          await requireOperator();
        while (!publication) await pause(100, cycle.signal, clock);
        accepting = false;
        if (!(await wait(publication)))
          throw new Error('session_update_rejected');
        if (browserOperationsEnabled) {
          // Prime only after the real publication CAS and completed navigation.
          // Every operation still captures a new RolesTable response.
          warmMetaPage = createWarmMetaPage({
            page,
            configuration: cycleConfig,
            now,
          });
          acceptFreshRolesResponse(warmMetaPage, warmObservation);
        }
        warmObservation = null;
        await send({
          type: 'operator',
          operation: 'manager_heartbeat',
          state: 'healthy',
          control_available: false,
        });
        if (unhealthy) stdout.write('instagram_session_recovered\n');
        unhealthy = null;
        // Recovery is a bounded child: the wrapper starts continuous refresh only after its real CAS receipt.
        if (env.INSTAGRAM_TESTER_RECONNECT_REQUEST_ID) return;
      } catch (error) {
        warmMetaPage?.dispose();
        warmMetaPage = null;
        if (shutdown.signal.aborted) break;
        const code =
          operatorState.required || error.message === 'operator_required'
            ? 'operator_required'
            : 'session_update_rejected';
        if (unhealthy !== code) stderr.write(`instagram_session_${code}\n`);
        unhealthy = code;
        if (code === 'operator_required') {
          operatorState.required = true;
          break;
        }
        if (!cycle.signal.aborted)
          await send({
            type: 'operator',
            operation: 'manager_heartbeat',
            state: 'failed',
            control_available: false,
          }).catch(() => {});
        if (reconnect.id) throw new Error('session_update_rejected');
      } finally {
        accepting = false;
        warmObservation = null;
        if (observe) page.off('response', observe);
        // Release pending headers/body/publication; never await them in cleanup.
        cycle.close();
      }
      // Browser operations run serially between refreshes. They never share
      // a live publication observer or the human reconnect queue.
      const refreshDue = now() + refreshInterval;
      while (!shutdown.signal.aborted && now() < refreshDue) {
        if (!browserOperationsEnabled || unhealthy) {
          await pause(refreshDue - now(), shutdown.signal, clock).catch(
            () => {}
          );
          break;
        }
        // Reserve the existing refresh window instead of extending the
        // manager heartbeat past its backend TTL with a late operation.
        if (refreshDue - now() <= BROWSER_OPERATION_BUDGET_MS) break;
        const operationScope = deadlineScope(
          shutdown.signal,
          clock,
          BROWSER_OPERATION_BUDGET_MS,
          now
        );
        const operationConfig = config;
        let executionPending = false;
        const diagnostic = {
          event: 'instagram_browser_operation_lifecycle',
          phase: 'read_requested',
          read_received: false,
          request_present: false,
          claim_received: false,
          execution_started: false,
          execution_returned: false,
          complete_requested: false,
          complete_received: false,
          executor_error_returned: false,
        };
        try {
          const sendOperation = payload =>
            operationScope.wait(
              publish(command, payload, {
                signal: operationScope.signal,
                clock,
              })
            );
          const envelope = await sendOperation({
            type: 'browser_operation',
            operation: 'read',
          });
          diagnostic.read_received = true;
          diagnostic.phase = 'read_received';
          if (envelope.request) {
            diagnostic.request_present = true;
            diagnostic.phase = 'claim_requested';
            const claimStartedAt = now();
            const claimed = await sendOperation({
              type: 'browser_operation',
              operation: 'claim',
              id: envelope.request.id,
              request_id: envelope.request.request_id,
            });
            diagnostic.claim_received = true;
            diagnostic.phase = 'claim_received';
            if (
              [
                'id',
                'request_id',
                'action',
                'app_id',
                'username',
                'target_id',
                'deadline',
              ].some(key => claimed.request[key] !== envelope.request[key])
            )
              throw new Error('publication_failed');
            executionPending = true;
            diagnostic.execution_started = true;
            diagnostic.phase = 'execute_started';
            // The executor must finish early enough for its completion
            // publish to land inside the operation scope, the claim window and
            // the request deadline.
            const requestDeadline = Date.parse(claimed.request.deadline);
            const executionBudgetMs =
              Math.min(
                operationScope.remaining(),
                claimStartedAt + CLAIM_WINDOW_MS - now(),
                Number.isNaN(requestDeadline) ? 0 : requestDeadline - Date.now()
              ) - COMPLETION_RESERVE_MS;
            const deadlineAt = now() + executionBudgetMs;
            const executionScope = deadlineScope(
              operationScope.signal,
              clock,
              Math.max(1, executionBudgetMs),
              now
            );
            let executionTimedOut = false;
            let result;
            try {
              result = await operationScope.wait(
                executeOperation({
                  context,
                  page,
                  configuration: operationConfig,
                  warmMetaPage,
                  request: claimed.request,
                  signal: executionScope.signal,
                  deadlineAt,
                  now,
                  onDiagnostic: observation =>
                    writeBrowserOperationDiagnostic(stderr, observation),
                  permitInvite: async (observation, { timeoutMs } = {}) => {
                    if (
                      observation?.target_id !== claimed.request.target_id ||
                      observation?.username !== claimed.request.username ||
                      observation?.status !== 'absent' ||
                      !Number.isFinite(timeoutMs) ||
                      timeoutMs <= 0
                    )
                      throw new Error('publication_failed');
                    // The permit has its own deadline. Its abort tears down
                    // this publish, and the publish promise is awaited to the
                    // end so the completion can use the publisher afterwards.
                    const permitScope = deadlineScope(
                      operationScope.signal,
                      clock,
                      timeoutMs,
                      now
                    );
                    try {
                      const permit = await publish(
                        command,
                        {
                          type: 'browser_operation',
                          operation: 'invite_permit',
                          id: claimed.request.id,
                          request_id: claimed.request.request_id,
                          claim: claimed.request.claim,
                          captured_at: observation.captured_at,
                          target_id: claimed.request.target_id,
                          username: claimed.request.username,
                          status: 'absent',
                        },
                        { signal: permitScope.signal, clock }
                      );
                      if (
                        permit.operation !== 'invite_permit' ||
                        ['id', 'request_id', 'claim'].some(
                          key => permit[key] !== claimed.request[key]
                        )
                      )
                        throw new Error('publication_failed');
                      return permit;
                    } finally {
                      permitScope.close();
                    }
                  },
                  requestGuard: request =>
                    isAllowedBrowserRequest({
                      ...request,
                      config: operationConfig,
                    }),
                })
              );
            } finally {
              executionTimedOut = executionScope.signal.aborted;
              executionScope.close();
            }
            executionPending = false;
            diagnostic.execution_returned = true;
            diagnostic.executor_error_returned = Boolean(result.error_code);
            diagnostic.phase = 'execute_returned';
            if (
              ['id', 'request_id', 'action', 'claim'].some(
                key => result[key] !== claimed.request[key]
              )
            )
              throw new Error('publication_failed');
            diagnostic.complete_requested = true;
            diagnostic.phase = 'complete_requested';
            const completed = await sendOperation(result);
            diagnostic.complete_received = true;
            diagnostic.phase = 'complete_received';
            if (
              completed.id !== claimed.request.id ||
              completed.request_id !== claimed.request.request_id
            )
              throw new Error('publication_failed');
            writeBrowserOperationDiagnostic(stderr, diagnostic);
            if (page.isClosed()) throw new Error('browser_runtime_required');
            if (
              ['operator_required', 'meta_session_expired'].includes(
                result.error_code
              )
            ) {
              operatorState.required = true;
              await sendOperation({
                type: 'operator',
                operation: 'manager_heartbeat',
                state: 'operator_required',
                control_available: false,
              }).catch(() => {});
              break;
            }
            // The truthful completion has landed. A Playwright call abandoned
            // by the execution deadline must not leak into the next operation.
            if (executionTimedOut) throw new Error('browser_runtime_required');
          }
        } catch (error) {
          writeBrowserOperationDiagnostic(stderr, diagnostic);
          // Cancellation does not cancel Playwright's underlying call. Stop
          // this lifecycle so cleanup finishes before another job can run.
          if (executionPending || error.message === 'browser_runtime_required')
            throw new Error('browser_runtime_required');
          if (!shutdown.signal.aborted)
            stderr.write('instagram_browser_operation_failed\n');
        } finally {
          operationScope.close();
        }
        await pause(
          Math.min(BROWSER_OPERATION_POLL_MS, Math.max(1, refreshDue - now())),
          shutdown.signal,
          clock
        ).catch(() => {});
      }
      if (operatorState.required) break;
    }
    if (operatorState.required) throw new Error('operator_required');
  } finally {
    warmMetaPage?.dispose();
    setup.close();
    const cleanup = deadlineScope(undefined, clock, 25000);
    try {
      if (context) await cleanup.wait(context.close()).catch(() => {});
      if (lock) await cleanup.wait(lock.close()).catch(() => {});
      // Never unlink a lock that this process failed to acquire.
      if (lock) await cleanup.wait(files.unlink(lockPath)).catch(() => {});
    } finally {
      cleanup.close();
      signals.removeListener('SIGTERM', stop);
      signals.removeListener('SIGINT', stop);
    }
  }
}

export function managerExitCode(error) {
  return error.message === 'operator_required' ? 2 : 1;
}

if (isMainModule(import.meta.url)) {
  run().catch(error => {
    process.exitCode = managerExitCode(error);
    process.stderr.write(
      process.exitCode === 2
        ? 'instagram_manager_operator_required\n'
        : 'instagram_manager_failed\n'
    );
  });
}
