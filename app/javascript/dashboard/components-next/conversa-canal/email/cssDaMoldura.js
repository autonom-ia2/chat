// Na moldura isolada (#1884), a altura da tela da moldura é a do próprio e-mail. CSS que
// depende dela (100vh, @media de altura) faria o e-mail crescer ou piscar sem fim. Como no
// Gmail, onde o e-mail vive no documento dele, essas medidas valem para a janela do
// painel: viram px, e a @media de altura é decidida pela janela. A moldura é sempre
// clara: @media de tema escuro sai, a de tema claro vale sempre. Lê o CSSOM, sem regex.

// Sem contêiner, as de contêiner (cq*) também valem pela tela.
const UNIDADES_DA_ALTURA = [
  'vh',
  'svh',
  'lvh',
  'dvh',
  'vb',
  'svb',
  'lvb',
  'dvb',
  'cqh',
  'cqb',
];
const UNIDADES_DO_MENOR = ['vmin', 'svmin', 'lvmin', 'dvmin', 'cqmin'];
const UNIDADES_DO_MAIOR = ['vmax', 'svmax', 'lvmax', 'dvmax', 'cqmax'];
const DA_ALTURA_DA_TELA = ['height', 'aspect-ratio', 'orientation'];
const TEMA = 'prefers-color-scheme';
const ESCURO = 'dark';

const ehDigito = letra => letra >= '0' && letra <= '9';
const ehLetra = letra =>
  (letra >= 'a' && letra <= 'z') || (letra >= 'A' && letra <= 'Z');
const parteDeNome = letra =>
  ehLetra(letra) || ehDigito(letra) || letra === '-' || letra === '_';
const SINAIS = ['-', '+'];

// Número solto (`100vh`, `-50vh`), não pedaço de nome (`h1`, `--a2`).
const comecaNumero = (texto, i) => {
  const letra = texto[i];
  if (!ehDigito(letra) && letra !== '.') return false;
  const antes = texto[i - 1] || ' ';
  const anterior = SINAIS.includes(antes) ? texto[i - 2] || ' ' : antes;
  return !parteDeNome(anterior);
};

const pxDa = (unidade, tela) => {
  const nome = unidade.toLowerCase();
  if (UNIDADES_DA_ALTURA.includes(nome)) return tela.altura / 100;
  if (UNIDADES_DO_MENOR.includes(nome))
    return Math.min(tela.altura, tela.largura) / 100;
  if (UNIDADES_DO_MAIOR.includes(nome))
    return Math.max(tela.altura, tela.largura) / 100;
  return 0;
};

const EXPOENTE = ['e', 'E'];

// `1e+06`: o navegador grava assim número grande. Devolve onde o expoente acaba (ou
// `fim`, se não há expoente ali).
const fimDoExpoente = (texto, fim) => {
  if (!EXPOENTE.includes(texto[fim])) return fim;
  let depois = fim + 1;
  if (SINAIS.includes(texto[depois])) depois += 1;
  if (!ehDigito(texto[depois] || '')) return fim;
  while (depois < texto.length && ehDigito(texto[depois])) depois += 1;
  return depois;
};

// Lê o número que começa em `inicio` e a unidade logo depois dele.
const lerMedida = (texto, inicio) => {
  let fim = inicio;
  while (fim < texto.length && (ehDigito(texto[fim]) || texto[fim] === '.'))
    fim += 1;
  fim = fimDoExpoente(texto, fim);
  let fimDaUnidade = fim;
  while (fimDaUnidade < texto.length && ehLetra(texto[fimDaUnidade]))
    fimDaUnidade += 1;
  return {
    numero: texto.slice(inicio, fim),
    unidade: texto.slice(fim, fimDaUnidade),
    fim: fimDaUnidade,
  };
};

const fimDaAspa = (texto, inicio) => {
  const aspa = texto[inicio];
  let fim = inicio + 1;
  while (fim < texto.length && texto[fim] !== aspa) {
    fim += texto[fim] === '\\' ? 2 : 1;
  }
  return Math.min(fim + 1, texto.length);
};

// `calc(100vh - 20px)` → `calc(800px - 20px)`. Texto entre aspas (url, fonte) fica.
export const semUnidadeDaTela = (texto, tela) => {
  let saida = '';
  let i = 0;
  while (i < texto.length) {
    const letra = texto[i];
    if (letra === '"' || letra === "'") {
      const fim = fimDaAspa(texto, i);
      saida += texto.slice(i, fim);
      i = fim;
    } else if (comecaNumero(texto, i)) {
      const { numero, unidade, fim } = lerMedida(texto, i);
      const px = Number(numero) * pxDa(unidade, tela);
      // Só medida de verdade (`.vh` de seletor dá NaN e fica como está).
      saida +=
        Number.isFinite(px) && px !== 0
          ? `${Math.round(px * 100) / 100}px`
          : texto.slice(i, fim);
      i = fim;
    } else {
      saida += letra;
      i += 1;
    }
  }
  return saida;
};

// Dentro da @media só há regras de estilo (o resto já saiu em estiloSeguroDoEmail).
const regrasDe = (lista, tela) =>
  [...lista].map(regra => semUnidadeDaTela(regra.cssText, tela)).join('\n');

// O tema e a altura da tela são decididos aqui, parte a parte; o resto da condição
// (largura, tipo de mídia) continua com a moldura.
const E = ' and ';
const NEGACAO = 'not ';

// Uma parte da condição: true/false quando decidida aqui, null quando fica.
const decidirParte = (parte, tela) => {
  const texto = parte.toLowerCase();
  if (texto.includes(TEMA)) return !texto.includes(ESCURO);
  if (DA_ALTURA_DA_TELA.some(nome => texto.includes(nome))) {
    return tela.combina(parte);
  }
  return null;
};

// Uma condição (entre vírgulas): true (vale sempre), false (nunca) ou o que sobra dela.
const decidirCondicao = (condicao, tela) => {
  const negada = condicao.toLowerCase().startsWith(NEGACAO);
  const partes = (negada ? condicao.slice(NEGACAO.length) : condicao).split(E);
  const decisoes = partes.map(parte => decidirParte(parte, tela));
  if (negada) {
    return decisoes.includes(null) ? condicao : !decisoes.every(Boolean);
  }
  if (decisoes.includes(false)) return false;
  const resto = partes.filter((_, i) => decisoes[i] === null);
  return resto.length ? resto.join(E) : true;
};

const mediaDaMoldura = (regra, tela) => {
  const lista = regra.media;
  const regras = regrasDe(regra.cssRules, tela);
  const condicoes = Array.from({ length: lista.length }, (_, i) =>
    decidirCondicao(lista[i], tela)
  );
  if (!condicoes.length || condicoes.includes(true)) return regras;
  const restam = condicoes.filter(condicao => typeof condicao === 'string');
  return restam.length ? `@media ${restam.join(', ')} {\n${regras}\n}` : '';
};

export const regraDaMoldura = (regra, tela) => {
  if (regra instanceof CSSMediaRule) return mediaDaMoldura(regra, tela);
  return semUnidadeDaTela(regra.cssText, tela);
};

// A janela do painel, onde o e-mail estaria no Gmail.
export const telaDoPainel = () => ({
  altura: window.innerHeight,
  largura: window.innerWidth,
  combina: condicao => window.matchMedia(condicao).matches,
});
