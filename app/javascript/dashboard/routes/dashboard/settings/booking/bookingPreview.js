import { bookingDays, clientTimeZone, isValidTimeZone } from './publicPage';

// A prévia do painel (#1289) monta as telas da página pública de verdade. Aqui
// o formulário do assistente vira o que a página pública recebe da API
// (Crm::BookingV2::PublicPageSerializer), e os dias que ela mostraria.
const DEFAULT_WINDOW_DAYS = 14;

// Quem atende: a primeira pessoa escolhida (página com várias pessoas tem um
// link por pessoa, e cada link mostra uma só).
const hostOf = (form, page) => {
  const people = page.people || [];
  return (
    people.find(person => form.peopleIds.includes(person.id)) ||
    people[0] ||
    null
  );
};

// A foto segue a ordem do servidor: a da página (`brand.photo_url`), depois a
// que a pessoa guardou para as páginas e, por último, a do perfil dela.
export const publicPageFrom = (form, page) => {
  const host = hostOf(form, page);
  return {
    title: form.title,
    description: page.description || '',
    agent_name: host?.name || '',
    agent_photo_url: host?.booking_photo_url || host?.avatar_url || null,
    duration_minutes: form.durationMinutes,
    brand: {
      color: form.color,
      headline: form.headline,
      logo_align: form.logoAlign,
      logo_url: page.logo_url || null,
      logo_dark_url: page.logo_dark_url || null,
      logo_dark_source: page.brand?.logo_dark_source || null,
      photo_url: page.photo_url || null,
    },
  };
};

export const previewDurations = form =>
  [...new Set([form.durationMinutes, ...(form.slotDurations || [])])].sort(
    (a, b) => a - b
  );

// O fuso da página (`preview.timezone`, nome IANA vindo do servidor). Sem ele,
// o de quem está vendo.
export const previewZone = page =>
  isValidTimeZone(page.preview?.timezone)
    ? page.preview.timezone
    : clientTimeZone();

// Os dias que a página mostra: no fuso dela, só nos dias da semana em que
// atende e sem os feriados fechados (os mesmos que o servidor manda à página).
export const previewDays = (form, page, now = new Date()) =>
  bookingDays(
    previewZone(page),
    page.booking_window_days ?? DEFAULT_WINDOW_DAYS,
    form.weekdays,
    form.closeHolidays ? page.preview?.closed_dates || [] : [],
    now
  );

// Quanto o relógio do fuso está adiantado em relação ao UTC num instante (ms).
const zoneOffset = (instant, timeZone) => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(new Date(instant));
  const part = type => Number(parts.find(item => item.type === type).value);
  const shown = Date.UTC(
    part('year'),
    part('month') - 1,
    part('day'),
    part('hour'),
    part('minute')
  );
  return shown - instant;
};

// O instante em que o relógio do fuso marca `hour` horas no dia `iso`. Sem
// biblioteca: parte da mesma hora em UTC e desconta a diferença do fuso. A
// segunda conta usa a diferença do instante achado, que é outra em dia de
// troca de horário (verão/inverno).
const zonedInstant = (iso, hour, timeZone) => {
  const [year, month, day] = iso.split('-').map(Number);
  const wall = Date.UTC(year, month - 1, day, hour);
  const first = wall - zoneOffset(wall, timeZone);
  return new Date(wall - zoneOffset(first, timeZone));
};

// O "Mais cedo" da prévia: o primeiro dia aberto, na hora em que o atendimento
// começa no fuso da página. É um exemplo: a página de verdade olha a agenda de
// quem atende.
export const previewEarliest = (
  days,
  startHour,
  timeZone,
  now = new Date()
) => {
  const opening = days
    .map(iso => zonedInstant(iso, startHour, timeZone))
    .find(date => date > now);
  return opening ? opening.toISOString() : null;
};
