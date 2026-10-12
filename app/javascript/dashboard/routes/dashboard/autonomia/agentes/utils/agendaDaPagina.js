// #1181 (item A) — o que a página de agendamento escolhida faz de verdade, só com o que GET
// crm/booking_pages devolve. Campos preferidos (#1305, quando vierem): `ai_status` ("ativa" |
// "pausada" | "sem_responsavel" | "agenda_pausada") e `recebe` ({ modo: "fixo" | "por_pessoa", nome }).
// O fuso não aparece na gaveta (#1370). Sem eles, a lista de hoje (PageSerializer#summary): `enabled`;
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

// #1307 — as pessoas da página que o dono libera para a IA (`config.booking_agent_ids`). A lista
// vem em `pessoas: [{ id, nome, ai_status: 'ativa' | 'agenda_pausada' }]`, na ordem fixa da página.
// Gravado vazio (ausente, null ou []) = todas. A preferência por uma pessoa vai na instrução; aqui é
// só quem a IA pode usar.
export const pessoasDaPagina = pagina =>
  Array.isArray(pagina?.pessoas) ? pagina.pessoas : [];

// Os ids marcados ao abrir: todas sem restrição gravada (ausente, null ou []); senão só as gravadas
// que ainda são da página (pode dar nenhuma: a restrição ficou velha e o dono precisa escolher de
// novo). Valor gravado que não é lista vale como ninguém, como no servidor (AgendaPessoas).
export const restricaoGravada = gravados =>
  gravados !== undefined &&
  gravados !== null &&
  !(Array.isArray(gravados) && !gravados.length);

export const idsLiberados = (gravados, pessoas) => {
  const ids = pessoas.map(({ id }) => id);
  if (!restricaoGravada(gravados)) return ids;
  if (!Array.isArray(gravados)) return [];
  const salvos = new Set(gravados.map(Number));
  return ids.filter(id => salvos.has(id));
};

// O que vai para o servidor: [] com todas marcadas (vale também para quem entrar na página depois);
// senão os ids marcados, na ordem da página.
export const liberacaoParaSalvar = (marcadas, pessoas) => {
  if (pessoas.every(({ id }) => marcadas.includes(id))) return [];
  return pessoas.map(({ id }) => id).filter(id => marcadas.includes(id));
};

// O estado da página para este agente: a lista de páginas não sabe da liberação. Ninguém liberado
// vira "ninguém atende"; todos os liberados com a agenda pausada viram "agenda pausada".
export const estadoComLiberacao = (estado, pessoas, liberadas) => {
  if (estado !== ESTADO_PAGINA.ATIVA || !pessoas.length) return estado;
  if (!liberadas.length) return ESTADO_PAGINA.SEM_NINGUEM;
  const pausadas = new Set(
    pessoas
      .filter(({ ai_status: status }) => status === 'agenda_pausada')
      .map(({ id }) => id)
  );
  return liberadas.every(id => pausadas.has(id))
    ? ESTADO_PAGINA.AGENDA_PAUSADA
    : estado;
};

// #1307 — a página nova é outra (não "Não marcar" e não a salva, comparando como texto: a config pode
// trazer o id em texto). Só então a liberação volta para todas (painel antigo, PanelTune).
export const outraPaginaDeAgenda = (nova, salva) =>
  Boolean(nova) && String(nova) !== String(salva ?? '');

// #1370 — rascunho: desligada e ainda falta algo para publicar (o `missing` da lista, como o selo
// de Páginas e links). Não é escolha na gaveta: a IA não marca por uma página que nunca foi ao ar.
export const ehRascunho = pagina =>
  pagina?.enabled !== true && Boolean(pagina?.missing?.length);

// #1370 — os locais da página como o assistente os nomeia (BOOKING.WHERE.<TIPO>.NAME), sem repetir.
export const tiposDeLocal = pagina => [
  ...new Set(
    (Array.isArray(pagina?.locations) ? pagina.locations : [])
      .map(local => local?.type)
      .filter(Boolean)
  ),
];
