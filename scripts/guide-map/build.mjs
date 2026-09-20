// Gerador do mapa do Guia da Plataforma (issue #534).
//
// O "onde fica" e o "por que importa" são escritos por nós, em
// lib/operator_guide/porques.md. A rota, o endereço e a permissão saem do PRÓPRIO
// roteador do painel — que é justamente o que envelhecia quando tudo era escrito
// à mão. Rode `pnpm guia:build` depois de mexer em rotas ou nas explicações.
//
// Saídas, ambas geradas e nunca editadas à mão:
//   lib/operator_guide/guia-produto.md                    — a base que o Guia ingere
//   app/javascript/dashboard/helper/guideRouteRegistry.js — para onde ele pode levar
import fs from 'fs';
import path from 'path';
import { createServer } from 'vite';
import { JSDOM } from 'jsdom';

const raiz = process.cwd();
const r = p => path.resolve(raiz, p);

const ENTRADA_ROTAS =
  '/app/javascript/dashboard/routes/dashboard/dashboard.routes.js';
const PORQUES = 'lib/operator_guide/porques.md';
const SAIDA_KB = 'lib/operator_guide/guia-produto.md';
const SAIDA_REGISTRY = 'app/javascript/dashboard/helper/guideRouteRegistry.js';

// Campos que o código sabe e o arquivo humano não repete.
const CAMPOS_GERADOS = ['rota', 'gate'];

// Alguns módulos da árvore de rotas tocam `window` ao serem importados. O gerador
// roda com o mesmo DOM de mentira que os testes já usam.
const prepararJanela = () => {
  const dom = new JSDOM('<!doctype html><html><body></body></html>', {
    url: 'https://local.test/',
  });
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
  globalThis.navigator = dom.window.navigator;
  globalThis.location = dom.window.location;
};

// O gerador quer as ROTAS, não a interface: componentes e estilos viram casca vazia.
const cascaVazia = {
  name: 'casca-vazia',
  enforce: 'pre',
  load: id => (/\.(vue|s?css)(\?|$)/.test(id) ? 'export default {}' : null),
};

const ALIASES = {
  vue: 'vue/dist/vue.esm-bundler.js',
  components: r('app/javascript/dashboard/components'),
  next: r('app/javascript/dashboard/components-next'),
  v3: r('app/javascript/v3'),
  dashboard: r('app/javascript/dashboard'),
  helpers: r('app/javascript/shared/helpers'),
  shared: r('app/javascript/shared'),
  assets: r('app/javascript/dashboard/assets'),
  widget: r('app/javascript/widget'),
  survey: r('app/javascript/survey'),
};

export const lerRotas = async () => {
  prepararJanela();
  const servidor = await createServer({
    configFile: false,
    plugins: [cascaVazia],
    resolve: { alias: ALIASES },
    server: { middlewareMode: true },
    optimizeDeps: { noDiscovery: true },
    logLevel: 'silent',
  });
  try {
    const modulo = await servidor.ssrLoadModule(ENTRADA_ROTAS);
    const rotas = [];

    // Rota filha tem caminho relativo ao pai. O endereço que interessa a quem lê o
    // Guia é o inteiro, então o percurso carrega o prefixo.
    const juntar = (prefixo, trecho) => {
      if (!trecho) return prefixo;
      if (trecho.startsWith('/')) return trecho;
      return `${prefixo.replace(/\/$/, '')}/${trecho}`;
    };

    const percorrer = (lista, prefixo = '') =>
      (lista || []).forEach(rota => {
        const caminho = juntar(prefixo, rota.path);
        if (rota.name) {
          rotas.push({
            nome: rota.name,
            caminho,
            papeis: rota.meta?.permissions || null,
            flag: rota.meta?.featureFlag || null,
          });
        }
        percorrer(rota.children, caminho);
      });
    percorrer(modulo.default?.routes || modulo.routes);
    return rotas;
  } finally {
    await servidor.close();
  }
};

// O arquivo humano usa o mesmo formato do KB: um bloco por fluxo, e o cabeçalho
// do bloco é o nome curto do fluxo. A tela vem no campo `rota`.
export const lerPorques = texto => {
  const blocos = texto.split(/^(?=### )/m).filter(b => b.startsWith('### '));
  return Object.fromEntries(
    blocos.map(bloco => {
      const linhas = bloco.split('\n');
      const chave = linhas[0].replace(/^###\s*/, '').trim();
      const campos = {};
      linhas.slice(1).forEach(linha => {
        const encontrado = linha.match(/^- ([a-z_]+):\s*(.*)$/);
        if (encontrado) campos[encontrado[1]] = encontrado[2].trim();
      });
      return [chave, campos];
    })
  );
};

const descreverPorta = rota => {
  const partes = [];
  if (rota.flag) partes.push(`feature flag \`${rota.flag}\``);
  if (rota.papeis?.length) {
    partes.push(`papel ${rota.papeis.map(p => `\`${p}\``).join(' ou ')}`);
  }
  return partes.length ? partes.join('; ') : 'sem restrição declarada na rota';
};

const montarFluxo = (chave, humano, rota) => {
  const linhas = [`### ${humano.titulo || chave}`];
  const campo = (nome, valor) => {
    if (valor) linhas.push(`- ${nome}: ${valor}`);
  };
  campo('intent', humano.intent);
  campo('onde_fica', humano.onde_fica);
  if (rota) {
    linhas.push(`- rota: \`${rota.nome}\` - \`${rota.caminho}\``);
    linhas.push(`- gate: ${descreverPorta(rota)}`);
  }
  campo('perfil', humano.perfil);
  campo('pre_requisitos', humano.pre_requisitos);
  campo('passos', humano.passos);
  campo('gotchas', humano.gotchas);
  campo('diagnostic', humano.diagnostic);
  const alvo = (humano.nav_target || rota?.nome || chave).replace(/`/g, '');
  linhas.push(`- nav_target: \`${alvo}\``);
  campo('highlight', humano.highlight);
  return linhas.join('\n');
};

const montarKb = fluxos =>
  [
    `# Guia da Plataforma Autonom.ia — base de conhecimento (${fluxos.length} fluxos)`,
    '',
    '> ARQUIVO GERADO por `pnpm guia:build`. Não edite à mão: a rota, o endereço e a',
    '> permissão saem do roteador do painel, e o texto humano fica em',
    '> `lib/operator_guide/porques.md`. Editar aqui é trabalho perdido no próximo build.',
    '',
    `Cada bloco é um fluxo: intent (perguntas), onde fica, ${CAMPOS_GERADOS.join(' e ')} (do código), perfil, pré-requisitos, passos, gotchas, nav_target.`,
    '',
    fluxos.join('\n\n'),
    '',
  ].join('\n');

const montarRegistry = (rotas, featuresEscritas = {}) => {
  const nomes = [...new Set(rotas.map(rota => rota.nome))].sort();

  // Nem toda exigência está no `meta` da rota: algumas telas checam a feature num
  // `beforeEnter` ou dentro do componente, e o roteador não conta isso. Para essas,
  // a exigência é declarada no bloco do fluxo em porques.md (`- feature: sla`).
  const features = new Map(
    rotas.filter(rota => rota.flag).map(rota => [rota.nome, rota.flag])
  );
  Object.entries(featuresEscritas).forEach(([nome, flag]) => {
    if (nomes.includes(nome)) features.set(nome, flag);
  });
  const comFlag = [...features.entries()].sort((a, b) =>
    a[0].localeCompare(b[0])
  );

  return [
    '// Guia da Plataforma — rotas para onde ele pode levar o usuário.',
    '//',
    '// ARQUIVO GERADO por `pnpm guia:build` a partir do roteador do painel. Não edite à mão.',
    '// Defesa em profundidade: o Guia só sugere navegação a partir do mapa, e o painel só',
    '// navega se o nome estiver AQUI E resolver no roteador E a pessoa tiver permissão.',
    'export const GUIDE_ROUTE_REGISTRY = new Set([',
    ...nomes.map(nome => `  '${nome}',`),
    ']);',
    '',
    '// Telas que dependem de uma feature: sem ela ligada na conta, o Guia não oferece o',
    '// botão — o backend negaria a tela e a pessoa cairia num beco.',
    'export const GUIDE_ROUTE_FEATURES = {',
    ...comFlag.map(([nome, flag]) => `  ${nome}: '${flag}',`),
    '};',
    '',
    'export const isGuideRoute = name => GUIDE_ROUTE_REGISTRY.has(name);',
    '',
    'export const guideRouteFeature = name => GUIDE_ROUTE_FEATURES[name] || null;',
    '',
    'export default GUIDE_ROUTE_REGISTRY;',
    '',
  ].join('\n');
};

export const construir = async ({ escrever = true } = {}) => {
  const rotas = await lerRotas();
  const porNome = new Map(rotas.map(rota => [rota.nome, rota]));
  const humanos = lerPorques(fs.readFileSync(r(PORQUES), 'utf8'));

  // Vários fluxos podem ensinar coisas diferentes na MESMA tela, então a chave do
  // bloco é o nome do fluxo e a tela vem no campo `rota`.
  const fluxos = [];
  const semRota = [];
  const rotasExplicadas = new Set();
  Object.entries(humanos).forEach(([chave, humano]) => {
    const rota = porNome.get(humano.rota);
    if (rota) rotasExplicadas.add(rota.nome);
    else semRota.push(chave);
    fluxos.push(montarFluxo(chave, humano, rota));
  });

  const semExplicacao = rotas
    .filter(rota => !rotasExplicadas.has(rota.nome))
    .map(rota => rota.nome);

  // Exigências de feature que o roteador não declara, escritas no bloco do fluxo.
  const featuresEscritas = Object.fromEntries(
    Object.values(humanos)
      .filter(humano => humano.feature && humano.rota)
      .map(humano => [humano.rota, humano.feature])
  );

  const kb = montarKb(fluxos);
  const registry = montarRegistry(rotas, featuresEscritas);
  if (escrever) {
    fs.writeFileSync(r(SAIDA_KB), kb);
    fs.writeFileSync(r(SAIDA_REGISTRY), registry);
  }

  return {
    kb,
    registry,
    fluxos: fluxos.length,
    rotas: rotas.length,
    semExplicacao,
    semRota,
  };
};

if (process.argv[1] && process.argv[1].endsWith('build.mjs')) {
  const resultado = await construir();
  console.log(
    `fluxos: ${resultado.fluxos} | rotas no mapa: ${resultado.rotas}`
  );
  console.log(`telas sem explicação: ${resultado.semExplicacao.length}`);
  console.log(
    `explicações sem rota: ${resultado.semRota.length}${
      resultado.semRota.length ? ` (${resultado.semRota.join(', ')})` : ''
    }`
  );
}
