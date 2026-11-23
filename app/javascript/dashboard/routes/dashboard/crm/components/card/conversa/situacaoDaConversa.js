// A situação da conversa em texto (Aberta, Pendente…), igual na lista e no visor.
const SITUACAO = {
  open: 'OPEN',
  pending: 'PENDING',
  resolved: 'RESOLVED',
  snoozed: 'SNOOZED',
};

export const situacaoDaConversa = (t, status) =>
  t(
    `CRM_KANBAN.DRAWER.CONVERSATION_STATUS_${SITUACAO[String(status || '').toLowerCase()] || 'UNKNOWN'}`
  );
