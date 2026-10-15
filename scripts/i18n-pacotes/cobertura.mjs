// #1550 — trava de cobertura do resultado de venda nos pacotes de segmento.
// Todo texto do catálogo base (painel e servidor, en e pt_BR) que fala em
// ganho/perda precisa de uma decisão: ou a camada do segmento troca o texto,
// ou a chave está em fora-do-pacote.json com o motivo. Chave nova sem decisão
// reprova o CI; exceção que não serve mais também reprova, para a lista não
// apodrecer. Lê só os nossos catálogos, com métodos de string (sem regex).
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import YAML from 'yaml';
import { baseDoPainel, baseDoServidor, camadasEncontradas } from './checar.mjs';

export const ARQUIVO_EXCECOES = 'scripts/i18n-pacotes/fora-do-pacote.json';

// pt: pedaço de palavra ("ganho", "ganhou", "perdido", "perda").
const PEDACOS_PT = ['ganh', 'perd'];
// en: palavra inteira; "won't" continua uma palavra só e não conta.
const PALAVRAS_EN = new Set(['won', 'win', 'lost', 'lose', 'loss', 'winning']);

const isObject = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

// Tira {x} e %{x}: nome de parâmetro não é texto que a pessoa lê.
const semParametros = texto => {
  let fora = '';
  let dentro = 0;
  [...texto].forEach(letra => {
    if (letra === '{') dentro += 1;
    else if (letra === '}' && dentro) dentro -= 1;
    else if (!dentro) fora += letra;
  });
  return fora;
};

const ehLetraDePalavra = letra =>
  letra.toLowerCase() !== letra.toUpperCase() ||
  (letra >= '0' && letra <= '9') ||
  letra === "'" ||
  letra === '’';

// Quebra em palavras por espaço e pontuação, letra a letra.
export const palavras = texto => {
  const lista = [];
  let atual = '';
  [...texto].forEach(letra => {
    if (ehLetraDePalavra(letra)) {
      atual += letra;
    } else {
      if (atual) lista.push(atual);
      atual = '';
    }
  });
  if (atual) lista.push(atual);
  return lista;
};

// Termos de ganho/perda que o texto usa, em minúsculas ([] quando não usa).
export function termosDeResultado(texto, idioma) {
  if (typeof texto !== 'string') return [];
  const limpo = semParametros(texto).toLowerCase();
  if (idioma === 'pt_BR') return PEDACOS_PT.filter(p => limpo.includes(p));
  return [...new Set(palavras(limpo).filter(p => PALAVRAS_EN.has(p)))];
}

// [[chave, texto]] de cada texto do catálogo; item de lista vira chave.N.
export function textos(arvore, prefixo = '') {
  if (typeof arvore === 'string') return [[prefixo, arvore]];
  const filhos = Array.isArray(arvore)
    ? arvore.map((valor, indice) => [String(indice), valor])
    : Object.entries(isObject(arvore) ? arvore : {});
  return filhos.flatMap(([chave, valor]) =>
    textos(valor, prefixo ? `${prefixo}.${chave}` : chave)
  );
}

const MOTIVO_FALTA = (catalogo, pastaDaCamada) =>
  `ponha o texto do segmento em ${pastaDaCamada} (en e pt_BR, e na camada do tipo se ele mudar) ` +
  `ou registre a chave em ${ARQUIVO_EXCECOES} > ${catalogo} com o motivo. Veja docs/segmentos/README.md.`;

// Um catálogo (painel ou servidor) contra o pacote e as exceções.
// base(idioma) e camada(idioma) devolvem árvores; camadas(idioma) devolve
// [[nome, árvore]] de todas as camadas, para conferir o texto do próprio pacote.
export function checarCatalogo({
  catalogo,
  idiomas,
  base,
  camada,
  pastaDaCamada,
  camadas = () => [],
  excecoes = {},
}) {
  const erros = [];
  const textosDoBase = new Map(
    idiomas.map(idioma => [idioma, new Map(textos(base(idioma)))])
  );
  const noPacote = idioma => new Set(textos(camada(idioma)).map(([c]) => c));

  idiomas.forEach(idioma => {
    const cobertas = noPacote(idioma);
    textosDoBase.get(idioma).forEach((texto, chave) => {
      const termos = termosDeResultado(texto, idioma);
      if (!termos.length || cobertas.has(chave) || chave in excecoes) return;
      erros.push(
        `${catalogo} ${idioma} ${chave} ("${texto}") fala em ${termos.join('/')} sem decisão: ${MOTIVO_FALTA(catalogo, pastaDaCamada)}`
      );
    });
    camadas(idioma).forEach(([nome, arvore]) => {
      textos(arvore).forEach(([chave, texto]) => {
        const termos = termosDeResultado(texto, idioma);
        if (termos.length) {
          erros.push(
            `${catalogo} ${idioma} ${chave}: o texto da camada ${nome} ainda fala em ${termos.join('/')}`
          );
        }
      });
    });
  });

  Object.entries(excecoes).forEach(([chave, motivo]) => {
    const onde = `${ARQUIVO_EXCECOES} > ${catalogo} > ${chave}`;
    if (typeof motivo !== 'string' || !motivo.trim()) {
      erros.push(`${onde}: falta o motivo`);
    }
    const noBase = idiomas.filter(idioma =>
      textosDoBase.get(idioma).has(chave)
    );
    if (!noBase.length) {
      erros.push(
        `${onde}: a chave não existe mais no catálogo base; tire da lista`
      );
      return;
    }
    const aindaFala = noBase.some(
      idioma =>
        termosDeResultado(textosDoBase.get(idioma).get(chave), idioma).length
    );
    if (!aindaFala) {
      erros.push(
        `${onde}: o texto não fala mais em ganho/perda; tire da lista`
      );
    }
    if (idiomas.some(idioma => noPacote(idioma).has(chave))) {
      erros.push(
        `${onde}: a chave está no pacote e nas exceções; fique com um dos dois`
      );
    }
  });
  return erros;
}

const lerJson = arquivo =>
  existsSync(arquivo) ? JSON.parse(readFileSync(arquivo, 'utf8')) : {};

const lerYml = (arquivo, idioma) =>
  existsSync(arquivo)
    ? YAML.parse(readFileSync(arquivo, 'utf8'))?.[idioma] || {}
    : {};

// Liga a trava aos arquivos do repositório; um par de checagens por segmento.
export function checarCobertura(
  pacotes,
  {
    excecoes = ARQUIVO_EXCECOES,
    dirLocalesPainel = 'app/javascript/dashboard/i18n/locale',
    dirLocalesServidor = 'config/locales',
  } = {}
) {
  if (!existsSync(excecoes))
    return [`${excecoes}: arquivo de exceções não existe`];
  const lista = JSON.parse(readFileSync(excecoes, 'utf8'));
  const { idiomas } = pacotes;
  const segmentos = Object.keys(
    isObject(pacotes.segmentos) ? pacotes.segmentos : {}
  );
  // Sem segmento não há o que conferir: passar calado esconderia a trava.
  if (!segmentos.length)
    return [
      'config/fork_i18n.json > pacotes.segmentos: nenhum segmento; a trava de cobertura não conferiu nada',
    ];
  const formatos = [
    {
      catalogo: 'painel',
      raiz: pacotes.painel,
      extensao: '.json',
      ler: lerJson,
      base: idioma => baseDoPainel(path.join(dirLocalesPainel, idioma)),
    },
    {
      catalogo: 'servidor',
      raiz: pacotes.servidor,
      extensao: '.yml',
      ler: lerYml,
      base: idioma => baseDoServidor(dirLocalesServidor, idioma),
    },
  ];
  return segmentos.flatMap(segmento =>
    formatos.flatMap(({ catalogo, raiz, extensao, ler, base }) => {
      const arquivo = (camada, idioma) =>
        path.join(raiz, camada, `${idioma}${extensao}`);
      const doSegmento = camadasEncontradas(raiz).filter(
        nome => nome === segmento || nome.startsWith(`${segmento}/`)
      );
      return checarCatalogo({
        catalogo,
        idiomas,
        base,
        camada: idioma => ler(arquivo(segmento, idioma), idioma),
        pastaDaCamada: `${raiz}/${segmento}/`,
        camadas: idioma =>
          doSegmento.map(nome => [nome, ler(arquivo(nome, idioma), idioma)]),
        excecoes: lista[catalogo] || {},
      });
    })
  );
}
