import { ESLint } from 'eslint';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// This is already a warning in the repository. Dynamic key contracts are covered
// by the real-locale render suite; all other warnings and every lint error fail.
export function violations(results) {
  return results.flatMap(file =>
    file.messages.filter(
      message =>
        message.severity === 2 ||
        message.ruleId !== '@intlify/vue-i18n/no-dynamic-keys'
    )
  );
}

async function main(files) {
  if (!files.length)
    throw new Error('Refusing an empty frontend lint selection');
  const eslint = new ESLint({
    overrideConfig: {
      settings: {
        'vue-i18n': {
          localeDir: './app/javascript/dashboard/i18n/locale/en/*.json',
        },
      },
      rules: { '@intlify/vue-i18n/no-missing-keys': 'error' },
    },
  });
  const results = await eslint.lintFiles(files);
  const target = 'tmp/email436/ci/eslint.json';
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, JSON.stringify(results, null, 2));
  const failures = violations(results);
  const warnings = results.reduce((sum, file) => sum + file.warningCount, 0);
  console.log(
    `ESLint: ${results.length} files, ${failures.length} blocking findings, ${warnings} dynamic-key warnings`
  );
  if (failures.length) {
    console.error((await eslint.loadFormatter('stylish')).format(results));
    process.exitCode = 1;
  }
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main(process.argv.slice(2)).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
