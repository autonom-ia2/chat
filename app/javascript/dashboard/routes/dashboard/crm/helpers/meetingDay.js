import parsePhoneNumber from 'libphonenumber-js';

// O dia da reunião da página de agendamento (#1193, J4): quando oferecer
// "Lembrar", "Enviar link para marcar outro horário" e "Chamar no WhatsApp", e
// como mostrar a recusa do servidor em frase leiga. Funções puras.

// Recusas de POST .../meetings/:id/remind e .../rebook_link (422) que têm
// frase própria (CRM_KANBAN.CALENDAR.MEETING_DAY.REFUSED.*). O resto cai em OTHER.
const REFUSALS = {
  'crm.booking_v2.not_remindable': 'NOT_REMINDABLE',
  'crm.booking_v2.already_confirmed': 'ALREADY_CONFIRMED',
  'crm.booking_v2.stopped': 'STOPPED',
  'crm.booking_v2.no_invite': 'NO_INVITE',
  'crm.booking_v2.recently_reminded': 'RECENTLY_REMINDED',
  'crm.booking_v2.recently_sent': 'RECENTLY_SENT',
  'crm.booking_v2.no_conversation': 'NO_CONVERSATION',
  'crm.booking_v2.cannot_reply': 'CANNOT_REPLY',
  'crm.booking_v2.not_rebookable': 'NOT_REBOOKABLE',
  'crm.booking_v2.no_page': 'NO_PAGE',
};

const isFuture = (value, now) => {
  const date = value ? new Date(value) : null;
  return Boolean(date && !Number.isNaN(date.getTime()) && date > now);
};

// "Lembrar": reunião de página de agendamento, ainda por acontecer, que o
// cliente não confirmou e cujos avisos ele não parou.
export const canRemind = (meeting, now = new Date()) =>
  Boolean(
    meeting?.booking &&
      meeting.status === 'scheduled' &&
      isFuture(meeting.starts_at, now) &&
      meeting.confirmation_status !== 'confirmed' &&
      !meeting.notices_stopped
  );

// "Enviar link para marcar outro horário": o cliente faltou.
export const canRebook = meeting =>
  Boolean(meeting?.booking && meeting.outcome === 'no_show');

// "Chamar no WhatsApp": a reunião é no WhatsApp e há conversa ou número.
const WHATSAPP_TYPES = ['whatsapp_video', 'whatsapp_voice'];
export const canCall = meeting =>
  Boolean(
    WHATSAPP_TYPES.includes(
      meeting?.location_type || meeting?.online_meeting_type
    ) &&
      (meeting?.client?.conversation_id || meeting?.client?.whatsapp_url)
  );

// { key, url } da resposta de erro do axios. `url` só vem quando o agente pode
// copiar o link e mandar de outro jeito (janela fechada, sem conversa).
export const refusalFrom = error => {
  const data = error?.response?.data || {};
  return {
    key: REFUSALS[data.error] || 'OTHER',
    url: typeof data.url === 'string' ? data.url : '',
  };
};

// Número do cliente para ler (+55 11 91234 5678). O E.164 vem gravado na
// reunião; a biblioteca de telefone só formata. Sem formato conhecido, mostra
// como veio.
export const formatClientPhone = phone => {
  if (!phone) return '';
  try {
    return parsePhoneNumber(phone)?.formatInternational() || phone;
  } catch {
    return phone;
  }
};

// Id da reunião num evento do calendário (`meeting_12`) ou na própria reunião.
const MEETING_PREFIX = 'meeting_';
export const meetingIdOf = meeting => {
  const raw = String(meeting?.meeting_id || meeting?.id || '');
  return raw.startsWith(MEETING_PREFIX)
    ? raw.slice(MEETING_PREFIX.length)
    : raw;
};
