import { canonicalizeMjml } from '../mjmlCanonical';
import aiEmail from './fixtures/aiEmail.mjml?raw';

const hasSelfClosingTag = mjml => mjml.includes('/>');
const FONT = 'font-family="Arial, Helvetica, sans-serif"';

describe('canonicalizeMjml', () => {
  it('writes every element of a real AI e-mail with an explicit close tag', () => {
    const out = canonicalizeMjml(aiEmail);

    // <br/> lives inside mj-text, which is kept verbatim; nothing else may self-close.
    expect(hasSelfClosingTag(out.split('<br/>').join(''))).toBe(false);
    expect(out).toContain('<mj-spacer height="24px"></mj-spacer>');
  });

  it('resolves the mj-attributes defaults into the body and drops mj-attributes', () => {
    const out = canonicalizeMjml(aiEmail);

    expect(out).not.toContain('mj-attributes');
    expect(out).not.toContain('<mj-all');
    expect(out).toContain('<mj-head>\n\n</mj-head>');
    // tag default + mj-all, explicit color kept
    expect(out).toContain(
      `<mj-text color="#666574" ${FONT} font-size="16px" line-height="1.6" padding="0">Olá {{ nome }},</mj-text>`
    );
    // only attributes mj-image accepts (no font-family)
    expect(out).toContain(
      '<mj-image src="https://example.com/logo.png" alt="Hub2you Insurtech" width="240px" align="center" padding="0"></mj-image>'
    );
    expect(out).toContain(
      `<mj-button align="left" href="https://wa.me/5511999999999?text=Ol%C3%A1%21%20Quero%20informa%C3%A7%C3%B5es%20sobre%20a%20live%20de%20mentoria%20de%20IA%20no%20mercado%20de%20seguros." padding="32px 0 0" ${FONT} background-color="#4B479B" color="#FFFFFF" font-size="16px" font-weight="700" border-radius="8px" inner-padding="14px 36px">`
    );
    expect(out).toContain(
      '<mj-divider border-color="#F1F1FA" border-width="1px" padding="0"></mj-divider>'
    );
    // explicit padding wins over the mj-section default
    expect(out).toContain(
      '<mj-section background-color="#FFFFFF" padding="32px 24px">'
    );
  });

  it('keeps the inner HTML of ending tags verbatim', () => {
    const out = canonicalizeMjml(aiEmail);

    expect(out).toContain(
      `line-height="1.2" padding="16px 0 0" ${FONT} color="#252432">IA no seguro.<br/>Onde está o<br/>próximo negócio?</mj-text>`
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

  it('brings back the defaults of a corrupted head saved by the old editor', () => {
    const corrupted =
      '<mjml><mj-head><mj-attributes>' +
      '<mj-all font-family="Arial"><mj-text color="#111" line-height="1.6">' +
      '<mj-button background-color="#4B479B"><mj-image padding="0"></mj-image></mj-button></mj-text></mj-all>' +
      '</mj-attributes></mj-head>' +
      '<mj-body><mj-section><mj-column><mj-text>Oi</mj-text><mj-button href="https://x.test">Ir</mj-button>' +
      '</mj-column></mj-section></mj-body></mjml>';

    const out = canonicalizeMjml(corrupted);

    expect(out).toBe(
      '<mjml><mj-head></mj-head><mj-body><mj-section><mj-column>' +
        '<mj-text font-family="Arial" color="#111" line-height="1.6">Oi</mj-text>' +
        '<mj-button href="https://x.test" font-family="Arial" background-color="#4B479B">Ir</mj-button>' +
        '</mj-column></mj-section></mj-body></mjml>'
    );
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
