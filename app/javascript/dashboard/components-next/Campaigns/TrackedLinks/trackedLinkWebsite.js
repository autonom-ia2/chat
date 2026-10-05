// Helpers for tracked links used as a website button (usage: 'website').
// Contract: docs/crm/ponte-lp-atribuicao.md, sections 2 and 5.

export const MAX_ALLOWED_ORIGINS = 5;
const LOCAL_HOSTS = ['localhost', '127.0.0.1'];
const DAY_MS = 24 * 60 * 60 * 1000;

// Turns what a person pasted ("placement.com.br", "https://Placement.com.br/lp")
// into the exact origin the server compares with the Origin header
// (scheme://host[:port], lowercase, no trailing slash). The URL parser does the
// work; null means "not a usable address". A public site is always saved as
// https; only localhost keeps http (and the server refuses it in production).
export const normalizeOrigin = value => {
  const text = String(value ?? '').trim();
  if (!text) return null;

  let url;
  try {
    url = new URL(text.includes('://') ? text : `https://${text}`);
  } catch {
    return null;
  }

  if (url.username || url.password) return null;
  if (LOCAL_HOSTS.includes(url.hostname)) {
    return ['http:', 'https:'].includes(url.protocol) ? url.origin : null;
  }
  if (!['http:', 'https:'].includes(url.protocol)) return null;
  if (!url.hostname.includes('.')) return null;
  // People type or copy http:// out of habit; the live site answers on https,
  // which is what the browser sends in the Origin header.
  return `https://${url.host}`;
};

// One address per line. Returns the de-duplicated origins plus what is wrong.
export const parseAllowedOrigins = text => {
  const lines = String(text ?? '')
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);
  const invalid = lines.filter(line => !normalizeOrigin(line));
  const origins = [...new Set(lines.map(normalizeOrigin).filter(Boolean))];

  return {
    origins,
    invalid,
    isEmpty: !origins.length && !invalid.length,
    isTooMany: origins.length > MAX_ALLOWED_ORIGINS,
    isValid:
      !invalid.length &&
      origins.length > 0 &&
      origins.length <= MAX_ALLOWED_ORIGINS,
  };
};

// 'recent' (< 24h), 'stale' (older) or 'never' (no accepted signal yet).
export const signalStatus = (lastSignalAt, now = Date.now()) => {
  if (!lastSignalAt) return 'never';
  const time = new Date(lastSignalAt).getTime();
  if (Number.isNaN(time)) return 'never';
  return now - time < DAY_MS ? 'recent' : 'stale';
};

// What the header of a website origin can honestly promise:
// 'needs_origins' (no site allowed, clicks are refused), 'waiting' (allowed,
// but no signal has arrived yet) or 'ready' (the site is already sending).
export const websiteReadiness = (link, now = Date.now()) => {
  if (!link?.allowed_origins?.length) return 'needs_origins';
  return signalStatus(link.last_signal_at, now) === 'never'
    ? 'waiting'
    : 'ready';
};

// { BRL: 151120, USD: 5000 } (cents) -> "R$ 1.511,20 · US$ 50,00".
export const formatValueByCurrency = (valueByCurrency, locale) => {
  const language = String(locale || 'en').replace('_', '-');
  return Object.entries(valueByCurrency || {})
    .filter(([, cents]) => Number(cents) > 0)
    .map(([currency, cents]) =>
      new Intl.NumberFormat(language, { style: 'currency', currency }).format(
        Number(cents) / 100
      )
    )
    .join(' · ');
};
