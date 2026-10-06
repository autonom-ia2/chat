import footerSource from '../lockedFooter.json';
import { LOCKED_FOOTER_MJML, editableFooterMjml } from '../lockedFooter';
import { FOOTER_MJML } from '../blocks';
import STARTER_MJML from '../starterMjml';

// WCAG 2.x relative luminance and contrast ratio.
const channel = hex => {
  const value = parseInt(hex, 16) / 255;
  return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
};
const luminance = color => {
  const hex = color.slice(1);
  const [r, g, b] = [0, 2, 4].map(start =>
    channel(hex.slice(start, start + 2))
  );
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a, b) => {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (light + 0.05) / (dark + 0.05);
};

const parse = mjml =>
  new DOMParser().parseFromString(`<root>${mjml}</root>`, 'text/xml');

const styleColor = style =>
  style
    .split(';')
    .map(rule => rule.split(':').map(part => part.trim()))
    .find(([prop]) => prop === 'color')[1];

describe('locked footer: one source of truth', () => {
  const doc = parse(LOCKED_FOOTER_MJML);
  const section = doc.querySelector('mj-section');
  const text = doc.querySelector('mj-text');
  const link = doc.querySelector('a');

  it('reads the shared JSON that the server also reads', () => {
    expect(LOCKED_FOOTER_MJML).toBe(footerSource.mjml);
  });

  it('is locked, carries the unsubscribe link and no brand', () => {
    expect(section.getAttribute('css-class')).toBe('footer-locked');
    expect(link.getAttribute('href')).toBe('{{ unsubscribe_url }}');
    ['hub2you', 'Hub2you', 'Autonomia', 'Av. Exemplo'].forEach(brand =>
      expect(LOCKED_FOOTER_MJML).not.toContain(brand)
    );
  });

  it('has text and link contrast of at least 4.5:1 (WCAG AA)', () => {
    const background = section.getAttribute('background-color');

    expect(
      contrast(text.getAttribute('color'), background)
    ).toBeGreaterThanOrEqual(4.5);
    expect(
      contrast(styleColor(link.getAttribute('style')), background)
    ).toBeGreaterThanOrEqual(4.5);
  });

  it('uses Arial explicitly and text of at least 12px', () => {
    expect(text.getAttribute('font-family')).toBe(
      'Arial, Helvetica, sans-serif'
    );
    expect(parseInt(text.getAttribute('font-size'), 10)).toBeGreaterThanOrEqual(
      12
    );
  });

  it('is the footer of the block and of the starter e-mail', () => {
    expect(FOOTER_MJML).toBe(editableFooterMjml({ social: true }));
    expect(STARTER_MJML).toContain(editableFooterMjml());
  });

  it('adds only editable placeholders to the shared footer', () => {
    const withSocial = parse(editableFooterMjml({ social: true }));

    expect(withSocial.querySelector('mj-text').getAttribute('color')).toBe(
      text.getAttribute('color')
    );
    expect(withSocial.querySelector('mj-text').textContent).toContain(
      footerSource.identity_placeholder
    );
    expect(
      withSocial.querySelector('mj-social').getAttribute('font-family')
    ).toBe('Arial, Helvetica, sans-serif');
    expect(withSocial.querySelectorAll('a')).toHaveLength(1);
  });
});
