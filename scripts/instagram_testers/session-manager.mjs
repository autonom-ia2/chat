/* eslint-disable no-await-in-loop, no-restricted-syntax -- Node operational steps and refresh cycles must run sequentially. */
/* eslint-disable no-bitwise, no-control-regex -- Check filesystem permission bits and reject control characters at the process boundary. */
import { mkdir, lstat, open, unlink } from 'node:fs/promises';
import { resolve, dirname, isAbsolute, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import {
  configuration,
  observedSession,
  rolesQueryFields,
  safeBrowserLocation,
  validateRolesResponse,
} from './session-observer.mjs';

const CYCLE_BUDGET_MS = 30000;
const REFRESH_INTERVAL_MS = 900000;

function cancellable(promise, signal) {
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

function pause(ms, signal, clock) {
  let timer;
  return cancellable(
    new Promise(done => {
      timer = clock.setTimeout(done, ms);
    }),
    signal
  ).finally(() => clock.clearTimeout(timer));
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
    let output = '';
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
      output += chunk;
      if (Buffer.byteLength(output) > 1024) {
        child.kill('SIGTERM');
        finish(new Error('publication_failed'));
      }
    });
    child.once('error', () => finish(new Error('publication_failed')));
    child.stdin.on('error', () => {
      child.kill('SIGTERM');
      finish(new Error('publication_failed'));
    });
    child.once('exit', code => {
      try {
        if (code !== 0) throw new Error();
        const result = JSON.parse(output);
        if (
          !result ||
          Array.isArray(result) ||
          Object.keys(result).length !== 1 ||
          !Object.hasOwn(result, 'version') ||
          (result.version !== null &&
            (typeof result.version !== 'string' || !result.version.length))
        )
          throw new Error();
        finish(null, result.version);
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
    return rolesQueryFields(body, config) !== null;
  } catch {
    return false;
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
  } = {}
) {
  const config = configuration(env);
  const profile = await files.privateProfile(
    env.INSTAGRAM_TESTER_BROWSER_PROFILE
  );
  const command = JSON.parse(
    env.INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON || 'null'
  );
  const lockPath = join(profile, '.instagram-manager.lock');
  const lock = await files.open(lockPath, 'wx', 0o600);
  let context;
  let unhealthy = null;
  const operatorState = { required: false };
  const shutdown = new AbortController();
  const stop = () => shutdown.abort(new Error('manager_stopped'));
  signals.once('SIGTERM', stop);
  signals.once('SIGINT', stop);
  try {
    if (
      !env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE ||
      !isAbsolute(env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE)
    )
      throw new Error('browser_runtime_required');
    delete process.env.DEBUG;
    delete process.env.PWDEBUG;
    const runtime = await loadRuntime(env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE);
    context = await runtime.chromium.launchPersistentContext(profile, {
      channel: 'chrome',
      headless: true,
      env: browserEnvironment(env),
      proxy: {
        server: `http://${config.host}:${Number(config.port)}`,
      },
      acceptDownloads: false,
      serviceWorkers: 'block',
      ignoreHTTPSErrors: false,
    });
    const page = context.pages()[0] || (await context.newPage());
    for (const other of context.pages())
      if (other !== page) await other.close();
    context.on('page', other => {
      other.close().catch(() => {});
    });
    // Prevent writes performed by this manager. It only opens the roles page;
    // invitations remain exclusively in the reviewed backend adapter.
    await context.route('**/*', async route => {
      const request = route.request();
      if (
        !isAllowedBrowserRequest({
          url: request.url(),
          method: request.method(),
          body: request.postData() || '',
          config,
        })
      )
        return route.abort();
      return route.continue();
    });
    while (!shutdown.signal.aborted) {
      const cycle = new AbortController();
      const cancel = () => cycle.abort(shutdown.signal.reason);
      shutdown.signal.addEventListener('abort', cancel, { once: true });
      const timer = clock.setTimeout(
        () => cycle.abort(new Error('session_update_rejected')),
        CYCLE_BUDGET_MS
      );
      const wait = promise => cancellable(promise, cycle.signal);
      const send = payload => {
        cycle.signal.throwIfAborted();
        return wait(publish(command, payload, { signal: cycle.signal, clock }));
      };
      let publication = null;
      let accepting = true;
      let observe;
      try {
        // Version is part of the recoverable cycle and is opaque to this client.
        const expectedVersion = await send({ operation: 'version' });
        const capturedAt = new Date(now()).toISOString();
        let operatorStop;
        const requireOperator = () => {
          if (!operatorStop) {
            operatorState.required = true;
            operatorStop = (async () => {
              if (expectedVersion !== null) {
                await send({
                  operation: 'invalidate',
                  expected_version: expectedVersion,
                  code: 'operator_required',
                }).catch(() => {});
              }
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
          publication = (async () => {
            const request = response.request();
            const headers = await wait(request.allHeaders());
            cycle.signal.throwIfAborted();
            const session = observedSession(
              {
                url: request.url(),
                method: request.method(),
                headers,
                body: request.postData(),
              },
              config
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
            if (!safeBrowserLocation(page.url(), config))
              await requireOperator();
            await send({
              operation: 'publish',
              session,
              expected_version: expectedVersion,
              captured_at: capturedAt,
              app_id: config.appId,
              business_id: config.businessId,
              proxy_fingerprint: config.proxyFingerprint,
              roles_response: rolesResponse,
            });
            return true;
          })();
          publication.catch(() => {});
        };
        page.on('response', observe);
        const navigation = await wait(
          page.goto(config.rolesUrl, {
            waitUntil: 'domcontentloaded',
            timeout: CYCLE_BUDGET_MS,
          })
        );
        if (
          !safeBrowserLocation(page.url(), config) ||
          [401, 403].includes(navigation?.status())
        )
          await requireOperator();
        while (!publication) await pause(100, cycle.signal, clock);
        accepting = false;
        if (!(await wait(publication)))
          throw new Error('session_update_rejected');
        if (unhealthy) stdout.write('instagram_session_recovered\n');
        unhealthy = null;
      } catch (error) {
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
      } finally {
        accepting = false;
        if (observe) page.off('response', observe);
        // Release pending headers/body/publication; never await them in cleanup.
        cycle.abort(new Error('session_update_rejected'));
        clock.clearTimeout(timer);
        shutdown.signal.removeEventListener('abort', cancel);
      }
      // A transport failure waits for the normal refresh, with no captured replay.
      await pause(REFRESH_INTERVAL_MS, shutdown.signal, clock).catch(() => {});
    }
    if (operatorState.required) throw new Error('operator_required');
  } finally {
    const cleanup = async promise => {
      const controller = new AbortController();
      const timer = clock.setTimeout(
        () => controller.abort(new Error('cleanup_timeout')),
        CYCLE_BUDGET_MS
      );
      try {
        return await cancellable(promise, controller.signal);
      } finally {
        clock.clearTimeout(timer);
      }
    };
    try {
      if (context) await cleanup(context.close()).catch(() => {});
      await cleanup(lock.close()).catch(error => {
        if (error.message !== 'cleanup_timeout') throw error;
      });
    } finally {
      try {
        await cleanup(files.unlink(lockPath)).catch(() => {});
      } finally {
        signals.removeListener('SIGTERM', stop);
        signals.removeListener('SIGINT', stop);
      }
    }
  }
}

export function managerExitCode(error) {
  return error.message === 'operator_required' ? 2 : 1;
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  run().catch(error => {
    process.exitCode = managerExitCode(error);
    process.stderr.write(
      process.exitCode === 2
        ? 'instagram_manager_operator_required\n'
        : 'instagram_manager_failed\n'
    );
  });
}
