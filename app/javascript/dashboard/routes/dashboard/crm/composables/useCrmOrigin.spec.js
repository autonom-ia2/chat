import {
  buildCrmOriginFromCampaigns,
  isMetaObjectId,
  safeSourceUrl,
  shortMetaId,
  useCrmOrigin,
} from './useCrmOrigin';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}(${params.name ?? params.id})` : key),
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
    originLabelOverHierarchy,
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

  it('leaves the campaign out of the label that sits over its own line', () => {
    const origin = originFromCampaign(landingPageTouch);

    expect(humanizedOriginLabel(origin)).toBe(
      'CRM_KANBAN.ORIGIN.META_PAID: LP Seguro Viagem · Viagem EUA Outubro'
    );
    expect(originLabelOverHierarchy(origin)).toBe(
      'CRM_KANBAN.ORIGIN.META_PAID: LP Seguro Viagem'
    );
  });

  it('keeps the label whole when there is no campaign line to repeat it', () => {
    const withoutUtm = originFromCampaign({
      ...landingPageTouch,
      utm_campaign: '',
    });
    const otherHeadline = originFromCampaign({
      ...landingPageTouch,
      headline: 'Seguro Viagem Europa',
    });

    expect(originLabelOverHierarchy(withoutUtm)).toBe(
      'CRM_KANBAN.ORIGIN.META_PAID: LP Seguro Viagem · Viagem EUA Outubro'
    );
    expect(originLabelOverHierarchy(otherHeadline)).toBe(
      'CRM_KANBAN.ORIGIN.META_PAID: Seguro Viagem Europa'
    );
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
});

describe('useCrmOrigin · Meta names (#1034)', () => {
  const { originFromCampaign, hierarchyItems, adHierarchyLines, touchDate } =
    useCrmOrigin();

  const idTouch = {
    source: 'meta_paid',
    headline: 'LP Seguro Viagem · 120254710067060416',
    utm_campaign: '120254710067060416',
    utm_term: '120254710067060417',
    utm_content: '120254710067060418',
  };

  it('tells a Meta ID from a name without a regular expression', () => {
    expect(isMetaObjectId('120254710067060416')).toBe(true);
    expect(isMetaObjectId('123456')).toBe(true);
    expect(isMetaObjectId('12345')).toBe(false);
    expect(isMetaObjectId('1'.repeat(31))).toBe(false);
    expect(isMetaObjectId('Viagem 2026')).toBe(false);
    expect(isMetaObjectId('12025471006706041a')).toBe(false);
    expect(isMetaObjectId('')).toBe(false);
    expect(isMetaObjectId(null)).toBe(false);
  });

  it('shortens a long ID and keeps short ones whole', () => {
    expect(shortMetaId('120254710067060416')).toBe('1202…0416');
    expect(shortMetaId('123456789')).toBe('123456789');
  });

  it('shows "ID 1202…0416" with the full ID in the title', () => {
    expect(hierarchyItems(originFromCampaign(idTouch))).toEqual([
      expect.objectContaining({
        field: 'campaign',
        level: 'CRM_KANBAN.ORIGIN.LEVEL.CAMPAIGN',
        value: 'CRM_KANBAN.ORIGIN.META_ID(1202…0416)',
        title: '120254710067060416',
      }),
      expect.objectContaining({ field: 'adset', title: '120254710067060417' }),
      expect.objectContaining({ field: 'ad', title: '120254710067060418' }),
    ]);
  });

  it('prefers the resolved names over the UTMs', () => {
    const origin = originFromCampaign({
      ...idTouch,
      campaign_name: 'Viagem EUA Outubro',
      adset_name: 'Conjunto 60+',
      ad_name: 'Video 2',
    });

    expect(adHierarchyLines(origin)).toEqual([
      'CRM_KANBAN.ORIGIN.CAMPAIGN_PART(Viagem EUA Outubro)',
      'CRM_KANBAN.ORIGIN.ADSET_PART(Conjunto 60+)',
      'CRM_KANBAN.ORIGIN.AD_PART(Video 2)',
    ]);
  });

  it('drops the raw ID suffix of the headline once the campaign has its name', () => {
    const origin = originFromCampaign({
      ...idTouch,
      campaign_name: 'Viagem EUA Outubro',
    });

    expect(useCrmOrigin().originLabelOverHierarchy(origin)).toBe(
      'CRM_KANBAN.ORIGIN.META_PAID: LP Seguro Viagem'
    );
  });

  it('uses the CTWA headline as the ad until the ad name is resolved', () => {
    const unresolved = originFromCampaign({
      source: 'meta_ctwa',
      headline: 'Cotação Rápida',
    });
    const resolved = originFromCampaign({
      source: 'meta_ctwa',
      headline: 'Cotação Rápida',
      ad_name: 'Cotação · vídeo',
      campaign_name: 'Julho',
    });

    expect(adHierarchyLines(unresolved)).toEqual([
      'CRM_KANBAN.ORIGIN.AD_PART(Cotação Rápida)',
    ]);
    expect(useCrmOrigin().originLabelOverHierarchy(unresolved)).toBe(
      'CRM_KANBAN.ORIGIN.META_CTWA'
    );
    expect(adHierarchyLines(resolved)).toEqual([
      'CRM_KANBAN.ORIGIN.CAMPAIGN_PART(Julho)',
      'CRM_KANBAN.ORIGIN.AD_PART(Cotação · vídeo)',
    ]);
  });

  it('formats the touch date and ignores a missing or broken one', () => {
    const date = touchDate(
      originFromCampaign({ ...idTouch, touched_at: '2026-07-10T14:32:00Z' })
    );

    expect(date.iso).toBe('2026-07-10T14:32:00.000Z');
    expect(date.label).toContain('10');
    expect(touchDate(originFromCampaign(idTouch))).toBeNull();
    expect(
      touchDate(originFromCampaign({ ...idTouch, touched_at: 'ontem' }))
    ).toBeNull();
  });
});

// Built in two parts: the lint forbids a literal script URL, even in a test.
const SCRIPT_SCHEME = ['java', 'script:'].join('');

describe('safeSourceUrl', () => {
  it('keeps http and https addresses', () => {
    expect(safeSourceUrl(' https://www.instagram.com/p/x/ ')).toBe(
      'https://www.instagram.com/p/x/'
    );
    expect(safeSourceUrl('http://placement.com.br/lp')).toBe(
      'http://placement.com.br/lp'
    );
  });

  it('drops any other scheme and anything that is not a URL', () => {
    expect(safeSourceUrl(`${SCRIPT_SCHEME}//evil.com/%0aalert(1)`)).toBe('');
    expect(
      safeSourceUrl(`${SCRIPT_SCHEME.toUpperCase()}//instagram.com/%0aalert(1)`)
    ).toBe('');
    expect(safeSourceUrl('data:text/html,hi')).toBe('');
    expect(safeSourceUrl('instagram.com/p/x')).toBe('');
    expect(safeSourceUrl(null)).toBe('');
  });
});
