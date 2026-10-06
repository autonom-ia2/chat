// Gera builder/mjmlAllowedAttributes.json (#1074): para cada componente MJML, os atributos que ele
// aceita (`allowedAttributes`). Fonte da verdade: o mjml-browser que o grapesjs-mjml usa para
// compilar o e-mail no editor. O registro de componentes não é exportado pelo bundle, então lemos o
// próprio código com o parser do Babel e pegamos as chamadas
//   _defineProperty(Componente, "componentName", "mj-x")
//   _defineProperty(Componente, "allowedAttributes", { ... })
// O front (mjmlCanonical.js) e o back (EmailCampaigns::MjmlCanonicalizer) leem o mesmo JSON.
//
// Uso: node scripts/mjml-attributes/build.mjs           (gera)
//      node scripts/mjml-attributes/build.mjs --check   (falha se o JSON estiver fora de dia)
import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { parse } from '@babel/parser';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const OUTPUT = path.join(
  ROOT,
  'app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/mjmlAllowedAttributes.json'
);

const mjmlBrowserPath = () => {
  const require = createRequire(path.join(ROOT, 'package.json'));
  const pluginDir = path.dirname(require.resolve('grapesjs-mjml/package.json'));
  const pluginRequire = createRequire(path.join(pluginDir, 'package.json'));
  return pluginRequire.resolve('mjml-browser');
};

const keyName = key => (key.type === 'Identifier' ? key.name : key.value);

// Every node of the AST, in source order.
const nodesOf = ast => {
  const found = [];
  const stack = [ast];
  while (stack.length) {
    const node = stack.pop();
    if (node && typeof node.type === 'string') found.push(node);
    Object.values(node || {}).forEach(value => {
      if (Array.isArray(value)) value.forEach(item => item && typeof item === 'object' && stack.push(item));
      else if (value && typeof value === 'object' && typeof value.type === 'string') stack.push(value);
    });
  }
  return found.sort((a, b) => a.start - b.start);
};

// _defineProperty(Identifier, "prop", value) -> { target, prop, value }
const definePropertyCall = node => {
  if (node.type !== 'CallExpression' || node.arguments.length !== 3) return null;
  const [target, prop, value] = node.arguments;
  if (target.type !== 'Identifier' || prop.type !== 'StringLiteral') return null;
  return { target: target.name, prop: prop.value, value };
};

// Components whose allowedAttributes spread another component's (the bundle references it by
// module, which a static read cannot follow). build() fails if a new one shows up unlisted.
const INHERITS = { 'mj-wrapper': 'mj-section' };

// Literal keys of an allowedAttributes value; `inherits` when it spreads something else.
const attributeKeys = node => {
  if (node.type === 'ObjectExpression') {
    return node.properties.reduce(
      (acc, prop) =>
        prop.type === 'SpreadElement'
          ? { keys: acc.keys, inherits: true }
          : { keys: [...acc.keys, keyName(prop.key)], inherits: acc.inherits },
      { keys: [], inherits: false }
    );
  }
  if (node.type === 'CallExpression') {
    return node.arguments.map(attributeKeys).reduce(
      (acc, part) => ({ keys: [...acc.keys, ...part.keys], inherits: acc.inherits || part.inherits }),
      { keys: [], inherits: false }
    );
  }
  return { keys: [], inherits: true };
};

const withInherited = (raw, inherited) =>
  Object.fromEntries(
    Object.entries(raw).map(([name, keys]) => {
      if (!inherited.has(name)) return [name, keys];
      const parent = INHERITS[name];
      if (!parent || !raw[parent]) throw new Error(`${name}: allowedAttributes herdado sem pai conhecido`);
      return [name, [...new Set([...raw[parent], ...keys])]];
    })
  );

export const extractAllowedAttributes = source => {
  const ast = parse(source, { sourceType: 'script', errorRecovery: false });
  const nameByTarget = {};
  const table = {};
  const inherited = new Set();
  nodesOf(ast).forEach(node => {
    const call = definePropertyCall(node);
    if (!call) return;
    if (call.prop === 'componentName' && call.value.type === 'StringLiteral') {
      nameByTarget[call.target] = call.value.value;
    } else if (call.prop === 'allowedAttributes') {
      const name = nameByTarget[call.target];
      if (!name) return;
      const { keys, inherits } = attributeKeys(call.value);
      table[name] = keys;
      if (inherits) inherited.add(name);
    }
  });
  const resolved = withInherited(table, inherited);
  return Object.fromEntries(Object.keys(resolved).sort().map(name => [name, resolved[name]]));
};

export const build = () => {
  const file = mjmlBrowserPath();
  const version = JSON.parse(
    fs.readFileSync(path.join(path.dirname(file), '..', 'package.json'), 'utf8')
  ).version;
  const table = extractAllowedAttributes(fs.readFileSync(file, 'utf8'));
  return `${JSON.stringify({ source: `mjml-browser ${version}`, components: table }, null, 2)}\n`;
};

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = build();
  if (process.argv.includes('--check')) {
    const current = fs.existsSync(OUTPUT) ? fs.readFileSync(OUTPUT, 'utf8') : '';
    if (current !== out) {
      process.stderr.write('mjmlAllowedAttributes.json fora de dia: rode node scripts/mjml-attributes/build.mjs\n');
      process.exit(1);
    }
  } else {
    fs.writeFileSync(OUTPUT, out);
  }
}
