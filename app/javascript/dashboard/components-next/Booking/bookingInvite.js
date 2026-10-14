// Estados do link de agenda por cliente (#1190), como o backend devolve.
// Ativo = ainda serve para o cliente marcar; o painel reaproveita em vez de criar outro.
export const ACTIVE_STATES = ['created', 'sent', 'opened'];

// O selo do card só fala do que o agente acompanha depois de mandar (J1-A10).
export const BADGE_STATES = ['sent', 'opened', 'scheduled'];

const STATE_KEYS = {
  created: 'CREATED',
  sent: 'SENT',
  opened: 'OPENED',
  scheduled: 'SCHEDULED',
  expired: 'EXPIRED',
  canceled: 'CANCELED',
};

export const stateLabelKey = state =>
  STATE_KEYS[state]
    ? `CRM_KANBAN.BOOKING_INVITE.STATE.${STATE_KEYS[state]}`
    : '';

// `usable: false` = a página ou o link individual deixou de atender: vale como vencido (não se reenvia link morto).
export const inviteState = invite =>
  invite?.usable === false && ACTIVE_STATES.includes(invite.state)
    ? 'expired'
    : invite?.state;

export const isActiveInvite = invite =>
  Boolean(invite) && ACTIVE_STATES.includes(inviteState(invite));

const STATE_TONES = {
  sent: 'bg-n-blue-3 text-n-blue-11',
  opened: 'bg-n-amber-3 text-n-amber-11',
  scheduled: 'bg-n-teal-3 text-n-teal-11',
};

export const stateToneClass = state =>
  STATE_TONES[state] || 'bg-n-alpha-2 text-n-slate-11';

export const formatValidUntil = (iso, locale) => {
  if (!iso) return '';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(String(locale).replace('_', '-'), {
    day: '2-digit',
    month: '2-digit',
  }).format(date);
};
