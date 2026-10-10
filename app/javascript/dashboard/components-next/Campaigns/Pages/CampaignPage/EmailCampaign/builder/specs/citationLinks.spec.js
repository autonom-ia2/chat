import cases from './fixtures/citationLinks.json';
import { linkCitations, linkMjmlCitations } from '../citationLinks';
import { prepareMjmlForEditor } from '../editorMjml';

// Same cases as spec/services/email_campaigns/ai/citation_links_spec.rb (#1079).
describe('citationLinks', () => {
  it.each(cases.text)('text: $name', ({ input, expected }) => {
    expect(linkCitations(input)).toBe(expected);
  });

  it.each(cases.mjml)('mjml: $name', ({ input, expected }) => {
    expect(linkMjmlCitations(input)).toBe(expected);
  });

  it('links citations of an old draft when it is loaded into the editor', () => {
    const { mjml } = prepareMjmlForEditor(
      '<mjml><mj-body><mj-section><mj-column><mj-text>' +
        'WhatsApp. ([viagem.hub2you.ai](https://viagem.hub2you.ai/?utm_source=openai))' +
        '</mj-text></mj-column></mj-section></mj-body></mjml>'
    );

    expect(mjml).toContain(
      'WhatsApp. (<a href="https://viagem.hub2you.ai/">viagem.hub2you.ai</a>)'
    );
    expect(mjml).not.toContain('utm_source=openai');
  });
});
