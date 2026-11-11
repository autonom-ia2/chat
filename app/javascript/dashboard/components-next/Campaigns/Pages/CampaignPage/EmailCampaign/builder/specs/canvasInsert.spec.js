import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { componentFromElement } from '../canvasInsert';

// componentFromElement relies on the view GrapesJS stores on each canvas element (el.__gjsv). It is
// not public API: this spec breaks when an upgrade of GrapesJS drops it (#2908, risk accepted).
describe('componentFromElement', () => {
  it('finds the component of the element or of its closest rendered ancestor', () => {
    const model = { id: 'texto' };
    const block = document.createElement('div');
    const inner = document.createElement('span');
    block.appendChild(inner);
    // eslint-disable-next-line no-underscore-dangle
    block.__gjsv = { model };

    expect(componentFromElement(inner)).toBe(model);
    expect(componentFromElement(document.createElement('p'))).toBeNull();
  });

  it('matches the installed GrapesJS: canvas elements still carry their view in __gjsv', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'node_modules/grapesjs/dist/grapes.mjs'),
      'utf8'
    );

    expect(source).toContain('el.__gjsv = view');
  });
});
