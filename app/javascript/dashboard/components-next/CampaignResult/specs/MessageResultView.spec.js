import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enResult from 'dashboard/i18n/locale/en/resultJourney.json';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';

const api = vi.hoisted(() => ({
  getResult: vi.fn(),
  getRecipients: vi.fn(),
  exportResult: vi.fn(),
}));
vi.mock('dashboard/api/campaignResults', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock(
  'dashboard/components-next/Campaigns/EmailProtection/presentation',
  () => ({
    downloadCsv: vi.fn(),
  })
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryBreakdown.vue',
  () => ({ default: { name: 'CampaignDeliveryBreakdown', render: () => null } })
);

const { default: MessageResultView } = await import('../MessageResultView.vue');

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const result = (overrides = {}) => ({
  campaign: {
    id: 5,
    channel: 'whatsapp_official',
    name: 'Renovação auto',
    status: 'completed',
    processing: false,
    inbox: { id: 1, name: 'Oficial' },
    scheduled_at: '2026-10-06T12:00:00Z',
    template_name: 'renovacao_auto_v2',
    audience: { id: 3, name: 'Auto vencendo' },
    ...overrides.campaign,
  },
  totals: {
    audience: 4,
    sent: 2,
    delivered: 2,
    read: 1,
    failed: 1,
    skipped: 1,
    queued: 0,
    replied: 1,
    ...overrides.totals,
  },
  filters: overrides.filters || [
    'queued',
    'sent',
    'delivered',
    'read',
    'failed',
    'skipped',
    'replied',
  ],
  crm: { source_id: 'campaign:whatsapp:11', enabled: true },
});

const rows = [
  {
    id: 1,
    contact: { id: 1, name: 'Ana', phone_number: '+55119****4321' },
    status: 'read',
    replied: true,
    message_content: 'Olá Ana',
    conversation_display_id: 42,
  },
  {
    id: 2,
    contact: { id: 2, name: 'Caio', phone_number: '+55319****4323' },
    status: 'failed',
    error_code: '131026',
    error_title: 'Número sem WhatsApp',
    conversation_display_id: null,
  },
];

const mountView = ({ channel = 'whatsapp_official', customRole } = {}) => {
  const dispatched = [];
  const store = createStore({
    getters: {
      getCurrentUser: () => ({
        accounts: [{ id: 1, permissions: customRole || [] }],
      }),
      getCurrentCustomRoleId: () => (customRole ? 7 : null),
      getCurrentAccountId: () => 1,
    },
    modules: {
      whatsappApiCampaigns: {
        namespaced: true,
        actions: {
          pause: (_, id) => dispatched.push(['pause', id]),
        },
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
  const wrapper = mount(MessageResultView, {
    props: { channel, campaignId: '5' },
    global: {
      plugins: [store, i18n],
      stubs: {
        'router-link': {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
        Dialog: { template: '<div><slot /></div>' },
      },
    },
  });
  return { wrapper, dispatched };
};

describe('message campaign result (#1007, PRD §6.5, O2)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.getResult.mockResolvedValue({ data: { payload: result() } });
    api.getRecipients.mockResolvedValue({
      data: { payload: { rows, meta: { total_pages: 1 } } },
    });
    api.exportResult.mockResolvedValue({ data: new Blob(['csv']) });
  });

  it('shows every number of WhatsApp Oficial and the E1 sum', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    const kpis = wrapper
      .findAll('[data-kpi]')
      .map(item => [item.attributes('data-kpi'), item.text()]);
    expect(kpis.map(([key]) => key)).toEqual([
      'audience',
      'sent',
      'delivered',
      'read',
      'replied',
      'failed',
      'skipped',
    ]);
    expect(kpis[4][1]).toContain('marked in the CRM');
    expect(wrapper.find('[data-balance]').text()).toBe(
      'Sent 2 + Failed 1 + Skipped 1 + Queued 0 = Audience 4'
    );
    expect(wrapper.find('[data-balance]').classes()).not.toContain(
      'text-n-ruby-11'
    );
  });

  it('WhatsApp API has no Entregues nor Lidas', async () => {
    api.getResult.mockResolvedValue({
      data: {
        payload: result({
          campaign: { channel: 'whatsapp_api', status: 'running' },
          filters: ['queued', 'sent', 'failed', 'skipped', 'replied'],
        }),
      },
    });
    const { wrapper } = mountView({ channel: 'whatsapp_api' });
    await flushPromises();

    const keys = wrapper
      .findAll('[data-kpi]')
      .map(item => item.attributes('data-kpi'));
    expect(keys).toEqual(['audience', 'sent', 'replied', 'failed', 'skipped']);
    expect(wrapper.find('[data-tab="read"]').exists()).toBe(false);
  });

  it('"Ver no CRM" opens the Kanban filtered by the campaign mark (K6)', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    expect(wrapper.find('[data-crm-band]').text()).toContain(
      'Campaign: Renovação auto'
    );
    expect(
      JSON.parse(wrapper.find('[data-crm-link]').attributes('data-to'))
    ).toEqual({
      name: 'crm_kanban_index',
      query: { campaign_source_ids: 'campaign:whatsapp:11' },
    });
  });

  it('opens the conversation of who replied and shows code and reason (E3)', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    const links = wrapper.findAll('[data-open-conversation]');
    expect(links.length).toBeGreaterThan(0);
    expect(JSON.parse(links[0].attributes('data-to'))).toEqual({
      name: 'inbox_conversation',
      params: { conversation_id: 42 },
    });
    const table = wrapper.find('[data-people-rows]').text();
    expect(table).toContain('Número sem WhatsApp');
    expect(table).toContain('code 131026');
    expect(table).toContain('Replied');
  });

  it('downloads the result of the chosen tab (E4)', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    await wrapper.find('[data-tab="failed"]').trigger('click');
    await flushPromises();
    expect(api.getRecipients).toHaveBeenLastCalledWith(
      'whatsapp_official',
      '5',
      { status: 'failed', page: 1 }
    );
    await wrapper.find('[data-export]').trigger('click');
    await flushPromises();

    expect(api.exportResult).toHaveBeenCalledWith('whatsapp_official', '5', {
      status: 'failed',
    });
  });

  it('A4: campaign_view sees the result but no download nor actions', async () => {
    api.getResult.mockResolvedValue({
      data: {
        payload: result({
          campaign: { channel: 'whatsapp_api', status: 'running' },
        }),
      },
    });
    const viewer = mountView({
      channel: 'whatsapp_api',
      customRole: ['campaign_view'],
    }).wrapper;
    const manager = mountView({ channel: 'whatsapp_api' }).wrapper;
    await flushPromises();

    expect(viewer.find('[data-kpi="sent"]').exists()).toBe(true);
    expect(viewer.find('[data-export]').exists()).toBe(false);
    expect(viewer.find('[data-action="pause"]').exists()).toBe(false);
    expect(manager.find('[data-export]').exists()).toBe(true);
    expect(manager.find('[data-action="pause"]').exists()).toBe(true);
    expect(manager.find('[data-action="cancel"]').exists()).toBe(true);
  });

  it('E2: while sending, shows the band and refreshes every 15 seconds', async () => {
    vi.useFakeTimers();
    api.getResult.mockResolvedValue({
      data: {
        payload: result({
          campaign: { status: 'processing', processing: true },
          totals: { queued: 3 },
        }),
      },
    });
    const { wrapper } = mountView();
    await flushPromises();

    expect(wrapper.find('[data-processing]').text()).toContain(
      'Still queued: 3'
    );
    expect(api.getResult).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(15000);
    expect(api.getResult).toHaveBeenCalledTimes(2);
    wrapper.unmount();
    vi.useRealTimers();
  });

  it('SMS without per-person records says so instead of an empty result', async () => {
    api.getResult.mockResolvedValue({
      data: {
        payload: result({
          campaign: { channel: 'sms' },
          totals: {
            audience: 0,
            sent: 0,
            delivered: 0,
            read: null,
            failed: 0,
            skipped: 0,
            replied: 0,
          },
        }),
      },
    });
    const { wrapper } = mountView({ channel: 'sms' });
    await flushPromises();

    expect(wrapper.find('[data-sms-partial]').exists()).toBe(true);
  });
});
