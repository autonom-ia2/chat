import { toLocaleTag } from '../localeTag';
import { formatInZone } from '../scheduleTime';

describe('toLocaleTag (pt_BR → pt-BR)', () => {
  it('turns the app locale into a BCP-47 tag Intl accepts', () => {
    expect(toLocaleTag('pt_BR')).toBe('pt-BR');
    expect(toLocaleTag('zh_TW')).toBe('zh-TW');
    expect(toLocaleTag('en')).toBe('en');
    expect(toLocaleTag(undefined)).toBe('en');
    expect(() => new Intl.DateTimeFormat(toLocaleTag('pt_BR'))).not.toThrow();
  });

  it('formatInZone accepts the app locale as is', () => {
    expect(() =>
      formatInZone('2026-10-06T12:00:00.000Z', 'America/Sao_Paulo', 'pt_BR')
    ).not.toThrow();
  });
});
