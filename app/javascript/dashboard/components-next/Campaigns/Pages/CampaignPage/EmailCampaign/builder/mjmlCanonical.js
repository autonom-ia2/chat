// Canonical MJML for the GrapesJS editor (#1074).
//
// grapesjs-mjml loads MJML through the browser HTML parser, which does not know MJML tags: a
// self-closed `<mj-all />`, `<mj-text />` or `<mj-image />` is read as an OPEN tag and swallows
// every following sibling. In <mj-attributes> that nests the defaults (the MJML compiler then
// ignores them: line-height and colors are lost) and the nested <mj-image>/<mj-divider> become
// visible ghost blocks in the canvas and in the sent HTML.
//
// canonicalizeMjml parses the MJML as XML (where `/>` means what MJML means) and writes every
// element with an explicit close tag, so the HTML parser can no longer nest anything. Inner HTML
// of ending tags (mj-text, mj-button...) is cut out before parsing and put back verbatim, so text,
// <br>, entities and Liquid survive byte for byte. Corrupted heads saved by the old editor
// (defaults nested inside each other) are flattened back into mj-attributes.

// Tags whose content is HTML/text for MJML, never MJML children.
const ENDING_TAGS = new Set([
  'mj-text',
  'mj-button',
  'mj-raw',
  'mj-table',
  'mj-navbar-link',
  'mj-social-element',
  'mj-accordion-title',
  'mj-accordion-text',
  'mj-style',
  'mj-title',
  'mj-preview',
]);
const XML_ENTITIES = new Set(['amp', 'lt', 'gt', 'quot', 'apos']);
const MAX_ENTITY_LENGTH = 40;
const NAME_STOP = ' \t\n\r/>';

const isAsciiAlnum = char =>
  (char >= 'a' && char <= 'z') ||
  (char >= 'A' && char <= 'Z') ||
  (char >= '0' && char <= '9');
const isDigit = char => char >= '0' && char <= '9';
const isHexDigit = char =>
  isDigit(char) || (char.toLowerCase() >= 'a' && char.toLowerCase() <= 'f');

// ---- ending-tag content: cut out before parsing, restored verbatim afterwards ----

const readTagName = (src, from) => {
  let end = from;
  while (end < src.length && !NAME_STOP.includes(src[end])) end += 1;
  return src.slice(from, end);
};

// Index of the `>` that closes the tag opened at `from`, skipping quoted attribute values.
const findTagEnd = (src, from) => {
  let quote = null;
  for (let i = from; i < src.length; i += 1) {
    const char = src[i];
    if (quote) {
      if (char === quote) quote = null;
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === '>') {
      return i;
    }
  }
  return -1;
};

const isSelfClosing = tag => tag.slice(0, -1).trimEnd().endsWith('/');

const slotToken = (nonce, index) => `MJSLOT${nonce}N${index}E`;

// Replaces the inner content of every ending tag (and every comment) with a token. Ending
// tags inside mj-attributes are left alone: there they are defaults (and, in corrupted heads,
// hold nested defaults).
const cutEndingContent = (src, nonce) => {
  const slots = [];
  let out = '';
  let pos = 0;
  let inAttributes = false;
  while (pos < src.length) {
    const lt = src.indexOf('<', pos);
    if (lt === -1) return { skeleton: out + src.slice(pos), slots };
    out += src.slice(pos, lt);
    if (src.startsWith('<!--', lt)) {
      // Comments are cut out whole: XML would read entities and '--' inside them.
      const close = src.indexOf('-->', lt);
      const end = close === -1 ? src.length : close + 3;
      slots.push(src.slice(lt, end));
      out += slotToken(nonce, slots.length - 1);
      pos = end;
    } else {
      const tagEnd = findTagEnd(src, lt);
      if (tagEnd === -1) return { skeleton: out + src.slice(lt), slots };
      const tag = src.slice(lt, tagEnd + 1);
      const closing = src[lt + 1] === '/';
      const name = readTagName(src, lt + (closing ? 2 : 1));
      out += tag;
      pos = tagEnd + 1;
      if (name === 'mj-attributes') {
        inAttributes = !closing && !isSelfClosing(tag);
      } else if (
        !closing &&
        !inAttributes &&
        ENDING_TAGS.has(name) &&
        !isSelfClosing(tag)
      ) {
        const closeAt = src.indexOf(`</${name}`, pos);
        if (closeAt !== -1) {
          slots.push(src.slice(pos, closeAt));
          out += slotToken(nonce, slots.length - 1);
          pos = closeAt;
        }
      }
    }
  }
  return { skeleton: out, slots };
};

const restoreEndingContent = (xml, slots, nonce) =>
  slots.reduce(
    (acc, slot, index) => acc.split(slotToken(nonce, index)).join(slot),
    xml
  );

// ---- entities: XML knows only five; HTML names become numeric, bare & becomes &amp; ----

const isCharReference = name => {
  if (name.length < 2 || name[0] !== '#') return false;
  const hex = name[1] === 'x' || name[1] === 'X';
  const digits = name.slice(hex ? 2 : 1);
  return digits.length > 0 && [...digits].every(hex ? isHexDigit : isDigit);
};

const decodeHtmlEntity = name => {
  const raw = `&${name};`;
  const text = new DOMParser().parseFromString(`<p>${raw}</p>`, 'text/html')
    .body.textContent;
  return text === raw ? null : text;
};

const entityFor = name => {
  if (name === null || name === '') return null;
  if (XML_ENTITIES.has(name) || isCharReference(name)) return `&${name};`;
  if (![...name].every(isAsciiAlnum)) return null;
  const text = decodeHtmlEntity(name);
  if (text === null) return null;
  return [...text].map(char => `&#${char.codePointAt(0)};`).join('');
};

const normalizeEntities = src => {
  let out = '';
  let pos = 0;
  for (;;) {
    const amp = src.indexOf('&', pos);
    if (amp === -1) return out + src.slice(pos);
    out += src.slice(pos, amp);
    const semi = src.indexOf(';', amp);
    const name =
      semi === -1 || semi - amp > MAX_ENTITY_LENGTH
        ? null
        : src.slice(amp + 1, semi);
    const entity = entityFor(name);
    out += entity || '&amp;';
    pos = entity ? semi + 1 : amp + 1;
  }
};

// ---- serialization: explicit close tags, flat mj-attributes ----

const escapeAttribute = value =>
  value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;');
// `>` stays literal so Liquid comparisons ({% if a > b %}) survive.
const escapeText = value =>
  value.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

const openTag = el =>
  `<${el.tagName}${Array.from(
    el.attributes,
    attr => ` ${attr.name}="${escapeAttribute(attr.value)}"`
  ).join('')}>`;
const closeTag = el => `</${el.tagName}>`;

const isNestedAttributes = el =>
  el.tagName === 'mj-attributes' &&
  Array.from(el.children).some(child => child.children.length > 0);

let serializeNode;

const serializeElement = el => {
  // Corrupted head: every default, in document order, as a direct child of mj-attributes.
  const inner = isNestedAttributes(el)
    ? Array.from(
        el.getElementsByTagName('*'),
        child => openTag(child) + closeTag(child)
      )
    : Array.from(el.childNodes, serializeNode);
  return openTag(el) + inner.join('') + closeTag(el);
};

serializeNode = node => {
  switch (node.nodeType) {
    case Node.ELEMENT_NODE:
      return serializeElement(node);
    case Node.TEXT_NODE:
      return escapeText(node.data);
    case Node.CDATA_SECTION_NODE:
      return `<![CDATA[${node.data}]]>`;
    case Node.COMMENT_NODE:
      return `<!--${node.data}-->`;
    default:
      return '';
  }
};

// Wrapped in a synthetic root so block fragments (several sibling sections) and the text around
// a full document parse too.
const ROOT = 'mj-canonical-root';

const parseXml = skeleton => {
  try {
    const doc = new DOMParser().parseFromString(
      `<${ROOT}>${skeleton}</${ROOT}>`,
      'application/xml'
    );
    if (doc.getElementsByTagName('parsererror').length) return null;
    return doc.documentElement;
  } catch {
    return null;
  }
};

export const canonicalizeMjml = (mjml = '') => {
  if (!mjml) return mjml || '';
  const nonce = Math.random().toString(36).slice(2);
  const { skeleton, slots } = cutEndingContent(mjml, nonce);
  const root = parseXml(normalizeEntities(skeleton));
  if (!root) {
    // eslint-disable-next-line no-console
    console.warn(
      '[mjmlCanonical] MJML is not well-formed; loading it unchanged'
    );
    return mjml;
  }
  const xml = Array.from(root.childNodes, serializeNode).join('');
  return restoreEndingContent(xml, slots, nonce);
};

export default canonicalizeMjml;
