// #1181 — o estado que a pessoa lê no cartão e na página do agente.
// "Atendendo" só quando o agente está ativo e ligado (mesma regra de Agent#operating? no backend).
// Rascunho continua "Falta terminar" mesmo com instrução (DECISOES.md item 5): só começa a atender
// quem escolheu onde. O agente de cotação mora no módulo de cotação e tem cartão próprio.
export const ESTADO = {
  ATENDENDO: 'atendendo',
  PARADO: 'parado',
  FALTA_TERMINAR: 'falta_terminar',
  COTACAO: 'cotacao',
};

const TIPO_COTACAO = 'insurance_quote';

export const estadoDoAgente = agente => {
  if (agente?.agent_type === TIPO_COTACAO) return ESTADO.COTACAO;
  if (!agente?.status || agente.status === 'draft') {
    return ESTADO.FALTA_TERMINAR;
  }
  if (agente.status === 'active' && agente.enabled === true) {
    return ESTADO.ATENDENDO;
  }
  return ESTADO.PARADO;
};

// Ordem da lista (protótipo T02): quem atende, os parados, a cotação e, por último, Falta terminar.
// Dentro de cada grupo fica a ordem que a API mandou.
const ORDEM = [
  ESTADO.ATENDENDO,
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
    parados: estados.filter(e => e === ESTADO.PARADO).length,
  };
};

// Caixas que a leitura L2 diz que este agente ocupa.
export const canaisDoAgente = (agenteId, canais) =>
  (canais || []).filter(
    canal =>
      canal.occupied_by?.kind === 'agent' &&
      canal.occupied_by.agent_id === agenteId
  );
