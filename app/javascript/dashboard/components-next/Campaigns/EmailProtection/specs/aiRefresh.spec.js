import { mount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import { createStore } from 'vuex';
import protection from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import campaignMessages from 'dashboard/i18n/locale/en/campaign.json';
import Page from 'dashboard/routes/dashboard/campaigns/pages/EmailCampaignsPage.vue';
import emailCampaigns from 'dashboard/store/modules/emailCampaigns';
import API from 'dashboard/api/emailCampaigns';
import ActionCable from 'dashboard/helper/actionCable';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

vi.mock('dashboard/api/emailCampaigns', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({ isImpersonating: { value: false } }),
}));
// Exercise the real event handlers without opening a socket or presence timer.
vi.mock('shared/helpers/BaseActionCableConnector', () => ({
  default: class {
    constructor(app) {
      this.app = app;
    }
  },
}));
vi.mock('dashboard/components-next/Campaigns/CampaignLayout.vue', () => ({
  default: { template: '<div><slot /></div>' },
}));
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue',
  () => ({ default: { template: '<div />' } })
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDetailsDialog.vue',
  () => ({ default: { template: '<div />' } })
);
const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});

it.each([
  ['onEmailCampaignAiReady', BUS_EVENTS.EMAIL_CAMPAIGN_AI_READY],
  ['onEmailCampaignAiFailed', BUS_EVENTS.EMAIL_CAMPAIGN_AI_FAILED],
])(
  'keeps paused filter through %s and cleans up the page listener',
  async (handler, event) => {
    const records = [
      { id: 1, name: 'Paused synthetic', status: 'paused' },
      { id: 2, name: 'Draft synthetic', status: 'draft' },
    ];
    API.get.mockImplementation(({ status }) =>
      Promise.resolve({
        data: {
          payload: {
            campaigns: records.filter(c => !status || c.status === status),
          },
        },
      })
    );
    const store = createStore({
      modules: {
        emailSenderIdentities: { namespaced: true, actions: { get: vi.fn() } },
        inboxes: { namespaced: true, actions: { get: vi.fn() } },
        emailCampaigns: {
          ...emailCampaigns,
          state: { ...emailCampaigns.state, records: [], uiFlags: {} },
        },
        globalConfig: {
          namespaced: true,
          getters: {
            get: () => ({ emailCampaignEnabled: true, crmKanbanEnabled: true }),
          },
        },
      },
      getters: { getCurrentAccountId: () => 436 },
    });
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/', component: Page }],
    });
    await router.push('/?email_status=paused');
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      fallbackLocale: false,
      messages: { en: { ...protection, ...campaignMessages } },
    });
    const wrapper = mount(Page, { global: { plugins: [store, router, i18n] } });
    const toastListener = vi.fn();
    emitter.on(event, toastListener);
    try {
      await flushPromises();
      API.get.mockClear();
      const connector = ActionCable.init(store, 'synthetic');
      const data = { account_id: 436, id: 2 };
      connector[handler](data);
      await flushPromises();
      expect(API.get).toHaveBeenCalledTimes(1);
      expect(API.get).toHaveBeenLastCalledWith(
        expect.objectContaining({ status: 'paused' })
      );
      expect(store.state.emailCampaigns.records).toEqual([records[0]]);
      expect(wrapper.text()).toContain('Paused synthetic');
      expect(wrapper.text()).not.toContain('Draft synthetic');
      expect(wrapper.find('select').element.value).toBe('paused');
      expect(toastListener).toHaveBeenCalledWith(data);
      wrapper.unmount();
      API.get.mockClear();
      connector[handler](data);
      await flushPromises();
      expect(API.get).not.toHaveBeenCalled();
    } finally {
      emitter.off(event, toastListener);
      wrapper.unmount();
    }
  }
);
