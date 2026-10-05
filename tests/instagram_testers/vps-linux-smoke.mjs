import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { on, once } from 'node:events';
import { readFileSync } from 'node:fs';
import filesystem from 'node:fs/promises';
import {
  access,
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  readlink,
  rm,
  unlink,
  writeFile,
} from 'node:fs/promises';
import http from 'node:http';
import { createRequire } from 'node:module';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { pathToFileURL } from 'node:url';

const DISPLAY = ':199';
const TEST_TIMEOUT_MS = 45_000;
const CLEANUP_TIMEOUT_MS = 10_000;
const HTML =
  '<!doctype html><html><title>Linux smoke</title><body><h1>synthetic Linux smoke</h1></body></html>';
const runtime = new URL(
  '../../scripts/instagram_testers/runtime/vps/gateway.mjs',
  import.meta.url
);

function report(stage) {
  process.stdout.write(`IG_VPS_LINUX_SMOKE ${stage}\n`);
}

async function bounded(operation, ms) {
  let timer;
  try {
    return await Promise.race([
      operation,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('smoke_timeout')), ms);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function stopChild(child) {
  if (
    !child ||
    child.exitCode !== null ||
    child.signalCode !== null ||
    !child.pid
  )
    return;
  const exited = once(child, 'exit');
  child.kill('SIGTERM');
  try {
    await bounded(exited, 1000);
  } catch {
    child.kill('SIGKILL');
    await bounded(exited, 1000);
  }
}

async function assertAbsent(filename) {
  await assert.rejects(lstat(filename), error => error.code === 'ENOENT');
}

async function assertPrivate(filename, uid, mode, kind) {
  const info = await lstat(filename);
  assert.equal(info.uid, uid);
  assert.equal(info.mode & 0o777, mode);
  assert.ok(
    kind === 'directory'
      ? info.isDirectory()
      : kind === 'socket'
        ? info.isSocket()
        : info.isFile()
  );
}

// Match TCP listeners to this child, rather than trusting flags or checking an unrelated port.
async function assertNoTcpListeners(pid) {
  const inodes = new Set();
  const directory = `/proc/${pid}/fd`;
  for (const fd of await readdir(directory)) {
    let target;
    try {
      target = await readlink(path.join(directory, fd));
    } catch (error) {
      if (error.code === 'ENOENT') continue;
      throw error;
    }
    if (target.startsWith('socket:[') && target.endsWith(']'))
      inodes.add(target.slice(8, -1));
  }
  for (const family of ['tcp', 'tcp6']) {
    const table = await readFile(`/proc/${pid}/net/${family}`, 'utf8');
    for (const row of table.trim().split('\n').slice(1)) {
      const columns = row.trim().split(' ').filter(Boolean);
      assert.ok(
        !(columns[3] === '0A' && inodes.has(columns[9])),
        'child_tcp_listener'
      );
    }
  }
}

function request(
  port,
  config,
  target,
  signal,
  { method = 'GET', cookie, ticket, origin, rawBody } = {}
) {
  const body =
    rawBody ?? (ticket ? new URLSearchParams({ ticket }).toString() : '');
  const headers = {
    Host: config.base.host,
    'X-Forwarded-Proto': 'https',
    Origin: origin ?? (ticket ? config.issuer : config.base.origin),
  };
  if (cookie) headers.Cookie = cookie;
  if (ticket || rawBody !== undefined) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    headers['Content-Length'] = Buffer.byteLength(body);
  }
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port,
        path: target,
        method,
        headers,
        signal,
        agent: false,
      },
      res => {
        const chunks = [];
        let size = 0;
        res.on('data', chunk => {
          size += chunk.length;
          if (size > 2 * 1024 * 1024)
            res.destroy(new Error('smoke_response_size'));
          else chunks.push(chunk);
        });
        res.on('error', reject);
        res.on('end', () =>
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks).toString('utf8'),
          })
        );
      }
    );
    req.on('error', reject);
    req.setTimeout(4000, () => req.destroy(new Error('smoke_http_timeout')));
    req.end(body);
  });
}

// Importing this module never registers tests, creates files, starts processes or opens sockets.
export async function runLinuxSmoke() {
  const controller = new AbortController();
  const { signal } = controller;
  const deadline = Date.now() + TEST_TIMEOUT_MS;
  const budget = maximum => {
    signal.throwIfAborted();
    assert.ok(Date.now() < deadline, 'smoke_timeout');
    return Math.max(1, Math.min(maximum, deadline - Date.now()));
  };
  const timer = setTimeout(
    () => controller.abort(new Error('smoke_timeout')),
    TEST_TIMEOUT_MS
  );
  const interrupt = () => controller.abort(new Error('smoke_interrupted'));
  process.once('SIGTERM', interrupt);
  process.once('SIGINT', interrupt);
  let root;
  let xauth;
  let xvnc;
  let context;
  let browser;
  let chromePid;
  let gateway;
  let ws;
  let stage = 'PREPARATION';
  const step = value => {
    signal.throwIfAborted();
    stage = value;
    report(value);
  };
  const killOwnChrome = () => {
    if (!chromePid) return;
    try {
      const command = readFileSync(`/proc/${chromePid}/cmdline`, 'utf8').split(
        '\0'
      );
      // Playwright's Linux launcher creates a separate process group for this browser.
      if (command.includes(`--user-data-dir=${path.join(root, 'profile')}`))
        process.kill(-chromePid, 'SIGKILL');
      chromePid = undefined;
    } catch (error) {
      if (!['ENOENT', 'ESRCH'].includes(error.code)) throw error;
      chromePid = undefined;
    }
  };

  try {
    step('PREPARATION');
    assert.equal(process.platform, 'linux');
    assert.equal(process.versions.node.split('.')[0], '24');
    assert.notEqual(process.getuid(), 0, 'smoke_requires_unprivileged_user');
    assert.ok(
      ![':199', ':199.0'].includes(process.env.DISPLAY),
      'smoke_display_is_reserved'
    );
    await access('/usr/bin/Xtigervnc');
    await access('/usr/bin/xauth');
    await assertAbsent('/tmp/.X199-lock');
    await assertAbsent('/tmp/.X11-unix/X199');
    const require = createRequire(runtime);
    const { chromium } = await import(
      pathToFileURL(
        path.join(
          path.dirname(require.resolve('playwright/package.json')),
          'index.mjs'
        )
      ).href
    );
    const { SignJWT } = await import(
      pathToFileURL(require.resolve('jose')).href
    );
    const WebSocket = require('ws');
    const { createGateway } = await import(runtime.href);
    const uid = process.getuid();
    const gid = process.getgid();
    // A single-UID component fixture cannot prove Linux account isolation.
    // Only state metadata is synthetic; production configFromEnv remains strict.
    report('SYNTHETIC_UID_FILESYSTEM_ISOLATION_NOT_PROVEN');
    root = await mkdtemp('/tmp/ig-linux-smoke-');
    await chmod(root, 0o700);
    const directories = [
      'home',
      'tmp',
      'runtime',
      'config',
      'cache',
      'profile',
      'gateway',
      'artifacts',
    ];
    for (const directory of directories)
      await mkdir(path.join(root, directory), { mode: 0o700 });
    const authority = path.join(root, 'Xauthority');
    await writeFile(authority, '', { mode: 0o600, flag: 'wx' });
    const env = {
      PATH: '/usr/local/bin:/usr/bin:/bin',
      LANG: 'C.UTF-8',
      HOME: path.join(root, 'home'),
      TMPDIR: path.join(root, 'tmp'),
      XDG_RUNTIME_DIR: path.join(root, 'runtime'),
      XDG_CONFIG_HOME: path.join(root, 'config'),
      XDG_CACHE_HOME: path.join(root, 'cache'),
      DISPLAY,
      XAUTHORITY: authority,
    };
    const config = {
      stack: 'hub2you',
      base: new URL('https://console.test/hub2you/'),
      issuer: 'https://issuer.test',
      key: randomBytes(32),
      gatewayUid: uid + 1,
      gatewayGid: gid + 1,
      browserUid: uid,
      viewerGid: gid,
      runtimeDir: path.join(root, 'runtime'),
      port: 0,
      stateDir: path.join(root, 'gateway'),
      requestFile: path.join(root, 'runtime/browser-request.json'),
      vncSocket: path.join(root, 'runtime/vnc.sock'),
    };
    await assertPrivate(root, uid, 0o700, 'directory');
    for (const directory of directories)
      await assertPrivate(path.join(root, directory), uid, 0o700, 'directory');

    await chmod(config.runtimeDir, 0o710);
    const projectState = (filename, info) => {
      if (
        filename === config.stateDir ||
        filename.startsWith(`${config.stateDir}/`)
      ) {
        info.uid = config.gatewayUid;
        info.gid = config.gatewayGid;
      }
      return info;
    };
    const fs = {
      ...filesystem,
      lstat: async filename =>
        projectState(filename, await filesystem.lstat(filename)),
      open: async (...args) => {
        const handle = await filesystem.open(...args);
        return new Proxy(handle, {
          get(target, key) {
            if (key === 'stat')
              return async () => projectState(args[0], await target.stat());
            const value = target[key];
            return typeof value === 'function' ? value.bind(target) : value;
          },
        });
      },
    };

    step('XAUTH');
    xauth = spawn('/usr/bin/xauth', ['-f', authority, 'source', '-'], {
      env,
      stdio: ['pipe', 'ignore', 'ignore'],
    });
    xauth.on('error', () => {});
    xauth.stdin.on('error', () => {});
    const authenticated = once(xauth, 'exit', { signal });
    // Synthetic cookie only over stdin, never argv, environment, stdout or a shell.
    xauth.stdin.end(
      `add ${DISPLAY} MIT-MAGIC-COOKIE-1 ${randomBytes(16).toString('hex')}\n`
    );
    assert.equal((await authenticated)[0], 0);
    await assertPrivate(authority, uid, 0o600, 'file');
    assert.ok((await lstat(authority)).size > 0);

    step('TIGERVNC');
    xvnc = spawn(
      '/usr/bin/Xtigervnc',
      [
        DISPLAY,
        '-geometry',
        '1024x768',
        '-depth',
        '24',
        '-nolisten',
        'tcp',
        '-noreset',
        '-auth',
        authority,
        '-rfbport',
        '-1',
        '-rfbunixpath',
        config.vncSocket,
        '-rfbunixmode',
        '0660',
        '-SecurityTypes',
        'None',
        '-NeverShared',
        '-DisconnectClients=0',
        '-AcceptCutText=0',
        '-SendCutText=0',
        '-SendPrimary=0',
        '-SetPrimary=0',
        '-AllowOverride=',
      ],
      { env, stdio: 'ignore' }
    );
    let xvncError;
    xvnc.on('error', error => {
      xvncError = error;
    });
    const readyUntil = Date.now() + 5000;
    for (;;) {
      signal.throwIfAborted();
      if (xvncError) throw xvncError;
      assert.equal(xvnc.exitCode, null, 'display_stopped');
      assert.equal(xvnc.signalCode, null, 'display_stopped');
      try {
        await lstat(config.vncSocket);
        break;
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
      assert.ok(Date.now() < readyUntil, 'display_start_timeout');
      await delay(50, undefined, { signal });
    }
    await assertPrivate(config.vncSocket, uid, 0o660, 'socket');
    await assertNoTcpListeners(xvnc.pid);

    step('CHROME');
    context = await chromium.launchPersistentContext(
      path.join(root, 'profile'),
      {
        channel: 'chrome',
        headless: false,
        chromiumSandbox: true,
        env,
        args: ['--disable-background-networking'],
        serviceWorkers: 'block',
        timeout: budget(10_000),
        artifactsDir: path.join(root, 'artifacts'),
        handleSIGINT: false,
        handleSIGTERM: false,
        handleSIGHUP: false,
      }
    );
    browser = context.browser();
    assert.ok(browser);
    signal.throwIfAborted();
    context.setDefaultTimeout(5000);
    context.setDefaultNavigationTimeout(5000);
    await bounded(
      context.route('**/*', route =>
        route.fulfill({ status: 200, contentType: 'text/html', body: HTML })
      ),
      budget(5000)
    );
    await bounded(
      context.routeWebSocket('**/*', socket => socket.close()),
      budget(5000)
    );
    const cdp = await bounded(browser.newBrowserCDPSession(), budget(5000));
    const { arguments: chromeArgs } = await bounded(
      cdp.send('Browser.getBrowserCommandLine'),
      budget(5000)
    );
    assert.ok(
      chromeArgs.includes(`--user-data-dir=${path.join(root, 'profile')}`)
    );
    assert.ok(!chromeArgs.includes('--no-sandbox'));
    assert.ok(!chromeArgs.includes('--disable-setuid-sandbox'));
    assert.ok(!chromeArgs.some(value => value.startsWith('--headless')));
    const { processInfo } = await bounded(
      cdp.send('SystemInfo.getProcessInfo'),
      budget(5000)
    );
    chromePid = processInfo.find(value => value.type === 'browser')?.id;
    assert.ok(Number.isSafeInteger(chromePid) && chromePid > 0);
    const command = (
      await readFile(`/proc/${chromePid}/cmdline`, 'utf8')
    ).split('\0');
    assert.ok(
      command.includes(`--user-data-dir=${path.join(root, 'profile')}`)
    );
    await bounded(cdp.detach(), budget(5000));
    const page =
      context.pages()[0] ?? (await bounded(context.newPage(), budget(5000)));
    // No external navigation: all future requests are intercepted, content is local and synthetic.
    await page.setContent(HTML, { timeout: budget(5000) });
    assert.equal(await bounded(page.title(), budget(5000)), 'Linux smoke');
    assert.equal(
      await page.locator('h1').textContent({ timeout: budget(5000) }),
      'synthetic Linux smoke'
    );
    await assertPrivate(path.join(root, 'profile'), uid, 0o700, 'directory');

    step('GATEWAY_HTTP');
    const now = Math.floor(Date.now() / 1000);
    const claims = {
      iss: config.issuer,
      aud: 'instagram-operator-browser:hub2you',
      sub: '17',
      jti: randomUUID(),
      iat: now,
      exp: now + 60,
      request_id: randomUUID(),
      deadline: now + 3600,
      stack: config.stack,
    };
    await writeFile(
      config.requestFile,
      JSON.stringify({
        request_id: claims.request_id,
        deadline: claims.deadline,
      }),
      { mode: 0o640, flag: 'wx' }
    );
    await chmod(config.requestFile, 0o640);
    gateway = await createGateway(config, { pollMs: 100, fs });
    const listening = once(gateway.server, 'listening', { signal });
    gateway.server.listen(0, '127.0.0.1');
    await listening;
    const { port, address } = gateway.server.address();
    assert.equal(address, '127.0.0.1');
    const denied = await request(port, config, '/hub2you/console/', signal);
    assert.ok([401, 403].includes(denied.status));
    const ticket = await new SignJWT(claims)
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .sign(config.key);
    const granted = await request(port, config, '/hub2you/grant', signal, {
      method: 'POST',
      ticket,
    });
    assert.equal(granted.status, 200);
    assert.equal(granted.headers['set-cookie']?.length, 1);
    const cookieHeader = granted.headers['set-cookie'][0];
    for (const attribute of [
      'Secure',
      'HttpOnly',
      'SameSite=Strict',
      'Path=/hub2you/',
    ]) {
      assert.ok(
        cookieHeader
          .split(';')
          .map(part => part.trim())
          .includes(attribute)
      );
    }
    const cookie = cookieHeader.split(';')[0];
    for (const [target, expected] of [
      ['/hub2you/console/', '<script type="module"'],
      ['/hub2you/assets/console.js', 'new RFB'],
      ['/hub2you/assets/novnc/core/rfb.js', 'class RFB'],
      ['/hub2you/assets/novnc/core/websock.js', 'class Websock'],
    ]) {
      const response = await request(port, config, target, signal, { cookie });
      assert.equal(response.status, 200);
      assert.ok(response.body.includes(expected));
      assert.equal(response.headers['cache-control'], 'no-store');
    }

    step('BROWSER_FORM_ORIGIN_AND_COOKIE');
    const railsView = await readFile(
      new URL(
        '../../app/views/super_admin/instagram_automation/browser.html.erb',
        import.meta.url
      ),
      'utf8'
    );
    assert.ok(
      railsView.includes('<meta name="referrer" content="strict-origin">')
    );
    const browserTicket = await new SignJWT({ ...claims, jti: randomUUID() })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .sign(config.key);
    const observedPosts = [];
    let renderedConsole = false;
    await page.route('https://console.test/**', async route => {
      const browserRequest = route.request();
      const headers = await browserRequest.allHeaders();
      const target = new URL(browserRequest.url()).pathname;
      const method = browserRequest.method();
      if (method === 'POST') observedPosts.push(headers.origin);
      const response = await request(port, config, target, signal, {
        method,
        cookie: headers.cookie,
        origin: headers.origin,
        ...(method === 'POST' ? { rawBody: browserRequest.postData() } : {}),
      });
      if (target === '/hub2you/console/' && response.status === 200)
        renderedConsole = true;
      const forwarded = { ...response.headers };
      delete forwarded['content-length'];
      delete forwarded['transfer-encoding'];
      delete forwarded.connection;
      if (Array.isArray(forwarded['set-cookie']))
        forwarded['set-cookie'] = forwarded['set-cookie'][0];
      await route.fulfill({
        status: response.status,
        headers: forwarded,
        body: response.body,
      });
    });
    await page.route('https://issuer.test/**', route => {
      const safe = new URL(route.request().url()).pathname === '/strict';
      return route.fulfill({
        status: 200,
        contentType: 'text/html',
        headers: { 'Referrer-Policy': safe ? 'strict-origin' : 'no-referrer' },
        body: `<html><head><meta name="referrer" content="${safe ? 'strict-origin' : 'no-referrer'}"></head>
          <body><form method="post" action="https://console.test/hub2you/grant">
          <input name="ticket" value="${browserTicket}"><button>Continue</button></form></body></html>`,
      });
    });
    step('BROWSER_FORM_NULL_ORIGIN_NAVIGATION');
    await page.goto('https://issuer.test/no-referrer', {
      timeout: budget(5000),
    });
    await Promise.all([
      page.waitForURL('https://console.test/hub2you/grant', {
        timeout: budget(5000),
      }),
      page.getByRole('button', { name: 'Continue' }).click(),
    ]);
    step('BROWSER_FORM_NULL_ORIGIN_ASSERTIONS');
    assert.equal(observedPosts.at(-1), 'null');
    assert.equal((await context.cookies(config.base.href)).length, 0);
    step('BROWSER_FORM_STRICT_ORIGIN_NAVIGATION');
    await page.goto('https://issuer.test/strict', { timeout: budget(5000) });
    await Promise.all([
      page.waitForURL('https://console.test/hub2you/console/', {
        timeout: budget(5000),
      }),
      page.getByRole('button', { name: 'Continue' }).click(),
    ]);
    step('BROWSER_FORM_STRICT_COOKIE_ASSERTIONS');
    assert.equal(observedPosts.at(-1), config.issuer);
    assert.equal(renderedConsole, true);
    const grantedCookie = (await context.cookies(config.base.href)).find(
      value => value.name.startsWith('__Secure-ig-')
    );
    assert.ok(
      grantedCookie?.secure &&
        grantedCookie.httpOnly &&
        grantedCookie.sameSite === 'Strict'
    );
    await page.close();

    step('WEBSOCKET_RFB');
    ws = new WebSocket(`ws://127.0.0.1:${port}/hub2you/ws`, {
      headers: {
        Host: config.base.host,
        'X-Forwarded-Proto': 'https',
        Origin: config.base.origin,
        Cookie: cookie,
      },
      handshakeTimeout: 5000,
      perMessageDeflate: false,
    });
    ws.on('error', () => {});
    const messages = on(ws, 'message', {
      signal: AbortSignal.any([signal, AbortSignal.timeout(5000)]),
    });
    const greeting = [];
    let greetingBytes = 0;
    for await (const [data, binary] of messages) {
      assert.equal(binary, true);
      greeting.push(data);
      greetingBytes += data.length;
      assert.ok(greetingBytes <= 12);
      if (greetingBytes === 12) break;
    }
    assert.equal(Buffer.concat(greeting).toString('ascii'), 'RFB 003.008\n');
    await assertNoTcpListeners(xvnc.pid);

    step('MARKER_REVOCATION');
    const closed = once(ws, 'close', {
      signal: AbortSignal.any([signal, AbortSignal.timeout(5000)]),
    });
    await unlink(config.requestFile);
    await closed;
    assert.equal(
      (await request(port, config, '/hub2you/console/', signal, { cookie }))
        .status,
      401
    );
    signal.throwIfAborted();
  } catch {
    // Never dump exception messages, child logs, tickets, cookies, paths or environment.
    report(`FAIL_${stage}`);
    throw new Error('linux_smoke_failed');
  } finally {
    clearTimeout(timer);
    process.removeListener('SIGTERM', interrupt);
    process.removeListener('SIGINT', interrupt);
    report('CLEANUP');
    // A cleanup error must not prevent the remaining owned resources from closing.
    let cleanupFailed = false;
    const cleanup = async operation => {
      try {
        await operation();
      } catch {
        cleanupFailed = true;
      }
    };
    const cleanupTimer = setTimeout(() => {
      // Hard ceiling: only child PIDs and the verified private-profile Chrome are signalled.
      try {
        killOwnChrome();
      } catch {}
      if (xvnc?.exitCode === null && xvnc?.signalCode === null)
        xvnc.kill('SIGKILL');
      if (xauth?.exitCode === null && xauth?.signalCode === null)
        xauth.kill('SIGKILL');
      report('FAIL_CLEANUP_TIMEOUT');
      process.exit(1);
    }, CLEANUP_TIMEOUT_MS);
    try {
      await cleanup(() => ws?.terminate());
      await cleanup(async () => {
        if (context) await bounded(context.close(), 2500);
      });
      await cleanup(async () => {
        if (browser) await bounded(browser.close(), 2500);
      });
      await cleanup(killOwnChrome);
      await cleanup(async () => {
        if (gateway) await bounded(gateway.close(), 1500);
      });
      await cleanup(() => stopChild(xvnc));
      await cleanup(() => stopChild(xauth));
      // No removal of global X11 paths, runtime files or directories owned by another job.
      await cleanup(async () => {
        if (root) await rm(root, { recursive: true, force: true });
      });
    } finally {
      clearTimeout(cleanupTimer);
    }
    if (cleanupFailed) {
      report('FAIL_CLEANUP');
      throw new Error('linux_smoke_cleanup_failed');
    }
  }
  report('PASS_COMPONENTS_SYNTHETIC_UID_ISOLATION_NOT_PROVEN');
}

const isMain =
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (isMain && process.env.IG_VPS_LINUX_SMOKE === '1') {
  try {
    await runLinuxSmoke();
  } catch {
    report('FAIL');
    process.exitCode = 1;
  }
} else if (isMain) {
  report('SKIP_FLAG_REQUIRED');
}
