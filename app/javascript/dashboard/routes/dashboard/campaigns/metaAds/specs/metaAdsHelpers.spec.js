import {
  clockTime,
  currentStep,
  duration,
  errorMessageKey,
  formatFact,
  money,
  thumbClass,
} from '../metaAdsHelpers';

describe('Anúncios da Meta · helpers (#1047)', () => {
  const connected = {
    configured: true,
    verified_at: '2026-10-06T10:00:00Z',
    ad_account: { id: '1', name: 'CA' },
    destinations: { whatsapp: true, site: false },
    sales_signal: { enabled: true },
  };

  it('walks the four steps from what the connection already has', () => {
    expect(currentStep(null)).toBe(1);
    expect(currentStep({ configured: false })).toBe(1);
    expect(currentStep({ ...connected, verified_at: null })).toBe(2);
    expect(
      currentStep({ ...connected, destinations: { whatsapp: false } })
    ).toBe(3);
    expect(
      currentStep({ ...connected, sales_signal: { enabled: false } })
    ).toBe(4);
    expect(currentStep(connected)).toBe(5);
  });

  it('maps API error codes to one sentence, with a generic fallback', () => {
    const error = code => ({ response: { data: { error: code } } });

    expect(errorMessageKey(error('not_your_portfolio'))).toBe(
      'CRM_KANBAN.META_ADS_HUB.ERRORS.NOT_YOUR_PORTFOLIO'
    );
    expect(errorMessageKey(error('platform_access_pending'))).toBe(
      'CRM_KANBAN.META_ADS_HUB.ERRORS.PLATFORM_ACCESS_PENDING'
    );
    expect(errorMessageKey(error('something_new'))).toBe(
      'CRM_KANBAN.META_ADS_HUB.ERRORS.GENERIC'
    );
    expect(errorMessageKey(new Error('network'))).toBe(
      'CRM_KANBAN.META_ADS_HUB.ERRORS.GENERIC'
    );
  });

  it('shows money in reais without cents', () => {
    expect(money(1720.4, 'BRL', 'pt_BR')).toMatch(/1\.720/);
    expect(money(null, 'BRL', 'pt_BR')).toBeNull();
  });

  it('formats the click time with the app locale (pt_BR is not an Intl tag)', () => {
    expect(clockTime('2026-10-06T16:52:00Z', 'pt_BR')).toBeTruthy();
    expect(clockTime(null, 'pt_BR')).toBeNull();
  });

  it('gives each ad the same color in the card and inside, from its id (#1088)', () => {
    expect(thumbClass('120254710067060999')).toBe(
      thumbClass('120254710067060999')
    );
    expect(new Set(['1', '2', '3', '4'].map(thumbClass)).size).toBe(4);
    expect(thumbClass(null)).toContain('from-[');
  });

  // t de mentira: devolve a última parte da chave com o número, para ver a unidade e o arredondamento.
  const t = (key, values = {}) => `${key.split('.').pop()}:${values.n ?? ''}`;

  it('turns seconds into a duration for a layperson, rounding down (#1110)', () => {
    expect(duration(null, t)).toBeNull();
    expect(duration(undefined, t)).toBeNull();
    expect(duration(0, t)).toBe('SECONDS:');
    expect(duration(59, t)).toBe('SECONDS:');
    expect(duration(60, t)).toBe('MINUTES:1');
    expect(duration(359, t)).toBe('MINUTES:5');
    expect(duration(3600, t)).toBe('HOURS:1');
    expect(duration(4800, t)).toBe('HOURS:1 MINUTES:20');
    expect(duration(48 * 3600 - 1, t)).toBe('HOURS:47 MINUTES:59');
    expect(duration(48 * 3600, t)).toBe('DAYS:2');
    expect(duration(5 * 24 * 3600 + 7000, t)).toBe('DAYS:5');
  });

  it('formats each fact of an advice action by its type, like the server (#1110)', () => {
    const options = { t, currency: 'BRL', locale: 'pt_BR' };

    expect(formatFact('value', 1464.64, options)).toMatch(/R\$\s1\.464,64/);
    expect(formatFact('spend', 842, options)).toMatch(/R\$\s842$/);
    expect(formatFact('count', 1234, options)).toBe('1.234');
    expect(formatFact('identified_pct', 0.69, options)).toMatch(/^69\s?%$/);
    expect(formatFact('frequency_7d', 4.6, options)).toBe('4,6');
    expect(formatFact('median_seconds', 1500, options)).toBe('MINUTES:25');
    expect(formatFact('ad_name', 'Promo 10/10', options)).toBe('Promo 10/10');
    expect(formatFact('median_seconds', null, options)).toBeNull();
    expect(formatFact('no_such_fact', 3, options)).toBeNull();
  });
});
