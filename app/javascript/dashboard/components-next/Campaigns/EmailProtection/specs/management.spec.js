import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import { computed } from 'vue';
import en from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import crm from 'dashboard/i18n/locale/en/crm.json';
import Reports from 'dashboard/api/emailCampaignReports';
import Page from 'dashboard/routes/dashboard/crm/pages/CrmCampaignManagementPage.vue';
import Recipients from '../EmailRecipients.vue';
import LineChart from 'shared/components/charts/LineChart.vue';
vi.mock('dashboard/api/emailCampaignReports', () => ({
  default: {
    getReports: vi.fn(),
    getRecipients: vi.fn(),
    getTimeline: vi.fn(),
    getClicks: vi.fn(),
  },
}));
vi.mock('dashboard/api/ctwaTrackedLinks', () => ({
  default: { get: vi.fn().mockResolvedValue({ data: { payload: [] } }) },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: name =>
    computed(() =>
      name === 'globalConfig/get'
        ? { emailCampaignEnabled: true, crmKanbanEnabled: true }
        : []
    ),
}));
vi.mock('shared/components/charts/LineChart.vue', () => ({
  default: { props: ['collection'], template: '<div />' },
}));
const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});
let wrapper;
afterEach(() => wrapper?.unmount());

it('retains independent campaign options and recipient filters through report refresh', async () => {
  const campaigns = [
    { id: 1, name: 'First', status: 'paused' },
    { id: 2, name: 'Second', status: 'sent' },
  ];
  Reports.getReports.mockImplementation(id =>
    Promise.resolve({
      data: {
        payload: {
          summary: { sent: 100, permanent_bounced: 2, hard_bounce_rate: 2 },
          campaigns: id ? [campaigns[0]] : campaigns,
          campaign_options: campaigns,
        },
      },
    })
  );
  Reports.getRecipients.mockResolvedValue({
    data: { payload: { recipients: [], meta: {} } },
  });
  Reports.getTimeline.mockResolvedValue({ data: { payload: { series: [] } } });
  Reports.getClicks.mockResolvedValue({ data: { payload: { clicks: [] } } });
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: Page }],
  });
  await router.push('/');
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...en, ...crm } },
  });
  wrapper = mount(Page, { global: { plugins: [i18n, router] } });
  await flushPromises();
  const selector = wrapper.find('select');
  expect(selector.findAll('option')).toHaveLength(3);
  await selector.setValue('1');
  await flushPromises();
  expect(selector.findAll('option')).toHaveLength(3);
  const recipients = wrapper.findComponent(Recipients);
  await recipients.find('select').setValue('failed');
  await flushPromises();
  const element = recipients.element;
  const refresh = wrapper
    .findAll('button')
    .find(button => button.text() === 'Refresh');
  await refresh.trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(Recipients).element).toBe(element);
  expect(wrapper.findComponent(Recipients).find('select').element.value).toBe(
    'failed'
  );
  await wrapper.findAll('select')[1].setValue('attention');
  await flushPromises();
  expect(Reports.getReports).toHaveBeenLastCalledWith(
    1,
    expect.objectContaining({ campaignStatus: 'attention' })
  );
  expect(router.currentRoute.value.query).toMatchObject({
    email_campaign: '1',
    email_status: 'attention',
  });
});

it.each([
  [
    'ses',
    {
      provider_confirmed: 10,
      direct_acceptance_only: 0,
      legacy_delivered_includes_acceptance: false,
    },
    'delivered',
  ],
  [
    'direct_inbox',
    {
      provider_confirmed: 0,
      direct_acceptance_only: 10,
      legacy_delivered_includes_acceptance: true,
    },
    'accepted_service',
  ],
  [
    undefined,
    {
      provider_confirmed: 7,
      direct_acceptance_only: 3,
      legacy_delivered_includes_acceptance: true,
    },
    'acceptance_recorded',
  ],
  [undefined, undefined, 'acceptance_recorded'],
  [undefined, { provider_confirmed: 7 }, 'acceptance_recorded'],
])(
  'renders report provenance without changing counts/rates (%s, %j)',
  async (mode, evidence, key) => {
    const campaign = {
      id: 1,
      name: 'Synthetic source',
      status: 'sent',
      delivery_mode: mode,
      delivered: 10,
      sent: 12,
      opened: 7,
      open_rate: 70,
      click_rate: 20,
      delivery_evidence: evidence,
    };
    const before = structuredClone(campaign);
    Reports.getReports.mockResolvedValue({
      data: { payload: { summary: campaign, campaigns: [campaign] } },
    });
    Reports.getRecipients.mockResolvedValue({
      data: { payload: { recipients: [], meta: {} } },
    });
    Reports.getTimeline.mockResolvedValue({
      data: {
        payload: {
          delivery_mode: mode,
          series: [
            {
              bucket: '2026-09-17T00:00:00Z',
              delivered: 10,
              open: 7,
              click: 2,
            },
            { bucket: '2026-09-18T00:00:00Z' },
          ],
        },
      },
    });
    Reports.getClicks.mockResolvedValue({ data: { payload: { clicks: [] } } });
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/', component: Page }],
    });
    await router.push('/?email_campaign=1');
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      fallbackLocale: false,
      messages: { en: { ...en, ...crm } },
    });
    const { t } = i18n.global;
    wrapper = mount(Page, { global: { plugins: [i18n, router] } });
    await flushPromises();
    const card = wrapper.find('section.grid').findAll(':scope > div')[1];
    expect(card.text()).toContain(t(`EMAIL_CAMPAIGN_PROTECTION.STATUS.${key}`));
    expect(card.find('.text-2xl').text()).toBe('10');
    expect(wrapper.findAll('section.grid > div')[2].text()).toContain('70%');
    const table = wrapper.findAll('table').at(-1);
    expect(table.findAll('th')[3].text()).toBe(
      t(`EMAIL_CAMPAIGN_PROTECTION.STATUS.${key}`)
    );
    expect(table.findAll('tbody td')[3].text()).toContain('10');
    expect(table.findAll('tbody td')[3].text()).toContain(
      t(`EMAIL_CAMPAIGN_PROTECTION.STATUS.${key}`)
    );
    expect(table.findAll('tbody td')[4].text()).toBe('70%');
    const chart = wrapper.findComponent(LineChart).props('collection');
    expect(chart.datasets[0].label).toBe(
      t(
        `EMAIL_CAMPAIGN_PROTECTION.STATUS.${{ ses: 'delivered', direct_inbox: 'accepted_service' }[mode] || 'acceptance_recorded'}`
      )
    );
    expect(chart.datasets[0].data).toEqual([10, null]);
    expect(chart.datasets[1].data).toEqual([7, null]);
    expect(wrapper.text()).toContain(
      t('EMAIL_CAMPAIGN_PROTECTION.METRICS_HINT')
    );
    if (key !== 'delivered')
      expect(wrapper.text()).toContain(
        t('EMAIL_CAMPAIGN_PROTECTION.DELIVERY_HINT')
      );
    if (evidence) {
      expect(wrapper.text()).toContain(
        `${t('EMAIL_CAMPAIGN_PROTECTION.STATUS.delivered')}: ${evidence.provider_confirmed}`
      );
      expect(wrapper.text()).toContain(
        `${t('EMAIL_CAMPAIGN_PROTECTION.STATUS.accepted_service')}: ${evidence.direct_acceptance_only ?? '—'}`
      );
    }
    expect(campaign).toEqual(before);
  }
);

it('uses the timeline response source even when report source differs, then clears absent provenance', async () => {
  Reports.getReports.mockResolvedValue({
    data: {
      payload: {
        summary: { delivered: 10, delivery_mode: 'ses' },
        campaigns: [
          { id: 1, name: 'Synthetic', status: 'sent', delivery_mode: 'ses' },
        ],
      },
    },
  });
  Reports.getRecipients.mockResolvedValue({
    data: { payload: { recipients: [], meta: {} } },
  });
  Reports.getTimeline
    .mockResolvedValueOnce({
      data: {
        payload: {
          delivery_mode: 'direct_inbox',
          series: [{ bucket: '2026-09-17', delivered: 10 }],
        },
      },
    })
    .mockResolvedValue({
      data: { payload: { series: [{ bucket: '2026-09-17', delivered: 8 }] } },
    });
  Reports.getClicks.mockResolvedValue({ data: { payload: { clicks: [] } } });
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: Page }],
  });
  await router.push('/?email_campaign=1');
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...en, ...crm } },
  });
  wrapper = mount(Page, { global: { plugins: [i18n, router] } });
  await flushPromises();
  expect(
    wrapper.findComponent(LineChart).props('collection').datasets[0].label
  ).toBe('Accepted by sending service');
  await wrapper
    .findAll('button')
    .find(
      button =>
        button.text() ===
        i18n.global.t('CAMPAIGN_MANAGEMENT.TIMELINE.INTERVAL.HOUR')
    )
    .trigger('click');
  await flushPromises();
  expect(
    wrapper.findComponent(LineChart).props('collection').datasets[0]
  ).toMatchObject({ label: 'Acceptance recorded', data: [8] });
});

it('keeps a mixed total conserved while labeling each campaign by its own source', async () => {
  const campaigns = [
    {
      id: 1,
      name: 'Synthetic SES',
      delivery_mode: 'ses',
      delivered: 7,
      status: 'sent',
    },
    {
      id: 2,
      name: 'Synthetic direct',
      delivery_mode: 'direct_inbox',
      delivered: 3,
      status: 'sent',
    },
  ];
  Reports.getReports.mockResolvedValue({
    data: {
      payload: {
        summary: {
          delivered: 10,
          delivery_evidence: {
            provider_confirmed: 7,
            direct_acceptance_only: 3,
            legacy_delivered_includes_acceptance: true,
          },
        },
        campaigns,
      },
    },
  });
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: Page }],
  });
  await router.push('/');
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...en, ...crm } },
  });
  wrapper = mount(Page, { global: { plugins: [i18n, router] } });
  await flushPromises();
  const rows = wrapper.findAll('table').at(-1).findAll('tbody tr');
  expect(rows[0].findAll('td')[3].text()).toBe(
    '7 Accepted by recipient server'
  );
  expect(rows[1].findAll('td')[3].text()).toBe('3 Accepted by sending service');
  const cards = wrapper.findAll('section.grid > div');
  expect(cards[0].find('.text-2xl').text()).toBe('—');
  expect(cards[1].find('.text-2xl').text()).toBe('10');
  expect(cards[1].text()).toContain('Acceptance recorded');
  expect(cards[2].find('.text-2xl').text()).toBe('—');
  expect(rows.every(row => row.findAll('td')[4].text() === '—')).toBe(true);
});
