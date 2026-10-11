// #1181 (item A) — o que a página de agendamento escolhida faz de verdade, só com o que GET
// crm/booking_pages devolve. Campos preferidos (#1305, quando vierem): `ai_status` ("ativa" |
// "pausada" | "sem_responsavel" | "agenda_pausada"), `recebe` ({ modo: "fixo" | "por_pessoa", nome })
// e `timezone`. Sem eles, a lista de hoje (Crm::BookingV2::PageSerializer#summary): `enabled`;
// `assignment_mode`; `attention` (responsável único ausente ou que não pode atender); `links` (só os
// ativos de quem pode atender, na ordem em que a IA procura o primeiro); `paused_people` (quem
// atende e pausou "Meus horários": a IA não acha horário dessa pessoa, Slots#host_paused?). Página
// apagada não vem na lista: o id gravado no agente fica sem página.
export const ESTADO_PAGINA = {
  NENHUMA: 'nenhuma',
  NAO_EXISTE: 'nao_existe',
  PAUSADA: 'pausada',
  SEM_NINGUEM: 'sem_ninguem',
  AGENDA_PAUSADA: 'agenda_pausada',
  ATIVA: 'ativa',
};

export const MODO_RECEBE = { FIXO: 'fixo', POR_PESSOA: 'por_pessoa' };

const DO_SERVIDOR = {
  ativa: ESTADO_PAGINA.ATIVA,
  pausada: ESTADO_PAGINA.PAUSADA,
  sem_responsavel: ESTADO_PAGINA.SEM_NINGUEM,
  agenda_pausada: ESTADO_PAGINA.AGENDA_PAUSADA,
};

const ninguemAtende = pagina => {
  if (pagina.assignment_mode === 'fixed') return pagina.attention === true;
  if (pagina.assignment_mode === 'per_agent') {
    return Array.isArray(pagina.links) && pagina.links.length === 0;
  }
  return false;
};

// Responsável único com a agenda pausada, ou todos os links de pessoas com a agenda pausada.
const agendaPausada = pagina => {
  const pausados = new Set((pagina.paused_people || []).map(({ id }) => id));
  if (!pausados.size) return false;
  if (pagina.assignment_mode === 'fixed') return true;
  if (pagina.assignment_mode !== 'per_agent') return false;
  return (pagina.links || []).every(link => pausados.has(link.agent_id));
};

// `escolhida`: há uma página gravada/escolhida; `pagina`: ela na lista (undefined se não está).
export const estadoDaPagina = (escolhida, pagina) => {
  if (!escolhida) return ESTADO_PAGINA.NENHUMA;
  if (!pagina) return ESTADO_PAGINA.NAO_EXISTE;
  if (DO_SERVIDOR[pagina.ai_status]) return DO_SERVIDOR[pagina.ai_status];
  if (pagina.enabled === false) return ESTADO_PAGINA.PAUSADA;
  if (ninguemAtende(pagina)) return ESTADO_PAGINA.SEM_NINGUEM;
  if (agendaPausada(pagina)) return ESTADO_PAGINA.AGENDA_PAUSADA;
  return ESTADO_PAGINA.ATIVA;
};

const MODO_DA_PAGINA = {
  fixed: MODO_RECEBE.FIXO,
  per_agent: MODO_RECEBE.POR_PESSOA,
};

// { modo, nome } de quem fica com a reunião; nome vazio quando a API não diz. null sem o modo.
// Responsável único: a lista de hoje não traz o nome dele.
export const quemRecebe = pagina => {
  const doServidor = pagina?.recebe;
  if (Object.values(MODO_RECEBE).includes(doServidor?.modo)) {
    return { modo: doServidor.modo, nome: doServidor.nome || '' };
  }
  const modo = MODO_DA_PAGINA[pagina?.assignment_mode];
  if (!modo) return null;
  const nome =
    modo === MODO_RECEBE.POR_PESSOA ? pagina.links?.[0]?.agent_name : '';
  return { modo, nome: nome || '' };
};

// Nome do fuso para leigo ("horário de Brasília"), pelo Intl no idioma da tela; o nome IANA cru
// quando o navegador não conhece o fuso. Vazio sem fuso (a lista de hoje não traz).
export const fusoLegivel = (timezone, idioma) => {
  if (!timezone) return '';
  try {
    const partes = new Intl.DateTimeFormat(idioma, {
      timeZone: timezone,
      timeZoneName: 'longGeneric',
    }).formatToParts(new Date());
    return partes.find(parte => parte.type === 'timeZoneName')?.value || '';
  } catch {
    return timezone;
  }
};
