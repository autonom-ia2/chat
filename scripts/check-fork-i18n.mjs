/* eslint-disable no-restricted-syntax, no-continue, no-console -- Standalone Node CLI: synchronous catalog traversal and diagnostic output. */
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import YAML from 'yaml';
import {
  camadasEncontradas,
  checarPacotes,
  parametros as parameters,
} from './i18n-pacotes/checar.mjs';
import { checarCobertura } from './i18n-pacotes/cobertura.mjs';

const root = 'app/javascript/dashboard/i18n/locale';
const registry = JSON.parse(readFileSync('config/fork_i18n.json', 'utf8'));
const crowdin = YAML.parse(readFileSync('crowdin.yml', 'utf8'));
const dashboard = crowdin.files.find(
  file => file.source === `/${root}/en/*.json`
);
const excluded = registry.catalogs
  .map(({ file }) => `/${root}/en/${file}`)
  .sort();
assert.deepEqual(
  [...dashboard.ignore].sort(),
  excluded,
  'Crowdin exclusions must match the fork registry'
);
assert.equal(new Set(excluded).size, excluded.length, 'Duplicate fork catalog');

function leaves(value, prefix = '') {
  if (typeof value === 'string') return [[prefix, value]];
  assert(
    value && typeof value === 'object' && !Array.isArray(value),
    `Invalid catalog node: ${prefix}`
  );
  return Object.entries(value).flatMap(([key, child]) =>
    leaves(child, prefix ? `${prefix}.${key}` : key)
  );
}

const locales = readdirSync(root, { withFileTypes: true })
  .filter(entry => entry.isDirectory())
  .map(entry => entry.name);
let messages = 0;
for (const {
  file,
  sourceLocale = registry.defaultSourceLocale,
} of registry.catalogs) {
  const source = new Map(
    leaves(JSON.parse(readFileSync(`${root}/${sourceLocale}/${file}`, 'utf8')))
  );
  for (const locale of locales) {
    const path = `${root}/${locale}/${file}`;
    if (!existsSync(path)) {
      assert(
        !registry.requiredLocales.includes(locale),
        `Missing required ${path}`
      );
      continue;
    }
    const translated = new Map(leaves(JSON.parse(readFileSync(path, 'utf8'))));
    for (const [key, value] of translated) {
      assert(value.trim(), `Empty ${locale}/${file}:${key}`);
      const params = parameters(value, `${locale}/${file}:${key}`);
      if (source.has(key) && registry.requiredLocales.includes(locale)) {
        assert.deepEqual(
          params,
          parameters(source.get(key), key),
          `Parameters differ: ${locale}/${file}:${key}`
        );
      }
      messages += 1;
    }
    if (registry.requiredLocales.includes(locale)) {
      for (const key of source.keys())
        assert(translated.has(key), `Missing ${locale}/${file}:${key}`);
      const index = readFileSync(`${root}/${locale}/index.js`, 'utf8');
      assert(
        index.includes(`'./${file}'`),
        `Catalog not imported: ${locale}/${file}`
      );
    }
  }
}

if (process.env.CROWDIN_SYNC === 'true') {
  assert(
    process.env.PR_BASE_SHA,
    'PR_BASE_SHA is required for sync protection'
  );
  const changed = execFileSync(
    'git',
    ['diff', '--name-only', `${process.env.PR_BASE_SHA}...HEAD`],
    { encoding: 'utf8' }
  )
    .trim()
    .split('\n');
  const protectedFiles = new Set(registry.catalogs.map(({ file }) => file));
  const overwritten = changed.filter(
    path =>
      path.startsWith(`${root}/`) && protectedFiles.has(path.split('/').at(-1))
  );
  assert.equal(
    overwritten.length,
    0,
    `Crowdin sync modifies fork-owned catalogs: ${overwritten.join(', ')}`
  );
}
// #1550 — pacotes de tradução por conta: chaves, idiomas, parâmetros e camadas.
const erros = [
  ...checarPacotes(registry.pacotes, { crowdin }),
  // Todo ganho/perda do base tem decisão: pacote do segmento ou exceção com motivo.
  ...checarCobertura(registry.pacotes),
];
assert.equal(erros.length, 0, erros.join('\n'));
const pacotes =
  camadasEncontradas(registry.pacotes.painel).length +
  camadasEncontradas(registry.pacotes.servidor).length;
console.log(
  `${registry.catalogs.length} fork catalogs checked; ${messages} messages compiled; en/pt_BR keys and parameters covered; ${pacotes} translation packs checked.`
);
