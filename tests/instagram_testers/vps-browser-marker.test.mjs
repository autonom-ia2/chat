import assert from 'node:assert/strict';
import filesystem from 'node:fs/promises';
import {
  chmod,
  lstat,
  link,
  mkdtemp,
  readFile,
  realpath,
  rm,
  symlink,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  publishBrowserMarker,
  requestMarker,
} from '../../scripts/instagram_testers/runtime/browser-request-marker.mjs';
import {
  chromiumSandbox,
  managerCycleBudget,
} from '../../scripts/instagram_testers/session-manager.mjs';
const id = '11111111-1111-4111-8111-111111111111';
const now = 1800000000000;
const environment = path => ({
  INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE: path,
  INSTAGRAM_TESTER_OPERATOR_REQUEST_ID: id,
  INSTAGRAM_TESTER_OPERATOR_REQUEST_DEADLINE: String(now / 1000 + 3600),
});
async function fixture(t) {
  const root = await mkdtemp(join(await realpath(tmpdir()), 'ig995-marker-'));
  await chmod(root, 0o710);
  t.after(() => rm(root, { recursive: true, force: true }));
  const projectStat = info => Object.assign(info, { uid: 2102, gid: 2202 });
  const options = {
    uid: 2102,
    groups: [2202, 2203],
    fs: {
      ...filesystem,
      lstat: async filename => projectStat(await filesystem.lstat(filename)),
      open: async (...args) => {
        const handle = await filesystem.open(...args);
        return new Proxy(handle, {
          get(target, key) {
            if (key === 'stat')
              return async () => projectStat(await target.stat());
            if (key === 'chown')
              return async (uid, gid) => {
                assert.equal(uid, -1);
                assert.equal(gid, 2202);
                await target.chown(-1, process.getgid());
              };
            const value = target[key];
            return typeof value === 'function' ? value.bind(target) : value;
          },
        });
      },
    },
  };
  return { root, path: join(root, 'browser-request.json'), options };
}
test('legacy browser mode has no marker or filesystem action', async () => {
  assert.equal(requestMarker({}), null);
  const release = await publishBrowserMarker({});
  await release();
});
test('marker holds only typed request metadata and is removed on close', async t => {
  const { path, options } = await fixture(t);
  const release = await publishBrowserMarker(
    environment(path),
    () => now,
    undefined,
    options
  );
  assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), {
    request_id: id,
    deadline: now / 1000 + 3600,
  });
  assert.equal((await lstat(path)).mode % 4096, 0o640);
  await release();
  await release();
  await assert.rejects(lstat(path), { code: 'ENOENT' });
});
test('existing marker is neither overwritten nor removed', async t => {
  const { path, options } = await fixture(t);
  await writeFile(path, 'synthetic existing owner', { mode: 0o600 });
  await assert.rejects(
    publishBrowserMarker(environment(path), () => now, undefined, options),
    { code: 'EEXIST' }
  );
  assert.equal(await readFile(path, 'utf8'), 'synthetic existing owner');
});
test('cleanup refuses a marker replaced by another owner', async t => {
  const { path, options } = await fixture(t);
  const release = await publishBrowserMarker(
    environment(path),
    () => now,
    undefined,
    options
  );
  await unlink(path);
  await writeFile(path, 'another marker');
  await assert.rejects(release());
  assert.equal(await readFile(path, 'utf8'), 'another marker');
});
test('symlink markers are refused without following the target', async t => {
  const { path, root, options } = await fixture(t);
  const target = join(root, 'sentinel');
  await writeFile(target, 'synthetic');
  await symlink(target, path);
  await assert.rejects(
    publishBrowserMarker(environment(path), () => now, undefined, options)
  );
  assert.equal(await readFile(target, 'utf8'), 'synthetic');
});
test('marker requires an owning runtime directory with mode 0710', async t => {
  const { path, root, options } = await fixture(t);
  await chmod(root, 0o755);
  await assert.rejects(
    publishBrowserMarker(environment(path), () => now, undefined, options)
  );
  await assert.rejects(lstat(path), { code: 'ENOENT' });
});
test('marker checks paths, id, deadlines before creating state', () => {
  [
    { INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE: 'relative' },
    { INSTAGRAM_TESTER_OPERATOR_REQUEST_FILE: '/tmp/../marker' },
    { INSTAGRAM_TESTER_OPERATOR_REQUEST_ID: 'invalid' },
    {
      INSTAGRAM_TESTER_OPERATOR_REQUEST_ID: id.toUpperCase().replace('4', 'F'),
    },
    { INSTAGRAM_TESTER_OPERATOR_REQUEST_DEADLINE: String(now / 1000) },
    { INSTAGRAM_TESTER_OPERATOR_REQUEST_DEADLINE: String(now / 1000 + 3601) },
    { INSTAGRAM_TESTER_OPERATOR_REQUEST_DEADLINE: 'NaN' },
    { INSTAGRAM_TESTER_OPERATOR_REQUEST_DEADLINE: '1800003600.0' },
  ].forEach(override =>
    assert.throws(() =>
      requestMarker({ ...environment('/tmp/marker'), ...override }, () => now)
    )
  );
});
test('VPS gets a bounded full-cycle budget but legacy deadlines remain unchanged', () => {
  assert.equal(managerCycleBudget({}), 30000);
  assert.equal(
    managerCycleBudget({ INSTAGRAM_TESTER_RUNTIME_MODE: 'vps' }),
    120000
  );
  assert.throws(() =>
    managerCycleBudget({ INSTAGRAM_TESTER_RUNTIME_MODE: 'anything' })
  );
});
test('VPS refuses to run without Chromium sandbox', () => {
  assert.throws(() =>
    chromiumSandbox({ INSTAGRAM_TESTER_RUNTIME_MODE: 'vps' })
  );
  assert.throws(() =>
    chromiumSandbox({
      INSTAGRAM_TESTER_RUNTIME_MODE: 'vps',
      INSTAGRAM_TESTER_CHROMIUM_SANDBOX: 'false',
    })
  );
  assert.throws(() =>
    chromiumSandbox({ INSTAGRAM_TESTER_CHROMIUM_SANDBOX: 'TRUE' })
  );
  assert.equal(
    chromiumSandbox({
      INSTAGRAM_TESTER_RUNTIME_MODE: 'vps',
      INSTAGRAM_TESTER_CHROMIUM_SANDBOX: 'true',
    }),
    true
  );
  assert.equal(chromiumSandbox({}), false);
});

test('publication exposes complete JSON only and refuses an existing destination atomically', async t => {
  const { path, options } = await fixture(t);
  const release = await publishBrowserMarker(
    environment(path),
    () => now,
    async (temporary, finalPath) => {
      await assert.rejects(lstat(finalPath), { code: 'ENOENT' });
      assert.deepEqual(JSON.parse(await readFile(temporary, 'utf8')), {
        request_id: id,
        deadline: now / 1000 + 3600,
      });
      await link(temporary, finalPath);
      assert.deepEqual(JSON.parse(await readFile(finalPath, 'utf8')), {
        request_id: id,
        deadline: now / 1000 + 3600,
      });
      assert.equal((await lstat(finalPath)).nlink, 2);
      assert.equal((await lstat(finalPath)).mode % 4096, 0o640);
    },
    options
  );
  assert.equal((await lstat(path)).nlink, 1);
  await release();
});

test('marker rejects foreign runtime owner, missing viewer group and special mode bits', async t => {
  const { root, path, options } = await fixture(t);
  await assert.rejects(
    publishBrowserMarker(environment(path), () => now, undefined, {
      ...options,
      uid: 2101,
    })
  );
  await assert.rejects(
    publishBrowserMarker(environment(path), () => now, undefined, {
      ...options,
      groups: [2203],
    })
  );
  const specialMode = {
    ...options,
    fs: {
      ...options.fs,
      lstat: async filename => {
        const info = await options.fs.lstat(filename);
        if (filename === root) info.mode = 0o2710;
        return info;
      },
    },
  };
  await assert.rejects(
    publishBrowserMarker(environment(path), () => now, undefined, specialMode)
  );
  await assert.rejects(lstat(path), { code: 'ENOENT' });
});

test('marker explicitly publishes mode 0640 even with umask 0077', async t => {
  const { path, options } = await fixture(t);
  const previous = process.umask(0o077);
  try {
    const release = await publishBrowserMarker(
      environment(path),
      () => now,
      undefined,
      options
    );
    assert.equal((await lstat(path)).mode % 4096, 0o640);
    await release();
  } finally {
    process.umask(previous);
  }
});

test('publication refuses runtime replacement before the atomic link', async t => {
  const { path, root, options } = await fixture(t);
  let reads = 0;
  const fs = {
    ...options.fs,
    lstat: async filename => {
      const info = await options.fs.lstat(filename);
      if (filename === root) {
        reads += 1;
        if (reads === 3) info.ino = -1;
      }
      return info;
    },
  };
  await assert.rejects(
    publishBrowserMarker(environment(path), () => now, undefined, {
      ...options,
      fs,
    })
  );
  await assert.rejects(lstat(path), { code: 'ENOENT' });
  assert.deepEqual(await filesystem.readdir(root), []);
});
