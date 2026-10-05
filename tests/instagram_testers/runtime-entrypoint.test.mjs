import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isMainModule } from '../../scripts/instagram_testers/runtime/entrypoint.mjs';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const scratch = mkdtempSync(join(tmpdir(), 'instagram-entrypoint-'));
const current = join(scratch, 'current');
symlinkSync(ROOT, current, 'dir');
after(() => rmSync(scratch, { recursive: true, force: true }));

const ENTRYPOINTS = [
  ['runtime/vps/gateway.mjs', 1, 'instagram_gateway_failed\n'],
  [
    'runtime/vps/publisher-broker.mjs',
    2,
    'instagram_session_publication_failed\n',
  ],
  [
    'runtime/vps/publisher-client.mjs',
    2,
    'instagram_session_publication_failed\n',
  ],
  ['session-manager.mjs', 1, 'instagram_manager_failed\n'],
  ['runtime/operator-waiter.mjs', 1, 'instagram_operator_waiter_failed\n'],
  [
    'session-browser.mjs',
    2,
    'Dedicated Instagram browser stopped; operator required\n',
  ],
  ['runtime/publisher-tunnel.mjs', 2, 'instagram_session_publication_failed\n'],
];

function execute(args, input = '') {
  const result = spawnSync(process.execPath, args, {
    // Missing config and malformed command JSON fail before any runtime or publisher work.
    env: { INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON: '{' },
    input,
    encoding: 'utf8',
    timeout: 5000,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  return result;
}

ENTRYPOINTS.forEach(([relative, exitCode, message]) => {
  ['direct', 'current symlink'].forEach(mode => {
    test(`${relative}: ${mode} runs the configuration gate`, () => {
      const root = mode === 'direct' ? ROOT : current;
      const result = execute([
        join(root, 'scripts/instagram_testers', relative),
      ]);
      assert.equal(result.status, exitCode);
      assert.equal(result.stdout, '');
      assert.equal(result.stderr, message);
    });
  });
});

const imports = ENTRYPOINTS.map(
  ([relative]) =>
    `await import(${JSON.stringify(pathToFileURL(join(ROOT, 'scripts/instagram_testers', relative)).href)});`
).join('\n');

test('importing entrypoints from another file has no CLI side effects', () => {
  const importer = join(scratch, 'importer.mjs');
  writeFileSync(importer, imports);
  const result = execute([importer]);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, '');
});

test('stdin imports do not run a main function', () => {
  const result = execute(['--input-type=module', '-'], imports);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, '');
});

test('eval imports with an entrypoint argument do not run main', () => {
  const result = execute([
    '--input-type=module',
    '--eval',
    imports,
    join(ROOT, 'scripts/instagram_testers/runtime/vps/gateway.mjs'),
  ]);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, '');
});

test('combined print/eval imports do not run main', () => {
  const result = execute([
    '-pe',
    `void (async () => { ${imports} })()`,
    join(ROOT, 'scripts/instagram_testers/runtime/vps/gateway.mjs'),
  ]);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, 'undefined\n');
  assert.equal(result.stderr, '');
});

test('canonical entrypoint comparison handles URL-reserved path characters', () => {
  const fixture = join(scratch, 'entry % # espaço.mjs');
  const helper = pathToFileURL(
    join(ROOT, 'scripts/instagram_testers/runtime/entrypoint.mjs')
  ).href;
  writeFileSync(
    fixture,
    `import { isMainModule } from ${JSON.stringify(helper)};\nif (isMainModule(import.meta.url)) process.stdout.write('main\\n');\n`
  );
  const result = execute([fixture]);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, 'main\n');
  assert.equal(result.stderr, '');
});

test('missing argv and stdin are not file entrypoints', () => {
  assert.equal(isMainModule(import.meta.url, null), false);
  assert.equal(isMainModule(import.meta.url, '-'), false);
});

test('a real entrypoint path error is not silently treated as an import', () => {
  assert.throws(
    () => isMainModule(import.meta.url, join(scratch, 'missing.mjs')),
    { code: 'ENOENT' }
  );
});
