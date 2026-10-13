// #1181 — o estado que a pessoa lê no cartão e na página do agente.
// "Atendendo" só quando o agente está ativo e ligado (mesma regra de Agent#operating? no backend).
// Rascunho continua "Falta terminar" mesmo com instrução (DECISOES.md item 5): só começa a atender
// quem escolheu onde. O agente de cotação mora no módulo de cotação e tem cartão próprio.
// #1366 (protótipo da Fase 2) — com o papel conhecido (segundo argumento, null = sem papel), o estado
// diz ONDE o agente trabalha: Atendendo (porta de um canal), Na equipe (área de um funil, sem canal
// próprio), Ajudando (consultado por outro agente) e Sem onde trabalhar. Sem onde trabalhar nunca
// aparece como ligado, mesmo que o servidor diga "ativo". Sem o papel (undefined), vale a regra antiga.
export const ESTADO = {
  ATENDENDO: 'atendendo',
  NA_EQUIPE: 'na_equipe',
  AJUDANDO: 'ajudando',
  SEM_ONDE: 'sem_onde',
  PARADO: 'parado',
  FALTA_TERMINAR: 'falta_terminar',
  COTACAO: 'cotacao',
};

// Estados em que o agente está trabalhando (o interruptor aparece ligado).
export const TRABALHANDO = [
  ESTADO.ATENDENDO,
  ESTADO.NA_EQUIPE,
  ESTADO.AJUDANDO,
];

const TIPO_COTACAO = 'insurance_quote';

const ESTADO_DO_LUGAR = {
  canal: ESTADO.ATENDENDO,
  equipe: ESTADO.NA_EQUIPE,
  ajuda: ESTADO.AJUDANDO,
};

// Onde o agente trabalha: a porta de um canal vem da contagem de canais da API; equipe e ajuda, do papel.
export const ondeTrabalha = (agente, papel) => {
  if ((agente?.channels_count || 0) > 0) return 'canal';
  if (papel?.tipo === 'equipe') return 'equipe';
  if (papel?.tipo === 'ajuda') return 'ajuda';
  return null;
};

const ligado = agente => agente.status === 'active' && agente.enabled === true;

export const estadoDoAgente = (agente, papel) => {
  if (agente?.agent_type === TIPO_COTACAO) return ESTADO.COTACAO;
  if (!agente?.status || agente.status === 'draft') {
    return ESTADO.FALTA_TERMINAR;
  }
  if (papel !== undefined) {
    const lugar = ondeTrabalha(agente, papel);
    if (!lugar) return ESTADO.SEM_ONDE;
    return ligado(agente) ? ESTADO_DO_LUGAR[lugar] : ESTADO.PARADO;
  }
  return ligado(agente) ? ESTADO.ATENDENDO : ESTADO.PARADO;
};

// Ordem da lista (protótipo T02): quem trabalha, os parados, quem não tem onde trabalhar, a cotação
// e, por último, Falta terminar. Dentro de cada grupo fica a ordem que a API mandou.
const ORDEM = [
  ESTADO.ATENDENDO,
  ESTADO.NA_EQUIPE,
  ESTADO.AJUDANDO,
  ESTADO.PARADO,
  ESTADO.SEM_ONDE,
  ESTADO.COTACAO,
  ESTADO.FALTA_TERMINAR,
];

const semPapel = () => undefined;

export const ordenarAgentes = (agentes, papelDe = semPapel) =>
  ORDEM.flatMap(estado =>
    (agentes || []).filter(
      agente => estadoDoAgente(agente, papelDe(agente)) === estado
    )
  );

export const contarEstados = agentes => {
  const estados = (agentes || []).map(agente => estadoDoAgente(agente));
  return {
    atendendo: estados.filter(e => e === ESTADO.ATENDENDO).length,
    parados: estados.filter(e => e === ESTADO.PARADO).length,
  };
};

// #1366 (protótipo): contagem por onde trabalha, com o papel de cada agente.
export const contarPorLugar = (agentes, papelDe) => {
  const estados = (agentes || []).map(agente =>
    estadoDoAgente(agente, papelDe(agente))
  );
  return {
    trabalhando: estados.filter(e => TRABALHANDO.includes(e)).length,
    parados: estados.filter(e => e === ESTADO.PARADO).length,
    semOnde: estados.filter(e => e === ESTADO.SEM_ONDE).length,
  };
};

// Caixas que a leitura L2 diz que este agente ocupa.
export const canaisDoAgente = (agenteId, canais) =>
  (canais || []).filter(
    canal =>
      canal.occupied_by?.kind === 'agent' &&
      canal.occupied_by.agent_id === agenteId
  );

// #1366 (protótipo) — áreas que o agente "Na equipe" cuida, no mesmo texto da tela do CRM "Caixas no
// CRM › Quem cuida do quê?": os funis, com o nome da caixa só quando as áreas estão em mais de uma.
export const nomesDasAreas = papel => {
  const areas = papel?.areas || [];
  const caixas = new Set(areas.map(area => area.caixa));
  return areas
    .map(area =>
      caixas.size > 1 ? `${area.funil} (${area.caixa})` : area.funil
    )
    .join(', ');
};
