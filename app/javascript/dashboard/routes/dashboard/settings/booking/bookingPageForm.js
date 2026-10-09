import {
  BRAND_COLORS,
  CALENDAR_LOCATIONS,
  IMAGE_TYPES,
  DEFAULT_CANCEL_UNTIL,
  DEFAULT_NOTICE_PRESET,
  MAX_IMAGE_BYTES,
  MISSING_STEP,
  STEP,
} from './constants';
import { noticeTemplatesPayload } from './bookingNotices';

// Converte a página da API (PageSerializer#full) no formulário do assistente e
// de volta. Funções puras: o assistente guarda um formulário só, e voltar um
// passo não perde nada.

const CALENDAR_TYPES = CALENDAR_LOCATIONS.map(item => item.type);

// `label` não tem campo na tela, mas a API aceita: o que vier salvo volta igual.
const locationFrom = item => ({
  type: item.type,
  url: item.url || '',
  address: item.address || '',
  label: item.label || '',
});

export const pageToForm = page => {
  const hours = page.working_hours || {};
  return {
    title: page.title || '',
    durationMinutes: page.duration_minutes || 30,
    slotDurations: [...(page.slot_durations || [])],
    peopleIds: (page.people || []).map(person => person.id),
    locations: (page.locations || []).map(locationFrom),
    calendarInboxId: page.calendar_inbox_id ?? null,
    weekdays: [...(hours.weekdays || [])].map(Number),
    startHour: Number(hours.start_hour ?? 9),
    endHour: Number(hours.end_hour ?? 17),
    minNoticeMinutes: page.min_notice_minutes ?? 0,
    bufferMinutes: page.buffer_minutes ?? 0,
    color: page.brand?.color || BRAND_COLORS[0].hex,
    headline: page.brand?.headline || '',
    pipelineId: page.default_pipeline_id ?? null,
    stageId: page.default_stage_id ?? null,
    noticeInboxId: page.notice_inbox_id ?? null,
    noticePreset: page.notice_preset || DEFAULT_NOTICE_PRESET,
    noticeTemplates: { ...(page.notice_templates || {}) },
    cancelUntilMinutes: page.cancel_until_minutes ?? DEFAULT_CANCEL_UNTIL,
  };
};

const locationFields = ({ type, url, address }) => {
  if (type === 'custom_link') return { type, url: url.trim() };
  if (type === 'in_person') return { type, address: address.trim() };
  return { type };
};

const locationPayload = item =>
  item.label
    ? { ...locationFields(item), label: item.label }
    : locationFields(item);

const usesCalendar = form =>
  form.locations.some(item => CALENDAR_TYPES.includes(item.type));

// O corpo do PATCH. A caixa de agenda só vai junto quando há Meet ou Teams:
// sem eles, a página não fica presa a caixa nenhuma.
const basePayload = form => ({
  title: form.title.trim(),
  duration_minutes: form.durationMinutes,
  slot_durations: form.slotDurations.filter(
    minutes => minutes !== form.durationMinutes
  ),
  locations: form.locations.map(locationPayload),
  calendar_inbox_id: usesCalendar(form) ? form.calendarInboxId : null,
  working_hours: {
    start_hour: form.startHour,
    end_hour: form.endHour,
    weekdays: [...form.weekdays].sort((a, b) => a - b),
  },
  min_notice_minutes: form.minNoticeMinutes,
  buffer_minutes: form.bufferMinutes,
  brand: { color: form.color, headline: form.headline.trim() },
  default_pipeline_id: form.pipelineId,
  default_stage_id: form.stageId,
  notice_preset: form.noticePreset,
  notice_templates: noticeTemplatesPayload(form),
  cancel_until_minutes: form.cancelUntilMinutes,
});

// A caixa de avisos só vai quando muda: o servidor confere a caixa contra as
// que a própria pessoa enxerga, e quem não vê a caixa escolhida por outra
// pessoa ainda precisa conseguir salvar o resto da página.
export const formToPayload = (form, page = null) => {
  const payload = basePayload(form);
  if (page && form.noticeInboxId === (page.notice_inbox_id ?? null)) {
    return payload;
  }
  return { ...payload, notice_inbox_id: form.noticeInboxId };
};

// `new URL` é o parser do navegador: aceita só endereço completo http(s).
export const isWebUrl = value => {
  try {
    const url = new URL(value.trim());
    return url.protocol === 'https:' || url.protocol === 'http:';
  } catch {
    return false;
  }
};

const locationProblem = item => {
  if (item.type === 'custom_link' && !isWebUrl(item.url)) return 'LINK';
  if (item.type === 'in_person' && !item.address.trim()) return 'ADDRESS';
  return null;
};

// O que falta em cada passo, antes de mandar para o servidor. Devolve a chave
// do aviso (BOOKING.WIZARD.ERRORS.*) ou null.
export const stepProblem = (step, form) => {
  if (step === STEP.CONTE) {
    if (!form.title.trim()) return 'TITLE';
    if (!form.peopleIds.length) return 'PEOPLE';
  }
  if (step === STEP.ONDE) {
    if (!form.locations.length) return 'LOCATION';
    const problem = form.locations.map(locationProblem).find(Boolean);
    if (problem) return problem;
    if (usesCalendar(form) && !form.calendarInboxId) return 'CALENDAR';
  }
  if (step === STEP.QUANDO) {
    if (!form.weekdays.length) return 'WEEKDAYS';
    if (form.startHour >= form.endHour) return 'HOURS';
  }
  return null;
};

export const imageProblem = file => {
  if (!IMAGE_TYPES.includes(file.type)) return 'IMAGE_TYPE';
  if (file.size > MAX_IMAGE_BYTES) return 'IMAGE_SIZE';
  return null;
};

// Recusas do servidor (422) que têm aviso próprio. O código vem do
// BookingPagesController; o campo, do errors do ActiveRecord::RecordInvalid.
const SERVER_ERROR_CODES = {
  'crm.booking_v2.calendar_inbox_invalid': 'CALENDAR_GONE',
  'crm.booking_v2.people_invalid': 'PEOPLE_GONE',
  'crm.booking_v2.notice_inbox_invalid': 'NOTICE_INBOX_GONE',
};
const SERVER_ERROR_FIELDS = {
  locations: 'LOCATIONS',
  working_hours: 'HOURS',
  min_notice_minutes: 'HOURS',
  slot_durations: 'HOURS',
  default_pipeline_id: 'PIPELINE',
  default_stage_id: 'PIPELINE',
  brand: 'BRAND',
  notice_inbox: 'NOTICE_INBOX_GONE',
  notice_templates: 'NOTICE_TEMPLATES',
  notice_preset: 'NOTICES',
  cancel_until_minutes: 'NOTICES',
};

// Devolve a chave do aviso (BOOKING.WIZARD.SERVER_ERRORS.*) ou null, quando
// só cabe o aviso geral de "não salvou".
export const serverProblem = data => {
  const code = SERVER_ERROR_CODES[data?.error];
  if (code) return code;
  const field = Object.keys(data?.errors || {}).find(
    key => SERVER_ERROR_FIELDS[key]
  );
  return field ? SERVER_ERROR_FIELDS[field] : null;
};

// O primeiro passo que resolve o que a publicação pediu.
export const firstMissingStep = missing =>
  Math.min(...missing.map(item => MISSING_STEP[item] || STEP.PREVIA));

export const brandSwatch = hex =>
  (BRAND_COLORS.find(color => color.hex === hex) || BRAND_COLORS[0]).swatch;
