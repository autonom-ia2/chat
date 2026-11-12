import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import CrmAutomacoesNoCrmAPI from 'dashboard/api/crmAutomacoesNoCrm';
import { todosOsPassos } from 'dashboard/routes/dashboard/automacoes/livre/receita';

// #2499 F6.3/F6.5 — as automações do motor novo no card e na etapa, da API (crmAutomacoesNoCrm), no formato que as
// telas usam. A receita vem como a da Automação livre (`gatilho` e `passos`), para as frases saírem do mesmo frases.js
// do editor, com o catálogo real. As regras antigas da etapa vêm do store (crmKanban/fetchStageAutomations).
// - automacoesDaEtapa(etapaId) → [{ id, nome, ativa, versaoId, receita }]: as com gatilho nesta etapa (entrou, saiu ou
//   parado), ligadas e desligadas.
// - ligarNaEtapa(item, ativa) → ativa: ligar é "assumir e religar", na versão que a tela mostrou (409 se mudou).
// - automacoesDoCard(card) → [{ id, automacaoId, nome, receita, passo, indice, situacao, comecou, historico }]: só
//   card aberto. `passo` é o passo onde a execução está (de qualquer galho); `indice`, o passo principal que o contém.
//   `historico` é [{ em, passo }], com o passo de cada coisa já feita.
// - pararNoCard(card, item) → para a automação só neste card.

// O passo principal (da lista de cima) que contém `id`, em qualquer galho; -1 se a receita não o tem.
export const indiceDoPrincipal = (passos, id) =>
  (passos || []).findIndex(passo =>
    todosOsPassos([passo]).some(dentro => dentro.id === id)
  );

export const acharNaReceita = (passos, id) =>
  todosOsPassos(passos || []).find(passo => passo.id === id) || null;

// A execução andando agora (entre um passo e outro) não espera; sem prazo, ela espera a condição do "esperar até".
const situacaoDa = execucao => {
  if (execucao.estado !== 'esperando') return { tipo: 'agindo' };
  if (execucao.esperando_sem_prazo) return { tipo: 'condicao' };
  return { tipo: 'espera', ate: execucao.esperando_ate };
};

const daExecucao = execucao => {
  const passos = execucao.receita?.passos || [];
  return {
    id: execucao.id,
    automacaoId: execucao.automacao_id,
    nome: execucao.nome,
    receita: execucao.receita,
    passo: execucao.passo ? acharNaReceita(passos, execucao.passo) : null,
    indice: execucao.passo ? indiceDoPrincipal(passos, execucao.passo) : -1,
    situacao: situacaoDa(execucao),
    comecou: execucao.comecou,
    historico: (execucao.feitos || [])
      .map(feito => ({
        em: feito.em,
        passo: acharNaReceita(passos, feito.passo),
      }))
      .filter(feito => feito.passo),
  };
};

export const automacoesDoCard = async card => {
  if (card?.status !== 'open' || !card?.id) return [];
  const { data } = await CrmAutomacoesNoCrmAPI.doCard(card.id);
  return (data.automacoes || []).map(daExecucao);
};

export const pararNoCard = async (card, item) => {
  await CrmAutomacoesNoCrmAPI.pararNoCard(card.id, item.automacaoId);
  return true;
};

export const automacoesDaEtapa = async etapaId => {
  const { data } = await CrmAutomacoesNoCrmAPI.daEtapa(etapaId);
  return (data.automacoes || []).map(automacao => ({
    id: automacao.id,
    nome: automacao.nome,
    ativa: automacao.ativa,
    versaoId: automacao.versao?.id,
    receita: automacao.versao?.receita,
  }));
};

export const ligarNaEtapa = async (item, ativa) => {
  const { data } = ativa
    ? await AutomacoesAPI.ligar(item.id, item.versaoId)
    : await AutomacoesAPI.desligar(item.id);
  return data.ativa;
};
