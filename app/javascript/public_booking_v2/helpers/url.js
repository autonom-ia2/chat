// Só http/https viram link ou botão. `javascript:`, `data:` e afins nunca chegam ao `href`.
const SAFE_PROTOCOLS = ['http:', 'https:'];

const parse = (value, base) => {
  try {
    return new URL(value, base);
  } catch (error) {
    return null;
  }
};

// Link absoluto http/https (reunião, WhatsApp, imagens).
export const safeAbsoluteUrl = value => {
  if (typeof value !== 'string' || !value.trim()) return null;
  const url = parse(value.trim());
  return url && SAFE_PROTOCOLS.includes(url.protocol) ? url.href : null;
};

// Link do próprio site (ex.: /public/api/v2/ics/<token>) ou absoluto http/https.
export const safeUrl = value => {
  if (typeof value !== 'string' || !value.trim()) return null;
  const url = parse(value.trim(), window.location.origin);
  return url && SAFE_PROTOCOLS.includes(url.protocol) ? url.href : null;
};
