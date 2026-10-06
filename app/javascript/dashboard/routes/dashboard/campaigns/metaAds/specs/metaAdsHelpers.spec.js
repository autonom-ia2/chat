import {
  clockTime,
  currentStep,
  errorMessageKey,
  money,
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
});
