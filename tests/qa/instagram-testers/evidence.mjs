/* eslint-disable no-await-in-loop, no-restricted-syntax -- Bounded filesystem batches avoid exhausting file descriptors. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir, realpath } from 'node:fs/promises';
import { isAbsolute, relative, resolve } from 'node:path';

export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

// Includes all local transitive imports, locale catalogs, Sass and Tailwind
// content inputs, rather than a hand-maintained list of the visible components.
const sourceTrees = [
  'app/javascript',
  'app/assets/stylesheets',
  'app/views',
  'enterprise/app/javascript',
  'enterprise/app/assets/stylesheets',
  'enterprise/app/views',
  'theme',
  'tests/qa/instagram-testers',
];
const sourceFiles = [
  'tailwind.config.js',
  'postcss.config.js',
  'vite.config.ts',
  'package.json',
  'pnpm-lock.yaml',
];

async function treeFiles(root, tree) {
  const entries = await readdir(resolve(root, tree), {
    withFileTypes: true,
  }).catch(error => {
    if (error.code === 'ENOENT') return [];
    throw error;
  });
  const children = await Promise.all(
    entries.map(entry => {
      const path = `${tree}/${entry.name}`;
      if (entry.isDirectory()) return treeFiles(root, path);
      return entry.isFile() ? [path] : [];
    })
  );
  return children.flat();
}

async function hashPaths(paths, toFile) {
  const pairs = [];
  for (let offset = 0; offset < paths.length; offset += 32)
    pairs.push(
      ...(await Promise.all(
        paths
          .slice(offset, offset + 32)
          .map(async path => [path, sha256(await readFile(toFile(path)))])
      ))
    );
  return Object.fromEntries(pairs);
}

export async function sourceFingerprints(root) {
  const trees = await Promise.all(
    sourceTrees.map(tree => treeFiles(root, tree))
  );
  const paths = [...new Set([...sourceFiles, ...trees.flat()])].sort();
  return hashPaths(paths, path => resolve(root, path));
}

export async function styleFingerprints(root, build) {
  return Object.fromEntries(
    await Promise.all(
      [build.css, build.utilities].map(async path => {
        const file = build.styleFiles[path];
        assert.ok(file, `CSS URL missing its physical file mapping: ${path}`);
        return [path, sha256(await readFile(resolve(root, file)))];
      })
    )
  );
}

export function consumedStyleFingerprints(records, build) {
  return Object.fromEntries(
    [build.css, build.utilities].map(path => {
      const hashes = new Set(
        records
          .flatMap(record => record.stylesConsumed || [])
          .filter(style => style.path === path)
          .map(style => style.sha256)
      );
      assert.equal(
        hashes.size,
        1,
        `Consumed CSS missing or changed between cases: ${path}`
      );
      return [path, [...hashes][0]];
    })
  );
}

// Also covers style tags injected by Vite for imported Sass/Vue modules.
export async function captureUsedStyleSheets(page) {
  const sheets = await page.evaluate(() =>
    [...document.styleSheets].map(sheet => ({
      href: sheet.href,
      owner:
        sheet.ownerNode?.getAttribute('data-vite-dev-id') ||
        sheet.ownerNode?.tagName,
      disabled: sheet.disabled,
      rules: [...sheet.cssRules].map(rule => rule.cssText).join('\n'),
    }))
  );
  return sheets.map(({ rules, ...sheet }) => ({
    ...sheet,
    bytes: Buffer.byteLength(rules),
    sha256: sha256(rules),
  }));
}

export async function dependencyMap(
  root,
  server,
  baseline,
  physicalRoots = [root]
) {
  const modules = [...server.moduleGraph.idToModuleMap.values()];
  // A virtual ID may still have a real file anchor; that file must be audited.
  const virtual = module => !module.file || module.file.startsWith('\0');
  const files = [
    ...new Set(
      modules.filter(module => !virtual(module)).map(module => module.file)
    ),
  ].sort();
  const allowedRoots = await Promise.all(
    physicalRoots.map(path => realpath(path))
  );
  for (const file of files) {
    assert.ok(
      isAbsolute(file) &&
        physicalRoots.some(path => resolve(file).startsWith(`${path}/`)),
      `Loaded physical module outside allowed roots: ${file}`
    );
    const canonical = await realpath(file);
    assert.ok(
      allowedRoots.some(path => canonical.startsWith(`${path}/`)),
      `Loaded physical module resolves outside allowed roots: ${file}`
    );
  }
  const sourceFilesUsed = files.filter(file => {
    const path = relative(root, file);
    return (
      file.startsWith(`${root}/`) &&
      !path.startsWith('node_modules/') &&
      !path.startsWith('tmp/')
    );
  });
  for (const file of sourceFilesUsed) {
    const path = relative(root, file);
    assert.ok(
      baseline[path],
      `Loaded source missing from pre-render snapshot: ${path}`
    );
    assert.equal(
      sha256(await readFile(file)),
      baseline[path],
      `Loaded source changed: ${path}`
    );
  }
  return {
    localSourcesUsed: sourceFilesUsed.map(file => relative(root, file)),
    modules: modules
      .map(module => ({
        id: module.id,
        kind: virtual(module) ? 'virtual' : 'physical',
        file: virtual(module) ? null : relative(root, module.file),
        transformedCodeAvailable:
          typeof module.transformResult?.code === 'string',
        imports: [...module.importedModules].map(child => child.id).sort(),
      }))
      .sort((a, b) => String(a.id).localeCompare(String(b.id))),
    servedModuleHashes: await hashPaths(
      files.map(file => relative(root, file)),
      path => resolve(root, path)
    ),
    transformedModuleHashes: Object.fromEntries(
      modules
        .filter(module => typeof module.transformResult?.code === 'string')
        .map(module => [module.id, sha256(module.transformResult.code)])
    ),
  };
}

// These are response bytes consumed by Chromium, not merely CSS file names.
export function observeStyles(page, record, origin, build) {
  const pending = [];
  record.stylesConsumed = [];
  page.on('response', response => {
    const url = new URL(response.url());
    if (
      url.origin !== origin ||
      ![build.css, build.utilities].includes(url.pathname)
    )
      return;
    pending.push(
      (async () => {
        const bytes = await response.body();
        record.stylesConsumed.push({
          path: url.pathname,
          status: response.status(),
          bytes: bytes.length,
          sha256: sha256(bytes),
        });
      })()
    );
  });
  return async () => {
    await Promise.all(pending);
    for (const path of [build.css, build.utilities]) {
      const styles = record.stylesConsumed.filter(style => style.path === path);
      assert.ok(
        styles.length &&
          styles.every(style => style.status === 200 && style.bytes > 0),
        `CSS response not consumed: ${path}`
      );
    }
  };
}
