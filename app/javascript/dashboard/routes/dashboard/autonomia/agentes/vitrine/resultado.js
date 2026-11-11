// #2858 F2 — o resultado do "Experimente" em linhas legíveis: os `dados` que o agente recebe viram pares
// [rótulo, valor]. Só aparece o campo que tem rótulo no i18n (AGENTS.VITRINE.CAMPOS.<CAMPO>): nunca a chave crua
// do servidor. Uma lista vira os três primeiros nomes e a contagem ("Acrelândia, Assis Brasil, Brasiléia e mais
// 19"); um objeto dentro de outro abre um nível só, com o rótulo <PAI>_<CAMPO>.
//
// `textos`:
//   rotulo(chave)          -> o rótulo do campo, ou '' quando não tem (o campo não aparece);
//   maisN({ nomes, n })    -> "Acrelândia, Assis Brasil, Brasiléia e mais 19";
//   sim, nao, zeroKm       -> os textos de verdadeiro, falso e do ano 32000 da tabela do carro;
//   idioma                 -> o idioma do navegador ("pt-BR") para datas, números e a lista curta.

const PRIMEIROS = 3;
// Na tabela do carro, o ano 32000 é o zero quilômetro.
const ANO_ZERO_KM = 32000;
const TAMANHO_DA_DATA = 10;

const ehObjeto = valor =>
  valor !== null && typeof valor === 'object' && !Array.isArray(valor);

const ehPrimitivo = valor =>
  ['string', 'number', 'boolean'].includes(typeof valor);

const ehDigito = caractere => caractere >= '0' && caractere <= '9';

// "2026-11-30" (o formato das datas que o servidor manda), conferido caractere a caractere.
const ehDataIso = texto =>
  typeof texto === 'string' &&
  texto.length === TAMANHO_DA_DATA &&
  texto[4] === '-' &&
  texto[7] === '-' &&
  [...texto.split('-').join('')].every(ehDigito);

const dataLegivel = (texto, idioma) => {
  const [ano, mes, dia] = texto.split('-').map(Number);
  return new Date(ano, mes - 1, dia).toLocaleDateString(idioma);
};

const numeroLegivel = (numero, idioma, unidade) => {
  const texto = new Intl.NumberFormat(idioma, {
    maximumFractionDigits: 4,
    useGrouping: false,
  }).format(numero);
  if (!unidade) return texto;
  return unidade.startsWith('R$')
    ? `${unidade} ${texto}`
    : `${texto} ${unidade}`;
};

const valorLegivel = (chave, valor, textos, unidade) => {
  if (typeof valor === 'boolean') return valor ? textos.sim : textos.nao;
  if (typeof valor === 'number') {
    if (chave === 'ano_modelo' && valor === ANO_ZERO_KM) return textos.zeroKm;
    return numeroLegivel(valor, textos.idioma, unidade);
  }
  if (ehDataIso(valor)) return dataLegivel(valor, textos.idioma);
  return String(valor);
};

const resumoDaLista = (nomes, total, textos) => {
  const quantos = Math.max(total ?? 0, nomes.length);
  const primeiros = nomes.slice(0, PRIMEIROS);
  const resto = quantos - primeiros.length;
  if (resto > 0) {
    return textos.maisN({ nomes: primeiros.join(', '), n: resto });
  }
  return new Intl.ListFormat(textos.idioma, { type: 'conjunction' }).format(
    primeiros
  );
};

// Os campos simples de um objeto, cada um com o rótulo de `rotuloDe`.
const linhasSimples = (objeto, rotuloDe, textos) => {
  const unidade = typeof objeto.unidade === 'string' ? objeto.unidade : '';
  const comNomeDoEstado = typeof objeto.estado === 'string';
  return Object.entries(objeto).flatMap(([chave, valor]) => {
    if (chave === 'uf' && comNomeDoEstado) return [];
    const rotulo = ehPrimitivo(valor) ? rotuloDe(chave) : '';
    return rotulo
      ? [[rotulo, valorLegivel(chave, valor, textos, unidade)]]
      : [];
  });
};

const linhasDaLista = (chave, itens, total, textos) => {
  if (!itens.length) return [];
  const rotulo = textos.rotulo(chave);
  if (itens.every(ehPrimitivo)) {
    return rotulo
      ? [[rotulo, resumoDaLista(itens.map(String), total, textos)]]
      : [];
  }
  if (itens.every(item => ehObjeto(item) && typeof item.nome === 'string')) {
    const nomes = itens.map(item => item.nome);
    return rotulo ? [[rotulo, resumoDaLista(nomes, total, textos)]] : [];
  }
  // Lista de objetos sem nome (os preços de cada ano na tabela do carro): o primeiro aberto e quantos são.
  const primeiro = ehObjeto(itens[0])
    ? linhasSimples(itens[0], textos.rotulo, textos)
    : [];
  const quantos =
    itens.length > 1 && rotulo
      ? [[rotulo, numeroLegivel(itens.length, textos.idioma)]]
      : [];
  return [...primeiro, ...quantos];
};

export const linhasDoResultado = (dados, textos) => {
  if (!ehObjeto(dados)) return [];
  const total = Number.isInteger(dados.total) ? dados.total : null;
  const unidade = typeof dados.unidade === 'string' ? dados.unidade : '';
  // A sigla do estado só aparece quando o nome dele não veio junto.
  const comNomeDoEstado = typeof dados.estado === 'string';
  return Object.entries(dados).flatMap(([chave, valor]) => {
    if (valor === null || valor === undefined) return [];
    if (chave === 'uf' && comNomeDoEstado) return [];
    if (Array.isArray(valor)) return linhasDaLista(chave, valor, total, textos);
    if (ehObjeto(valor)) {
      const prefixo = `${chave}_`;
      return linhasSimples(
        valor,
        filho => textos.rotulo(`${prefixo}${filho}`),
        textos
      );
    }
    const rotulo = textos.rotulo(chave);
    return rotulo
      ? [[rotulo, valorLegivel(chave, valor, textos, unidade)]]
      : [];
  });
};
