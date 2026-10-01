import { mount, config, flushPromises } from '@vue/test-utils';
import { computed } from 'vue';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import protection from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import campaignMessages from 'dashboard/i18n/locale/en/campaign.json';
import ptBrProtection from 'dashboard/i18n/locale/pt_BR/emailCampaignProtection.json';
import ptBrCampaignMessages from 'dashboard/i18n/locale/pt_BR/campaign.json';
import Page from 'dashboard/routes/dashboard/campaigns/pages/EmailCampaignsPage.vue';
import EmailStatusFilter from '../EmailStatusFilter.vue';
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
                counts: { invalid: 1, review: 2, protected: 3, total: 6 },
              },
            },
            {
              id: 2,
              name: 'Próxima campanha',
              status: 'scheduled',
              subject: 'Uma mensagem agendada',
              scheduled_at: '2099-12-31T12:30:00Z',
              updated_at: '2099-12-01T12:30:00Z',
              recipients_count: 1234,
            },
          ],
        })[name]
    ),
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    template: '<div><slot /></div>',
    methods: { open() {}, close() {} },
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
const messages = {
  en: { ...protection, ...campaignMessages },
  pt_BR: { ...ptBrProtection, ...ptBrCampaignMessages },
  zh_CN: { ...protection, ...campaignMessages },
};

const makeI18n = locale =>
  createI18n({
    legacy: false,
    locale,
    fallbackLocale: 'en',
    messages,
  });

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
    routes: [
      { path: '/', component: Page },
      {
        path: '/templates',
        name: 'campaigns_email_templates',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push('/?email_status=paused');
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages,
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
  expect(wrapper.text()).not.toContain(
    i18n.global.t('EMAIL_CAMPAIGN_PROTECTION.STATUS.invalid')
  );
  await wrapper
    .findAll('button')
    .find(button =>
      button
        .text()
        .includes(
          i18n.global.t('CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE.SEE_DETAILS')
        )
    )
    .trigger('click');
  await flushPromises();
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
  wrapper
    .findComponent(EmailStatusFilter)
    .vm.$emit('update:modelValue', 'attention');
  await flushPromises();
  expect(dispatch).toHaveBeenLastCalledWith(
    'emailCampaigns/get',
    expect.objectContaining({ status: 'attention' })
  );
  expect(router.currentRoute.value.query.email_status).toBe('attention');
  wrapper.findComponent(EmailStatusFilter).vm.$emit('update:modelValue', '');
  await flushPromises();
  expect(dispatch).toHaveBeenLastCalledWith(
    'emailCampaigns/get',
    expect.objectContaining({ status: '' })
  );
});

it.each(['pt_BR', 'zh_CN'])(
  'keeps campaign search and next scheduled date working for the %s profile locale',
  async profileLocale => {
    dispatch.mockResolvedValue(undefined);
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/', component: Page },
        {
          path: '/templates',
          name: 'campaigns_email_templates',
          component: { template: '<div />' },
        },
      ],
    });
    await router.push('/');
    const i18n = makeI18n(profileLocale);
    wrapper = mount(Page, { global: { plugins: [i18n, router] } });
    await flushPromises();

    const expectedDate = new Intl.DateTimeFormat(
      profileLocale.replace('_', '-'),
      { dateStyle: 'medium', timeStyle: 'short' }
    ).format(new Date('2099-12-31T12:30:00Z'));
    expect(wrapper.text()).toContain(expectedDate);

    await wrapper.find('input[type="search"]').setValue('PRÓXIMA');
    await flushPromises();

    const visibleCards = wrapper.findAll('article');
    expect(visibleCards).toHaveLength(1);
    expect(visibleCards[0].text()).toContain('Próxima campanha');
    expect(visibleCards[0].text()).not.toContain('Synthetic');
  }
);
