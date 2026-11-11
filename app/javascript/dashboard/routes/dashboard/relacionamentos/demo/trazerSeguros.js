// #2897 — o que "trazer seguros" acha na demonstração: a planilha, os PDFs e o
// Agger de exemplo, e o que a conta já trouxe. Só é carregado no ambiente de
// desenvolvimento (fonte/trazerSegurosFonte.js, `import.meta.env.DEV`).
//
// Tudo é inventado e sempre igual. A planilha traz a carteira inteira (168
// seguros de 120 pessoas) e os 40 PDFs, 39 seguros de 31 pessoas. O Agger traz o
// que na carteira fictícia (demo/carteira.js) veio dele. Os nomes, as fichas de
// exemplo e o histórico da conta cheia saem dessa carteira e da base do bloco A,
// para tudo bater entre as telas.
import { pessoas } from './base';
import { segurosDaCarteira } from './carteira';
import { PLANILHA_DE_ORIGEM, SEGURADORAS } from './carteiraPlano';
import {
  aplicarConserto,
  aplicarDeixarDeFora,
  aplicarDestino,
  aplicarReabrir,
  porcentagemDaTrazida,
  quemTrouxeNaDemo,
} from './trazer';
import { DESTINOS_DE_SEGURO } from '../carteira/destinosDeSeguro';
import { DIA_EM_MS } from '../fonte/grupos';
import { SELOS, seloDoSeguro } from '../fonte/selosDoSeguro';
import { SITUACAO_DO_PROBLEMA } from '../trazer/contagem';
import { DESTINOS } from '../trazer/destinos';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';

export const ORIGENS = { PLANILHA: 'planilha', PDFS: 'pdfs', AGGER: 'agger' };

const [ATLANTICA, HORIZONTE, SERRA_AZUL, AURORA] = SEGURADORAS;
const DIAS_ANTES = 60;
const SEM_SEGUROS = 0;

// Cada problema é de uma pessoa da base (`pessoaId`): o nome vem de lá.
const abertos = (problemas, agora) => {
  const gente = pessoas(agora);
  const nomeDe = id => gente.find(pessoa => pessoa.id === id)?.name ?? '';
  return problemas.map(({ pessoaId, ...problema }) => ({
    ...problema,
    ...(pessoaId ? { nome: nomeDe(pessoaId) } : {}),
    estado: SITUACAO_DO_PROBLEMA.ABERTO,
  }));
};

// ---- as fichas de exemplo: gente e seguros da carteira fictícia --------------

const exemploDe = (pessoaId, gente, carteira) => {
  const pessoa = gente.find(item => item.id === pessoaId);
  return {
    nome: pessoa.name,
    telefone: pessoa.phone_number ?? '',
    email: pessoa.email ?? '',
    empresa: '',
    cliente: true,
    seguros: carteira
      .filter(seguro => seguro.pessoaId === pessoaId)
      .map(({ tipo, seguradora, termina }) => ({ tipo, seguradora, termina })),
  };
};

const exemplosDe = (ids, agora) => {
  const gente = pessoas(agora);
  const carteira = segurosDaCarteira(agora);
  return ids.map(id => exemploDe(id, gente, carteira));
};

// ---- a planilha ---------------------------------------------------------------

// Uma pessoa com três seguros, uma com um e uma sem telefone.
const EXEMPLOS_DA_PLANILHA = [23, 4, 59];

// Os nomes das colunas são os da planilha do corretor (a tela só os repete).
const COLUNAS_DA_PLANILHA = [
  { nome: 'Nome', destino: DESTINOS.NOME },
  { nome: 'Celular', destino: DESTINOS.TELEFONE },
  { nome: 'E-mail', destino: DESTINOS.EMAIL },
  { nome: 'CPF/CNPJ', destino: DESTINOS_DE_SEGURO.DOCUMENTO },
  { nome: 'Apólice', destino: DESTINOS_DE_SEGURO.NUMERO },
  { nome: 'Ramo', destino: DESTINOS_DE_SEGURO.TIPO },
  { nome: 'Cia', destino: DESTINOS_DE_SEGURO.SEGURADORA },
  { nome: 'Início', destino: DESTINOS_DE_SEGURO.COMECA },
  { nome: 'Fim', destino: DESTINOS_DE_SEGURO.TERMINA },
  { nome: 'Valor', destino: DESTINOS_DE_SEGURO.VALOR },
  { nome: 'Bem', destino: DESTINOS_DE_SEGURO.BEM },
];

const PROBLEMAS_DA_PLANILHA = [
  { linha: 52, tipo: 'falta_termina', pessoaId: 48 },
  { linha: 71, tipo: 'seguradora', pessoaId: 13, valor: 'Atl.' },
  {
    linha: 131,
    tipo: 'duplicado',
    pessoaId: 24,
    numero: 'AT-001288',
    outraLinha: 88,
    duplicadas: [
      { linha: 88, valor: 3410 },
      { linha: 131, valor: 3140 },
    ],
  },
  // O telefone da planilha veio com um número a menos.
  { linha: 140, tipo: 'telefone', pessoaId: 29, valor: '+55 11 9186-0029' },
];

export const leituraDaPlanilha = (id, arquivo, agora) => ({
  id,
  origem: ORIGENS.PLANILHA,
  arquivo: arquivo || PLANILHA_DE_ORIGEM,
  achei: { seguros: 168, pessoas: 120 },
  prontos: 164,
  jaEstavam: 120,
  semTelefone: SEM_SEGUROS,
  naoEApolice: [],
  efeito: { dias: DIAS_ANTES, seguros: 22 },
  seguradoras: [...SEGURADORAS],
  exemplos: exemplosDe(EXEMPLOS_DA_PLANILHA, agora),
  problemas: abertos(PROBLEMAS_DA_PLANILHA, agora),
  colunas: COLUNAS_DA_PLANILHA.map(coluna => ({ ...coluna })),
});

// ---- os PDFs ------------------------------------------------------------------

const PDFS_COM_NUMERO = 38;
const BOLETO = 'boleto-marco.pdf';
const FOTO_ESCURA = 'apolice-ana.jpg';
const EXEMPLOS_DOS_PDFS = [38, 41, 4];
export const DURACAO_DA_LEITURA_MS = 6000;
export const CASO_FOTO_ESCURA = 'foto_escura';

const doisDigitos = numero => String(numero).padStart(2, '0');

export const pdfsDeExemplo = () =>
  [
    ...Array.from(
      { length: PDFS_COM_NUMERO },
      (_, i) => `apolice-${doisDigitos(i + 1)}.pdf`
    ),
    'apolice-foto-do-celular.jpg',
    BOLETO,
  ].map(name => ({ name }));

// Quantos PDFs já foram lidos: de 0 ao total em DURACAO_DA_LEITURA_MS.
export const pdfsLidos = (inicio, agora, total) =>
  Math.min(
    total,
    Math.max(0, Math.floor(((agora - inicio) / DURACAO_DA_LEITURA_MS) * total))
  );

const SEM_TELEFONE_NO_PDF = {
  linha: 2,
  tipo: 'telefone',
  pessoaId: 105,
  arquivo: 'apolice-31.pdf',
  valor: '',
  podeSeguirSem: true,
};
const FOTO_QUE_NAO_DEU = {
  linha: 2,
  tipo: 'foto_escura',
  arquivo: FOTO_ESCURA,
};

export const leituraDosPdfs = (id, agora, caso = null) => ({
  id,
  origem: ORIGENS.PDFS,
  arquivo: '',
  achei: { pdfs: 40, seguros: 39, pessoas: 31 },
  prontos: 37,
  jaEstavam: SEM_SEGUROS,
  semTelefone: SEM_SEGUROS,
  naoEApolice: [BOLETO],
  efeito: { dias: DIAS_ANTES, seguros: 6 },
  seguradoras: [...SEGURADORAS],
  exemplos: exemplosDe(EXEMPLOS_DOS_PDFS, agora),
  problemas: abertos(
    [
      {
        linha: 1,
        tipo: 'falta_termina',
        pessoaId: 117,
        arquivo: 'apolice-17.pdf',
      },
      caso === CASO_FOTO_ESCURA ? FOTO_QUE_NAO_DEU : SEM_TELEFONE_NO_PDF,
    ],
    agora
  ),
  colunas: [],
});

// ---- o Agger ------------------------------------------------------------------

export const PASSO_DA_BUSCA_MS = 1500;
export const SITUACOES_DA_BUSCA = {
  PRONTA: 'pronta',
  BUSCANDO: 'buscando',
  FALTA_SENHA: 'falta_senha',
};

// As três que respondem, uma depois da outra; a quarta não tem a senha guardada.
const RESPONDEM = [
  { nome: ATLANTICA, seguros: 64 },
  { nome: HORIZONTE, seguros: 52 },
  { nome: SERRA_AZUL, seguros: 40 },
];

// `denovoDesde`: quando a pessoa pediu "Buscar de novo agora" (a seguradora sem
// senha é buscada outra vez por um instante).
export const buscaDoAgger = (inicio, agora, denovoDesde = null) => {
  const passos = Math.floor((agora - inicio) / PASSO_DA_BUSCA_MS);
  const buscandoDeNovo =
    denovoDesde !== null && agora - denovoDesde < PASSO_DA_BUSCA_MS;
  const seguradoras = [
    ...RESPONDEM.map((seguradora, posicao) => ({
      ...seguradora,
      situacao:
        passos > posicao
          ? SITUACOES_DA_BUSCA.PRONTA
          : SITUACOES_DA_BUSCA.BUSCANDO,
    })),
    {
      nome: AURORA,
      seguros: SEM_SEGUROS,
      situacao: buscandoDeNovo
        ? SITUACOES_DA_BUSCA.BUSCANDO
        : SITUACOES_DA_BUSCA.FALTA_SENHA,
    },
  ];
  return {
    seguradoras,
    terminou: seguradoras.every(
      ({ situacao }) => situacao !== SITUACOES_DA_BUSCA.BUSCANDO
    ),
  };
};

// O que o Agger acha é o que, na carteira fictícia, veio dele: os números batem
// com a aba Seguros e com o histórico da conta cheia.
export const leituraDoAgger = (id, agora) => {
  const doAgger = segurosDaCarteira(agora).filter(
    seguro => seguro.origem.tipo === ORIGENS.AGGER
  );
  const quantasPessoas = new Set(doAgger.map(seguro => seguro.pessoaId)).size;
  const semTelefone = doAgger.filter(
    seguro => !seguro.pessoa.phone_number
  ).length;
  return {
    id,
    origem: ORIGENS.AGGER,
    arquivo: '',
    achei: { seguros: doAgger.length, pessoas: quantasPessoas },
    prontos: doAgger.length - semTelefone,
    jaEstavam: quantasPessoas,
    semTelefone,
    naoEApolice: [],
    efeito: {
      dias: DIAS_ANTES,
      seguros: doAgger.filter(
        seguro => seloDoSeguro(seguro, agora) === SELOS.EM_RENOVACAO
      ).length,
    },
    seguradoras: [...SEGURADORAS],
    exemplos: [],
    problemas: [],
    colunas: [],
  };
};

// ---- o que a conta já trouxe ----------------------------------------------------

const CHEGOU_DO_AGGER_HA_DIAS = 8;
const CHEGOU_DA_PLANILHA_HA_DIAS = 20;
const HORA_DA_BUSCA = 6;
const MINUTO_DA_BUSCA = 10;
const NOVOS_NA_ULTIMA_BUSCA = 2;

// A busca de todo dia roda às 06:10: a última é a de hoje ou, antes disso, a de
// ontem.
const ultimaBuscaAntesDe = agora => {
  const hoje = new Date(agora);
  hoje.setHours(HORA_DA_BUSCA, MINUTO_DA_BUSCA, 0, 0);
  return hoje.getTime() <= agora ? hoje.getTime() : hoje.getTime() - DIA_EM_MS;
};

const resumoDe = seguros => ({
  seguros: seguros.length,
  pessoas: new Set(seguros.map(seguro => seguro.pessoaId)).size,
  cards: seguros.filter(seguro => seguro.renovacao).length,
  propostas: seguros.filter(seguro => seguro.renovacao?.proposta?.enviadaEm)
    .length,
});

const doAgger = agora => ({
  buscaTodoDia: true,
  ultimaBusca: ultimaBuscaAntesDe(agora),
});

const entrada = ({ id, tipo, arquivo = '', haDias, resumo, agora }) => ({
  id,
  tipo,
  arquivo,
  quando: agora - haDias * DIA_EM_MS,
  quem: quemTrouxeNaDemo(),
  situacao: SITUACOES_DA_LISTA.PRONTO,
  total: resumo.seguros,
  ...resumo,
});

// Na conta cheia a carteira veio do Agger e de uma planilha; nos outros estados
// ainda não veio seguro nenhum.
export const historicoDeSeguros = (agora, estado) => {
  if (estado !== 'cheio') return [];
  const carteira = segurosDaCarteira(agora);
  const de = tipo => carteira.filter(seguro => seguro.origem.tipo === tipo);
  return [
    {
      ...entrada({
        id: 'seguros-do-agger',
        tipo: ORIGENS.AGGER,
        haDias: CHEGOU_DO_AGGER_HA_DIAS,
        resumo: resumoDe(de(ORIGENS.AGGER)),
        agora,
      }),
      ...doAgger(agora),
      novos: NOVOS_NA_ULTIMA_BUSCA,
    },
    entrada({
      id: 'seguros-da-planilha',
      tipo: ORIGENS.PLANILHA,
      arquivo: PLANILHA_DE_ORIGEM,
      haDias: CHEGOU_DA_PLANILHA_HA_DIAS,
      resumo: resumoDe(de(ORIGENS.PLANILHA)),
      agora,
    }),
  ];
};

// O que acabou de ser trazido: os cards nascem amanhã cedo, então ainda não há
// card nem proposta para desfazer.
export const entradaTrazida = (id, leitura, quantos, agora) => ({
  id,
  tipo: leitura.origem,
  arquivo: leitura.arquivo,
  pdfs: leitura.achei.pdfs ?? SEM_SEGUROS,
  quando: agora,
  quem: quemTrouxeNaDemo(),
  situacao: SITUACOES_DA_LISTA.TRAZENDO,
  total: quantos.seguros,
  seguros: quantos.seguros,
  pessoas: quantos.pessoas,
  cards: SEM_SEGUROS,
  propostas: SEM_SEGUROS,
  ...(leitura.origem === ORIGENS.AGGER
    ? { buscaTodoDia: true, ultimaBusca: agora, novos: SEM_SEGUROS }
    : {}),
});

export const demoDeTrazerSeguros = {
  PLANILHA_DE_EXEMPLO: PLANILHA_DE_ORIGEM,
  leituraDaPlanilha,
  pdfsDeExemplo,
  pdfsLidos,
  leituraDosPdfs,
  buscaDoAgger,
  leituraDoAgger,
  historicoDeSeguros,
  entradaTrazida,
  aplicarConserto,
  aplicarDeixarDeFora,
  aplicarReabrir,
  aplicarDestino,
  porcentagemDaTrazida,
};
