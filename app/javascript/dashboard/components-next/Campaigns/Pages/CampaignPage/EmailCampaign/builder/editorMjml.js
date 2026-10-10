// What goes into and comes out of the GrapesJS canvas (#1074).
//
// Load: canonical MJML (explicit close tags, head defaults resolved into the body — see
// mjmlCanonical.js) minus <mj-title> and <mj-preview>: grapesjs-mjml has no component for them and
// prints their text at the top of the canvas. They are held aside and put back on export, so the
// saved MJML and the sent HTML (subject title, inbox preview text) keep them.
// Web-search citations left as markdown by old AI drafts are linked first (citationLinks.js), so
// the canvas shows real links and the next save stores them.
// Plain string scanning on canonical MJML — no regex.
import { canonicalizeMjml } from './mjmlCanonical';
import { linkMjmlCitations } from './citationLinks';

// mj-font (#1076): the brand font of an identity e-mail; one per family, all held.
const HELD_TAGS = ['mj-title', 'mj-preview', 'mj-font'];

// [start, end) of the first <tag ...>...</tag> in mjml, or null.
const elementRange = (mjml, tag) => {
  const start = mjml.indexOf(`<${tag}`);
  if (start === -1) return null;
  const close = mjml.indexOf(`</${tag}>`, start);
  if (close === -1) return null;
  return [start, close + tag.length + 3];
};

const cutTag = ({ mjml, held }, tag) => {
  const range = elementRange(mjml, tag);
  if (!range) return { mjml, held };
  return cutTag(
    {
      mjml: mjml.slice(0, range[0]) + mjml.slice(range[1]),
      held: held + mjml.slice(range[0], range[1]),
    },
    tag
  );
};

// -> { mjml: for setComponents, held: head markup to give back on export }
export const prepareMjmlForEditor = source =>
  HELD_TAGS.reduce(cutTag, {
    mjml: canonicalizeMjml(linkMjmlCitations(source)),
    held: '',
  });

const afterOpenTag = (mjml, tag) => {
  const start = mjml.indexOf(`<${tag}`);
  return start === -1 ? -1 : mjml.indexOf('>', start) + 1;
};

// Puts the held head markup back into what the editor exports.
export const restoreHeldHead = (mjml, held) => {
  if (!held) return mjml;
  const inHead = afterOpenTag(mjml, 'mj-head');
  if (inHead > 0) return mjml.slice(0, inHead) + held + mjml.slice(inHead);
  const inRoot = afterOpenTag(mjml, 'mjml');
  if (inRoot > 0) {
    return `${mjml.slice(0, inRoot)}<mj-head>${held}</mj-head>${mjml.slice(inRoot)}`;
  }
  // No <mjml> root (empty or partial export): never drop the title/preview silently.
  // eslint-disable-next-line no-console
  console.error(
    '[editorMjml] export has no <mjml> root; wrapping it to keep <mj-title>/<mj-preview>'
  );
  return `<mjml><mj-head>${held}</mj-head>${mjml}</mjml>`;
};
