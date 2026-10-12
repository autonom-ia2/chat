// Situação de uma página de agendamento (#1371, #1370): no ar, pausada ou
// rascunho. Regra única para o selo (BookingStatusBadge) e para a gaveta
// "Marcar reuniões" do agente, que não oferece rascunho como escolha.
// Rascunho: desligada e ainda falta algo para publicar (o `missing` do index).
export const PAGE_STATUS = { LIVE: 'LIVE', PAUSED: 'PAUSED', DRAFT: 'DRAFT' };

export const pageStatus = page => {
  if (page?.enabled === true) return PAGE_STATUS.LIVE;
  return page?.missing?.length ? PAGE_STATUS.DRAFT : PAGE_STATUS.PAUSED;
};

export const isDraftPage = page => pageStatus(page) === PAGE_STATUS.DRAFT;
