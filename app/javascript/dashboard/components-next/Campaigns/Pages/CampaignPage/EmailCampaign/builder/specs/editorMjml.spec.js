import grapesjs from 'grapesjs';
import mjmlPlugin from 'grapesjs-mjml';
import { prepareMjmlForEditor, restoreHeldHead } from '../editorMjml';

const SOURCE =
  '<mjml><mj-head><mj-title>Titulo</mj-title><mj-preview>Previa da caixa</mj-preview>' +
  '<mj-style>.x { color: red }</mj-style><mj-attributes><mj-text color="#4B479B"/></mj-attributes></mj-head>' +
  '<mj-body><mj-section><mj-column><mj-text>Oi</mj-text></mj-column></mj-section></mj-body></mjml>';

const typesIn = (component, acc = []) => {
  acc.push(component.get('type'));
  component.components().forEach(child => typesIn(child, acc));
  return acc;
};

describe('editorMjml', () => {
  it('holds mj-title and mj-preview aside from the canvas', () => {
    const { mjml, held } = prepareMjmlForEditor(SOURCE);

    expect(mjml).toBe(
      '<mjml><mj-head><mj-style>.x { color: red }</mj-style></mj-head>' +
        '<mj-body><mj-section><mj-column><mj-text color="#4B479B">Oi</mj-text></mj-column></mj-section></mj-body></mjml>'
    );
    expect(held).toBe(
      '<mj-title>Titulo</mj-title><mj-preview>Previa da caixa</mj-preview>'
    );
  });

  it('gives the held head back on export, with or without an exported mj-head', () => {
    const held = '<mj-title>T</mj-title>';

    expect(
      restoreHeldHead(
        '<mjml><mj-head></mj-head><mj-body></mj-body></mjml>',
        held
      )
    ).toBe(
      '<mjml><mj-head><mj-title>T</mj-title></mj-head><mj-body></mj-body></mjml>'
    );
    expect(restoreHeldHead('<mjml><mj-body></mj-body></mjml>', held)).toBe(
      '<mjml><mj-head><mj-title>T</mj-title></mj-head><mj-body></mj-body></mjml>'
    );
    expect(restoreHeldHead('<mjml></mjml>', '')).toBe('<mjml></mjml>');
  });

  it('holds every brand font (mj-font) aside and gives them back on export (#1076)', () => {
    const source =
      '<mjml><mj-head><mj-font name="Roboto" href="https://fonts.googleapis.com/css2?family=Roboto"></mj-font>' +
      '<mj-font name="Inter" href="https://fonts.googleapis.com/css2?family=Inter"></mj-font></mj-head>' +
      '<mj-body></mj-body></mjml>';

    const { mjml, held } = prepareMjmlForEditor(source);

    expect(mjml).not.toContain('mj-font');
    const restored = restoreHeldHead(mjml, held);
    expect(restored).toContain('<mj-font name="Roboto"');
    expect(restored).toContain('<mj-font name="Inter"');
  });

  it('keeps the canvas free of head blocks and the sent HTML with title and preview', () => {
    const container = document.createElement('div');
    document.body.appendChild(container);
    const editor = grapesjs.init({
      container,
      fromElement: false,
      storageManager: false,
      panels: { defaults: [] },
      plugins: [mjmlPlugin],
      pluginsOpts: { [mjmlPlugin]: { useCustomTheme: false, blocks: [] } },
    });
    const { mjml, held } = prepareMjmlForEditor(SOURCE);
    editor.setComponents(mjml);
    const head = editor
      .getWrapper()
      .components()
      .at(0)
      .components()
      .find(c => c.get('type') === 'mj-head');
    const saved = restoreHeldHead(editor.runCommand('mjml-code'), held);
    const html = editor.runCommand('mjml-code-to-html', { mjml: saved }).html;
    editor.destroy();
    container.remove();

    expect(typesIn(head)).not.toContain('mj-title');
    expect(typesIn(head)).not.toContain('mj-preview');
    expect(saved).toContain(
      '<mj-title>Titulo</mj-title><mj-preview>Previa da caixa</mj-preview>'
    );
    expect(html).toContain('<title>Titulo</title>');
    expect(html).toContain('Previa da caixa');
  }, 30000);
  it('keeps the held title and preview when the export has no <mjml> root', () => {
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const out = restoreHeldHead(
      '<mj-body></mj-body>',
      '<mj-title>Titulo</mj-title>'
    );

    expect(out).toBe(
      '<mjml><mj-head><mj-title>Titulo</mj-title></mj-head><mj-body></mj-body></mjml>'
    );
    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });
});
