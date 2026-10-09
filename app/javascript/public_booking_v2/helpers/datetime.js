// Datas e horas da página (RA-08). Os dias da agenda são datas no fuso da PÁGINA (é o que a API espera em
// `?date=`); os horários aparecem no fuso de quem abre a página, e a página diz qual é cada um.
export const MAX_WINDOW_DAYS = 60;

export const clientTimeZone = () =>
  Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';

export const isValidTimeZone = timeZone => {
  if (typeof timeZone !== 'string' || !timeZone) return false;
  try {
    Intl.DateTimeFormat('en', { timeZone });
    return true;
  } catch (error) {
    return false;
  }
};

export const toIntlLocale = locale => String(locale || 'en').replace('_', '-');

// YYYY-MM-DD de `date` no fuso informado.
export const dateInZone = (date, timeZone) => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const part = type => parts.find(item => item.type === type).value;
  return `${part('year')}-${part('month')}-${part('day')}`;
};

const parseIsoDate = iso => {
  const [year, month, day] = iso.split('-').map(Number);
  return { year, month, day };
};

// Hoje (no fuso da página) e os próximos `windowDays` dias.
export const bookingDays = (timeZone, windowDays, now = new Date()) => {
  const count = Math.min(Math.max(Number(windowDays) || 0, 0), MAX_WINDOW_DAYS);
  const { year, month, day } = parseIsoDate(dateInZone(now, timeZone));
  return Array.from({ length: count + 1 }, (_, offset) =>
    new Date(Date.UTC(year, month - 1, day + offset)).toISOString().slice(0, 10)
  );
};

// Rótulo de um dia da agenda: é uma data de calendário, então formatamos ao meio-dia UTC em UTC.
export const dayLabel = (iso, locale) => {
  const { year, month, day } = parseIsoDate(iso);
  const date = new Date(Date.UTC(year, month - 1, day, 12));
  const format = options =>
    new Intl.DateTimeFormat(toIntlLocale(locale), {
      timeZone: 'UTC',
      ...options,
    }).format(date);
  return {
    weekday: format({ weekday: 'short' }),
    day: format({ day: 'numeric' }),
    month: format({ month: 'short' }),
    full: format({ weekday: 'long', day: 'numeric', month: 'long' }),
  };
};

export const timeLabel = (iso, locale, timeZone = clientTimeZone()) =>
  new Intl.DateTimeFormat(toIntlLocale(locale), {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

export const whenLabel = (iso, locale, timeZone = clientTimeZone()) =>
  new Intl.DateTimeFormat(toIntlLocale(locale), {
    timeZone,
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

// Nome amigável do fuso ("horário de Brasília"), com o identificador como reserva.
export const zoneLabel = (timeZone, locale) => {
  try {
    const parts = new Intl.DateTimeFormat(toIntlLocale(locale), {
      timeZone,
      timeZoneName: 'longGeneric',
    }).formatToParts(new Date());
    return parts.find(item => item.type === 'timeZoneName')?.value || timeZone;
  } catch (error) {
    return timeZone;
  }
};
