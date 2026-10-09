import {
  BRAND_COLORS,
  CALENDAR_LOCATIONS,
  IMAGE_TYPES,
  MAX_IMAGE_BYTES,
  MISSING_STEP,
  STEP,
} from './constants';

// Converte a página da API (PageSerializer#full) no formulário do assistente e
// de volta. Funções puras: o assistente guarda um formulário só, e voltar um
// passo não perde nada.

const CALENDAR_TYPES = CALENDAR_LOCATIONS.map(item => item.type);

const locationFrom = item => ({
  type: item.type,
  url: item.url || '',
  address: item.address || '',
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
  };
};

const locationPayload = ({ type, url, address }) => {
  if (type === 'custom_link') return { type, url: url.trim() };
  if (type === 'in_person') return { type, address: address.trim() };
  return { type };
};

const usesCalendar = form =>
  form.locations.some(item => CALENDAR_TYPES.includes(item.type));

// O corpo do PATCH. A caixa de agenda só vai junto quando há Meet ou Teams:
// sem eles, a página não fica presa a caixa nenhuma.
export const formToPayload = form => ({
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
});

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

// O primeiro passo que resolve o que a publicação pediu.
export const firstMissingStep = missing =>
  Math.min(...missing.map(item => MISSING_STEP[item] || STEP.PREVIA));

export const brandSwatch = hex =>
  (BRAND_COLORS.find(color => color.hex === hex) || BRAND_COLORS[0]).swatch;
