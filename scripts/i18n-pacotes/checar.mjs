/* eslint-disable no-restricted-syntax, no-continue -- Standalone Node checker: synchronous tree traversal. */
// #1550 — confere os pacotes de tradução por conta (painel e servidor) contra o
// catálogo base. Funções puras sobre arquivos; quem chama decide o que fazer
// com a lista de erros (check-fork-i18n.mjs reprova o CI).
//
// Reprova:
//  (a) chave do pacote que não é folha de texto no base do mesmo idioma;
//  (b) idiomas da mesma camada com chaves diferentes, idioma faltando ou fora da lista;
//  (c) parâmetros diferentes do base ({x} no painel, %{x} no servidor);
//  (d) pasta fora de seguros e seguros/<tipo>, raiz do yml diferente do nome do
//      arquivo, mensagem vazia, arquivo que não é <idioma>.json / <idioma>.yml.
// E confere que nenhuma fonte do crowdin.yml cobre as pastas de pacote.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import YAML from 'yaml';

const require = createRequire(import.meta.url);
const i18nRequire = createRequire(require.resolve('vue-i18n'));
const coreRequire = createRequire(i18nRequire.resolve('@intlify/core-base'));
const { baseCompile } = coreRequire('@intlify/message-compiler');

const isObject = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

// Parâmetros de uma mensagem do vue-i18n ({nome}, {0}), pelo compilador do próprio vue-i18n.
export function parametros(message, label) {
  const { ast } = baseCompile(message, {
    onError: error => {
      throw new Error(`${label}: ${error.message}`);
    },
  });
  const names = new Set();
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 4) names.add(node.key);
    if (node.type === 5) names.add(String(node.index));
    Object.values(node).forEach(child => {
      if (Array.isArray(child)) child.forEach(visit);
      else if (child && typeof child === 'object') visit(child);
    });
  }
  visit(ast);
  return [...names].sort();
}

// Parâmetros de uma mensagem do I18n do Rails (%{nome}), varrendo com indexOf.
export function parametrosRuby(message) {
  const names = new Set();
  let inicio = message.indexOf('%{');
  while (inicio !== -1) {
    const fim = message.indexOf('}', inicio + 2);
    if (fim === -1) break;
    names.add(message.slice(inicio + 2, fim));
    inicio = message.indexOf('%{', fim + 1);
  }
  return [...names].sort();
}

// "seguros" e "seguros/<tipo>" para cada segmento do registro.
export function camadasValidas(pacotes) {
  return Object.entries(pacotes?.segmentos || {}).flatMap(
    ([segmento, tipos]) => [
      segmento,
      ...tipos.map(tipo => `${segmento}/${tipo}`),
    ]
  );
}

// [[caminho, valor]] de cada folha; nó que não é texto nem objeto vira folha também,
// para quem chama acusar.
export function folhas(value, prefix = '') {
  if (!isObject(value)) return [[prefix, value]];
  return Object.entries(value).flatMap(([key, child]) =>
    folhas(child, prefix ? `${prefix}.${key}` : key)
  );
}

const valorEm = (arvore, caminho) =>
  caminho
    .split('.')
    .reduce((no, chave) => (isObject(no) ? no[chave] : undefined), arvore);

const entreAspas = (texto, depois) => {
  const inicio = texto.indexOf("'", depois);
  const fim = texto.indexOf("'", inicio + 1);
  return inicio === -1 || fim === -1 ? null : texto.slice(inicio + 1, fim);
};

// Catálogo do painel de um idioma, montado como locale/<l>/index.js monta:
// `import X from './Y.json'` e o spread raso na mesma ordem do export.
export function baseDoPainel(dirLocale) {
  const linhas = readFileSync(path.join(dirLocale, 'index.js'), 'utf8')
    .split('\n')
    .map(linha => linha.trim());
  const arquivos = new Map();
  linhas
    .filter(linha => linha.startsWith('import ') && linha.endsWith(".json';"))
    .forEach(linha => {
      const nome = linha
        .slice('import '.length, linha.indexOf(' from '))
        .trim();
      arquivos.set(nome, entreAspas(linha, linha.indexOf(' from ')));
    });
  return linhas
    .filter(linha => linha.startsWith('...') && linha.endsWith(','))
    .map(linha => linha.slice(3, -1))
    .reduce((base, nome) => {
      const arquivo = arquivos.get(nome);
      if (!arquivo)
        throw new Error(
          `${dirLocale}/index.js: ...${nome} sem import de .json`
        );
      return {
        ...base,
        ...JSON.parse(readFileSync(path.join(dirLocale, arquivo), 'utf8')),
      };
    }, {});
}

const mesclar = (alvo, fonte) => {
  if (!isObject(alvo) || !isObject(fonte)) return fonte;
  const resultado = { ...alvo };
  Object.entries(fonte).forEach(([chave, valor]) => {
    resultado[chave] = mesclar(alvo[chave], valor);
  });
  return resultado;
};

// Catálogo do servidor de um idioma: todo yml de config/locales cuja raiz é o idioma.
export function baseDoServidor(dirLocales, idioma) {
  return readdirSync(dirLocales)
    .filter(nome => nome.endsWith('.yml'))
    .sort()
    .map(nome => YAML.parse(readFileSync(path.join(dirLocales, nome), 'utf8')))
    .filter(doc => isObject(doc) && isObject(doc[idioma]))
    .reduce((base, doc) => mesclar(base, doc[idioma]), {});
}

// Pastas (relativas a raiz) que guardam arquivos, com os nomes dos arquivos.
function pastasComArquivos(raiz, relativa = '') {
  const entradas = readdirSync(path.join(raiz, relativa), {
    withFileTypes: true,
  });
  const arquivos = entradas
    .filter(e => e.isFile())
    .map(e => e.name)
    .sort();
  const filhas = entradas
    .filter(e => e.isDirectory())
    .flatMap(e =>
      pastasComArquivos(raiz, relativa ? `${relativa}/${e.name}` : e.name)
    );
  return arquivos.length ? [{ camada: relativa, arquivos }, ...filhas] : filhas;
}

export function camadasEncontradas(raiz) {
  return existsSync(raiz)
    ? pastasComArquivos(raiz).map(({ camada }) => camada)
    : [];
}

// Uma mensagem do pacote contra a do base: texto não vazio, folha de texto no base e mesmos parâmetros.
function erroDaMensagem({ onde, chave, valor, catalogo, idioma, params }) {
  if (typeof valor !== 'string' || !valor.trim()) {
    return `${onde}: mensagem vazia ou não é texto`;
  }
  const original = valorEm(catalogo, chave);
  if (typeof original !== 'string') {
    return `${onde}: não é folha de texto no catálogo base de ${idioma}`;
  }
  try {
    const doPacote = params(valor, onde).join(',');
    const doBase = params(original, `${idioma}:${chave}`).join(',');
    return doPacote === doBase
      ? null
      : `${onde}: parâmetros [${doPacote}] diferem do base [${doBase}]`;
  } catch (error) {
    return error.message;
  }
}

// Um arquivo de uma camada: { erros, idioma, chaves } (sem idioma quando o nome ou o conteúdo não servem).
function checarArquivo(
  { raiz, extensao, idiomas, ler, base, params },
  camada,
  arquivo
) {
  const rotulo = `${raiz}/${camada || '.'}/${arquivo}`;
  const idioma = arquivo.endsWith(extensao)
    ? arquivo.slice(0, -extensao.length)
    : null;
  if (!idioma || !idiomas.includes(idioma)) {
    const aceitos = idiomas.map(i => i + extensao).join(', ');
    return { erros: [`${rotulo}: arquivo fora de ${aceitos}`] };
  }
  const lido = ler(path.join(raiz, camada, arquivo), idioma);
  if (lido.erro) return { erros: [`${rotulo}: ${lido.erro}`] };

  const catalogo = base(idioma);
  const lista = folhas(lido.mensagens);
  const erros = lista
    .map(([chave, valor]) =>
      erroDaMensagem({
        onde: `${rotulo}:${chave}`,
        chave,
        valor,
        catalogo,
        idioma,
        params,
      })
    )
    .filter(Boolean);
  return { erros, idioma, chaves: lista.map(([chave]) => chave).sort() };
}

// Os idiomas de uma camada: nenhum faltando e todos com as mesmas chaves.
function errosDosIdiomas({
  rotulo,
  idiomas,
  extensao,
  arquivos,
  chavesPorIdioma,
}) {
  const faltando = idiomas
    .filter(
      idioma =>
        !chavesPorIdioma.has(idioma) && !arquivos.includes(idioma + extensao)
    )
    .map(idioma => `${rotulo}: falta ${idioma}${extensao}`);
  const [referencia, ...outros] = [...chavesPorIdioma.entries()];
  const divergentes = outros
    .filter(([, chaves]) => chaves.join('|') !== referencia[1].join('|'))
    .map(
      ([idioma]) =>
        `${rotulo}: ${idioma}${extensao} e ${referencia[0]}${extensao} têm chaves diferentes`
    );
  return [...faltando, ...divergentes];
}

function checarCamada(contexto, { camada, arquivos }) {
  const { raiz, validas, idiomas, extensao } = contexto;
  const rotulo = `${raiz}/${camada || '.'}`;
  if (!validas.includes(camada)) {
    return [`${rotulo}: camada fora de ${validas.join(', ')}`];
  }
  const resultados = arquivos.map(arquivo =>
    checarArquivo(contexto, camada, arquivo)
  );
  const chavesPorIdioma = new Map(
    resultados.filter(r => r.idioma).map(r => [r.idioma, r.chaves])
  );
  return [
    ...resultados.flatMap(r => r.erros),
    ...errosDosIdiomas({
      rotulo,
      idiomas,
      extensao,
      arquivos,
      chavesPorIdioma,
    }),
  ];
}

// Regras comuns a painel e servidor; `ler` devolve { mensagens } ou { erro } de um arquivo,
// `base(idioma)` o catálogo base e `params` a função de parâmetros do formato.
function checarArvore(contexto) {
  if (!existsSync(contexto.raiz)) {
    return [`${contexto.raiz}: pasta de pacotes não existe`];
  }
  return pastasComArquivos(contexto.raiz).flatMap(pasta =>
    checarCamada(contexto, pasta)
  );
}

const lerJson = arquivo => {
  try {
    const mensagens = JSON.parse(readFileSync(arquivo, 'utf8'));
    return isObject(mensagens)
      ? { mensagens }
      : { erro: 'o json precisa ser um objeto' };
  } catch (error) {
    return { erro: `json inválido (${error.message})` };
  }
};

const lerYml = (arquivo, idioma) => {
  let doc;
  try {
    doc = YAML.parse(readFileSync(arquivo, 'utf8'));
  } catch (error) {
    return { erro: `yml inválido (${error.message})` };
  }
  const raizes = isObject(doc) ? Object.keys(doc) : [];
  if (raizes.length !== 1 || raizes[0] !== idioma || !isObject(doc[idioma])) {
    return {
      erro: `a raiz do yml precisa ser só "${idioma}:" (achou ${raizes.join(', ') || 'nada'})`,
    };
  }
  return { mensagens: doc[idioma] };
};

const memo = fn => {
  const cache = new Map();
  return chave => {
    if (!cache.has(chave)) cache.set(chave, fn(chave));
    return cache.get(chave);
  };
};

export function checarPainel({ raiz, dirLocales, pacotes }) {
  return checarArvore({
    raiz,
    extensao: '.json',
    idiomas: pacotes.idiomas,
    validas: camadasValidas(pacotes),
    ler: lerJson,
    base: memo(idioma => baseDoPainel(path.join(dirLocales, idioma))),
    params: parametros,
  });
}

export function checarServidor({ raiz, dirLocales, pacotes }) {
  return checarArvore({
    raiz,
    extensao: '.yml',
    idiomas: pacotes.idiomas,
    validas: camadasValidas(pacotes),
    ler: lerYml,
    base: memo(idioma => baseDoServidor(dirLocales, idioma)),
    params: parametrosRuby,
  });
}

// Nenhuma fonte do Crowdin pode cobrir as pastas de pacote: elas são do fork.
// Compara o trecho fixo da fonte (antes do primeiro *) com a pasta, nos dois sentidos.
export function checarCrowdin(crowdin, pacotes) {
  const pastas = [pacotes.painel, pacotes.servidor].map(pasta => `/${pasta}/`);
  return (crowdin?.files || []).flatMap(({ source }) => {
    const estrela = source.indexOf('*');
    const fixo = estrela === -1 ? source : source.slice(0, estrela);
    return pastas
      .filter(pasta => pasta.startsWith(fixo) || fixo.startsWith(pasta))
      .map(
        pasta =>
          `crowdin.yml: a fonte ${source} cobre ${pasta}; pacotes não vão ao Crowdin`
      );
  });
}

export function checarPacotes(
  pacotes,
  {
    crowdin,
    dirLocalesPainel = 'app/javascript/dashboard/i18n/locale',
    dirLocalesServidor = 'config/locales',
  } = {}
) {
  if (!pacotes) return ['config/fork_i18n.json: falta a chave "pacotes"'];
  return [
    ...checarPainel({
      raiz: pacotes.painel,
      dirLocales: dirLocalesPainel,
      pacotes,
    }),
    ...checarServidor({
      raiz: pacotes.servidor,
      dirLocales: dirLocalesServidor,
      pacotes,
    }),
    ...checarCrowdin(crowdin, pacotes),
  ];
}
