import fs from 'node:fs';
import path from 'node:path';

// G2 (no native <select>, no old ComboBox), F4 (no technical label), D3 (no batch) and B1a
// (no "Jev", "IA" or model name) over every screen and text of the new journey (#993).
const root = process.cwd();
const dirs = [
  'app/javascript/dashboard/components-next/CampaignJourney',
  'app/javascript/dashboard/routes/dashboard/campaigns/journey',
];
const vueFiles = dirs.flatMap(dir =>
  fs
    .readdirSync(path.join(root, dir))
    .filter(file => file.endsWith('.vue'))
    .map(file => path.join(root, dir, file))
);

const strings = value =>
  typeof value === 'string'
    ? [value]
    : Object.values(value).flatMap(item => strings(item));

const catalogs = ['en', 'pt_BR'].map(locale =>
  JSON.parse(
    fs.readFileSync(
      path.join(
        root,
        `app/javascript/dashboard/i18n/locale/${locale}/campaignJourney.json`
      ),
      'utf8'
    )
  )
);
const texts = catalogs.flatMap(catalog => strings(catalog));
const words = text =>
  text
    .split(' ')
    .map(word => word.toLowerCase())
    .map(word =>
      word
        .split('')
        .filter(char => char.toLowerCase() !== char.toUpperCase())
        .join('')
    );

describe('campaign journey acceptance (#993)', () => {
  it('G2: no native select nor the old ComboBox in the new screens', () => {
    expect(vueFiles.length).toBeGreaterThan(10);
    vueFiles.forEach(file => {
      const source = fs.readFileSync(file, 'utf8');
      expect(source.includes('<select'), file).toBe(false);
      expect(source.includes('combobox/ComboBox'), file).toBe(false);
      expect(source.includes('TagMultiSelectComboBox'), file).toBe(false);
    });
  });

  it('B1a, D3, F4: texts never mention the engine, AI, batches or label names', () => {
    const forbidden = ['jev', 'ia', 'ai', 'lote', 'lotes', 'batch', 'batches'];
    texts.forEach(text => {
      const found = words(text).filter(word => forbidden.includes(word));
      expect(found, text).toEqual([]);
      expect(text.includes('campanha_'), text).toBe(false);
    });
  });
});
