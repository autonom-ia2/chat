import grapesjs from 'grapesjs';
import mjmlPlugin from 'grapesjs-mjml';
import registerAutonomiaBlocks, { FOOTER_MJML } from '../blocks';
import STARTER_MJML from '../starterMjml';
import { mjmlEditorPlugins, mjmlEditorPluginsOpts } from '../grapesMjmlSetup';

describe('registerAutonomiaBlocks', () => {
  it('registers every block with explicit close tags only', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const added = [];
    registerAutonomiaBlocks({
      Blocks: { add: (id, block) => added.push(block.content) },
    });

    expect(added.length).toBeGreaterThan(0);
    added.forEach(content => {
      // <br/> lives inside mj-text (kept verbatim); no MJML tag may self-close.
      expect(content.split('<br/>').join('')).not.toContain('/>');
    });
    expect(warn).not.toHaveBeenCalled();
    warn.mockRestore();
  });

  it.each([
    ['footer block', () => FOOTER_MJML],
    ['starter e-mail', () => STARTER_MJML],
  ])('keeps the %s brand-neutral and locked with unsubscribe', (_, footer) => {
    const mjml = footer();

    expect(mjml).toContain('footer-locked');
    expect(mjml).toContain('{{ unsubscribe_url }}');
    ['hub2you', 'Autonomia', 'Av. Exemplo'].forEach(brand =>
      expect(mjml).not.toContain(brand)
    );
  });

  it('compiles the starter e-mail and every block with Arial only: no web font import', () => {
    const contents = [];
    registerAutonomiaBlocks({
      Blocks: { add: (id, block) => contents.push(block.content) },
    });
    const container = document.createElement('div');
    document.body.appendChild(container);
    const editor = grapesjs.init({
      container,
      fromElement: false,
      storageManager: false,
      panels: { defaults: [] },
      plugins: mjmlEditorPlugins(mjmlPlugin),
      pluginsOpts: mjmlEditorPluginsOpts(mjmlPlugin),
    });
    const html = [
      STARTER_MJML,
      `<mjml><mj-body>${contents.join('')}</mj-body></mjml>`,
    ].map(mjml => editor.runCommand('mjml-code-to-html', { mjml }).html);
    editor.destroy();
    container.remove();

    html.forEach(out => {
      expect(out).toContain('font-family:Arial, Helvetica, sans-serif');
      expect(out).not.toContain('Ubuntu');
      expect(out).not.toContain('fonts.googleapis.com');
    });
  }, 30000);
});
