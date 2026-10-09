import { format } from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';

// Resposta do cliente e avisos no WhatsApp de uma reunião do agendamento
// (#1192, J4-A5). Os campos vêm do serializer da reunião: `confirmation_status`
// (pending | confirmed | change_requested), `notices_stopped` e `notices`
// ([{ kind, due_at, status, skip_reason }]). Aqui só exibe; o "Lembrar" é F2-B.

const CONFIRMATION = {
  confirmed: {
    key: 'CONFIRMED',
    icon: 'i-lucide-circle-check',
    className: 'bg-n-teal-9/10 text-n-teal-11',
  },
  change_requested: {
    key: 'CHANGE_REQUESTED',
    icon: 'i-lucide-calendar-clock',
    className: 'bg-n-amber-9/10 text-n-amber-11',
  },
  pending: {
    key: 'PENDING',
    icon: 'i-lucide-clock',
    className: 'bg-n-alpha-2 text-n-slate-11',
  },
};

const NOTICE_STATUS_CLASS = {
  pending: 'bg-n-alpha-2 text-n-slate-11',
  sending: 'bg-n-blue-9/10 text-n-blue-11',
  sent: 'bg-n-teal-9/10 text-n-teal-11',
  skipped: 'bg-n-amber-9/10 text-n-amber-11',
  failed: 'bg-n-ruby-9/10 text-n-ruby-11',
};

// Motivos de "não saiu" que têm texto próprio (contrato F2-A); o resto cai em OTHER.
const SKIP_REASONS = [
  'disabled',
  'canceled',
  'past_due',
  'stale',
  'too_close',
  'replaced',
  'opted_out',
  'stopped',
  'no_inbox',
  'no_invite',
  'no_contact',
  'no_phone',
  'unsupported_inbox',
  'template_required',
  'template_without_link',
  'waha_outside_window',
  'number_cap',
  'account_cap',
];

const NOTICE_KINDS = ['booked', 'rescheduled', 'day_before', 'hour_before'];

// Reunião que passou pela página de agendamento com avisos ou resposta do
// cliente. Reunião comum (Google, Teams) não ganha o selo "Ainda não respondeu".
export const hasClientReply = meeting =>
  Boolean(
    meeting &&
      ((meeting.notices || []).length ||
        meeting.notices_stopped ||
        (meeting.confirmation_status &&
          meeting.confirmation_status !== 'pending'))
  );

export const confirmationMeta = status => CONFIRMATION[status] || null;

export const noticeStatusClass = status =>
  NOTICE_STATUS_CLASS[status] || NOTICE_STATUS_CLASS.pending;

export const noticeKindKey = kind =>
  NOTICE_KINDS.includes(kind) ? kind.toUpperCase() : null;

export const skipReasonKey = reason =>
  SKIP_REASONS.includes(reason) ? reason.toUpperCase() : 'OTHER';

// Dia e hora curtos no idioma da pessoa (14/10/2026, 15:00 ou 10/14/2026, 3:00 PM).
export const formatBookingTime = (value, locale) => {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return '';
  return format(date, 'Pp', { locale: locale === 'pt_BR' ? ptBR : enUS });
};
