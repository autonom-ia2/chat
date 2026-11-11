// Markup of the Image and Text blocks, shared by the block library, the drop/paste of content on the
// canvas and the repair of loose content on load (#2908). Explicit close tags only: grapesjs-mjml reads
// it with the HTML parser (see mjmlCanonical.js). Plain string building — no regex.

// Email-safe font on every text: without it MJML falls back to Ubuntu and imports the web font (#1081).
export const FONT_FAMILY = 'Arial, Helvetica, sans-serif';
export const TEXT_COLOR = '#1f2937';
export const TEXT_ATTRIBUTES = {
  'font-family': FONT_FAMILY,
  'font-size': '15px',
  color: TEXT_COLOR,
  'line-height': '1.6',
};
const SECTION_ATTRIBUTES = 'background-color="#ffffff" padding="16px 24px"';

// HOSTED image placeholder (PNG via placehold.co). data:image/svg+xml does NOT render in Gmail, so the
// placeholder must be an https URL returning a raster — the dragged block already shows in the sent e-mail.
const PLACEHOLDER_HOST = 'https://placehold.co/';
export const placeholderImage = (width, height, label) =>
  `${PLACEHOLDER_HOST}${width}x${height}/e2e8f0/64748b/png?text=${encodeURIComponent(label)}`;

// The frame shown where an image did not come with a public address (loose <img> of an old draft, an
// image pasted from Word): the person clicks it and uploads the file in the properties panel.
export const UPLOAD_PLACEHOLDER_LABEL = 'Clique para subir sua imagem';
export const UPLOAD_PLACEHOLDER_SRC = placeholderImage(
  600,
  300,
  UPLOAD_PLACEHOLDER_LABEL
);

export const isPlaceholderImageSrc = src =>
  String(src || '').startsWith(PLACEHOLDER_HOST);

export const isPublicImageSrc = src => {
  const text = String(src || '').trim();
  return text.startsWith('https://') || text.startsWith('http://');
};

export const escapeAttribute = value =>
  String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;');

export const attributesMarkup = attrs =>
  Object.entries(attrs)
    .map(([name, value]) => ` ${name}="${escapeAttribute(value)}"`)
    .join('');

// mj-image of a dropped/repaired image: public address kept, anything else becomes the upload frame.
export const imageElementMjml = ({ src, alt }, extra = {}) => {
  const publicSrc = isPublicImageSrc(src) ? String(src).trim() : '';
  const attrs = {
    src: publicSrc || UPLOAD_PLACEHOLDER_SRC,
    alt: String(alt || '').trim() || 'Imagem',
    ...extra,
  };
  return `<mj-image${attributesMarkup(attrs)}></mj-image>`;
};

// innerHtml must already be safe e-mail HTML (pastedHtml.js or canonical serialization).
export const textElementMjml = innerHtml =>
  `<mj-text${attributesMarkup(TEXT_ATTRIBUTES)}>${innerHtml}</mj-text>`;

const sectionMjml = inner =>
  `<mj-section ${SECTION_ATTRIBUTES}><mj-column>${inner}</mj-column></mj-section>`;

export const imageSectionMjml = image =>
  sectionMjml(imageElementMjml(image, { padding: '0' }));

export const textSectionMjml = innerHtml =>
  sectionMjml(textElementMjml(innerHtml));

// How many images of an HTML e-mail still show a placeholder (review before sending, #2908).
export const countPlaceholderImages = html => {
  if (!html) return 0;
  const doc = new DOMParser().parseFromString(html, 'text/html');
  return Array.from(doc.images).filter(img =>
    isPlaceholderImageSrc(img.getAttribute('src'))
  ).length;
};
