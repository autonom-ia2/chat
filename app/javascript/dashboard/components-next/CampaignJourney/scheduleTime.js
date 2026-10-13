// "Quando" of the review step (#993, PRD §6.4): date and time are read in the account
// time zone, whatever the browser zone is, and sent in UTC.
import { zonedTimeToUtc } from 'date-fns-tz';
import { toLocaleTag } from './localeTag';

const browserTimeZone = () => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  } catch {
    return 'UTC';
  }
};

const isValidTimeZone = timeZone => {
  try {
    Intl.DateTimeFormat('en', { timeZone });
    return true;
  } catch {
    return false;
  }
};

/**
 * Account zone, the one the platform uses: chosen in Configurações > Conta
 * (`custom_attributes.timezone`), kept in `settings.reporting_timezone` by the
 * server (Account#sync_reporting_timezone). The browser zone only when the
 * account has none (#954 fills it on the admin's next visit).
 */
export const accountTimeZone = account =>
  [
    account?.timezone,
    account?.custom_attributes?.timezone,
    account?.settings?.reporting_timezone,
  ].find(zone => zone && isValidTimeZone(zone)) || browserTimeZone();

/** `2026-10-06T09:00` typed in `timeZone` → ISO string in UTC; null when empty. */
export const scheduleToUtc = (localDateTime, timeZone) => {
  if (!localDateTime) return null;
  const date = zonedTimeToUtc(localDateTime, timeZone);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
};

/** True when the typed date and time are later than now. */
export const isFutureSchedule = (localDateTime, timeZone, now = Date.now()) => {
  const iso = scheduleToUtc(localDateTime, timeZone);
  return Boolean(iso) && new Date(iso).getTime() > now;
};

/** Human date and time of an ISO instant in the account zone. */
export const formatInZone = (iso, timeZone, locale) =>
  new Date(iso).toLocaleString(toLocaleTag(locale), {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone,
  });
