// #1181 — o estado que a pessoa lê no cartão e na página do agente.
// "Atendendo" só quando o agente está ativo e ligado (mesma regra de Agent#operating? no backend).
// Rascunho continua "Falta terminar" mesmo com instrução (DECISOES.md item 5): só começa a atender
// quem escolheu onde. O agente de cotação mora no módulo de cotação e tem cartão próprio.
// #1366 (protótipo da Fase 2) — com o papel conhecido (segundo argumento, null = sem papel), o estado
// diz COMO o agente trabalha: Atendendo (atende primeiro em alguma caixa), Na equipe (recebe quando
// alguém passar, em alguma caixa), Ajudando (só responde a outros agentes) e Sem onde trabalhar.
// Sem onde trabalhar nunca aparece como ligado, mesmo que o servidor diga "ativo". Sem o papel
// (undefined), vale a regra antiga.
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

// Como o agente trabalha, pelo papel: atender primeiro em alguma caixa vale mais que receber.
export const ondeTrabalha = (_agente, papel) => {
  if (papel?.tipo === 'ajuda') return papel.ajuda?.length ? 'ajuda' : null;
  const caixas = papel?.caixas || [];
  if (caixas.some(item => item.papel === 'primeiro')) return 'canal';
  if (caixas.some(item => item.papel === 'recebe')) return 'equipe';
  return null;
};

// Nomes das caixas em que o agente tem um papel ("primeiro" ou "recebe").
export const caixasDoPapel = (papel, qual) =>
  (papel?.caixas || [])
    .filter(item => item.papel === qual)
    .map(item => item.caixa);

// Assuntos (funis) de que cuida, sem repetir, em todas as caixas.
export const assuntosDoPapel = papel => [
  ...new Set((papel?.caixas || []).flatMap(item => item.assuntos || [])),
];

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
