import fs from 'node:fs';
import path from 'node:path';
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
vi.mock('../NewAudiencePage.vue', () => ({ default: vazio }));
vi.mock('../NewCampaignPage.vue', () => ({ default: vazio }));
vi.mock('../../../contacts/pages/ContactsIndex.vue', () => ({
  default: vazio,
}));
vi.mock('../../../contacts/pages/ContactManageView.vue', () => ({
  default: vazio,
}));
vi.mock('../../../contacts/pages/CampaignImportHistory.vue', () => ({
  default: vazio,
}));

const { default: campaignsRoutes } = await import('../../campaigns.routes');
const { routes: contactRoutes } = await import('../../../contacts/routes');
const { withCampaignJourneyRedirects } = await import('../journeyRedirects');

// Same wiring as dashboard.routes.js.
const navigate = async (name, query = {}) => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', name: 'home', component: vazio },
      ...withCampaignJourneyRedirects(contactRoutes),
      ...withCampaignJourneyRedirects(campaignsRoutes.routes),
    ],
  });
  await router.push({ name, params: { accountId: 1 }, query });
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

  it('A3: with the flag on, old channel lists open Campanha filtered by channel', async () => {
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'true',
      WHATSAPP_API_CAMPAIGNS_ENABLED: 'true',
      EMAIL_CAMPAIGN_ENABLED: 'true',
      CRM_KANBAN_ENABLED: 'true',
    };
    const cases = {
      campaigns_livechat_index: 'live_chat',
      campaigns_sms_index: 'sms',
      campaigns_whatsapp_index: 'whatsapp_official',
      campaigns_whatsapp_api_index: 'whatsapp_api',
      campaigns_email_index: 'email',
      campaigns_ongoing_index: 'live_chat',
    };
    const landed = [];
    // eslint-disable-next-line no-restricted-syntax
    for (const name of Object.keys(cases)) {
      // eslint-disable-next-line no-await-in-loop
      const route = await navigate(name);
      landed.push([name, route.name, route.query.channel]);
    }

    expect(landed).toEqual(
      Object.entries(cases).map(([name, channel]) => [
        name,
        'campaigns_journey_index',
        channel,
      ])
    );
    // The first navigation compiles the lazy route modules.
  }, 30000);

  it('A3: the old import history opens Público', async () => {
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'true',
      CAMPAIGN_IMPORT_ENABLED: 'true',
    };
    expect((await navigate('contacts_campaign_imports')).name).toBe(
      'campaigns_journey_audiences'
    );
  });

  it('A3: a visit from the journey list itself still opens the old page', async () => {
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'true',
      CAMPAIGN_IMPORT_ENABLED: 'true',
    };
    expect((await navigate('campaigns_sms_index', { legacy: '1' })).name).toBe(
      'campaigns_sms_index'
    );
    expect(
      (await navigate('contacts_campaign_imports', { legacy: '1' })).name
    ).toBe('contacts_campaign_imports');
  });

  it('A5: with the flag off, old addresses open the old pages', async () => {
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'false',
      CAMPAIGN_IMPORT_ENABLED: 'true',
    };
    expect((await navigate('campaigns_sms_index')).name).toBe(
      'campaigns_sms_index'
    );
    expect((await navigate('contacts_campaign_imports')).name).toBe(
      'contacts_campaign_imports'
    );
  });

  it('A4: Novo público and Nova campanha need campaign_manage', async () => {
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'true',
      CAMPAIGN_IMPORT_ENABLED: 'true',
    };
    const audience = await navigate('campaigns_journey_audience_new');
    const campaign = await navigate('campaigns_journey_new');

    expect(audience.path).toBe('/app/accounts/1/campaigns/audiences/new');
    expect(campaign.path).toBe('/app/accounts/1/campaigns/new');
    expect(audience.meta.permissions).toEqual([
      'administrator',
      'campaign_manage',
    ]);
    expect(campaign.meta.permissions).toEqual([
      'administrator',
      'campaign_manage',
    ]);
  });

  it('the app wires the redirects into the dashboard routes', () => {
    const source = fs.readFileSync(
      path.join(
        process.cwd(),
        'app/javascript/dashboard/routes/dashboard/dashboard.routes.js'
      ),
      'utf8'
    );
    expect(source).toContain('...withCampaignJourneyRedirects(contactRoutes)');
    expect(source).toContain(
      '...withCampaignJourneyRedirects(campaignsRoutes.routes)'
    );
  });
});
