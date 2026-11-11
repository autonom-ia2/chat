// #2858 F2 — o resultado do "Experimente" em linhas legíveis: os `dados` que o agente recebe viram pares
// [rótulo, valor]. Só aparece o campo que tem rótulo no i18n (AGENTS.VITRINE.CAMPOS.<CAMPO>): nunca a chave crua
// do servidor. Uma lista vira os três primeiros nomes e a contagem ("Acrelândia, Assis Brasil, Brasiléia e mais
// 19"); um objeto dentro de outro abre um nível só, com o rótulo <PAI>_<CAMPO>.
// #2858 F4 — lista de objetos: o nome de cada um vem do primeiro campo de CAMPOS_DE_NOME que todos têm (a seguradora,
// a descrição da NCM, o objeto da compra). Depois dos nomes, o primeiro item aberto (a situação do corretor, a
// distância da estação), e as listas dentro dele viram nomes também, um nível só. Com mais de um item, o primeiro só
// abre com 2 campos com rótulo além do nome, e a primeira linha diz de qual item se trata ("Primeiro da lista"):
// sem isso, o endereço de um hospital parecia valer para todos. Lista sem campo de nome: o primeiro aberto e quantos são.
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

// Dinheiro (a unidade "R$", ou o campo valor_*: o valor estimado da compra) tem separador de milhar; ano e código não.
const ehDinheiro = (chave, unidade) =>
  unidade.startsWith('R$') || String(chave).startsWith('valor_');

const numeroLegivel = (numero, idioma, unidade, comMilhar = false) => {
  const texto = new Intl.NumberFormat(idioma, {
    maximumFractionDigits: 4,
    useGrouping: comMilhar,
  }).format(numero);
  if (!unidade) return texto;
  return unidade.startsWith('R$')
    ? `${unidade} ${texto}`
    : `${texto} ${unidade}`;
};

// "-- Parafusos autoperfurantes" (o recuo da tabela da NCM) -> "Parafusos autoperfurantes".
const semTracoInicial = texto => {
  let resto = texto;
  while (resto.startsWith('-') || resto.startsWith(' ')) resto = resto.slice(1);
  return resto || texto;
};

// O nome completo igual ao nome (o banco) não se repete.
const repete = (objeto, chave, valor) =>
  chave === 'nome_completo' && valor === objeto.nome;

const valorLegivel = (chave, valor, textos, unidade) => {
  if (typeof valor === 'boolean') return valor ? textos.sim : textos.nao;
  if (typeof valor === 'number') {
    if (chave === 'ano_modelo' && valor === ANO_ZERO_KM) return textos.zeroKm;
    return numeroLegivel(
      valor,
      textos.idioma,
      unidade,
      ehDinheiro(chave, unidade)
    );
  }
  if (ehDataIso(valor)) return dataLegivel(valor, textos.idioma);
  return semTracoInicial(String(valor));
};

const resumoDaLista = (nomes, total, textos) => {
  const quantos = Math.max(total ?? 0, nomes.length);
  const primeiros = nomes.slice(0, PRIMEIROS).map(semTracoInicial);
  const resto = quantos - primeiros.length;
  if (resto > 0) {
    return textos.maisN({ nomes: primeiros.join(', '), n: resto });
  }
  return new Intl.ListFormat(textos.idioma, { type: 'conjunction' }).format(
    primeiros
  );
};

// O campo que dá nome aos objetos de uma lista, na ordem de preferência.
const CAMPOS_DE_NOME = [
  'nome',
  'seguradora',
  'descricao',
  'objeto',
  'razao_social',
];

const campoDeNome = itens =>
  CAMPOS_DE_NOME.find(campo =>
    itens.every(item => ehObjeto(item) && typeof item[campo] === 'string')
  );

const quantosSao = (itens, total, textos) =>
  numeroLegivel(Math.max(total ?? 0, itens.length), textos.idioma);

// Uma lista dentro do item aberto: os nomes, ou só quantos são (não abre de novo).
const resumoDentro = (itens, rotulo, total, textos) => {
  if (!rotulo || !itens.length) return [];
  if (itens.every(ehPrimitivo)) {
    return [[rotulo, resumoDaLista(itens.map(String), total, textos)]];
  }
  const campo = campoDeNome(itens);
  const nomes = campo ? itens.map(item => item[campo]) : null;
  const valor = nomes
    ? resumoDaLista(nomes, total, textos)
    : quantosSao(itens, total, textos);
  return [[rotulo, valor]];
};

// Os campos de um objeto, cada um com o rótulo de `rotuloDe`; `omitir`, o campo que já apareceu (o nome do item).
// A unidade de medida vale só no nível de cima (o "R$" do dólar): dentro de um item, `unidade` é outra coisa (a
// unidade do órgão na compra do governo).
const linhasSimples = (objeto, rotuloDe, textos, omitir = '') => {
  const comNomeDoEstado = typeof objeto.estado === 'string';
  const total = Number.isInteger(objeto.total) ? objeto.total : null;
  return Object.entries(objeto).flatMap(([chave, valor]) => {
    if (chave === omitir || repete(objeto, chave, valor)) return [];
    if (chave === 'uf' && comNomeDoEstado) return [];
    if (Array.isArray(valor)) {
      return resumoDentro(valor, rotuloDe(chave), total, textos);
    }
    const rotulo = ehPrimitivo(valor) ? rotuloDe(chave) : '';
    return rotulo ? [[rotulo, valorLegivel(chave, valor, textos, '')]] : [];
  });
};

// O primeiro item de uma lista com nome. Item único: os detalhes dele (o nome já está na lista). Mais de um: só com
// MINIMO_PARA_ABRIR campos com rótulo além do nome, e com o nome dele na primeira linha.
const MINIMO_PARA_ABRIR = 2;
const primeiroAberto = (itens, campo, textos) => {
  const detalhes = linhasSimples(itens[0], textos.rotulo, textos, campo);
  if (itens.length === 1) return detalhes;
  if (detalhes.length < MINIMO_PARA_ABRIR) return [];
  const nome = semTracoInicial(itens[0][campo]);
  return [[textos.rotulo('primeiro_da_lista'), nome], ...detalhes];
};

const linhasDaLista = (chave, itens, total, textos) => {
  if (!itens.length) return [];
  const rotulo = textos.rotulo(chave);
  if (itens.every(ehPrimitivo)) {
    return rotulo
      ? [[rotulo, resumoDaLista(itens.map(String), total, textos)]]
      : [];
  }
  const campo = campoDeNome(itens);
  if (campo) {
    const nomes = itens.map(item => item[campo]);
    const resumo = rotulo
      ? [[rotulo, resumoDaLista(nomes, total, textos)]]
      : [];
    return [...resumo, ...primeiroAberto(itens, campo, textos)];
  }
  // Lista de objetos sem nome (os preços de cada ano na tabela do carro): o primeiro aberto e quantos são.
  const primeiro = ehObjeto(itens[0])
    ? linhasSimples(itens[0], textos.rotulo, textos)
    : [];
  const quantos =
    itens.length > 1 && rotulo
      ? [[rotulo, quantosSao(itens, total, textos)]]
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
    if (repete(dados, chave, valor)) return [];
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
