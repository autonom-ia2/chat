import { withCampaignJourney } from '../journeySidebar';

const LEGACY = [
  { name: 'Email Campaigns' },
  { name: 'Campaign Links and QR codes' },
  { name: 'Campaign WhatsApp Templates' },
  { name: 'WhatsApp' },
  { name: 'WhatsApp API' },
  { name: 'Live chat' },
  { name: 'SMS' },
  { name: 'Campaign Management' },
];

const options = overrides => ({
  enabled: true,
  audiencesEnabled: true,
  t: key => key,
  accountScopedRoute: name => ({ name }),
  ...overrides,
});

describe('Campanhas menu (PRD D17, A5)', () => {
  it('flag off: returns the current entries untouched', () => {
    expect(withCampaignJourney(options({ enabled: false }), LEGACY)).toBe(
      LEGACY
    );
  });

  it('flag on: Público first, then Campanha, Modelos, Links e QR codes, Gestão', () => {
    const items = withCampaignJourney(options(), LEGACY);

    expect(items.map(item => item.name)).toEqual([
      'Campaign Audiences',
      'Campaign Journey',
      'Campaign WhatsApp Templates',
      'Campaign Links and QR codes',
      'Campaign Management',
    ]);
    expect(items[0].label).toBe('CAMPAIGN_JOURNEY.SIDEBAR.AUDIENCES');
    expect(items[0].to).toEqual({ name: 'campaigns_journey_audiences' });
    expect(items[1].label).toBe('CAMPAIGN_JOURNEY.SIDEBAR.CAMPAIGNS');
    expect(items[1].to).toEqual({ name: 'campaigns_journey_index' });
  });

  it('flag on: Anúncios da Meta stays, right after Links e QR codes, when its own flag shows it (#1068)', () => {
    const withMetaAds = [...LEGACY, { name: 'Campaign Meta Ads' }];
    const names = withCampaignJourney(options(), withMetaAds).map(
      item => item.name
    );

    expect(names).toEqual([
      'Campaign Audiences',
      'Campaign Journey',
      'Campaign WhatsApp Templates',
      'Campaign Links and QR codes',
      'Campaign Meta Ads',
      'Campaign Management',
    ]);
  });

  it('flag on: per-channel entries leave the menu', () => {
    const names = withCampaignJourney(options(), LEGACY).map(item => item.name);

    ['Email Campaigns', 'WhatsApp', 'WhatsApp API', 'Live chat', 'SMS'].forEach(
      name => expect(names).not.toContain(name)
    );
  });

  it('flag on without campaign imports: no Público entry (CAMPAIGN_IMPORT_ENABLED turns it off)', () => {
    const names = withCampaignJourney(
      options({ audiencesEnabled: false }),
      LEGACY
    ).map(item => item.name);

    expect(names[0]).toBe('Campaign Journey');
    expect(names).not.toContain('Campaign Audiences');
  });

  it('flag on keeps hiding entries the seat could not see before', () => {
    const names = withCampaignJourney(options(), [
      { name: 'Campaign WhatsApp Templates' },
    ]).map(item => item.name);

    expect(names).toEqual([
      'Campaign Audiences',
      'Campaign Journey',
      'Campaign WhatsApp Templates',
    ]);
  });

  it('keeps the group lit on the creation pages of the journey', () => {
    const [audiences, campaigns] = withCampaignJourney(options(), LEGACY);

    expect(audiences.activeOn).toContain('campaigns_journey_audience_new');
    expect(campaigns.activeOn).toEqual(
      expect.arrayContaining([
        'campaigns_journey_new',
        'campaigns_journey_live_chat_new',
        'campaigns_journey_live_chat_edit',
      ])
    );
  });
});
