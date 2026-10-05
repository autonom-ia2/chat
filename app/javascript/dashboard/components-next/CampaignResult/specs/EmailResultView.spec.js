import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enResult from 'dashboard/i18n/locale/en/resultJourney.json';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import enProtection from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import enCrm from 'dashboard/i18n/locale/en/crm.json';

const api = vi.hoisted(() => ({
  results: {
    getResult: vi.fn(),
    getRecipients: vi.fn(),
    exportResult: vi.fn(),
  },
  reports: { getReports: vi.fn(), getTimeline: vi.fn(), getClicks: vi.fn() },
  campaigns: { show: vi.fn() },
  templates: { create: vi.fn() },
}));
vi.mock('dashboard/api/campaignResults', () => ({ default: api.results }));
vi.mock('dashboard/api/emailCampaignReports', () => ({ default: api.reports }));
vi.mock('dashboard/api/emailCampaigns', () => ({ default: api.campaigns }));
vi.mock('dashboard/api/emailCampaignTemplates', () => ({
  default: api.templates,
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

// The e-mail report pieces are reused as they are (O1); here they only need to be there.
const stub = name => ({
  default: {
    name,
    props: ['campaign', 'campaignId', 'series', 'refreshKey'],
    render: () => null,
  },
});
vi.mock(
  'dashboard/components-next/Campaigns/EmailProtection/EmailRecipients.vue',
  () => stub('EmailRecipients')
);
vi.mock(
  'dashboard/components-next/Campaigns/EmailProtection/EmailCampaignHealth.vue',
  () => stub('EmailCampaignHealth')
);
vi.mock(
  'dashboard/components-next/Campaigns/EmailProtection/CampaignTimelineChart.vue',
  () => stub('CampaignTimelineChart')
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/RecipientImportStatus.vue',
  () => stub('RecipientImportStatus')
);

const { default: EmailResultView } = await import('../EmailResultView.vue');

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const summary = {
  sent: 1232,
  delivered: 1206,
  opened: 505,
  open_rate: 41.87,
  clicked: 74,
  click_rate: 6.1,
  unsubscribed: 4,
  unsubscribe_rate: 0.33,
  permanent_bounced: 19,
  hard_bounce_rate: 1.5,
  complained: 0,
  complaint_rate: 0,
  temporary_bounced: 7,
  unknown_bounced: 1,
  delivery_mode: 'ses',
  delivery_evidence: { provider_confirmed: 1206, direct_acceptance_only: 0 },
};

const mountView = ({ status = 'sent', customRole, reportsOn = true } = {}) => {
  api.results.getResult.mockResolvedValue({
    data: {
      payload: {
        campaign: {
          id: 9,
          channel: 'email',
          name: 'Novidades de outubro',
          status,
          processing: status === 'sending',
          from_email: 'novidades@hub2you.ai',
          sent_at: '2026-10-09T11:00:00Z',
          audience: { id: 2, name: 'Corretoras parceiras' },
        },
        totals: {
          eligible: 1250,
          delivered: 1213,
          bounced: 19,
          not_sent: 18,
          replied: 11,
        },
        filters: ['replied'],
        crm: { source_id: 'campaign:email:9', enabled: true },
      },
    },
  });
  api.reports.getReports.mockResolvedValue({
    data: {
      payload: {
        summary,
        campaigns: [{ id: 9, status }],
        protection: { state: 'healthy' },
      },
    },
  });
  api.campaigns.show.mockResolvedValue({
    data: {
      payload: {
        id: 9,
        name: 'Novidades de outubro',
        status,
        body_html: '<p>Oi</p>',
      },
    },
  });
  const actions = {
    pause: vi.fn(),
    cancel: vi.fn(),
    delete: vi.fn(),
    duplicate: vi.fn(() => ({ id: 10 })),
  };
  const store = createStore({
    getters: {
      getCurrentUser: () => ({
        accounts: [{ id: 1, permissions: customRole || [] }],
      }),
      getCurrentCustomRoleId: () => (customRole ? 7 : null),
      getCurrentAccountId: () => 1,
    },
    modules: {
      globalConfig: {
        namespaced: true,
        getters: {
          get: () => ({
            emailCampaignEnabled: reportsOn,
            crmKanbanEnabled: true,
          }),
        },
      },
      emailCampaigns: { namespaced: true, actions },
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...enJourney, ...enResult, ...enProtection, ...enCrm } },
    missingWarn: false,
    fallbackWarn: false,
  });
  const wrapper = mount(EmailResultView, {
    props: { campaignId: '9' },
    global: {
      plugins: [store, i18n],
      stubs: {
        'router-link': {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
        Dialog: {
          template: '<div><slot /></div>',
          methods: { open() {}, close() {} },
        },
        ResultRepliedList: { name: 'ResultRepliedList', render: () => null },
      },
    },
  });
  return { wrapper, actions };
};

describe('e-mail campaign result (#1007, O1, L8)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.reports.getTimeline.mockResolvedValue({
      data: { payload: { series: [] } },
    });
    api.reports.getClicks.mockResolvedValue({
      data: {
        payload: {
          clicks: [
            {
              url: 'https://hub2you.ai/live',
              unique_clicks: 52,
              total_clicks: 61,
            },
          ],
        },
      },
    });
    api.results.exportResult.mockResolvedValue({ data: new Blob(['csv']) });
  });

  it('O1: keeps every indicator of the old Gestão and adds Responderam', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    expect(
      wrapper.findAll('[data-kpi]').map(item => item.attributes('data-kpi'))
    ).toEqual([
      'ELIGIBLE',
      'SENT',
      'DELIVERED',
      'OPENED',
      'CLICKED',
      'REPLIED',
      'UNSUBSCRIBED',
      'BOUNCED',
      'TEMPORARY',
      'COMPLAINED',
      'UNKNOWN',
    ]);
    expect(wrapper.find('[data-kpi="REPLIED"]').text()).toContain('11');
    expect(wrapper.find('[data-kpi="OPENED"]').text()).toContain(
      '(approximate)'
    );
    expect(wrapper.find('[data-kpi-details-toggle]').exists()).toBe(true);
    expect(wrapper.find('[data-link-clicks]').text()).toContain(
      'https://hub2you.ai/live'
    );
  });

  it('O1: reuses the chart, health, import status and the per-person table with export', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    expect(
      wrapper.findComponent({ name: 'CampaignTimelineChart' }).exists()
    ).toBe(true);
    expect(
      wrapper.findComponent({ name: 'EmailCampaignHealth' }).props('campaign')
    ).toMatchObject({
      id: 9,
      protection: { state: 'healthy' },
    });
    expect(
      wrapper.findComponent({ name: 'RecipientImportStatus' }).exists()
    ).toBe(true);
    expect(
      wrapper.findComponent({ name: 'EmailRecipients' }).props('campaignId')
    ).toBe('9');
    expect(wrapper.findComponent({ name: 'ResultRepliedList' }).exists()).toBe(
      true
    );
    expect(api.reports.getReports).toHaveBeenCalledWith('9');
  });

  it('E1: Entregues + Voltaram + Não enviados = Público elegível', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    expect(wrapper.find('[data-balance]').text()).toBe(
      'Delivered 1213 + Bounced 19 + Not sent 18 = Eligible audience 1250'
    );
  });

  it('"Ver no CRM" opens the Kanban filtered by this e-mail campaign', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    expect(
      JSON.parse(wrapper.find('[data-crm-link]').attributes('data-to'))
    ).toEqual({
      name: 'crm_kanban_index',
      query: { campaign_source_ids: 'campaign:email:9' },
    });
  });

  it('L8: offers the actions that fit the situation and runs them', async () => {
    const sent = mountView({ status: 'sent' }).wrapper;
    await flushPromises();
    const visible = wrapper =>
      wrapper
        .findAll('[data-action]')
        .map(item => item.attributes('data-action'));
    expect(visible(sent)).toEqual(['duplicate', 'template']);

    const { wrapper: sending, actions } = mountView({ status: 'sending' });
    await flushPromises();
    expect(visible(sending)).toEqual([
      'pause',
      'duplicate',
      'template',
      'cancel',
    ]);
    await sending.find('[data-action="pause"]').trigger('click');
    await flushPromises();
    expect(actions.pause).toHaveBeenCalled();

    const draft = mountView({ status: 'draft' }).wrapper;
    await flushPromises();
    expect(visible(draft)).toEqual([
      'edit',
      'duplicate',
      'template',
      'cancel',
      'delete',
    ]);
  });

  it('A4: campaign_view reads everything but has no action nor download', async () => {
    const { wrapper } = mountView({
      status: 'sending',
      customRole: ['campaign_view'],
    });
    await flushPromises();

    expect(wrapper.find('[data-kpi="SENT"]').exists()).toBe(true);
    expect(wrapper.find('[data-email-actions]').exists()).toBe(false);
    expect(wrapper.find('[data-export]').exists()).toBe(false);
  });

  it('E4: "Baixar resultado" asks the masked export', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    await wrapper.find('[data-export]').trigger('click');
    await flushPromises();

    expect(api.results.exportResult).toHaveBeenCalledWith('email', '9');
  });

  it('keeps the paywall of the e-mail reports when they are off', async () => {
    const { wrapper } = mountView({ reportsOn: false });
    await flushPromises();

    expect(wrapper.find('[data-paywall]').exists()).toBe(true);
    expect(api.results.getResult).not.toHaveBeenCalled();
  });
});
