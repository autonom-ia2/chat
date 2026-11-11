// Where dropped or pasted content goes on the canvas (#2908). Every insertion is a whole block (an
// mj-section, child of mj-body), so nothing enters loose inside a column. The tree is walked by hand:
// Component#find hangs under jsdom (see specs/mjmlCanonicalGrapes.spec.js).

const typeOf = component => component?.get?.('type');

const ancestors = component => {
  const list = [];
  let node = component;
  while (node) {
    list.push(node);
    node = node.parent?.();
  }
  return list;
};

export const isLockedFooter = component =>
  String(component?.getAttributes?.()['css-class'] || '')
    .split(' ')
    .includes('footer-locked');

// The component GrapesJS rendered as this element (or its closest rendered ancestor).
export const componentFromElement = element => {
  let node = element;
  while (node) {
    // eslint-disable-next-line no-underscore-dangle
    const model = node.__gjsv?.model;
    if (model) return model;
    node = node.parentNode;
  }
  return null;
};

const findType = (component, type) => {
  if (!component) return null;
  if (typeOf(component) === type) return component;
  return (
    component
      .components()
      .map(child => findType(child, type))
      .find(Boolean) || null
  );
};

export const findBody = editor => findType(editor.getWrapper(), 'mj-body');

export const imageAt = component =>
  ancestors(component).find(node => typeOf(node) === 'mj-image') || null;

// The top-level block (direct child of mj-body) holding the component.
export const blockOf = component =>
  ancestors(component).find(node => typeOf(node.parent?.()) === 'mj-body') ||
  null;

// { block, after }: next to which block the content goes. No block = end of the e-mail, above the
// locked footer. The locked footer itself never moves: content dropped on it goes right above it.
export const anchorFor = (component, { before = false } = {}) => {
  const block = component ? blockOf(component) : null;
  if (!block) return { block: null, after: true };
  if (isLockedFooter(block)) return { block, after: false };
  return { block, after: !before };
};

const insertionIndex = (body, anchor) => {
  const children = body.components();
  const alive = anchor.block && anchor.block.parent?.() === body;
  if (alive) return anchor.block.index() + (anchor.after ? 1 : 0);
  const footer = children.find(isLockedFooter);
  return footer ? footer.index() : children.length;
};

// Adds one block of MJML at the anchor; returns the anchor right after it (for the next block).
export const insertBlock = (editor, anchor, markup) => {
  const body = findBody(editor);
  if (!body) return anchor;
  const added = body
    .components()
    .add(markup, { at: insertionIndex(body, anchor) });
  const block = Array.isArray(added) ? added[0] : added;
  return block ? { block, after: true } : anchor;
};

// mj-image exports the src from the model property, which overrides the attribute (useEmailEditor.js).
export const replaceImageSrc = (image, src) => {
  image.set('src', src);
  image.addAttributes({ src });
};
