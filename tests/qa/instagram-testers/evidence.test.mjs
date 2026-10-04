import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import {
  sourceFingerprints,
  styleFingerprints,
  dependencyMap,
  observeStyles,
  sha256,
  consumedStyleFingerprints,
} from './evidence.mjs';

test('source snapshot includes transitive UI, locales, instructions, styles, config and capture harness', async () => {
  const scratch = resolve('tmp/instagram-931/qa-unit');
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(resolve(scratch, 'sources-'));
  const paths = [
    'tailwind.config.js',
    'postcss.config.js',
    'vite.config.ts',
    'package.json',
    'pnpm-lock.yaml',
    'app/javascript/dashboard/composables/useInstagramTester.js',
    'app/javascript/dashboard/composables/index.js',
    'app/javascript/dashboard/components/SnackbarContainer.vue',
    'app/javascript/dashboard/components/Snackbar.vue',
    'app/javascript/shared/helpers/mitt.js',
    'app/javascript/dashboard/api/channel/instagramClient.js',
    'app/javascript/dashboard/routes/TesterAcceptanceInstructions.vue',
    'app/javascript/dashboard/i18n/locale/en/inboxMgmt.json',
    'app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json',
    'app/assets/stylesheets/dashboard.scss',
    'theme/colors.js',
    'tests/qa/instagram-testers/wizard.mjs',
    'tests/qa/instagram-testers/entry.js',
    'tests/qa/instagram-testers/toast-helpers.mjs',
  ];
  await Promise.all(
    paths.map(async path => {
      await mkdir(dirname(resolve(root, path)), { recursive: true });
      await writeFile(resolve(root, path), 'before');
    })
  );
  const before = await sourceFingerprints(root);
  assert.deepEqual(Object.keys(before).sort(), paths.sort());
  const composable = paths.find(path => path.includes('useInstagramTester'));
  const module = {
    id: composable,
    file: resolve(root, composable),
    importedModules: new Set(),
  };
  const server = {
    moduleGraph: { idToModuleMap: new Map([[composable, module]]) },
  };
  assert.deepEqual(
    (await dependencyMap(root, server, before)).localSourcesUsed,
    [composable]
  );
  await writeFile(resolve(root, composable), 'after');
  const after = await sourceFingerprints(root);
  assert.notEqual(after[composable], before[composable]);
  await assert.rejects(dependencyMap(root, server, before), {
    code: 'ERR_ASSERTION',
  });
});

test('dependency map refuses an actual loaded local source absent from the baseline', async () => {
  const scratch = resolve('tmp/instagram-931/qa-unit');
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(resolve(scratch, 'unlisted-'));
  const source = {
    id: 'unlisted.vue',
    file: resolve(root, 'unlisted.vue'),
    importedModules: new Set(),
  };
  await writeFile(source.file, 'loaded source absent from manifest');
  await assert.rejects(
    dependencyMap(
      root,
      { moduleGraph: { idToModuleMap: new Map([['unlisted', source]]) } },
      {}
    ),
    {
      code: 'ERR_ASSERTION',
      message: 'Loaded source missing from pre-render snapshot: unlisted.vue',
    }
  );
});

test('physically missing loaded dependency remains an ENOENT failure', async () => {
  const scratch = resolve('tmp/instagram-931/qa-unit');
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(resolve(scratch, 'missing-'));
  const source = {
    id: 'missing.vue',
    file: resolve(root, 'missing.vue'),
    importedModules: new Set(),
  };
  const virtual = {
    id: '\0plugin-vue:export-helper',
    file: '\0plugin-vue:export-helper',
    importedModules: new Set(),
    transformResult: { code: 'export default {};' },
  };
  await assert.rejects(
    dependencyMap(
      root,
      {
        moduleGraph: {
          idToModuleMap: new Map([
            ['virtual', virtual],
            ['missing', source],
          ]),
        },
      },
      { 'missing.vue': sha256('previous source') }
    ),
    { code: 'ENOENT', path: source.file }
  );
});

test('dependency evidence separates virtual modules and hashes transformed code without opening virtual IDs', async () => {
  const scratch = resolve('tmp/instagram-931/qa-unit');
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(resolve(scratch, 'virtual-'));
  const file = resolve(root, 'source.js');
  await writeFile(file, 'physical source');
  const virtualId = '\0plugin-vue:export-helper';
  const virtual = {
    id: virtualId,
    file: virtualId,
    importedModules: new Set(),
    transformResult: { code: 'export default {};' },
  };
  const physical = {
    id: '\0wrapped-physical',
    file,
    importedModules: new Set([virtual]),
    transformResult: { code: 'transformed physical source' },
  };
  const unavailable = {
    id: '\0virtual-without-transform',
    file: null,
    importedModules: new Set(),
  };
  const result = await dependencyMap(
    root,
    {
      moduleGraph: {
        idToModuleMap: new Map([
          [file, physical],
          [virtualId, virtual],
          [unavailable.id, unavailable],
        ]),
      },
    },
    { 'source.js': sha256('physical source') }
  );
  assert.deepEqual(result.localSourcesUsed, ['source.js']);
  assert.deepEqual(result.servedModuleHashes, {
    'source.js': sha256('physical source'),
  });
  assert.deepEqual(result.transformedModuleHashes, {
    [physical.id]: sha256('transformed physical source'),
    [virtualId]: sha256('export default {};'),
  });
  const virtualRecord = result.modules.find(module => module.id === virtualId);
  assert.equal(
    result.modules.find(module => module.id === physical.id).kind,
    'physical'
  );
  assert.equal(virtualRecord.kind, 'virtual');
  assert.equal(virtualRecord.file, null);
  assert.equal(virtualRecord.transformedCodeAvailable, true);
  assert.equal(
    result.modules.find(module => module.id === unavailable.id)
      .transformedCodeAvailable,
    false
  );
  assert.equal(
    Object.hasOwn(result.transformedModuleHashes, unavailable.id),
    false
  );
});

test('physical dependency outside the allowed roots is rejected before hashing', async () => {
  const scratch = resolve('tmp/instagram-931/qa-unit');
  await mkdir(scratch, { recursive: true });
  const directory = await mkdtemp(resolve(scratch, 'boundary-'));
  const root = resolve(directory, 'root');
  await mkdir(root);
  const file = resolve(directory, 'outside.js');
  await writeFile(file, 'synthetic outside source');
  const source = { id: file, file, importedModules: new Set() };
  await assert.rejects(
    dependencyMap(
      root,
      {
        moduleGraph: { idToModuleMap: new Map([[file, source]]) },
      },
      {}
    ),
    {
      code: 'ERR_ASSERTION',
      message: `Loaded physical module outside allowed roots: ${file}`,
    }
  );
});

test('CSS fingerprints use explicit public and generated file mappings and still reject missing CSS', async () => {
  const scratch = resolve('tmp/instagram-931/qa-unit');
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(resolve(scratch, 'styles-'));
  const css = '/vite-test/assets/dashboard-test.css';
  const utilities = '/tmp/instagram-931/qa-evidence/current-utilities.css';
  const build = {
    css,
    utilities,
    styleFiles: {
      [css]: 'public/vite-test/assets/dashboard-test.css',
      [utilities]: 'tmp/instagram-931/qa-evidence/current-utilities.css',
    },
  };
  await Promise.all(
    Object.values(build.styleFiles).map(async file => {
      await mkdir(dirname(resolve(root, file)), { recursive: true });
      await writeFile(resolve(root, file), file);
    })
  );
  assert.deepEqual(await styleFingerprints(root, build), {
    [css]: sha256(build.styleFiles[css]),
    [utilities]: sha256(build.styleFiles[utilities]),
  });
  await assert.rejects(
    styleFingerprints(root, {
      ...build,
      styleFiles: {
        ...build.styleFiles,
        [css]: 'public/vite-test/assets/missing.css',
      },
    }),
    {
      code: 'ENOENT',
      path: resolve(root, 'public/vite-test/assets/missing.css'),
    }
  );
  await assert.rejects(styleFingerprints(root, { ...build, styleFiles: {} }), {
    code: 'ERR_ASSERTION',
  });
});

test('CSS evidence hashes the response bytes consumed and requires both style responses', async () => {
  const page = new EventEmitter();
  const origin = 'http://127.0.0.1:39211';
  const build = { css: '/dashboard.css', utilities: '/current-utilities.css' };
  const record = {};
  const verify = observeStyles(page, record, origin, build);
  await assert.rejects(verify(), { code: 'ERR_ASSERTION' });
  [build.css, build.utilities].forEach(path =>
    page.emit('response', {
      url: () => `${origin}${path}`,
      status: () => 200,
      body: async () => Buffer.from(`actually served ${path}`),
    })
  );
  await verify();
  assert.equal(record.stylesConsumed.length, 2);
  assert.equal(
    record.stylesConsumed[0].sha256,
    sha256(Buffer.from('actually served /dashboard.css'))
  );
  assert.ok(
    record.stylesConsumed.every(
      style => style.bytes > 0 && style.status === 200
    )
  );
});

test('changed served CSS invalidates the gallery even when its file path is unchanged', () => {
  const build = { css: '/dashboard.css', utilities: '/current-utilities.css' };
  const initial = {
    stylesConsumed: [
      { path: build.css, sha256: 'dashboard-a' },
      { path: build.utilities, sha256: 'utilities-a' },
    ],
  };
  assert.deepEqual(consumedStyleFingerprints([initial], build), {
    '/dashboard.css': 'dashboard-a',
    '/current-utilities.css': 'utilities-a',
  });
  assert.throws(
    () =>
      consumedStyleFingerprints(
        [
          initial,
          {
            stylesConsumed: [{ path: build.css, sha256: 'dashboard-b' }],
          },
        ],
        build
      ),
    { code: 'ERR_ASSERTION' }
  );
});
