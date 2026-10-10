import fs from 'fs';
import path from 'path';

// Regra do Rodrigo (18/09/2026): nada de <select> nativo nem de componente que
// renderiza um por baixo. Também sem CSS próprio nem style="" (só Tailwind).
const ROOT = path.resolve(__dirname, '..');
const FORBIDDEN_IMPORTS = [
  'Form/Select.vue',
  'components-next/select/Select.vue',
];

const vueFiles = dir =>
  fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return vueFiles(full);
    return entry.name.endsWith('.vue') ? [full] : [];
  });

const files = vueFiles(ROOT);

describe('CRM › Agendamento sem <select> nativo', () => {
  it('encontra os componentes da tela', () => {
    expect(files.length).toBeGreaterThan(10);
  });

  it.each(files.map(file => [path.relative(ROOT, file), file]))(
    '%s não usa <select>, Select legado, <style> nem style=""',
    (_name, file) => {
      const source = fs.readFileSync(file, 'utf8').toLowerCase();
      expect(source.includes('<select')).toBe(false);
      FORBIDDEN_IMPORTS.forEach(item => {
        expect(source.includes(item.toLowerCase())).toBe(false);
      });
      expect(source.includes('<style')).toBe(false);
      expect(source.includes(' style="')).toBe(false);
      expect(source.includes(':style=')).toBe(false);
    }
  );
});
