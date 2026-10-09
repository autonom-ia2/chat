import fs from 'node:fs';
import path from 'node:path';
import { formatNumber, toLocaleTag } from '../localeTag';

const campaignOverviewPath = path.join(
  process.cwd(),
  'app/javascript/dashboard/routes/dashboard/campaigns/journey/CampaignOverviewPage.vue'
);

describe('shared localeTag (D9/F0)', () => {
  it('converts app locales to BCP-47 and falls back to en', () => {
    expect(toLocaleTag('pt_BR')).toBe('pt-BR');
    expect(toLocaleTag('zh_TW')).toBe('zh-TW');
    expect(toLocaleTag('en')).toBe('en');
    expect(toLocaleTag(undefined)).toBe('en');
    expect(toLocaleTag(null)).toBe('en');
    expect(() => new Intl.DateTimeFormat(toLocaleTag('pt_BR'))).not.toThrow();
  });

  it('formats counts without passing pt_BR to Intl and maps null to zero', () => {
    expect(formatNumber(12345, 'pt_BR')).toBe('12.345');
    expect(formatNumber(12345, 'en')).toBe('12,345');
    expect(formatNumber(null, 'pt_BR')).toBe('0');
  });

  it('makes CampaignOverviewPage consume the shared locale implementation', () => {
    const source = fs.readFileSync(campaignOverviewPath, 'utf8');

    expect(source).toContain("from 'dashboard/helper/localeTag'");
    expect(source).toContain('toLocaleTag');
    expect(source).not.toContain('const localeTag =');
    expect(source).not.toContain("locale.value.replace('_', '-')");
  });
});
