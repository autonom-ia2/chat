import { readFileSync, readdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import en from '../i18n/en.json';
import pt_BR from '../i18n/pt_BR.json';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const componentsDir = join(root, 'components');
const vueFiles = [
  'App.vue',
  ...readdirSync(componentsDir)
    .filter(name => name.endsWith('.vue'))
    .map(name => `components/${name}`),
];

const keyPaths = (object, prefix = '') =>
  Object.entries(object).flatMap(([key, value]) =>
    value && typeof value === 'object'
      ? keyPaths(value, `${prefix}${key}.`)
      : [`${prefix}${key}`]
  );

describe('i18n parity', () => {
  it('en and pt_BR have exactly the same keys', () => {
    expect(keyPaths(pt_BR).sort()).toEqual(keyPaths(en).sort());
  });

  it('no message is empty', () => {
    [en, pt_BR].forEach(messages => {
      keyPaths(messages).forEach(path => {
        const value = path
          .split('.')
          .reduce((node, part) => node[part], messages);
        expect(String(value).trim(), path).not.toBe('');
      });
    });
  });
});

describe('components markup rules', () => {
  it.each(vueFiles)('%s has no native <select> and no style=""', file => {
    const source = readFileSync(join(root, file), 'utf8');
    expect(source.includes('<select')).toBe(false);
    expect(source.includes('style=')).toBe(false);
    expect(source.includes(':style')).toBe(false);
    expect(source.includes('<style')).toBe(false);
  });
});
