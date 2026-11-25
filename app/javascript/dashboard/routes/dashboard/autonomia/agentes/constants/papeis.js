import { MODELO_DO_MEU_JEITO } from './modelos';
import {
  ATUACAO_INTERNA_NA_QUERY,
  PAPEL_AJUDANTE_NA_QUERY,
  PAPEL_AREA_NA_QUERY,
} from './criacao';

// #3219 — criar agente em dois passos. Passo 1: o que ele vai fazer (o papel). Passo 2: como começar.
// Atender clientes é o caminho da maioria e vem em destaque. O agente da equipe só existe com a Fase 2 (useFase2); o
// ajudante, com a Fase 2 e pelo menos um agente na conta (ele só responde a outro agente); conectar, só com o agente
// por caixa (useAgenteIaPorCaixa). Os textos ficam em AGENTS.JORNADA.CRIAR_EM_PASSOS.PAPEIS.<I18N>; `comNome`: o
// cartão mostra também o nome com que o agente aparece na lista (PAPEIS.<I18N>.NOME), porque o título diz a tarefa.
//
// Passo 2 só existe para quem tem mais de um jeito de começar: atender clientes (pronto, conversar ou escrever) e o
// Copiloto (conversar ou escrever). Ele mora na URL (`?papel=atender|copiloto`): o "voltar" do navegador volta ao
// passo 1. O agente da equipe e o ajudante têm um jeito só (conversar com a IA), e a criação deles já começa com os
// passos próprios (os canais; quem ele ajuda): a escolha vai direto para lá, com as URLs de sempre (`?papel=area`,
// `?papel=ajudante`). Conectar vai direto para a página de conectar (`?conectar=outro`).
export const PAPEL = {
  ATENDER: 'atender',
  COPILOTO: 'copiloto',
  EQUIPE: 'equipe',
  AJUDANTE: 'ajudante',
  CONECTAR: 'conectar',
};

export const PAPEIS = [
  {
    chave: PAPEL.ATENDER,
    i18n: 'ATENDER',
    icone: 'i-lucide-messages-square',
    passo2: 'atender',
  },
  {
    chave: PAPEL.COPILOTO,
    i18n: 'COPILOTO',
    icone: 'i-lucide-users',
    passo2: 'copiloto',
    comNome: true,
  },
  {
    chave: PAPEL.EQUIPE,
    i18n: 'EQUIPE',
    icone: 'i-lucide-hand-helping',
    comNome: true,
    direto: { papel: PAPEL_AREA_NA_QUERY },
  },
  {
    chave: PAPEL.AJUDANTE,
    i18n: 'AJUDANTE',
    icone: 'i-lucide-bot',
    comNome: true,
    direto: { papel: PAPEL_AJUDANTE_NA_QUERY },
  },
  {
    chave: PAPEL.CONECTAR,
    i18n: 'CONECTAR',
    icone: 'i-lucide-plug',
    direto: { conectar: 'outro' },
  },
];

const DISPONIVEL = {
  [PAPEL.EQUIPE]: ({ fase2 }) => fase2,
  [PAPEL.AJUDANTE]: ({ fase2, temQuemAjudar }) => fase2 && temQuemAjudar,
  [PAPEL.CONECTAR]: ({ porCaixa }) => porCaixa,
};

// `temQuemAjudar`: a conta tem algum agente que o ajudante pode ajudar (a mesma regra do passo "quem ele ajuda").
export const papeisDisponiveis = ({
  fase2 = false,
  porCaixa = false,
  temQuemAjudar = false,
} = {}) =>
  PAPEIS.filter(papel => {
    const regra = DISPONIVEL[papel.chave];
    return !regra || regra({ fase2, porCaixa, temQuemAjudar });
  });

export const papelPelaChave = chave =>
  PAPEIS.find(papel => papel.chave === chave) || null;

// O papel do passo 2 lido da URL (`?papel=atender|copiloto`); null no passo 1 e nas outras marcas (`area`,
// `ajudante`), que são da criação.
export const papelDoPasso = (query = {}) =>
  PAPEIS.find(papel => papel.passo2 && papel.passo2 === query.papel)?.chave ||
  null;

// Para onde a escolha do papel leva: o passo 2 dele ou, sem passo 2, a página do papel.
export const queryDoPapel = chave => {
  const papel = papelPelaChave(chave);
  if (!papel) return {};
  return papel.passo2 ? { papel: papel.passo2 } : { ...papel.direto };
};

export const temPasso2 = chave => !!papelPelaChave(chave)?.passo2;

// Os jeitos de começar do passo 2; "começar de um pronto" é só de atender clientes.
export const JEITO = { CONVERSAR: 'conversar', ESCREVER: 'escrever' };
export const OPCOES_DE_COMECO = [
  { chave: JEITO.CONVERSAR, i18n: 'CONVERSAR', icone: 'i-lucide-sparkles' },
  { chave: JEITO.ESCREVER, i18n: 'ESCREVER', icone: 'i-lucide-pen-line' },
];

// Conversar com a IA: as URLs de sempre da criação ("Do meu jeito" e o Copiloto).
export const queryDeConversar = chave =>
  chave === PAPEL.COPILOTO
    ? { atuacao: ATUACAO_INTERNA_NA_QUERY }
    : { modelo: MODELO_DO_MEU_JEITO };

// Escrever eu mesmo leva o papel junto: a página mostra o papel, volta ao passo 2 dele e, no Copiloto, cria interno.
export const queryDeEscrever = chave => ({
  escrever: '1',
  ...(temPasso2(chave) ? { papel: papelPelaChave(chave).passo2 } : {}),
});
