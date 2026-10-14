// #1181 — o estado que a pessoa lê no cartão e na página do agente.
// "Atendendo" só quando o agente está ativo e ligado (mesma regra de Agent#operating? no backend)
// E tem onde trabalhar (#1366, Agent#tem_onde_trabalhar? no backend, lido em `tem_onde_trabalhar`):
// externo ativo sem canal aparece "Parado", nunca "Atendendo". O Copiloto da equipe (interno)
// trabalha no painel, sem canal: o servidor responde true para ele.
// #1433 (tema 13) — o agente da equipe (só vínculos de área, `na_equipe` do servidor) ligado aparece
// "Na equipe": recebe a conversa quando alguém passa, não atende primeiro. Nunca "Atendendo" como o
// principal, nem "Parado" só por não ocupar caixa nenhuma.
// Rascunho continua "Falta terminar" mesmo com instrução (DECISOES.md item 5): só começa a atender
// quem escolheu onde. O agente de cotação mora no módulo de cotação e tem cartão próprio.
export const ESTADO = {
  ATENDENDO: 'atendendo',
  NA_EQUIPE: 'na_equipe',
  PARADO: 'parado',
  FALTA_TERMINAR: 'falta_terminar',
  COTACAO: 'cotacao',
};

// Estados em que o agente está trabalhando (o interruptor aparece ligado).
export const TRABALHANDO = [ESTADO.ATENDENDO, ESTADO.NA_EQUIPE];

const TIPO_COTACAO = 'insurance_quote';

// Operação, sem o caso da cotação: a lista e a página leem daqui.
export const estadoDeAtendimento = agente => {
  if (!agente?.status || agente.status === 'draft') {
    return ESTADO.FALTA_TERMINAR;
  }
  const ligado = agente.status === 'active' && agente.enabled === true;
  if (!ligado || agente.tem_onde_trabalhar === false) return ESTADO.PARADO;
  return agente.na_equipe === true ? ESTADO.NA_EQUIPE : ESTADO.ATENDENDO;
};

export const estadoDoAgente = agente => {
  if (agente?.agent_type === TIPO_COTACAO) return ESTADO.COTACAO;
  return estadoDeAtendimento(agente);
};

// Ordem da lista (protótipo T02): quem atende, quem está na equipe, os parados, a cotação e, por
// último, Falta terminar. Dentro de cada grupo fica a ordem que a API mandou.
const ORDEM = [
  ESTADO.ATENDENDO,
  ESTADO.NA_EQUIPE,
  ESTADO.PARADO,
  ESTADO.COTACAO,
  ESTADO.FALTA_TERMINAR,
];

export const ordenarAgentes = agentes =>
  ORDEM.flatMap(estado =>
    (agentes || []).filter(agente => estadoDoAgente(agente) === estado)
  );

export const contarEstados = agentes => {
  const estados = (agentes || []).map(estadoDoAgente);
  return {
    atendendo: estados.filter(e => e === ESTADO.ATENDENDO).length,
    naEquipe: estados.filter(e => e === ESTADO.NA_EQUIPE).length,
    parados: estados.filter(e => e === ESTADO.PARADO).length,
  };
};

// Caixas que a leitura L2 diz que este agente ocupa (como o principal).
export const canaisDoAgente = (agenteId, canais) =>
  (canais || []).filter(
    canal =>
      canal.occupied_by?.kind === 'agent' &&
      canal.occupied_by.agent_id === agenteId
  );
