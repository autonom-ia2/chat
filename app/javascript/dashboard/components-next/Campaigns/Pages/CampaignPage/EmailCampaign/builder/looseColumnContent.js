// Repair of loose content inside <mj-column> on load (#2908).
//
// An image file dropped on the canvas used to enter as a bare <img> inside the column (GrapesJS default
// for external drops), and dropped/pasted text as bare HTML. MJML ignores both: the image never reached
// the sent e-mail, and the server cleaner turned its data: address into '#', so the reopened draft showed
// an empty-image frame at the photo's original size covering the canvas.
//
// Each bare <img> becomes an mj-image (public http(s) address kept, anything else becomes the "Clique para
// subir sua imagem" frame; no size style) and each run of bare text/HTML becomes one mj-text with the
// e-mail-safe font. The compiled HTML already drops the loose nodes, so the server needs no mirror: the
// next save stores the repaired MJML. Plain DOM walking — no regex.
import { imageElementMjml, textElementMjml } from './sectionMarkup';

const isElement = node => node.nodeType === Node.ELEMENT_NODE;
const isMjmlElement = node => isElement(node) && node.tagName.startsWith('mj-');
const isImage = node => isElement(node) && node.tagName.toLowerCase() === 'img';

// Text that holds only whitespace and the tokens that stand for cut-out comments (mjmlCanonical.js).
const isInertText = (text, slotPrefix) => {
  let rest = text.trim();
  while (rest.startsWith(slotPrefix)) {
    const end = rest.indexOf('E', slotPrefix.length);
    if (end === -1) return false;
    rest = rest.slice(end + 1).trim();
  }
  return rest === '';
};

// serialize(node, { plain }) writes one node; plain = no head defaults (they are for MJML tags only).
export const serializeColumnChildren = (nodes, { serialize, slotPrefix }) => {
  const out = [];
  let loose = [];
  const isInert = node =>
    node.nodeType === Node.COMMENT_NODE ||
    (node.nodeType === Node.TEXT_NODE && isInertText(node.data, slotPrefix));
  const flush = () => {
    if (loose.some(node => !isInert(node))) {
      const html = loose.map(node => serialize(node, { plain: true })).join('');
      out.push(textElementMjml(html.trim()));
    } else {
      out.push(...loose.map(node => serialize(node, { plain: true })));
    }
    loose = [];
  };
  nodes.forEach(node => {
    if (isMjmlElement(node)) {
      flush();
      out.push(serialize(node, { plain: false }));
    } else if (isImage(node)) {
      flush();
      out.push(
        imageElementMjml({
          src: node.getAttribute('src'),
          alt: node.getAttribute('alt'),
        })
      );
    } else {
      loose.push(node);
    }
  });
  flush();
  return out.join('');
};
