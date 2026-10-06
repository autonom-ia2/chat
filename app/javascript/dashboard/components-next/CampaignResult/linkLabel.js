// How a clicked link of an e-mail campaign is shown (#990): only http/https addresses become
// links; the label is the site plus the start of the path, the full address stays in the title.
const SAFE_PROTOCOLS = ['http:', 'https:'];
const WWW = 'www.';
export const PATH_LIMIT = 32;
const ELLIPSIS = '…';

const shortPath = url => {
  const path = `${url.pathname === '/' ? '' : url.pathname}${url.search}`;
  return path.length > PATH_LIMIT
    ? `${path.slice(0, PATH_LIMIT)}${ELLIPSIS}`
    : path;
};

/**
 * @returns {{ href: string|null, label: string }} href is null when the address is not a web link.
 */
export const linkLabel = value => {
  const text = String(value || '').trim();
  let url;
  try {
    url = new URL(text);
  } catch {
    return { href: null, label: text };
  }
  if (!SAFE_PROTOCOLS.includes(url.protocol))
    return { href: null, label: text };
  const host = url.hostname.startsWith(WWW)
    ? url.hostname.slice(WWW.length)
    : url.hostname;
  return { href: url.href, label: `${host}${shortPath(url)}` };
};
