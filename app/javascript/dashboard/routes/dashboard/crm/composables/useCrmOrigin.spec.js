import {
  buildCrmOriginFromCampaigns,
  hasWebsiteOrigin,
  useCrmOrigin,
} from './useCrmOrigin';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}(${params.name})` : key),
  }),
}));

const landingPageTouch = {
  source: 'meta_paid',
  source_id: 'site:AB3CDE:120211',
  headline: 'LP Seguro Viagem · Viagem EUA Outubro',
  source_url: 'https://placement.com.br/seguro-viagem',
  utm_campaign: 'Viagem EUA Outubro',
  utm_term: 'Conjunto 60+',
  utm_content: 'Video 2',
};

describe('useCrmOrigin', () => {
  const {
    originFromCampaign,
    formatOriginTitle,
    humanizedOriginLabel,
    adHierarchyLines,
  } = useCrmOrigin();

  it('carries campaign, ad set and ad from the UTMs', () => {
    const origin = originFromCampaign(landingPageTouch);

    expect(origin).toMatchObject({
      source: 'meta_paid',
      campaign: 'Viagem EUA Outubro',
      adset: 'Conjunto 60+',
      ad: 'Video 2',
    });
  });

  it('titles a landing page origin with the Meta hierarchy, not the page URL', () => {
    expect(formatOriginTitle(originFromCampaign(landingPageTouch))).toBe(
      'CRM_KANBAN.ORIGIN.CAMPAIGN_PART(Viagem EUA Outubro) · ' +
        'CRM_KANBAN.ORIGIN.ADSET_PART(Conjunto 60+) · ' +
        'CRM_KANBAN.ORIGIN.AD_PART(Video 2)'
    );
  });

  it('only lists the parts the ad actually sent', () => {
    const origin = originFromCampaign({
      ...landingPageTouch,
      utm_term: '',
      utm_content: null,
    });

    expect(formatOriginTitle(origin)).toBe(
      'CRM_KANBAN.ORIGIN.CAMPAIGN_PART(Viagem EUA Outubro)'
    );
  });

  it('keeps the source name when the ad sent no parameters (only fbclid)', () => {
    const origin = originFromCampaign({
      source: 'meta_paid',
      headline: 'LP Seguro Viagem',
      source_url: 'https://placement.com.br/seguro-viagem',
    });

    expect(humanizedOriginLabel(origin)).toBe(
      'CRM_KANBAN.ORIGIN.META_PAID: LP Seguro Viagem'
    );
    expect(formatOriginTitle(origin)).toBe(
      'https://placement.com.br/seguro-viagem'
    );
  });

  it('keeps the CTWA title unchanged', () => {
    const origin = buildCrmOriginFromCampaigns([
      { source: 'meta_ctwa', headline: 'Promo', source_url: '' },
      { source: 'meta_ctwa', headline: 'Outra', source_url: '' },
    ]);

    expect(formatOriginTitle(origin)).toBe(
      'CRM_KANBAN.ORIGIN.META_CTWA: Promo · CRM_KANBAN.ORIGIN.META_CTWA: Outra'
    );
  });

  it('puts each origin on its own line when one has the Meta hierarchy', () => {
    const origin = buildCrmOriginFromCampaigns([
      { source: 'meta_ctwa', headline: 'Promo' },
      landingPageTouch,
    ]);

    expect(formatOriginTitle(origin).split('\n')).toHaveLength(2);
  });

  it('lists campaign, ad set and ad as separate visible lines', () => {
    expect(adHierarchyLines(originFromCampaign(landingPageTouch))).toEqual([
      'CRM_KANBAN.ORIGIN.CAMPAIGN_PART(Viagem EUA Outubro)',
      'CRM_KANBAN.ORIGIN.ADSET_PART(Conjunto 60+)',
      'CRM_KANBAN.ORIGIN.AD_PART(Video 2)',
    ]);
    expect(
      adHierarchyLines(originFromCampaign({ source: 'meta_ctwa' }))
    ).toEqual([]);
  });

  it('flags landing page touches by their site: source id', () => {
    const site = buildCrmOriginFromCampaigns([
      { source: 'meta_ctwa', source_id: 'ad-1' },
      landingPageTouch,
    ]);
    const qr = buildCrmOriginFromCampaigns([
      { source: 'tracked_link', source_id: 'click:K7P2M9QX' },
    ]);

    expect(hasWebsiteOrigin(site)).toBe(true);
    expect(hasWebsiteOrigin(qr)).toBe(false);
    expect(hasWebsiteOrigin(null)).toBe(false);
  });
});
