import { createRouter, createMemoryHistory } from 'vue-router';
import { mount, flushPromises } from '@vue/test-utils';

// #1007 — Resultado route and Gestão de campanhas with CAMPAIGN_JOURNEY_ENABLED on and off (A5).
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
vi.mock('../CampaignResultPage.vue', () => ({ default: vazio }));
vi.mock('../CampaignOverviewPage.vue', () => ({
  __esModule: true,
  default: { name: 'CampaignOverviewPage', render: () => null },
}));
vi.mock('../../../crm/pages/CrmCampaignManagementPage.vue', () => ({
  __esModule: true,
  default: { name: 'CrmCampaignManagementPage', render: () => null },
}));

const { default: campaignsRoutes } = await import('../../campaigns.routes');
const { withCampaignJourneyRedirects } = await import('../journeyRedirects');
const { default: CampaignManagementSwitch } = await import(
  '../CampaignManagementSwitch.vue'
);

const navigate = async (name, params = {}) => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', name: 'home', component: vazio },
      ...withCampaignJourneyRedirects(campaignsRoutes.routes),
    ],
  });
  await router.push({ name, params: { accountId: 1, ...params } });
  return router.currentRoute.value;
};

describe('Resultado and Gestão routes (#1007, A5)', () => {
  afterEach(() => {
    window.globalConfig = {};
  });

  it('flag on: a campaign Resultado opens with the campaign permissions', async () => {
    window.globalConfig = { CAMPAIGN_JOURNEY_ENABLED: 'true' };
    const route = await navigate('campaigns_journey_result', {
      channel: 'email',
      campaignId: 9,
    });

    expect(route.path).toBe('/app/accounts/1/campaigns/results/email/9');
    expect(route.meta.permissions).toEqual([
      'administrator',
      'campaign_view',
      'campaign_manage',
    ]);
  });

  it('flag on: a channel without a result goes back to Campanha', async () => {
    window.globalConfig = { CAMPAIGN_JOURNEY_ENABLED: 'true' };
    const route = await navigate('campaigns_journey_result', {
      channel: 'live_chat',
      campaignId: 4,
    });

    expect(route.name).toBe('campaigns_journey_index');
  });

  it('flag off: the Resultado address falls back to the old campaign pages', async () => {
    window.globalConfig = { CAMPAIGN_JOURNEY_ENABLED: 'false' };
    const route = await navigate('campaigns_journey_result', {
      channel: 'whatsapp_official',
      campaignId: 5,
    });

    expect(route.name).toBe('campaigns_livechat_index');
  });

  it('Gestão de campanhas: overview with the flag on, the old page untouched with it off', async () => {
    window.globalConfig = { CAMPAIGN_JOURNEY_ENABLED: 'true' };
    const on = mount(CampaignManagementSwitch);
    window.globalConfig = { CAMPAIGN_JOURNEY_ENABLED: 'false' };
    const off = mount(CampaignManagementSwitch);
    await flushPromises();

    expect(on.findComponent({ name: 'CampaignOverviewPage' }).exists()).toBe(
      true
    );
    expect(
      on.findComponent({ name: 'CrmCampaignManagementPage' }).exists()
    ).toBe(false);
    expect(
      off.findComponent({ name: 'CrmCampaignManagementPage' }).exists()
    ).toBe(true);
    expect(off.findComponent({ name: 'CampaignOverviewPage' }).exists()).toBe(
      false
    );
  });
});
