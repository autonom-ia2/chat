import registerAutonomiaBlocks from '../blocks';
import STARTER_MJML from '../starterMjml';
import { contrast } from './helpers/contrast';

// Every text and button of the editor blocks and starter e-mail meets WCAG AA (#1081):
// 4.5:1, or 3:1 for large text (>= 24px bold). Colors MJML falls back to when unset.
const MJML_DEFAULTS = {
  text: '#000000',
  buttonText: '#ffffff',
  buttonBackground: '#414141',
  page: '#ffffff',
};
const LARGE_PX = 24;

const blocks = () => {
  const added = [];
  registerAutonomiaBlocks({
    Blocks: { add: (id, block) => added.push([id, block.content]) },
  });
  return [...added, ['starter', STARTER_MJML]];
};

const parse = mjml =>
  new DOMParser().parseFromString(`<root>${mjml}</root>`, 'text/xml');

// Background behind an element: nearest ancestor (column, section, wrapper, body) that sets one.
const backgroundOf = element => {
  let node = element.parentElement;
  while (node) {
    const color = node.getAttribute('background-color');
    if (color) return color;
    node = node.parentElement;
  }
  return MJML_DEFAULTS.page;
};

const isLarge = element =>
  parseFloat(element.getAttribute('font-size') || '13') >= LARGE_PX &&
  ['bold', '700', '800', '900'].includes(element.getAttribute('font-weight'));

const pairsOf = (id, mjml) => {
  const doc = parse(mjml);
  const texts = [...doc.querySelectorAll('mj-text')].map(el => ({
    el,
    fg: el.getAttribute('color') || MJML_DEFAULTS.text,
    bg: backgroundOf(el),
  }));
  const buttons = [...doc.querySelectorAll('mj-button')].map(el => ({
    el,
    fg: el.getAttribute('color') || MJML_DEFAULTS.buttonText,
    bg: el.getAttribute('background-color') || MJML_DEFAULTS.buttonBackground,
  }));
  return [...texts, ...buttons].map(({ el, fg, bg }) => ({
    label: `${id}: ${el.tagName} "${el.textContent.trim().slice(0, 30)}" ${fg} on ${bg}`,
    ratio: contrast(fg, bg),
    minimum: isLarge(el) ? 3 : 4.5,
  }));
};

describe('editor blocks and starter e-mail: WCAG AA contrast', () => {
  const pairs = blocks().flatMap(([id, mjml]) => pairsOf(id, mjml));

  it('checks every text and button', () => {
    expect(pairs.length).toBeGreaterThan(40);
  });

  it('has no pair below the AA minimum', () => {
    const failing = pairs
      .filter(({ ratio, minimum }) => ratio < minimum)
      .map(({ label, ratio }) => `${label} = ${ratio.toFixed(2)}`);

    expect(failing).toEqual([]);
  });
});
