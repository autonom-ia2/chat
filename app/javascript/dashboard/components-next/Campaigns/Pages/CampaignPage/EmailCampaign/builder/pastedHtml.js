// HTML pasted or dropped on the e-mail canvas (#2908): an e-mail or text from Word, Google Docs, a site
// or an AI chat. Keeps what reads as formatting (paragraphs, bold, italic, underline, lists, links) and
// drops the rest (styles, classes, Word/Docs markup). Images are taken out: they become Image blocks
// (useImageDrop.js), never loose <img> inside a text. The result keeps the order of what was pasted —
// text, image, text… — so an e-mail pasted whole comes back as it was written. DOMParser walking and
// DOM Range splitting — no regex.

const BLOCK_TAGS = new Set(['p', 'ul', 'ol', 'li']);
const INLINE_TAGS = new Set(['strong', 'em', 'u']);
const RENAME = { b: 'strong', i: 'em', h1: 'p', h2: 'p', h3: 'p' };
const PARAGRAPH_LIKE = new Set([
  'div',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'section',
  'article',
  'header',
  'footer',
  'tr',
]);
const HEADINGS = new Set(['h1', 'h2', 'h3']);
const DROPPED = new Set([
  'script',
  'style',
  'meta',
  'link',
  'title',
  'head',
  'iframe',
  'object',
  'embed',
  'svg',
  'video',
  'audio',
  'button',
  'input',
  'select',
  'textarea',
  'form',
  'template',
]);
const SAFE_LINK_PREFIXES = ['https://', 'http://', 'mailto:', 'tel:', '{{'];
const BOLD_WEIGHTS = new Set(['bold', 'bolder', '600', '700', '800', '900']);

const safeHref = href => {
  const text = String(href || '').trim();
  return SAFE_LINK_PREFIXES.some(prefix =>
    text.toLowerCase().startsWith(prefix)
  )
    ? text
    : '';
};

// Google Docs marks bold/italic with spans styles instead of <b>/<i>.
const styleWrappers = el => {
  const style = el.style || {};
  const wrappers = [];
  if (BOLD_WEIGHTS.has(String(style.fontWeight || '').toLowerCase())) {
    wrappers.push('strong');
  }
  if (String(style.fontStyle || '').toLowerCase() === 'italic') {
    wrappers.push('em');
  }
  if (String(style.textDecoration || '').includes('underline')) {
    wrappers.push('u');
  }
  return wrappers;
};

// Docs wraps the whole paste in <b style="font-weight:normal">: that b is not bold.
const isFakeBold = el =>
  el.tagName.toLowerCase() === 'b' &&
  String(el.style?.fontWeight || '').toLowerCase() === 'normal';

const wrapIn = (doc, names, children) =>
  names.reduceRight((inner, name) => {
    const wrapper = doc.createElement(name);
    inner.forEach(child => wrapper.appendChild(child));
    return [wrapper];
  }, children);

const hasBlock = nodes =>
  nodes.some(
    node =>
      node.nodeType === Node.ELEMENT_NODE &&
      BLOCK_TAGS.has(node.tagName.toLowerCase())
  );

const MARKER = 'data-pasted-image';

let cleanChildren;

const cleanElement = (el, doc, images) => {
  const name = el.tagName.toLowerCase();
  if (DROPPED.has(name)) return [];
  if (name === 'img') {
    // A marker where the image was: the text is split there afterwards.
    const marker = doc.createElement('img');
    marker.setAttribute(MARKER, String(images.length));
    images.push({
      src: el.getAttribute('src') || '',
      alt: el.getAttribute('alt') || '',
    });
    return [marker];
  }
  if (name === 'br') return [doc.createElement('br')];
  const children = cleanChildren(el, doc, images);
  if (name === 'a') {
    const href = safeHref(el.getAttribute('href'));
    if (!href) return children;
    const link = doc.createElement('a');
    link.setAttribute('href', href);
    children.forEach(child => link.appendChild(child));
    return [link];
  }
  const target = isFakeBold(el) ? null : RENAME[name] || name;
  const inner = HEADINGS.has(name)
    ? wrapIn(doc, ['strong'], children)
    : children;
  // A paragraph never wraps another block (a Word <div> around <p>s): the wrapper goes away.
  if ((target === 'p' || PARAGRAPH_LIKE.has(name)) && hasBlock(inner)) {
    return inner;
  }
  if (BLOCK_TAGS.has(target) || INLINE_TAGS.has(target)) {
    return wrapIn(doc, [target, ...styleWrappers(el)], inner);
  }
  if (PARAGRAPH_LIKE.has(name)) return wrapIn(doc, ['p'], inner);
  return wrapIn(doc, styleWrappers(el), inner);
};

cleanChildren = (el, doc, images) =>
  Array.from(el.childNodes).flatMap(node => {
    if (node.nodeType === Node.TEXT_NODE) {
      return [doc.createTextNode(node.data)];
    }
    if (node.nodeType === Node.ELEMENT_NODE) {
      return cleanElement(node, doc, images);
    }
    return [];
  });

// Whatever holds no text and no line break (Word spacing, the empty half of a split paragraph).
const isEmptyNode = node =>
  node.nodeType === Node.TEXT_NODE
    ? !node.data.trim()
    : node.nodeType === Node.ELEMENT_NODE &&
      !node.querySelector('br') &&
      node.tagName.toLowerCase() !== 'br' &&
      !node.textContent.trim();

const textSegment = (doc, fragment) => {
  const holder = doc.createElement('div');
  Array.from(fragment.childNodes)
    .filter(node => !isEmptyNode(node))
    .forEach(node => holder.appendChild(node));
  const html = holder.innerHTML.trim();
  return html ? [{ type: 'text', html }] : [];
};

// Splits the cleaned tree at each image marker; a paragraph holding an image becomes two paragraphs.
const splitAtImages = (doc, root, images) => {
  const segments = [];
  const range = doc.createRange();
  range.setStart(root, 0);
  root.querySelectorAll(`img[${MARKER}]`).forEach(marker => {
    range.setEndBefore(marker);
    segments.push(...textSegment(doc, range.cloneContents()));
    segments.push({
      type: 'image',
      ...images[Number(marker.getAttribute(MARKER))],
    });
    range.setStartAfter(marker);
  });
  range.setEnd(root, root.childNodes.length);
  segments.push(...textSegment(doc, range.cloneContents()));
  return segments;
};

// -> { segments: [{ type: 'text', html } | { type: 'image', src, alt }] in pasted order,
//      html: all the text together (may be ''), images: [{ src, alt }] }
export const sanitizePastedHtml = source => {
  const parsed = new DOMParser().parseFromString(
    String(source || ''),
    'text/html'
  );
  const images = [];
  const out = parsed.createElement('div');
  cleanChildren(parsed.body, parsed, images).forEach(node =>
    out.appendChild(node)
  );
  const segments = splitAtImages(parsed, out, images);
  const html = segments
    .filter(segment => segment.type === 'text')
    .map(segment => segment.html)
    .join('');
  return { segments, html, images };
};

const escapeText = text =>
  text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

// Plain text dropped on the canvas: one paragraph per line.
export const plainTextToHtml = text =>
  String(text || '')
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .map(line => `<p>${escapeText(line)}</p>`)
    .join('');
