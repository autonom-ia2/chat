import {
  formatValueByCurrency,
  normalizeOrigin,
  parseAllowedOrigins,
  signalStatus,
  websiteReadiness,
} from '../trackedLinkWebsite';

describe('normalizeOrigin', () => {
  it.each([
    ['https://placement.com.br', 'https://placement.com.br'],
    ['https://Placement.com.br/seguro-viagem?x=1', 'https://placement.com.br'],
    ['placement.com.br/', 'https://placement.com.br'],
    [
      '  https://www.placement.com.br:8443/  ',
      'https://www.placement.com.br:8443',
    ],
    ['http://localhost:3000', 'http://localhost:3000'],
    // People type or copy http:// out of habit; the live site answers on https.
    ['http://placement.com.br/seguro-viagem', 'https://placement.com.br'],
  ])('turns %s into %s', (input, expected) => {
    expect(normalizeOrigin(input)).toBe(expected);
  });

  it.each([
    'ftp://placement.com.br',
    'https://placement',
    'https://user:pass@placement.com.br',
    'not a site',
    '',
  ])('refuses %s', input => {
    expect(normalizeOrigin(input)).toBeNull();
  });
});

describe('parseAllowedOrigins', () => {
  it('reads one address per line and drops repeats', () => {
    const parsed = parseAllowedOrigins(
      'https://placement.com.br\n\nhttps://placement.com.br/lp\r\nhttps://outra.com.br'
    );

    expect(parsed.origins).toEqual([
      'https://placement.com.br',
      'https://outra.com.br',
    ]);
    expect(parsed.isValid).toBe(true);
  });

  it('flags invalid lines, too many origins and an empty list', () => {
    expect(parseAllowedOrigins('minha página').invalid).toEqual([
      'minha página',
    ]);
    const six = Array.from({ length: 6 }, (_, i) => `https://s${i}.com`);
    expect(parseAllowedOrigins(six.join('\n'))).toMatchObject({
      isTooMany: true,
      isValid: false,
    });
    expect(parseAllowedOrigins('  \n ')).toMatchObject({
      isEmpty: true,
      isValid: false,
    });
  });
});

describe('signalStatus', () => {
  const now = new Date('2026-10-05T12:00:00Z').getTime();

  it('is recent under 24 hours, stale after and never without a signal', () => {
    expect(signalStatus('2026-10-05T11:55:00Z', now)).toBe('recent');
    expect(signalStatus('2026-10-04T11:59:00Z', now)).toBe('stale');
    expect(signalStatus(null, now)).toBe('never');
    expect(signalStatus('garbage', now)).toBe('never');
  });
});

describe('websiteReadiness', () => {
  const now = new Date('2026-10-05T12:00:00Z').getTime();
  const origins = ['https://placement.com.br'];

  it('needs origins before anything else', () => {
    expect(
      websiteReadiness(
        { allowed_origins: [], last_signal_at: '2026-10-05T11:55:00Z' },
        now
      )
    ).toBe('needs_origins');
    expect(websiteReadiness({}, now)).toBe('needs_origins');
  });

  it('waits without a signal and is ready once one arrived', () => {
    expect(
      websiteReadiness({ allowed_origins: origins, last_signal_at: null }, now)
    ).toBe('waiting');
    expect(
      websiteReadiness(
        { allowed_origins: origins, last_signal_at: '2026-10-05T11:55:00Z' },
        now
      )
    ).toBe('ready');
    expect(
      websiteReadiness(
        { allowed_origins: origins, last_signal_at: '2026-09-01T00:00:00Z' },
        now
      )
    ).toBe('ready');
  });
});

describe('formatValueByCurrency', () => {
  it('formats cents per currency and skips zero', () => {
    const text = formatValueByCurrency({ BRL: 37780, USD: 0 }, 'pt_BR');
    expect(text).toContain('377,80');
    expect(text).not.toContain('US$');
    expect(formatValueByCurrency({}, 'pt_BR')).toBe('');
  });
});
