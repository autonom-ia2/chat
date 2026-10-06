import registerAutonomiaBlocks, { FOOTER_MJML } from '../blocks';
import STARTER_MJML from '../starterMjml';

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
});
