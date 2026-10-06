import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enResult from 'dashboard/i18n/locale/en/resultJourney.json';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';

const api = vi.hoisted(() => ({ getOverview: vi.fn() }));
vi.mock('dashboard/api/campaignResults', () => ({ default: api }));
const replace = vi.fn();
const currentRoute = { query: {} };
vi.mock('vue-router', () => ({
  useRouter: () => ({ replace }),
  useRoute: () => currentRoute,
}));

const { default: CampaignOverviewPage } = await import(
  '../CampaignOverviewPage.vue'
);

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const overview = {
  period: { days: 30 },
  totals: {
    campaigns: 2,
    reached: 1301,
    replied: 17,
    deals: { cards: 9, won: 2 },
    email_health: { hard_bounce_rate: 1.4, complaint_rate: 0 },
  },
  campaigns: [
    {
      channel: 'email',
      id: 9,
      name: 'Novidades de outubro',
      sent_at: '2026-10-09T11:00:00Z',
      sent: 1232,
      delivered: 1206,
      engagement: { kind: 'opened', count: 505, rate: 41 },
      replied: 11,
      reply_rate: 0.9,
      email: { click_rate: 6, hard_bounce_rate: 1.5, unsubscribe_rate: 0.3 },
    },
    {
      channel: 'whatsapp_official',
      id: 5,
      name: 'Renovação auto',
      sent_at: '2026-10-06T12:00:00Z',
      sent: 94,
      delivered: 90,
      engagement: { kind: 'read', count: 69, rate: 73.4 },
      replied: 6,
      reply_rate: 6.4,
      email: null,
    },
  ],
  meta: { total_pages: 1 },
};

const mountPage = () => {
  const store = createStore({
    getters: { getCurrentAccountId: () => 1 },
    modules: {
      inboxes: {
        namespaced: true,
        getters: {
          getInboxes: () => [
            { channel_type: 'Channel::Whatsapp', provider: 'whatsapp_cloud' },
            { channel_type: 'Channel::WebWidget' },
          ],
        },
        actions: { get: () => {} },
      },
      emailSenderIdentities: {
        namespaced: true,
        getters: { getIdentities: () => [{ status: 'verified' }] },
        actions: { get: () => {} },
      },
      globalConfig: {
        namespaced: true,
        getters: {
          get: () => ({ emailCampaignEnabled: true, crmKanbanEnabled: true }),
        },
      },
      accounts: {
        namespaced: true,
        getters: { isFeatureEnabledonAccount: () => () => true },
      },
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...enJourney, ...enResult } },
    missingWarn: false,
    fallbackWarn: false,
  });
  return mount(CampaignOverviewPage, {
    global: {
      plugins: [store, i18n],
      stubs: {
        'router-link': {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });
};

describe('Gestão de campanhas overview (#1007, PRD §6.10, O3)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    currentRoute.query = {};
    api.getOverview.mockResolvedValue({ data: { payload: overview } });
  });

  it('shows the totals of the period, CRM deals and e-mail health', async () => {
    const wrapper = mountPage();
    await flushPromises();

    expect(api.getOverview).toHaveBeenCalledWith({
      days: 30,
      channel: '',
      page: 1,
    });
    const kpis = wrapper
      .findAll('[data-kpi]')
      .map(item => [item.attributes('data-kpi'), item.text()]);
    expect(kpis.map(([key]) => key)).toEqual([
      'campaigns',
      'reached',
      'replied',
      'deals',
      'email_health',
    ]);
    expect(kpis[3][1]).toContain('9');
    expect(kpis[4][1]).toContain('1.4%');
  });

  it('compares the campaigns and each row opens its Resultado', async () => {
    const wrapper = mountPage();
    await flushPromises();

    const table = wrapper.find('[data-overview-rows]');
    expect(table.text()).toContain('41% opened');
    expect(table.text()).toContain('73.4% read');
    const targets = table
      .findAll('a')
      .map(link => JSON.parse(link.attributes('data-to')));
    expect(targets).toEqual([
      {
        name: 'campaigns_journey_result',
        params: { channel: 'email', campaignId: 9 },
      },
      {
        name: 'campaigns_journey_result',
        params: { channel: 'whatsapp_official', campaignId: 5 },
      },
    ]);
    expect(table.text()).not.toContain('Permanent bounce');
  });

  it('offers only connected channels and shows the e-mail columns of the old comparison for e-mail', async () => {
    const wrapper = mountPage();
    await flushPromises();

    expect(
      wrapper
        .findAll('[data-channel]')
        .map(tab => tab.attributes('data-channel'))
    ).toEqual(['all', 'email', 'whatsapp_official']);

    await wrapper.find('[data-channel="email"]').trigger('click');
    await flushPromises();
    expect(api.getOverview).toHaveBeenLastCalledWith({
      days: 30,
      channel: 'email',
      page: 1,
    });
    const table = wrapper.find('[data-overview-rows]').text();
    expect(table).toContain('Clicks');
    expect(table).toContain('Permanent bounce');
    expect(table).toContain('Unsubscribes');
  });

  it('old ?email_campaign links open that e-mail Resultado', async () => {
    currentRoute.query = { email_campaign: '9' };
    mountPage();
    await flushPromises();

    expect(replace).toHaveBeenCalledWith({
      name: 'campaigns_journey_result',
      params: { channel: 'email', campaignId: '9' },
    });
    expect(api.getOverview).not.toHaveBeenCalled();
  });
});
