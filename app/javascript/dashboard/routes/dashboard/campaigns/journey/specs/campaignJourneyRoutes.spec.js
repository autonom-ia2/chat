import { createRouter, createMemoryHistory } from 'vue-router';

const vazio = { render: () => null };
vi.mock('../../pages/CampaignsPageRouteView.vue', () => ({ default: vazio }));
vi.mock('../../pages/LiveChatCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../../pages/SMSCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../../pages/WhatsAppCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../../pages/WhatsAppCampaignAnalyticsPage.vue', () => ({
  default: vazio,
}));
vi.mock('../../pages/WhatsAppApiCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../../pages/EmailSenderPage.vue', () => ({ default: vazio }));
vi.mock('../../pages/EmailCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../../../settings/SettingsWrapper.vue', () => ({ default: vazio }));
vi.mock('../../../settings/templates/Index.vue', () => ({ default: vazio }));
vi.mock('../CampaignJourneyPage.vue', () => ({ default: vazio }));
vi.mock('../AudiencesPage.vue', () => ({ default: vazio }));

const { default: campaignsRoutes } = await import('../../campaigns.routes');

const navigate = async name => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', name: 'home', component: vazio },
      ...campaignsRoutes.routes,
    ],
  });
  await router.push({ name, params: { accountId: 1 } });
  return router.currentRoute.value;
};

describe('campaign journey routes (PRD A5, §8.0)', () => {
  afterEach(() => {
    window.globalConfig = {};
  });

  it('flag off: Campanha falls back to the old campaign pages', async () => {
    window.globalConfig = { CAMPAIGN_JOURNEY_ENABLED: 'false' };
    const route = await navigate('campaigns_journey_index');

    expect(route.name).toBe('campaigns_livechat_index');
  });

  it('flag off: Público falls back to the old campaign pages', async () => {
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'false',
      CAMPAIGN_IMPORT_ENABLED: 'true',
    };
    const route = await navigate('campaigns_journey_audiences');

    expect(route.name).toBe('campaigns_livechat_index');
  });

  it('flag on: both new pages open with the campaign permissions', async () => {
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'true',
      CAMPAIGN_IMPORT_ENABLED: 'true',
    };
    const list = await navigate('campaigns_journey_index');
    const audiences = await navigate('campaigns_journey_audiences');

    expect(list.path).toBe('/app/accounts/1/campaigns/all');
    expect(audiences.path).toBe('/app/accounts/1/campaigns/audiences');
    expect(list.meta.permissions).toEqual([
      'administrator',
      'campaign_view',
      'campaign_manage',
    ]);
  });

  it('flag on but campaign imports off: Público goes to Campanha', async () => {
    window.globalConfig = { CAMPAIGN_JOURNEY_ENABLED: 'true' };
    const route = await navigate('campaigns_journey_audiences');

    expect(route.name).toBe('campaigns_journey_index');
  });

  it('old addresses keep working with the flag on', async () => {
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'true',
      WHATSAPP_API_CAMPAIGNS_ENABLED: 'true',
    };

    expect((await navigate('campaigns_sms_index')).name).toBe(
      'campaigns_sms_index'
    );
    expect((await navigate('campaigns_whatsapp_api_index')).name).toBe(
      'campaigns_whatsapp_api_index'
    );
  });
});
