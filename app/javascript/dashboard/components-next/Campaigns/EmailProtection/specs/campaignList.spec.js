import { mount, config, flushPromises } from '@vue/test-utils';
import { computed } from 'vue';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import protection from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import campaignMessages from 'dashboard/i18n/locale/en/campaign.json';
import Page from 'dashboard/routes/dashboard/campaigns/pages/EmailCampaignsPage.vue';
const { dispatch } = vi.hoisted(() => ({ dispatch: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: name =>
    computed(
      () =>
        ({
          'globalConfig/get': {
            emailCampaignEnabled: true,
            crmKanbanEnabled: true,
          },
          'emailCampaigns/getUIFlags': {},
          'emailCampaigns/getCampaigns': [
            {
              id: 1,
              name: 'Synthetic',
              status: 'paused',
              last_error: 'private provider message',
              suppressed_count: 6,
              preflight: {
                counts: { invalid: 1, review: 2, protected: 3 },
              },
            },
          ],
        })[name]
    ),
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
let wrapper;
afterEach(() => wrapper?.unmount());
it('sends the list status filter to the store and keeps unsafe legacy resume hidden', async () => {
  dispatch.mockResolvedValue(undefined);
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: Page }],
  });
  await router.push('/?email_status=paused');
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...protection, ...campaignMessages } },
  });
  wrapper = mount(Page, { global: { plugins: [i18n, router] } });
  await flushPromises();
  expect(dispatch).toHaveBeenCalledWith(
    'emailCampaigns/get',
    expect.objectContaining({
      status: 'paused',
      signal: expect.any(AbortSignal),
    })
  );
  expect(
    wrapper.findAll('button').some(button => button.text() === 'Resume sending')
  ).toBe(false);
  expect(wrapper.text()).not.toContain('private provider message');
  expect(wrapper.text()).toContain(
    i18n.global.t('EMAIL_CAMPAIGN_PROTECTION.STATUS.invalid')
  );
  expect(wrapper.text()).toContain(
    i18n.global.t('EMAIL_CAMPAIGN_PROTECTION.STATUS.review')
  );
  expect(wrapper.text()).toContain(
    i18n.global.t('EMAIL_CAMPAIGN_PROTECTION.STATUS.protected')
  );
  expect(wrapper.text()).not.toContain(
    i18n.global.t('EMAIL_CAMPAIGN_PROTECTION.STATUS.suppressed')
  );
  await wrapper.find('select').setValue('attention');
  await flushPromises();
  expect(dispatch).toHaveBeenLastCalledWith(
    'emailCampaigns/get',
    expect.objectContaining({ status: 'attention' })
  );
  expect(router.currentRoute.value.query.email_status).toBe('attention');
  await wrapper.find('select').setValue('');
  await flushPromises();
  expect(dispatch).toHaveBeenLastCalledWith(
    'emailCampaigns/get',
    expect.objectContaining({ status: '' })
  );
});
