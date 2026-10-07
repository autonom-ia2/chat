// Head defaults (<mj-attributes>) resolved into the body elements (#1074).
//
// grapesjs-mjml has no component for <mj-attributes>: its children (mj-button, mj-image...) are
// rendered as visible blocks, and each canvas block is compiled in isolation, so mj-all / tag /
// mj-class defaults never reach the canvas. Writing them as explicit attributes on each body
// element makes canvas and sent e-mail identical, and <mj-attributes> can then be dropped.
//
// Precedence follows mjml-core: explicit > mj-class children of an ancestor's class > mj-class >
// tag default > mj-all. Only attributes the target tag accepts are written; the list comes from
// mjmlAllowedAttributes.json, generated from the mjml-browser bundle that grapesjs-mjml compiles
// with (scripts/mjml-attributes/build.mjs). EmailCampaigns::MjmlHeadDefaults does the same in Ruby.
import table from './mjmlAllowedAttributes.json';

const ALLOWED = Object.fromEntries(
  Object.entries(table.components).map(([tag, keys]) => [tag, new Set(keys)])
);
// mjml-core accepts css-class on every component.
const GLOBAL_ATTRIBUTES = new Set(['css-class']);
const EMPTY = { all: {}, byTag: {}, classes: {}, classesDefault: {} };

const attributesOf = el =>
  Object.fromEntries(
    Array.from(el.attributes, attr => [attr.name, attr.value])
  );

const merge = (map, key, attrs) => ({
  ...map,
  [key]: { ...map[key], ...attrs },
});

const addDefault = (defaults, el) => {
  const attrs = attributesOf(el);
  if (el.tagName === 'mj-all') {
    return { ...defaults, all: { ...defaults.all, ...attrs } };
  }
  if (el.tagName === 'mj-class') {
    const { name, ...classAttrs } = attrs;
    return name
      ? { ...defaults, classes: merge(defaults.classes, name, classAttrs) }
      : defaults;
  }
  return { ...defaults, byTag: merge(defaults.byTag, el.tagName, attrs) };
};

// <mj-class name="x"><mj-text .../></mj-class>: defaults for mj-text inside an element of class x.
const addClassChildren = (defaults, classEl) => {
  const name = classEl.getAttribute('name');
  if (!name) return defaults;
  return Array.from(classEl.children).reduce((acc, child) => {
    const byTag = merge(
      acc.classesDefault[name] || {},
      child.tagName,
      attributesOf(child)
    );
    return { ...acc, classesDefault: { ...acc.classesDefault, [name]: byTag } };
  }, defaults);
};

// Saved by the old editor: defaults nested inside each other (a self-closed tag read as open).
// mj-all / tag defaults never have children, so any of them with children means corruption.
const isCorrupted = attributesEl =>
  Array.from(attributesEl.children).some(
    child => child.tagName !== 'mj-class' && child.children.length > 0
  );

const collectOne = (defaults, attributesEl) => {
  if (isCorrupted(attributesEl)) {
    return Array.from(attributesEl.getElementsByTagName('*')).reduce(
      addDefault,
      defaults
    );
  }
  return Array.from(attributesEl.children).reduce(
    (acc, child) =>
      child.tagName === 'mj-class'
        ? addClassChildren(addDefault(acc, child), child)
        : addDefault(acc, child),
    defaults
  );
};

export const collectHeadDefaults = attributesEls =>
  attributesEls.reduce(collectOne, EMPTY);

const classNames = value => (value || '').split(' ').filter(Boolean);

// mjml-core: later classes win, but css-class values are concatenated.
const classAttributes = (defaults, names) =>
  names.reduce((acc, name) => {
    const attrs = defaults.classes[name] || {};
    const css =
      acc['css-class'] && attrs['css-class']
        ? { 'css-class': `${acc['css-class']} ${attrs['css-class']}` }
        : {};
    return { ...acc, ...attrs, ...css };
  }, {});

const classChildAttributes = (defaults, names, tag) =>
  names.reduce(
    (acc, name) => ({ ...acc, ...(defaults.classesDefault[name] || {})[tag] }),
    {}
  );

const accepts = (tag, attr) =>
  ALLOWED[tag].has(attr) || GLOBAL_ATTRIBUTES.has(attr);

// Attributes to write on a body element: its own (minus mj-class) plus the defaults it inherits.
export const resolveAttributes = (defaults, el, inheritedClasses) => {
  const { 'mj-class': ownClasses, ...own } = attributesOf(el);
  const tag = el.tagName;
  if (!ALLOWED[tag]) return own;
  const inherited = {
    ...defaults.all,
    ...defaults.byTag[tag],
    ...classAttributes(defaults, classNames(ownClasses)),
    ...classChildAttributes(defaults, classNames(inheritedClasses), tag),
  };
  const added = Object.entries(inherited).filter(
    ([attr]) => !Object.hasOwn(own, attr) && accepts(tag, attr)
  );
  return { ...own, ...Object.fromEntries(added) };
};
