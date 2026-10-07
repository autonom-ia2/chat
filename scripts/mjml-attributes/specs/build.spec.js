import fs from 'fs';
import { build, extractAllowedAttributes, OUTPUT } from '../build.mjs';

describe('mjml allowed attributes table', () => {
  it('reads componentName and allowedAttributes, following a known inherited table', () => {
    const source = `
      (0,u.default)(a,"componentName","mj-section"),(0,u.default)(a,"allowedAttributes",{padding:"unit",'background-color':"color"});
      (0,u.default)(b,"componentName","mj-wrapper"),(0,u.default)(b,"allowedAttributes",_objectSpread(_objectSpread({},n.default.allowedAttributes),{},{gap:"unit"}));
    `;

    expect(extractAllowedAttributes(source)).toEqual({
      'mj-section': ['padding', 'background-color'],
      'mj-wrapper': ['padding', 'background-color', 'gap'],
    });
  });

  it('fails on an inherited table it does not know', () => {
    const source =
      '(0,u.default)(c,"componentName","mj-new"),(0,u.default)(c,"allowedAttributes",_objectSpread({},x.allowedAttributes));';

    expect(() => extractAllowedAttributes(source)).toThrow('mj-new');
  });

  it('is up to date with the installed mjml-browser', () => {
    expect(fs.readFileSync(OUTPUT, 'utf8')).toBe(build());
  }, 30000);
});
