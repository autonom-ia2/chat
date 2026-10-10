import { WEEKDAYS } from './constants';

// Textos montados a partir de números (duração, antecedência, dias). Recebem o
// `t` do vue-i18n para não ter frase solta no código.

const HOUR = 60;
const DAY = 24 * HOUR;

export const WEEKDAY_KEYS = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

export const formatMinutes = (t, minutes) => {
  if (minutes >= DAY && minutes % DAY === 0) {
    const days = minutes / DAY;
    return days === 1
      ? t('BOOKING.FORMAT.ONE_DAY')
      : t('BOOKING.FORMAT.DAYS', { n: days });
  }
  if (minutes < HOUR) return t('BOOKING.FORMAT.MINUTES', { n: minutes });
  const hours = Math.floor(minutes / HOUR);
  const rest = minutes % HOUR;
  if (rest) return t('BOOKING.FORMAT.MIXED', { hours, minutes: rest });
  return hours === 1
    ? t('BOOKING.FORMAT.ONE_HOUR')
    : t('BOOKING.FORMAT.HOURS', { n: hours });
};

export const formatHour = (t, hour) =>
  t('BOOKING.FORMAT.HOUR', { hour: String(hour).padStart(2, '0') });

export const weekdayShort = (t, day) =>
  t(`BOOKING.WEEKDAYS.${WEEKDAY_KEYS[day]}`);

export const weekdayLong = (t, day) =>
  t(`BOOKING.WEEKDAYS_LONG.${WEEKDAY_KEYS[day]}`);

// "Seg a Sex" quando os dias escolhidos são seguidos; senão "Seg, Qua, Sex".
export const formatWeekdays = (t, days) => {
  const chosen = WEEKDAYS.filter(day => days.includes(day));
  if (!chosen.length) return '';
  const first = WEEKDAYS.indexOf(chosen[0]);
  const last = WEEKDAYS.indexOf(chosen[chosen.length - 1]);
  const contiguous = last - first + 1 === chosen.length;
  if (contiguous && chosen.length >= 3) {
    return t('BOOKING.FORMAT.DAY_RANGE', {
      first: weekdayShort(t, chosen[0]),
      last: weekdayShort(t, chosen[chosen.length - 1]),
    });
  }
  return chosen.map(day => weekdayShort(t, day)).join(', ');
};

export const joinNames = names => names.filter(Boolean).join(', ');
