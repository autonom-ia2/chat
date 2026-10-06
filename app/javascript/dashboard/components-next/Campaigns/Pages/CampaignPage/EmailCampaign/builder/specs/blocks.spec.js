import registerAutonomiaBlocks from '../blocks';

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
});
