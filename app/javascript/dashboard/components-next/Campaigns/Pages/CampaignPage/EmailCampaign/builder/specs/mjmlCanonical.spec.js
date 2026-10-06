import { canonicalizeMjml } from '../mjmlCanonical';
import aiEmail from './fixtures/aiEmail.mjml?raw';

const parse = mjml => new DOMParser().parseFromString(mjml, 'application/xml');
const hasSelfClosingTag = mjml => mjml.includes('/>');
// The body keeps ending-tag content verbatim (not XML); the head alone is.
const headOf = mjml =>
  mjml.slice(mjml.indexOf('<mj-head>'), mjml.indexOf('</mj-head>') + 10);
const attributeChildren = mjml =>
  Array.from(
    parse(headOf(mjml)).getElementsByTagName('mj-attributes')[0].children,
    child => child.tagName
  );

describe('canonicalizeMjml', () => {
  it('writes every element of a real AI e-mail with an explicit close tag', () => {
    const out = canonicalizeMjml(aiEmail);

    expect(out).not.toBe(aiEmail);
    // <br/> lives inside mj-text, which is kept verbatim; nothing else may self-close.
    expect(hasSelfClosingTag(out.split('<br/>').join(''))).toBe(false);
    expect(out).toContain(
      '<mj-all font-family="Arial, Helvetica, sans-serif"></mj-all>'
    );
    expect(out).toContain('<mj-spacer height="24px"></mj-spacer>');
    expect(out).toContain(
      '<mj-image src="https://example.com/logo.png" alt="Hub2you Insurtech" width="240px" align="center"></mj-image>'
    );
  });

  it('keeps the mj-attributes defaults as flat siblings', () => {
    expect(attributeChildren(canonicalizeMjml(aiEmail))).toEqual([
      'mj-all',
      'mj-text',
      'mj-section',
      'mj-button',
      'mj-image',
      'mj-divider',
    ]);
  });

  it('keeps the inner HTML of ending tags verbatim', () => {
    const out = canonicalizeMjml(aiEmail);

    expect(out).toContain(
      '<mj-text font-size="32px" font-weight="800" line-height="1.2" padding="16px 0 0">IA no seguro.<br/>Onde está o<br/>próximo negócio?</mj-text>'
    );
    expect(out).toContain(
      '([segurogta.com.br](https://segurogta.com.br/2020/noticia/?cit=502&def=gta-inova-com-lan-amento-de-assistente-virtual))'
    );
    expect(out).toContain(
      '<a href="{{ unsubscribe_url }}" style="color:#4B479B;text-decoration:underline;">Cancelar inscrição</a>'
    );
  });

  it('survives HTML entities and bare ampersands outside ending tags', () => {
    const mjml =
      '<mjml><mj-body><mj-section><mj-column>' +
      '<mj-image src="https://x.test/a.png?w=1&h=2" alt="&copy; Marca &amp; Cia" />' +
      '<mj-text>Tudo&nbsp;certo &mdash; &copy; 2026<br></mj-text>' +
      '</mj-column></mj-section></mj-body></mjml>';

    const out = canonicalizeMjml(mjml);

    expect(out).toContain('src="https://x.test/a.png?w=1&amp;h=2"');
    expect(out).toContain('alt="© Marca &amp; Cia"');
    expect(out).toContain(
      '<mj-text>Tudo&nbsp;certo &mdash; &copy; 2026<br></mj-text>'
    );
    expect(out).toContain('></mj-image>');
  });

  it('keeps comments verbatim, entities and all', () => {
    const mjml =
      '<!--\n  Template: Thank You & Review -- notes\n-->\n' +
      '<mjml><mj-body><!-- Footer & socials --><mj-section></mj-section></mj-body></mjml>';

    expect(canonicalizeMjml(mjml)).toBe(mjml);
  });

  it('lifts nested defaults of a corrupted saved head back to mj-attributes', () => {
    const corrupted =
      '<mjml><mj-head><mj-attributes>' +
      '<mj-all font-family="Arial"><mj-text color="#111" line-height="1.6">' +
      '<mj-button font-family="Arial"></mj-button></mj-text></mj-all>' +
      '</mj-attributes></mj-head>' +
      '<mj-body><mj-section><mj-column><mj-text>Oi</mj-text></mj-column></mj-section></mj-body></mjml>';

    const out = canonicalizeMjml(corrupted);

    expect(attributeChildren(out)).toEqual(['mj-all', 'mj-text', 'mj-button']);
    expect(out).toContain(
      '<mj-attributes><mj-all font-family="Arial"></mj-all><mj-text color="#111" line-height="1.6"></mj-text><mj-button font-family="Arial"></mj-button></mj-attributes>'
    );
    expect(out).toContain('<mj-text>Oi</mj-text>');
  });

  it('is idempotent', () => {
    const once = canonicalizeMjml(aiEmail);
    expect(canonicalizeMjml(once)).toBe(once);
  });

  it('returns unparseable input unchanged and warns', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const broken =
      '<mjml><mj-body><mj-section><mj-column></mj-section></mj-body></mjml>';

    expect(canonicalizeMjml(broken)).toBe(broken);
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });

  it('returns empty input unchanged', () => {
    expect(canonicalizeMjml('')).toBe('');
    expect(canonicalizeMjml(undefined)).toBe('');
  });
});
