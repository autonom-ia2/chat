// #2897 — a planilha que traz seguros, em funções puras: o que a leitura de
// "Trazer minha lista" (trazer/useTrazerLista.js) ganha na conta que tem a
// carteira de seguros e o que a tela conta a partir dela. Nada aqui interpreta
// texto de pessoa: são os códigos que o servidor manda.
//   - a pergunta `seguros` ("Esta planilha tem seguros?"), com a resposta `sim`
//     ou `nao`;
//   - com `sim`, a leitura traz o bloco `seguros`: os destinos de seguro que as
//     colunas podem ter (`destinos`), quais são obrigatórios (`obrigatorios`),
//     os obrigatórios que ainda não têm coluna (`faltam`) e a coluna que o
//     servidor sugere para cada destino ainda sem coluna (`sugestao`). Sugerida
//     não é escolhida: só vale o destino que a coluna tem em `colunas`, e é a
//     confirmação da pessoa que o põe lá. Enquanto falta algum obrigatório, as
//     linhas ainda não foram conferidas como seguro;
//   - conferida, o `resumo` diz quantos seguros entram, de quantas pessoas, e
//     quantos de cada tipo. O tipo de cada seguro já vem decidido.
// Cada número diz "seguros" ou "pessoas": `resumo.novas` e `resumo.completadas`
// contam linhas e não aparecem na planilha com seguros.
import { contarProblemas, problemasPorCarregar } from '../trazer/contagem';
import { TIPOS_DE_SEGURO } from './tiposDeSeguro';

export const PERGUNTA_SEGUROS = 'seguros';
export const TEM_SEGUROS = 'sim';
export const SO_PESSOAS = 'nao';

const ZERO = 0;

// A pessoa respondeu que a planilha tem seguros (só então o bloco existe).
export const temSeguros = leitura => Boolean(leitura?.seguros);

// Os destinos obrigatórios que ainda não têm coluna, na ordem do servidor.
export const destinosQueFaltam = leitura => leitura?.seguros?.faltam ?? [];

// As linhas já foram conferidas como seguro (há o que contar e o que trazer).
export const segurosConferidos = leitura =>
  temSeguros(leitura) && destinosQueFaltam(leitura).length === ZERO;

// ---- as colunas ---------------------------------------------------------------

// O nome de cada destino de seguro na tela. Destino que a tela não conhece
// (o servidor ganhou um novo) não é oferecido.
const BASE_DOS_DESTINOS = 'RELACIONAMENTOS_CARTEIRA.TRAZER.DESTINOS';
const CHAVES_DOS_DESTINOS = new Map([
  ['seguro_numero', `${BASE_DOS_DESTINOS}.NUMERO`],
  ['seguro_seguradora', `${BASE_DOS_DESTINOS}.SEGURADORA`],
  ['seguro_tipo', `${BASE_DOS_DESTINOS}.TIPO`],
  ['seguro_termina', `${BASE_DOS_DESTINOS}.TERMINA`],
  ['seguro_comeca', `${BASE_DOS_DESTINOS}.COMECA`],
  ['seguro_valor', `${BASE_DOS_DESTINOS}.VALOR`],
  ['seguro_bem', `${BASE_DOS_DESTINOS}.BEM`],
]);

export const chaveDoDestino = destino => CHAVES_DOS_DESTINOS.get(destino);

// `[{ value, chave }]`: os destinos de seguro que esta leitura aceita.
export const destinosDeSeguro = leitura =>
  (leitura?.seguros?.destinos ?? [])
    .filter(destino => CHAVES_DOS_DESTINOS.has(destino))
    .map(destino => ({ value: destino, chave: chaveDoDestino(destino) }));

// Onde está cada coisa do seguro, antes de as linhas serem conferidas:
// `[{ destino, chave, obrigatorio, situacao, coluna }]`, na ordem do servidor.
// `mexidas` é o que a pessoa escolheu na tela e ainda não confirmou
// (`{ destino: índice da coluna }`; nulo: ela deu a coluna a outro destino).
//   - CONFIRMADA: o servidor já guarda a coluna deste destino;
//   - ESCOLHIDA: a pessoa apontou a coluna agora, e falta confirmar;
//   - SUGERIDA: o servidor sugere a coluna, e falta confirmar;
//   - FALTA: obrigatório sem coluna (a pessoa aponta à mão);
//   - OPCIONAL: não é obrigatório e não tem coluna (a planilha pode não ter).
export const SITUACAO_DA_COLUNA = {
  CONFIRMADA: 'confirmada',
  ESCOLHIDA: 'escolhida',
  SUGERIDA: 'sugerida',
  FALTA: 'falta',
  OPCIONAL: 'opcional',
};

const DESTINO_LIVRE = 'informacao';

const colunaDoDestino = (leitura, destino, mexidas) => {
  const colunas = leitura?.colunas ?? [];
  const existe = indice => colunas.some(coluna => coluna.indice === indice);
  const confirmada = colunas.find(coluna => coluna.destino === destino);
  if (destino in mexidas && mexidas[destino] !== confirmada?.indice) {
    return existe(mexidas[destino])
      ? { situacao: SITUACAO_DA_COLUNA.ESCOLHIDA, coluna: mexidas[destino] }
      : null;
  }
  if (confirmada) {
    return {
      situacao: SITUACAO_DA_COLUNA.CONFIRMADA,
      coluna: confirmada.indice,
    };
  }
  const sugerida = leitura?.seguros?.sugestao?.[destino];
  // A coluna sugerida que a pessoa já deu a outro destino não é sugerida de novo.
  const tomada = Object.values(mexidas).includes(sugerida);
  return existe(sugerida) && !tomada
    ? { situacao: SITUACAO_DA_COLUNA.SUGERIDA, coluna: sugerida }
    : null;
};

export const colunasDosSeguros = (leitura, mexidas = {}) => {
  const obrigatorios = leitura?.seguros?.obrigatorios ?? [];
  return destinosDeSeguro(leitura).map(({ value: destino, chave }) => {
    const obrigatorio = obrigatorios.includes(destino);
    const semColuna = obrigatorio
      ? SITUACAO_DA_COLUNA.FALTA
      : SITUACAO_DA_COLUNA.OPCIONAL;
    const achada = colunaDoDestino(leitura, destino, mexidas);
    return {
      destino,
      chave,
      obrigatorio,
      situacao: achada?.situacao ?? semColuna,
      coluna: achada?.coluna ?? null,
    };
  });
};

// As colunas que a pessoa pode apontar para um destino de seguro: as que ainda
// são só informação da pessoa e as que já são de algum destino de seguro. A
// coluna do nome, do telefone, do e-mail ou da empresa não é oferecida.
export const colunasQueServem = leitura => {
  const deSeguro = leitura?.seguros?.destinos ?? [];
  return (leitura?.colunas ?? []).filter(
    ({ destino }) => destino === DESTINO_LIVRE || deSeguro.includes(destino)
  );
};

// A pessoa apontou `coluna` para `destino`: o destino que tinha essa coluna na
// tela fica sem coluna (cada coluna guarda uma coisa só, como no servidor).
export const comAEscolhaDaColuna = (leitura, mexidas, destino, coluna) => {
  const outros = colunasDosSeguros(leitura, mexidas)
    .filter(linha => linha.destino !== destino && linha.coluna === coluna)
    .map(linha => [linha.destino, null]);
  return { ...mexidas, ...Object.fromEntries(outros), [destino]: coluna };
};

// Os obrigatórios que ainda não têm coluna na tela.
export const obrigatoriosSemColuna = linhas =>
  linhas
    .filter(({ situacao }) => situacao === SITUACAO_DA_COLUNA.FALTA)
    .map(({ destino }) => destino);

// O que "Está certo" manda ao servidor: `[{ destino, coluna }]` das colunas
// que estão na tela e o servidor ainda não guarda, os destinos que não são
// obrigatórios primeiro e os obrigatórios por último. Só a confirmação que
// completa os obrigatórios faz a planilha ser lida de novo: assim ela é lida
// uma vez só.
export const colunasParaConfirmar = linhas => {
  const pendentes = linhas.filter(
    ({ situacao, coluna }) =>
      coluna !== null && situacao !== SITUACAO_DA_COLUNA.CONFIRMADA
  );
  return [
    ...pendentes.filter(({ obrigatorio }) => !obrigatorio),
    ...pendentes.filter(({ obrigatorio }) => obrigatorio),
  ].map(({ destino, coluna }) => ({ destino, coluna }));
};

// ---- os números ---------------------------------------------------------------

const inteiro = valor => (Number.isInteger(valor) ? valor : ZERO);

// Quantos seguros entram se a pessoa mandar trazer agora, e de quantas pessoas.
export const numerosDosSeguros = leitura => {
  const resumo = leitura?.resumo ?? {};
  const pessoas = inteiro(resumo.pessoas);
  const jaEstavam = Math.min(pessoas, inteiro(resumo.pessoasQueJaEstavam));
  return {
    seguros: inteiro(resumo.seguros),
    pessoas,
    pessoasNovas: Math.max(ZERO, pessoas - jaEstavam),
    pessoasQueJaEstavam: jaEstavam,
    repetidos: inteiro(resumo.repetidos),
    // Seguros da planilha que aqui estão cancelados: a linha entra, o seguro
    // continua cancelado.
    cancelados: inteiro(resumo.cancelados),
    // Pessoas que entram sem o telefone escrito na planilha (conta das listas).
    semTelefone: inteiro(resumo.semTelefone),
  };
};

// Os contadores do topo do Conferir: `[{ chave, count }]`, sem os zerados. As
// linhas que ainda não vieram do servidor contam como "precisam de você".
export const contadoresDosSeguros = leitura => {
  const { abertos, deixados } = contarProblemas(leitura?.problemas);
  const numeros = numerosDosSeguros(leitura);
  return [
    { chave: 'PRECISAM', count: abertos + problemasPorCarregar(leitura) },
    { chave: 'DEIXADOS', count: deixados },
    { chave: 'PESSOAS_NOVAS', count: numeros.pessoasNovas },
    { chave: 'JA_ESTAVAM', count: numeros.pessoasQueJaEstavam },
  ].filter(({ count }) => count > ZERO);
};

// Os seguros que entram, por tipo, na ordem em que a tela mostra os tipos:
// `[{ tipo, count }]`, sem os zerados.
export const segurosPorTipo = leitura => {
  const porTipo = leitura?.resumo?.porTipo ?? {};
  return TIPOS_DE_SEGURO.map(tipo => ({
    tipo,
    count: inteiro(porTipo[tipo]),
  })).filter(({ count }) => count > ZERO);
};

// ---- as linhas que precisam da pessoa ----------------------------------------

// A linha com problema no seguro só pode ficar de fora (quem conserta é a
// planilha); a apólice que aparece em duas linhas com dados diferentes pede a
// escolha de qual fica.
export const TIPO_DUPLICADO = 'duplicado';
const TIPOS_DO_SEGURO = [
  'numero',
  'seguradora',
  'falta_termina',
  'comeca',
  'valor',
  TIPO_DUPLICADO,
];

export const ehProblemaDoSeguro = problema =>
  TIPOS_DO_SEGURO.includes(problema?.tipo);

export const ehApoliceRepetida = problema => problema?.tipo === TIPO_DUPLICADO;

// A frase de cada problema, pelo tipo e pelo motivo que o servidor manda. O
// motivo só vem na linha aberta: a linha deixada de fora (e o motivo que a tela
// não conhece) fica com a frase do tipo, que não afirma a causa.
const BASE_DOS_PROBLEMAS = 'RELACIONAMENTOS_CARTEIRA.TRAZER.PRECISAM.PROBLEMA';
const FRASE_DO_TIPO = new Map([
  ['numero', `${BASE_DOS_PROBLEMAS}.NUMERO_COM_PROBLEMA`],
  ['seguradora', `${BASE_DOS_PROBLEMAS}.SEGURADORA`],
  ['falta_termina', `${BASE_DOS_PROBLEMAS}.TERMINA_COM_PROBLEMA`],
  ['comeca', `${BASE_DOS_PROBLEMAS}.COMECA`],
  ['valor', `${BASE_DOS_PROBLEMAS}.VALOR`],
  [TIPO_DUPLICADO, `${BASE_DOS_PROBLEMAS}.DUPLICADO`],
]);
const FRASE_DO_MOTIVO = new Map([
  ['numero:falta', `${BASE_DOS_PROBLEMAS}.NUMERO`],
  ['numero:notacao_cientifica', `${BASE_DOS_PROBLEMAS}.NUMERO_ESTRAGADO`],
  ['numero:de_outra_pessoa', `${BASE_DOS_PROBLEMAS}.DE_OUTRA_PESSOA`],
  ['falta_termina:falta', `${BASE_DOS_PROBLEMAS}.TERMINA`],
  ['falta_termina:data_invalida', `${BASE_DOS_PROBLEMAS}.TERMINA_ILEGIVEL`],
  ['falta_termina:termina_antes', `${BASE_DOS_PROBLEMAS}.TERMINA_ANTES`],
  ['falta_termina:termo_ambiguo', `${BASE_DOS_PROBLEMAS}.TERMO_AMBIGUO`],
]);

export const chaveDoProblemaDoSeguro = problema =>
  FRASE_DO_MOTIVO.get(`${problema.tipo}:${problema.motivo}`) ??
  FRASE_DO_TIPO.get(problema.tipo);
