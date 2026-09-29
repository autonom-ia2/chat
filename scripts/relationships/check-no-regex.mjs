import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { extname } from 'node:path';

const require = createRequire(import.meta.url);
const babel = createRequire(require.resolve('@vitejs/plugin-vue'))(
  '@babel/parser'
);
const vue = createRequire(require.resolve('eslint-plugin-vue'))(
  'vue-eslint-parser'
);
const BASE = '8396d7255e097ba79507a22081701eb41ddb6ce5';
const git = args =>
  execFileSync('git', args, {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'ignore'],
  });
const names = new Set([
  ...git(['diff', '--name-only', '-z', BASE]).split('\0'),
  ...git(['ls-files', '--others', '--exclude-standard', '-z']).split('\0'),
]);
const files = [...names].filter(
  file =>
    existsSync(file) &&
    ['.js', '.mjs', '.ts', '.vue', '.rb'].includes(extname(file))
);
const forbiddenNames = new Set([
  'RegExp',
  'Regexp',
  'getRegexp',
  'normalizeRegexPattern',
]);
function javascript(source, file) {
  const ast = file.endsWith('.vue')
    ? vue.parse(source, {
        sourceType: 'module',
        ecmaVersion: 2022,
        range: true,
      })
    : babel.parse(source, {
        sourceType: 'unambiguous',
        plugins: file.endsWith('.ts') ? ['typescript'] : [],
      });
  const found = [];
  const seen = new Set();
  function visit(node) {
    if (!node || typeof node !== 'object' || seen.has(node)) return;
    seen.add(node);
    if (
      node.type === 'RegExpLiteral' ||
      node.regex ||
      (node.type === 'Identifier' && forbiddenNames.has(node.name))
    ) {
      const start = node.range?.[0] ?? node.start;
      const end = node.range?.[1] ?? node.end;
      found.push(source.slice(start, end));
    }
    Object.entries(node).forEach(([key, child]) => {
      if (['parent', 'tokens', 'comments', 'loc'].includes(key)) return;
      if (Array.isArray(child)) child.forEach(visit);
      else visit(child);
    });
  }
  visit(ast);
  return found;
}
const entries = files.map(file => {
  let before = '';
  try {
    before = git(['show', `${BASE}:${file}`]);
  } catch {
    /* Added file. */
  }
  return { file, before, after: readFileSync(file, 'utf8') };
});
const rubyEntries = entries.filter(({ file }) => file.endsWith('.rb'));
const rubyNodes = JSON.parse(
  execFileSync(
    'bundle',
    ['exec', 'ruby', 'scripts/relationships/check_no_regex.rb'],
    {
      input: JSON.stringify(
        rubyEntries.flatMap(({ before, after }) => [before, after])
      ),
      encoding: 'utf8',
      maxBuffer: 10 * 1024 * 1024,
    }
  )
);
const parsedRuby = new Map(
  rubyEntries.map(({ file }, index) => [
    file,
    rubyNodes.slice(index * 2, index * 2 + 2),
  ])
);
const violations = [];
entries.forEach(({ file, before, after }) => {
  const [oldNodes, newNodes] = file.endsWith('.rb')
    ? parsedRuby.get(file)
    : [javascript(before, file), javascript(after, file)];
  const remaining = [...oldNodes];
  newNodes.forEach(node => {
    const index = remaining.indexOf(node);
    if (index === -1) violations.push(file);
    else remaining.splice(index, 1);
  });
});
if (violations.length) {
  process.stderr.write(
    `New regex AST nodes or matcher imports:\n${[...new Set(violations)].join('\n')}\n`
  );
  process.exitCode = 1;
} else
  process.stdout.write(
    `No new regex: ${files.length} changed source/test files parsed against ${BASE}.\n`
  );
