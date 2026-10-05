import fs from 'node:fs';
import path from 'node:path';

// G2 (no native <select>, no old ComboBox) and B1a (no engine, AI or batch words) over the
// result and Gestão screens of #1007 and their texts.
const root = process.cwd();
const files = [
  ...fs
    .readdirSync(
      path.join(root, 'app/javascript/dashboard/components-next/CampaignResult')
    )
    .filter(file => file.endsWith('.vue'))
    .map(
      file => `app/javascript/dashboard/components-next/CampaignResult/${file}`
    ),
  'app/javascript/dashboard/routes/dashboard/campaigns/journey/CampaignResultPage.vue',
  'app/javascript/dashboard/routes/dashboard/campaigns/journey/CampaignOverviewPage.vue',
  'app/javascript/dashboard/routes/dashboard/campaigns/journey/CampaignManagementSwitch.vue',
].map(file => path.join(root, file));

const strings = value =>
  typeof value === 'string'
    ? [value]
    : Object.values(value).flatMap(item => strings(item));
const texts = ['en', 'pt_BR'].flatMap(locale =>
  strings(
    JSON.parse(
      fs.readFileSync(
        path.join(
          root,
          `app/javascript/dashboard/i18n/locale/${locale}/resultJourney.json`
        ),
        'utf8'
      )
    )
  )
);
const letters = word =>
  word
    .split('')
    .filter(char => char.toLowerCase() !== char.toUpperCase())
    .join('')
    .toLowerCase();

describe('campaign result acceptance (#1007)', () => {
  it('G2: no native select nor the old ComboBox', () => {
    expect(files.length).toBeGreaterThan(8);
    files.forEach(file => {
      const source = fs.readFileSync(file, 'utf8');
      expect(source.includes('<select'), file).toBe(false);
      expect(source.includes('combobox/ComboBox'), file).toBe(false);
    });
  });

  it('B1a, D3: texts never mention the engine, AI or batches', () => {
    const forbidden = ['jev', 'ia', 'ai', 'lote', 'lotes', 'batch', 'batches'];
    texts.forEach(text => {
      const found = text
        .split(' ')
        .map(letters)
        .filter(word => forbidden.includes(word));
      expect(found, text).toEqual([]);
    });
  });
});
