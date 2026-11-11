// #2858 F2 — o resultado do "Experimente" em linhas legíveis: os `dados` que o agente recebe viram pares
// [rótulo, valor]. Só aparece o campo que tem rótulo no i18n (AGENTS.VITRINE.CAMPOS.<CAMPO>): nunca a chave crua
// do servidor. Uma lista vira os três primeiros nomes e a contagem ("Acrelândia, Assis Brasil, Brasiléia e mais
// 19"); um objeto dentro de outro abre um nível só, com o rótulo <PAI>_<CAMPO>.
// #2858 F4 — lista de objetos: o nome de cada um vem do primeiro campo de CAMPOS_DE_NOME que todos têm (a seguradora,
// a descrição da NCM, o objeto da compra). Depois dos nomes, o primeiro item aberto (a situação do corretor, a
// distância da estação), e as listas dentro dele viram nomes também, um nível só. Com mais de um item, o primeiro só
// abre com 2 campos com rótulo além do nome, e a primeira linha diz de qual item se trata ("Primeiro da lista"):
// sem isso, o endereço de um hospital parecia valer para todos. Lista sem campo de nome (#2858 F7): um item só abre
// inteiro; com mais de um, o item é identificado por CAMPOS_IDENTIFICADORES e o primeiro vai sob "Primeiro da lista";
// sem identificador, só a contagem. Uma unidade de campo pode vir em `unidades` (campo -> unidade), no nível de cima.
// #2858 regra final da lista sem nome: a linha dos identificadores leva o rótulo do próprio identificador ("Combustível:
// Gasolina e Flex"); o rótulo da lista só aparece na contagem. Todos os itens com o mesmo único campo além do
// identificador viram pares numa linha com o rótulo desse campo ("Chuva no dia (mm): 04/11/2026: 0,9 · …").
//
// `textos`:
//   rotulo(chave)          -> o rótulo do campo, ou '' quando não tem (o campo não aparece);
//   maisN({ nomes, n })    -> "Acrelândia, Assis Brasil, Brasiléia e mais 19";
//   sim, nao, zeroKm       -> os textos de verdadeiro, falso e do ano 32000 da tabela do carro;
//   nenhumValor            -> o "—" do item da linha de pares que veio sem o valor;
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

// O Date empurra a data impossível para outra ("2026-02-31" vira 03/03): se ano, mês e dia não batem com o texto, a
// data não existe.
const bateComODia = (data, ano, mes, dia) =>
  data.getFullYear() === ano &&
  data.getMonth() === mes - 1 &&
  data.getDate() === dia;

const dataLegivel = (texto, idioma) => {
  const [ano, mes, dia] = texto.split('-').map(Number);
  const data = new Date(ano, mes - 1, dia);
  if (!bateComODia(data, ano, mes, dia)) return texto;
  return data.toLocaleDateString(idioma);
};

// "AAAA-MM-DD HH:MM", com ":ss" e fração opcionais, com espaço ou "T" no meio; hora até 23, minuto e segundo até 59.
// Com fuso no fim ou qualquer outro texto, não é data com hora: o texto vai como veio (nenhuma fonte manda fuso).
const HORA_MAXIMA = 23;
const MINUTO_MAXIMO = 59;
const ehNumeroDeDoisDigitos = (texto, maximo) =>
  texto.length === 2 && [...texto].every(ehDigito) && Number(texto) <= maximo;
const ehFracao = resto =>
  resto === '' ||
  (resto.startsWith('.') &&
    resto.length > 1 &&
    [...resto.slice(1)].every(ehDigito));
const ehSegundos = resto =>
  resto === '' ||
  (resto.startsWith(':') &&
    ehNumeroDeDoisDigitos(resto.slice(1, 3), MINUTO_MAXIMO) &&
    ehFracao(resto.slice(3)));
const ehDataComHora = texto =>
  typeof texto === 'string' &&
  ehDataIso(texto.slice(0, TAMANHO_DA_DATA)) &&
  [' ', 'T'].includes(texto[TAMANHO_DA_DATA]) &&
  ehNumeroDeDoisDigitos(texto.slice(11, 13), HORA_MAXIMA) &&
  texto[13] === ':' &&
  ehNumeroDeDoisDigitos(texto.slice(14, 16), MINUTO_MAXIMO) &&
  ehSegundos(texto.slice(16));

const dataComHoraLegivel = (texto, idioma) => {
  const [ano, mes, dia] = texto
    .slice(0, TAMANHO_DA_DATA)
    .split('-')
    .map(Number);
  const [hora, minuto] = [texto.slice(11, 13), texto.slice(14, 16)].map(Number);
  const data = new Date(ano, mes - 1, dia, hora, minuto);
  if (!bateComODia(data, ano, mes, dia)) return texto;
  const horario = data.toLocaleTimeString(idioma, {
    hour: '2-digit',
    minute: '2-digit',
  });
  return `${data.toLocaleDateString(idioma)} ${horario}`;
};

// Dinheiro (a unidade "R$", ou o campo valor_*: o valor estimado da compra) tem de 2 a 4 casas (a PTAX tem 4).
const ehDinheiro = (chave, unidade) =>
  unidade.startsWith('R$') || String(chave).startsWith('valor_');

// Todo número tem separador de milhar, menos o que identifica (ano, CEP, código, registro, documento): esse vai como
// veio e sem unidade, nem quando há `unidade` no nível de cima.
const CHAVES_DE_IDENTIFICACAO = [
  'ano',
  'ano_modelo',
  'cep',
  'matricula',
  'numero',
  'cnpj',
  'cpf',
  'ispb',
  'cnes',
  'ddd',
  'rntrc',
];
const PREFIXOS_DE_IDENTIFICACAO = ['codigo', 'registro'];
const ehIdentificacao = chave =>
  CHAVES_DE_IDENTIFICACAO.includes(chave) ||
  PREFIXOS_DE_IDENTIFICACAO.some(prefixo => String(chave).startsWith(prefixo));

const numeroLegivel = (
  numero,
  idioma,
  unidade = '',
  dinheiro = false,
  agrupa = true
) => {
  const texto = new Intl.NumberFormat(idioma, {
    minimumFractionDigits: dinheiro ? 2 : 0,
    maximumFractionDigits: 4,
    useGrouping: agrupa,
  }).format(numero);
  if (!unidade) return texto;
  return unidade.startsWith('R$')
    ? `${unidade} ${texto}`
    : `${texto} ${unidade}`;
};

// "-- Parafusos autoperfurantes" (o recuo da tabela da NCM) -> "Parafusos autoperfurantes". Só no nome do item e na
// descrição: em outro texto o traço pode ser o sinal ("-0,5").
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
    if (ehIdentificacao(chave)) {
      return numeroLegivel(valor, textos.idioma, '', false, false);
    }
    return numeroLegivel(
      valor,
      textos.idioma,
      unidade,
      ehDinheiro(chave, unidade)
    );
  }
  if (ehDataIso(valor)) return dataLegivel(valor, textos.idioma);
  if (ehDataComHora(valor)) return dataComHoraLegivel(valor, textos.idioma);
  return chave === 'descricao' ? semTracoInicial(String(valor)) : String(valor);
};

// A lista curta: os três primeiros (já legíveis) e quantos faltam. Com `separador` (os pares "data: valor"), ele
// separa os itens, porque a vírgula se confundiria com a do número, e vem também antes do "e mais N".
const resumoDaLista = (legiveis, total, textos, separador = '') => {
  const quantos = Math.max(total ?? 0, legiveis.length);
  const primeiros = legiveis.slice(0, PRIMEIROS);
  const resto = quantos - primeiros.length;
  if (resto > 0) {
    const nomes = separador
      ? `${primeiros.join(separador)}${separador.trimEnd()}`
      : primeiros.join(', ');
    return textos.maisN({ nomes, n: resto });
  }
  if (separador) return primeiros.join(separador);
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
// #2858 F7 — sem nome, o que identifica cada item (o número do telefone, a placa, o ano do preço), na ordem de
// preferência. Só identifica o campo que tem valor diferente em cada item: dois combustíveis do mesmo ano pulam o
// ano. `tipo` fica fora: é categoria ("Hospital geral" em vários). Sem nenhum, a lista de mais de um item é contada.
const CAMPOS_IDENTIFICADORES = [
  'numero',
  'telefone',
  'email',
  'placa',
  'cno',
  'conselho',
  'ano',
  'ano_modelo',
  'combustivel',
  'data',
];
// Campos que ficam sem rótulo de propósito (não aparecem): `ispb` (código interno do banco, sem uso para o dono),
// `cnes` (o cadastro do estabelecimento no Ministério da Saúde; o nome e o endereço dizem mais), `regiao` (só na lista
// de estados, onde abrir o primeiro estado não ajuda), `coberturas` e `condicoes` (ficam dentro de cada produto, um
// nível abaixo do que a tela abre: a lista de produtos mostra os nomes).

const campoComum = (itens, campos, aceita) =>
  campos.find(campo =>
    itens.every(item => ehObjeto(item) && aceita(item[campo]))
  );
const campoDeNome = itens =>
  campoComum(itens, CAMPOS_DE_NOME, valor => typeof valor === 'string');
const todosDiferentes = (itens, campo) =>
  new Set(itens.map(item => item[campo])).size === itens.length;
// O identificador precisa de rótulo: é ele que dá nome à linha ("Combustível: Gasolina e Flex").
const campoIdentificador = (itens, textos) =>
  CAMPOS_IDENTIFICADORES.filter(
    campo =>
      textos.rotulo(campo) &&
      campoComum(itens, [campo], valor =>
        ['string', 'number'].includes(typeof valor)
      )
  ).find(campo => todosDiferentes(itens, campo));

// A unidade de um campo: `unidades` (campo -> unidade), mandada no nível de cima (a mediana do Focus).
const unidadeDe = (textos, chave) => {
  const { unidades } = textos;
  return unidades &&
    Object.hasOwn(unidades, chave) &&
    typeof unidades[chave] === 'string'
    ? unidades[chave]
    : '';
};

const legivel = (chave, valor, textos) =>
  valorLegivel(chave, valor, textos, unidadeDe(textos, chave));
const nomesLegiveis = (itens, campo) =>
  itens.map(item => semTracoInicial(String(item[campo])));
const identificadores = (itens, campo, textos) =>
  itens.map(item => legivel(campo, item[campo], textos));

const quantosSao = (itens, total, textos) =>
  numeroLegivel(Math.max(total ?? 0, itens.length), textos.idioma);

// Os itens de uma lista, legíveis: valores simples ou nomes; null quando não há nenhum dos dois.
const legiveisDaLista = (chave, itens, textos) => {
  if (itens.every(ehPrimitivo)) {
    return itens.map(item => legivel(chave, item, textos));
  }
  const nome = campoDeNome(itens);
  return nome ? nomesLegiveis(itens, nome) : null;
};

// Lista sem nome com identificador: a linha leva o rótulo do identificador. null quando não é esse o caso.
const linhaDosIdentificadores = (itens, total, textos) => {
  if (itens.every(ehPrimitivo) || campoDeNome(itens)) return null;
  const id = campoIdentificador(itens, textos);
  if (!id) return null;
  const ids = identificadores(itens, id, textos);
  return [textos.rotulo(id), resumoDaLista(ids, total, textos)];
};

// Uma lista dentro do item aberto: os nomes, os identificadores ou só quantos são (não abre de novo).
const resumoDentro = (chave, itens, rotulo, total, textos) => {
  if (!rotulo || !itens.length) return [];
  const doIdentificador = linhaDosIdentificadores(itens, total, textos);
  if (doIdentificador) return [doIdentificador];
  const legiveis = legiveisDaLista(chave, itens, textos);
  const valor = legiveis
    ? resumoDaLista(legiveis, total, textos)
    : quantosSao(itens, total, textos);
  return [[rotulo, valor]];
};

// Os campos de um objeto, cada um com o rótulo de `rotuloDe`; `omitir`, o campo que já apareceu (o nome do item).
// A unidade de medida vale só no nível de cima (o "R$" do dólar) ou por `unidades`: dentro de um item, `unidade` é
// outra coisa (a unidade do órgão na compra do governo).
const linhasSimples = (objeto, rotuloDe, textos, omitir = '') => {
  const comNomeDoEstado = typeof objeto.estado === 'string';
  const total = Number.isInteger(objeto.total) ? objeto.total : null;
  return Object.entries(objeto).flatMap(([chave, valor]) => {
    if (chave === omitir || repete(objeto, chave, valor)) return [];
    if (chave === 'uf' && comNomeDoEstado) return [];
    if (Array.isArray(valor)) {
      return resumoDentro(chave, valor, rotuloDe(chave), total, textos);
    }
    const rotulo = ehPrimitivo(valor) ? rotuloDe(chave) : '';
    return rotulo ? [[rotulo, legivel(chave, valor, textos)]] : [];
  });
};

// O primeiro item de uma lista com nome. Item único (a lista inteira tem um só, contado pelo total da fonte): os
// detalhes dele (o nome já está na lista). Mais de um: só com MINIMO_PARA_ABRIR campos com rótulo além do nome, e com o
// nome dele na primeira linha.
const MINIMO_PARA_ABRIR = 2;
const primeiroAberto = (itens, campo, umSo, textos) => {
  const detalhes = linhasSimples(itens[0], textos.rotulo, textos, campo);
  if (umSo) return detalhes;
  if (detalhes.length < MINIMO_PARA_ABRIR) return [];
  const [nome] = nomesLegiveis(itens, campo);
  return [[textos.rotulo('primeiro_da_lista'), nome], ...detalhes];
};

// O campo da linha de pares: o único campo com rótulo além do identificador, o mesmo em todos os itens, com valor
// simples. Item sem o campo, ou com ele nulo, entra com "—". '' quando os itens têm campos diferentes ou mais de um.
const campoDosPares = (itens, id, textos) => {
  const campos = new Set(
    itens.flatMap(item =>
      Object.keys(item).filter(chave => chave !== id && textos.rotulo(chave))
    )
  );
  if (campos.size !== 1) return '';
  const [campo] = campos;
  const simples = itens.every(
    item =>
      item[campo] === null ||
      item[campo] === undefined ||
      ehPrimitivo(item[campo])
  );
  return simples ? campo : '';
};

const valorDoPar = (item, campo, textos) =>
  item[campo] === null || item[campo] === undefined
    ? textos.nenhumValor
    : legivel(campo, item[campo], textos);

// Lista sem nome e com mais de um item. Todos com o mesmo único campo além do identificador (a chuva de cada dia): os
// pares numa linha com o rótulo do campo ("Chuva no dia (mm): 04/11/2026: 0,9 · 05/11/2026: 6,2 · e mais 4").
// Senão, os identificadores com o rótulo do identificador e, com MINIMO_PARA_ABRIR campos com rótulo (a mesma regra da
// lista com nome), o primeiro sob "Primeiro da lista". Sem identificador, só quantos são, com o rótulo da lista (abrir
// o primeiro faria os campos dele parecerem valer para todos).
const SEPARADOR_DE_PARES = ' · ';
const listaSemNome = (rotulo, itens, total, textos) => {
  // Lista sem rótulo não aparece (coberturas, condicoes), nem pelo identificador nem pelos pares.
  if (!rotulo) return [];
  const id = campoIdentificador(itens, textos);
  if (!id) return [[rotulo, quantosSao(itens, total, textos)]];
  const ids = identificadores(itens, id, textos);
  const campo = campoDosPares(itens, id, textos);
  if (campo) {
    const pares = itens.map(
      (item, i) => `${ids[i]}: ${valorDoPar(item, campo, textos)}`
    );
    return [
      [
        textos.rotulo(campo),
        resumoDaLista(pares, total, textos, SEPARADOR_DE_PARES),
      ],
    ];
  }
  const resumo = [[textos.rotulo(id), resumoDaLista(ids, total, textos)]];
  const detalhes = linhasSimples(itens[0], textos.rotulo, textos, id);
  if (detalhes.length < MINIMO_PARA_ABRIR) return resumo;
  return [...resumo, [textos.rotulo('primeiro_da_lista'), ids[0]], ...detalhes];
};

const linhasDaLista = (chave, itens, total, textos) => {
  if (!itens.length) return [];
  const rotulo = textos.rotulo(chave);
  if (itens.every(ehPrimitivo)) {
    const valores = itens.map(item => legivel(chave, item, textos));
    return rotulo ? [[rotulo, resumoDaLista(valores, total, textos)]] : [];
  }
  const umSo = Math.max(total ?? 0, itens.length) === 1;
  const campo = campoDeNome(itens);
  if (campo) {
    const nomes = nomesLegiveis(itens, campo);
    const resumo = rotulo
      ? [[rotulo, resumoDaLista(nomes, total, textos)]]
      : [];
    return [...resumo, ...primeiroAberto(itens, campo, umSo, textos)];
  }
  // Um item só sem nome (o preço do carro de um ano): ele inteiro.
  if (umSo) {
    return ehObjeto(itens[0])
      ? linhasSimples(itens[0], textos.rotulo, textos)
      : [];
  }
  return listaSemNome(rotulo, itens, total, textos);
};

export const linhasDoResultado = (dados, textosDaTela) => {
  if (!ehObjeto(dados)) return [];
  const unidades = ehObjeto(dados.unidades) ? dados.unidades : {};
  const textos = { ...textosDaTela, unidades };
  const total = Number.isInteger(dados.total) ? dados.total : null;
  const unidade = typeof dados.unidade === 'string' ? dados.unidade : '';
  // A sigla do estado só aparece quando o nome dele não veio junto.
  const comNomeDoEstado = typeof dados.estado === 'string';
  return Object.entries(dados).flatMap(([chave, valor]) => {
    if (valor === null || valor === undefined || chave === 'unidades') {
      return [];
    }
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
    const daLinha = unidade || unidadeDe(textos, chave);
    return rotulo
      ? [[rotulo, valorLegivel(chave, valor, textos, daLinha)]]
      : [];
  });
};
