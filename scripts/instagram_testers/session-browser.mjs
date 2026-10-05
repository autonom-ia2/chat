import { open, unlink } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isMainModule } from './runtime/entrypoint.mjs';
import { configuration, proxyConfiguration } from './session-observer.mjs';
import { publishBrowserMarker } from './runtime/browser-request-marker.mjs';
import {
  privateProfile,
  browserEnvironment,
  chromiumSandbox,
  deadlineScope,
  cancellable,
} from './session-manager.mjs';

// Human-only authorization in a dedicated profile. Shutdown releases its lock.
export async function run(
  env = process.env,
  args = process.argv.slice(2),
  {
    signals = process,
    clock = globalThis,
    files = { privateProfile, open, unlink },
    loadRuntime = path => import(pathToFileURL(path)),
    stdout = process.stdout,
    marker = publishBrowserMarker,
  } = {}
) {
  const initialize = args.length === 1 && args[0] === '--initialize';
  if (args.length && !initialize) throw new Error('operator_required');
  const config = initialize ? proxyConfiguration(env) : configuration(env);
  if (
    !env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE ||
    !isAbsolute(env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE)
  )
    throw new Error('browser_runtime_required');
  const shutdown = new AbortController();
  const stop = () => shutdown.abort(new Error('browser_stopped'));
  signals.once('SIGTERM', stop);
  signals.once('SIGINT', stop);
  const setup = deadlineScope(shutdown.signal, clock);
  let lock;
  let lockPath;
  let context;
  let releaseMarker;
  try {
    const profile = await setup.wait(
      files.privateProfile(env.INSTAGRAM_TESTER_BROWSER_PROFILE)
    );
    lockPath = join(profile, '.instagram-manager.lock');
    lock = await setup.wait(files.open(lockPath, 'wx', 0o600));
    delete process.env.DEBUG;
    delete process.env.PWDEBUG;
    const runtime = await setup.wait(
      loadRuntime(env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE)
    );
    context = await setup.wait(
      runtime.chromium
        .launchPersistentContext(profile, {
          channel: 'chrome',
          headless: false,
          chromiumSandbox: chromiumSandbox(env),
          timeout: setup.remaining(),
          env: browserEnvironment(env),
          proxy: { server: `http://${config.host}:${Number(config.port)}` },
          acceptDownloads: false,
          ignoreHTTPSErrors: false,
        })
        .then(value => {
          if (setup.signal.aborted) {
            value.close().catch(() => {});
            throw new Error('browser_stopped');
          }
          return value;
        })
    );
    releaseMarker = await setup.wait(
      marker(env).then(release => {
        if (setup.signal.aborted) {
          release().catch(() => {});
          throw new Error('browser_stopped');
        }
        return release;
      })
    );
    const closed = new Promise(done => {
      context.once('close', done);
    });
    const page = context.pages()[0] || (await setup.wait(context.newPage()));
    await setup.wait(
      page.goto(
        initialize ? 'https://developers.facebook.com/' : config.rolesUrl,
        {
          waitUntil: 'domcontentloaded',
          timeout: setup.remaining(),
        }
      )
    );
    setup.close();
    stdout.write(
      'Complete authorization manually in the dedicated window, then close it.\n'
    );
    await cancellable(closed, shutdown.signal);
  } finally {
    setup.close();
    const cleanup = deadlineScope(undefined, clock, 25000);
    try {
      if (releaseMarker) await cleanup.wait(releaseMarker()).catch(() => {});
      if (context) await cleanup.wait(context.close()).catch(() => {});
      if (lock) await cleanup.wait(lock.close()).catch(() => {});
      if (lock) await cleanup.wait(files.unlink(lockPath)).catch(() => {});
    } finally {
      cleanup.close();
      signals.removeListener('SIGTERM', stop);
      signals.removeListener('SIGINT', stop);
    }
  }
}

if (isMainModule(import.meta.url)) {
  run().catch(() => {
    process.stderr.write(
      'Dedicated Instagram browser stopped; operator required\n'
    );
    process.exitCode = 2;
  });
}
