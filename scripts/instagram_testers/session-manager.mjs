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

const pause = ms =>
  new Promise(done => {
    setTimeout(done, ms);
  });

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

export function publisher(command, payload) {
  return new Promise((done, reject) => {
    if (
      !Array.isArray(command) ||
      !command.length ||
      !command.every(
        value =>
          typeof value === 'string' && value.length && !/[\x00\r\n]/.test(value)
      )
    ) {
      reject(new Error('publisher_required'));
      return;
    }
    // The operator configures the command. Captured fields never enter argv or
    // shell code. Discard stderr; publish only the validated opaque version.
    const child = spawn(command[0], command.slice(1), {
      stdio: ['pipe', 'pipe', 'ignore'],
      shell: false,
    });
    let output = '';
    let failed = false;
    const timer = setTimeout(() => {
      failed = true;
      child.kill();
    }, 30000);
    child.stdout.on('data', chunk => {
      output += chunk;
      if (Buffer.byteLength(output) > 1024) {
        failed = true;
        child.kill();
      }
    });
    child.once('error', () => {
      clearTimeout(timer);
      reject(new Error('publication_failed'));
    });
    child.stdin.on('error', () => {
      failed = true;
    });
    child.once('exit', code => {
      clearTimeout(timer);
      try {
        if (failed || code !== 0) throw new Error();
        const result = JSON.parse(output);
        if (
          Object.keys(result).length !== 1 ||
          !('version' in result) ||
          (result.version !== null && !/^[a-f0-9-]{36}$/.test(result.version))
        )
          throw new Error();
        done(result.version);
      } catch {
        reject(new Error('publication_failed'));
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

async function requireOperator(command, version) {
  if (version) {
    await publisher(command, {
      operation: 'invalidate',
      expected_version: version,
      code: 'operator_required',
    }).catch(() => {});
  }
  throw new Error('operator_required');
}

export async function run(env = process.env) {
  const config = configuration(env);
  const profile = await privateProfile(env.INSTAGRAM_TESTER_BROWSER_PROFILE);
  const command = JSON.parse(
    env.INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON || 'null'
  );
  const lockPath = join(profile, '.instagram-manager.lock');
  const lock = await open(lockPath, 'wx', 0o600);
  let context;
  let stopping = false;
  let unhealthy = null;
  const stop = () => {
    stopping = true;
  };
  process.once('SIGTERM', stop);
  process.once('SIGINT', stop);
  try {
    if (
      !env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE ||
      !isAbsolute(env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE)
    )
      throw new Error('browser_runtime_required');
    delete process.env.DEBUG;
    delete process.env.PWDEBUG;
    const runtime = await import(
      pathToFileURL(env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE)
    );
    context = await runtime.chromium.launchPersistentContext(profile, {
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
    while (!stopping) {
      const expectedVersion = await publisher(command, {
        operation: 'version',
      });
      const capturedAt = new Date().toISOString();
      let publication = null;
      let accepting = true;
      const observe = response => {
        if (
          !accepting ||
          publication ||
          response.url() !== 'https://developers.facebook.com/api/graphql/'
        )
          return;
        publication = (async () => {
          const request = response.request();
          const session = observedSession(
            {
              url: request.url(),
              method: request.method(),
              headers: await request.allHeaders(),
              body: request.postData(),
            },
            config
          );
          if (!session) {
            publication = null;
            return false;
          }
          if (response.status() === 401 || response.status() === 403) {
            await requireOperator(command, expectedVersion);
          }
          if (response.status() !== 200)
            throw new Error('session_update_rejected');
          const rolesResponse = await response.text();
          validateRolesResponse(rolesResponse);
          if (!safeBrowserLocation(page.url(), config))
            throw new Error('operator_required');
          await publisher(command, {
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
      try {
        const navigation = await page.goto(config.rolesUrl, {
          waitUntil: 'domcontentloaded',
          timeout: 30000,
        });
        if (
          !safeBrowserLocation(page.url(), config) ||
          [401, 403].includes(navigation?.status())
        ) {
          await requireOperator(command, expectedVersion);
        }
        const deadline = Date.now() + 30000;
        while (!publication && Date.now() < deadline && !stopping)
          await pause(100);
        accepting = false;
        if (!publication || !(await publication))
          throw new Error('session_update_rejected');
        // Static status only. Never log browser URLs, headers, forms or errors.
        if (unhealthy) process.stdout.write('instagram_session_recovered\n');
        unhealthy = null;
      } catch (error) {
        const code =
          error.message === 'operator_required'
            ? 'operator_required'
            : 'session_update_rejected';
        if (unhealthy !== code)
          process.stderr.write(`instagram_session_${code}\n`);
        unhealthy = code;
        if (code === 'operator_required') {
          stopping = true;
          break;
        }
      } finally {
        accepting = false;
        page.off('response', observe);
        if (publication) await publication.catch(() => {});
      }
      // Refresh only by a legitimate browser page load. No direct HTTP fallback,
      // proxy rotation, password/2FA handling or retry of a captured request.
      for (let elapsed = 0; elapsed < 900000 && !stopping; elapsed += 1000)
        await pause(1000);
    }
    if (unhealthy) throw new Error('operator_required');
  } finally {
    if (context) await context.close().catch(() => {});
    await lock.close();
    await unlink(lockPath).catch(() => {});
    process.removeListener('SIGTERM', stop);
    process.removeListener('SIGINT', stop);
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  run().catch(() => {
    process.stderr.write(
      'Instagram session manager stopped; operator required\n'
    );
    process.exitCode = 2;
  });
}
