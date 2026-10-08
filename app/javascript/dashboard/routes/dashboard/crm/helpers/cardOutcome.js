// Desfecho do card conforme o funil (#1144). Funil que conta como venda fecha em
// won/lost; os outros fecham em resolved/cancelled, e nunca entram em venda.
// O funil pode dar nome próprio aos dois desfechos (metadata.outcome_labels).
export const SUCCESS_STATUSES = ['won', 'resolved'];
export const FAILURE_STATUSES = ['lost', 'cancelled'];
export const CLOSED_STATUSES = [...SUCCESS_STATUSES, ...FAILURE_STATUSES];

export const countsAsSale = pipeline => pipeline?.counts_as_sale !== false;

// Status que o fechamento grava neste funil.
export const outcomeStatuses = pipeline =>
  countsAsSale(pipeline)
    ? { success: 'won', failure: 'lost' }
    : { success: 'resolved', failure: 'cancelled' };

export const cardStatusLabel = (t, status, pipeline) => {
  const custom = pipeline?.metadata?.outcome_labels || {};
  if (SUCCESS_STATUSES.includes(status) && custom.success)
    return custom.success;
  if (FAILURE_STATUSES.includes(status) && custom.failure)
    return custom.failure;
  return t(
    `CRM_KANBAN.DRAWER.STATUS_${String(status || 'open').toUpperCase()}`
  );
};

// Nome dos dois desfechos do funil, para botões, abas e filtros.
export const outcomeLabels = (t, pipeline) => {
  const statuses = outcomeStatuses(pipeline);
  return {
    success: cardStatusLabel(t, statuses.success, pipeline),
    failure: cardStatusLabel(t, statuses.failure, pipeline),
  };
};

export const STATUS_PILL_CLASSES = {
  won: 'bg-n-teal-3 text-n-teal-11',
  resolved: 'bg-n-teal-3 text-n-teal-11',
  lost: 'bg-n-ruby-3 text-n-ruby-11',
  cancelled: 'bg-n-ruby-3 text-n-ruby-11',
  archived: 'bg-n-slate-4 text-n-slate-10',
};
