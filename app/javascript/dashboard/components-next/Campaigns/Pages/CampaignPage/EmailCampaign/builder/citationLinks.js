// Web-search citations left as markdown in e-mail copy (#1079).
//
// The AI generator sometimes writes its sources as `([site](https://site/?utm_source=openai))`.
// The server links them when it generates (EmailCampaigns::Ai::CitationLinks, #1078), but drafts
// saved before that still hold the raw markdown, and e-mail clients show it as typed. This is the
// same rule, run when MJML is loaded into the editor, so the next save stores real links: each
// `[label](http(s)://url)` inside mj-text / mj-button content becomes `<a href="url">label</a>`
// and the `utm_source=openai` pair added by the search is dropped. Anything the Ruby leaves as
// written (other schemes, broken markdown, URLs Ruby's URI rejects) stays as written here too.
// specs/fixtures/citationLinks.json is shared with the Ruby spec, so both sides stay identical.
// Plain string scanning — no regex.
import { mapEndingContent } from './mjmlCanonical';

const TAGS = ['mj-text', 'mj-button'];
const SCHEMES = ['http://', 'https://'];
const SEARCH_UTM = ['utm_source', 'openai'];
const URL_STOP = [' ', '\t', '\n', '\r', '"', "'", '<', '>'];
const LABEL_STOP = ['[', '<', '\n'];
const DEFAULT_PORTS = { http: 80, https: 443 };

// Characters Ruby's URI (RFC 3986 parser) accepts in each part of the URL; `%` is checked apart.
const ALNUM = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const HOST_CHARS = `${ALNUM}-._~!$&'()*+,;=`;
const USERINFO_CHARS = `${HOST_CHARS}:`;
const PATH_CHARS = `${HOST_CHARS}:@/`;
const FRAGMENT_CHARS = `${PATH_CHARS}?`;
const HEX_DIGITS = '0123456789abcdefABCDEF';
const ASCII_LIMIT = 128;

const isHex = char => Boolean(char) && HEX_DIGITS.includes(char);
const isDigit = char => char >= '0' && char <= '9';

const escapeHtml = value =>
  value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

// ---- the URL, as Ruby's URI.parse splits and validates it ----

const splitUrl = url => {
  const hashAt = url.indexOf('#');
  const beforeHash = hashAt === -1 ? url : url.slice(0, hashAt);
  const queryAt = beforeHash.indexOf('?');
  const hier = queryAt === -1 ? beforeHash : beforeHash.slice(0, queryAt);
  const schemeEnd = hier.indexOf('://');
  const rest = hier.slice(schemeEnd + 3);
  const slash = rest.indexOf('/');
  const authority = slash === -1 ? rest : rest.slice(0, slash);
  const at = authority.indexOf('@');
  const hostPort = authority.slice(at + 1);
  const colon = hostPort.indexOf(':');
  return {
    scheme: hier.slice(0, schemeEnd),
    userinfo: at === -1 ? null : authority.slice(0, at),
    host: colon === -1 ? hostPort : hostPort.slice(0, colon),
    port: colon === -1 ? null : hostPort.slice(colon + 1),
    path: slash === -1 ? '' : rest.slice(slash),
    query: queryAt === -1 ? null : beforeHash.slice(queryAt + 1),
    fragment: hashAt === -1 ? null : url.slice(hashAt + 1),
  };
};

// Every char allowed, every `%` followed by two hex digits.
const strictPart = (part, chars) =>
  Array.from(part).every((char, i) =>
    char === '%'
      ? isHex(part[i + 1]) && isHex(part[i + 2])
      : chars.includes(char)
  );

// The query takes anything but a `%` followed by two non-hex chars (URI::Generic#query=).
const lenientQuery = query =>
  !Array.from(query).some(
    (char, i) =>
      char === '%' &&
      i + 2 < query.length &&
      !isHex(query[i + 1]) &&
      !isHex(query[i + 2])
  );

const isParsable = (url, parts) =>
  Array.from(url).every(char => char.codePointAt(0) < ASCII_LIMIT) &&
  (parts.userinfo === null || strictPart(parts.userinfo, USERINFO_CHARS)) &&
  strictPart(parts.host, HOST_CHARS) &&
  (parts.port === null || Array.from(parts.port).every(isDigit)) &&
  strictPart(parts.path, PATH_CHARS) &&
  (parts.query === null || lenientQuery(parts.query)) &&
  (parts.fragment === null || strictPart(parts.fragment, FRAGMENT_CHARS));

// URI::Generic#to_s: lowercase scheme, default port left out.
const buildUrl = ({ scheme, userinfo, host, port, path, query, fragment }) => {
  const lower = scheme.toLowerCase();
  const keepPort =
    port !== null && port !== '' && Number(port) !== DEFAULT_PORTS[lower];
  return [
    `${lower}://`,
    userinfo === null ? '' : `${userinfo}@`,
    host,
    keepPort ? `:${Number(port)}` : '',
    path,
    query === null ? '' : `?${query}`,
    fragment === null ? '' : `#${fragment}`,
  ].join('');
};

// URI.decode_www_form: split on `&` (a trailing `&` adds nothing), empty pieces kept as ['', ''].
// The leading `&` stops URLSearchParams from eating a `?` that starts the piece.
const formPairs = query => {
  const pieces = query.split('&');
  if (query.endsWith('&')) pieces.pop();
  return pieces.map(
    piece => [...new URLSearchParams(`&${piece}`)][0] ?? ['', '']
  );
};

const isSearchUtm = ([key, value]) =>
  key === SEARCH_UTM[0] && value === SEARCH_UTM[1];

const withoutSearchUtm = (url, parts) => {
  const pairs = formPairs(parts.query);
  const kept = pairs.filter(pair => !isSearchUtm(pair));
  if (kept.length === pairs.length) return url;
  const query = kept.length ? new URLSearchParams(kept).toString() : null;
  return buildUrl({ ...parts, query });
};

const cleanUrl = url => {
  if (!SCHEMES.some(scheme => url.toLowerCase().startsWith(scheme))) {
    return null;
  }
  const parts = splitUrl(url);
  if (!isParsable(url, parts)) return null;
  return parts.query ? withoutSearchUtm(url, parts) : url;
};

// ---- the markdown ----

const isValidLabel = label =>
  label.trim() !== '' && LABEL_STOP.every(stop => !label.includes(stop));

// Index of the `)` closing the URL (parentheses inside it must balance), or -1.
const urlEndAt = (text, from) => {
  let depth = 0;
  for (let i = from; i < text.length; i += 1) {
    const char = text[i];
    if (URL_STOP.includes(char)) return -1;
    if (char === ')' && depth === 0) return i;
    if (char === '(') depth += 1;
    if (char === ')') depth -= 1;
  }
  return -1;
};

// [label](url) starting at `open` -> { anchor, finish: index after the closing paren }, or null.
const anchorAt = (text, open) => {
  const close = text.indexOf(']', open);
  if (close === -1 || text[close + 1] !== '(') return null;
  const label = text.slice(open + 1, close);
  const urlEnd = urlEndAt(text, close + 2);
  if (urlEnd === -1 || !isValidLabel(label)) return null;
  const url = cleanUrl(text.slice(close + 2, urlEnd));
  if (!url) return null;
  return {
    anchor: `<a href="${escapeHtml(url)}">${label}</a>`,
    finish: urlEnd + 1,
  };
};

export const linkCitations = text => {
  if (!text.includes('](')) return text;
  let out = '';
  let pos = 0;
  let open = text.indexOf('[', pos);
  while (open !== -1) {
    const found = anchorAt(text, open);
    out += text.slice(pos, open) + (found ? found.anchor : '[');
    pos = found ? found.finish : open + 1;
    open = text.indexOf('[', pos);
  }
  return out + text.slice(pos);
};

export const linkMjmlCitations = mjml =>
  mapEndingContent(mjml ?? '', TAGS, linkCitations);
