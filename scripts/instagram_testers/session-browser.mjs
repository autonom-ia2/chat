import { open, unlink } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { configuration } from './session-observer.mjs';
import { privateProfile, browserEnvironment } from './session-manager.mjs';

// Future operator-only initialization/recovery. It opens a dedicated window;
// the human completes login and 2FA. No credential/cookie/form is inspected.
async function run() {
  const config = configuration(process.env);
  if (
    !process.env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE ||
    !isAbsolute(process.env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE)
  )
    throw new Error('browser_runtime_required');
  const profile = await privateProfile(
    process.env.INSTAGRAM_TESTER_BROWSER_PROFILE
  );
  const lockPath = join(profile, '.instagram-manager.lock');
  const lock = await open(lockPath, 'wx', 0o600);
  let context;
  try {
    delete process.env.DEBUG;
    delete process.env.PWDEBUG;
    const runtime = await import(
      pathToFileURL(process.env.INSTAGRAM_TESTER_PLAYWRIGHT_MODULE)
    );
    context = await runtime.chromium.launchPersistentContext(profile, {
      headless: false,
      env: browserEnvironment(process.env),
      proxy: {
        server: `http://${config.host}:${Number(config.port)}`,
      },
      acceptDownloads: false,
      ignoreHTTPSErrors: false,
    });
    const closed = new Promise(done => {
      context.once('close', done);
    });
    const page = context.pages()[0] || (await context.newPage());
    await page.goto(config.rolesUrl, {
      waitUntil: 'domcontentloaded',
      timeout: 30000,
    });
    process.stdout.write(
      'Complete authorization manually in the dedicated window, then close it.\n'
    );
    await closed;
  } finally {
    if (context) await context.close().catch(() => {});
    await lock.close();
    await unlink(lockPath).catch(() => {});
  }
}

run().catch(() => {
  process.stderr.write(
    'Dedicated Instagram browser stopped; operator required\n'
  );
  process.exitCode = 2;
});
