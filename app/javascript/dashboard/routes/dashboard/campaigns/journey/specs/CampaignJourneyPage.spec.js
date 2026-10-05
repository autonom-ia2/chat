import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';

const stub = name => ({ default: { name, render: () => null } });
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue',
  () => stub('EmailCampaignDialog')
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue',
  () => stub('WhatsAppCampaignDialog')
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppApiCampaign/WhatsAppApiCampaignDialog.vue',
  () => stub('WhatsAppApiCampaignDialog')
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignDialog.vue',
  () => stub('SMSCampaignDialog')
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignDialog.vue',
  () => stub('LiveChatCampaignDialog')
);
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));

const { default: CampaignJourneyPage } = await import(
  '../CampaignJourneyPage.vue'
);

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const module = (getters, actions = {}) => ({
  namespaced: true,
  getters,
  actions,
});

const mountPage = ({ inboxes, campaigns = [] }) => {
  const dispatched = [];
  const track = name => () => {
    dispatched.push(name);
  };
  const store = createStore({
    getters: {
      getCurrentUser: () => ({ accounts: [{ id: 1, permissions: [] }] }),
      getCurrentCustomRoleId: () => null,
      getCurrentAccountId: () => 1,
    },
    modules: {
      inboxes: module(
        { getInboxes: () => inboxes },
        { get: track('inboxes/get') }
      ),
      campaigns: module(
        { getAllCampaigns: () => campaigns },
        { get: track('campaigns/get') }
      ),
      whatsappApiCampaigns: module(
        { getCampaigns: () => [] },
        { get: track('whatsappApiCampaigns/get') }
      ),
      emailCampaigns: module(
        { getCampaigns: () => [] },
        { get: track('emailCampaigns/get') }
      ),
      emailSenderIdentities: module(
        { getIdentities: () => [] },
        { get: track('emailSenderIdentities/get') }
      ),
      globalConfig: module({
        get: () => ({
          emailCampaignEnabled: false,
          crmKanbanEnabled: false,
          whatsappApiCampaignsEnabled: false,
          campaignImportEnabled: true,
        }),
      }),
      accounts: module({ isFeatureEnabledonAccount: () => () => true }),
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: enJourney },
  });
  const wrapper = mount(CampaignJourneyPage, {
    attachTo: document.body,
    global: {
      plugins: [store, i18n],
      stubs: { 'router-link': { template: '<a><slot /></a>' } },
    },
  });
  return { wrapper, dispatched };
};

describe('Campanha page (PRD §6.1, M1–M2)', () => {
  it('"Nova campanha" offers only the channels connected in the account', async () => {
    const { wrapper, dispatched } = mountPage({
      inboxes: [
        { channel_type: 'Channel::Sms' },
        { channel_type: 'Channel::WebWidget' },
      ],
    });
    await flushPromises();

    expect(dispatched).toEqual(['inboxes/get', 'campaigns/get']);
    await wrapper.find('[data-test="new-campaign"]').trigger('click');
    const offered = wrapper
      .findAll('[data-channel]')
      .map(button => button.attributes('data-channel'));
    expect(offered).toEqual(['sms', 'live_chat']);
    wrapper.unmount();
  });

  it('choosing a channel opens its existing creation flow', async () => {
    const { wrapper } = mountPage({
      inboxes: [{ channel_type: 'Channel::Sms' }],
    });
    await flushPromises();

    await wrapper.find('[data-test="new-campaign"]').trigger('click');
    await wrapper.find('[data-channel="sms"]').trigger('click');

    expect(wrapper.findAll('[data-channel]')).toHaveLength(0);
    expect(wrapper.findComponent({ name: 'SMSCampaignDialog' }).exists()).toBe(
      true
    );
    wrapper.unmount();
  });

  it('channel filter chips list connected channels without campaigns too', async () => {
    const { wrapper } = mountPage({
      inboxes: [{ channel_type: 'Channel::WebWidget' }],
      campaigns: [
        {
          id: 4,
          title: 'Boas-vindas',
          campaign_type: 'ongoing',
          enabled: true,
          inbox: { name: 'Site', channel_type: 'Channel::WebWidget' },
        },
      ],
    });
    await flushPromises();

    expect(
      wrapper
        .findAll('[data-filter]')
        .map(chip => chip.attributes('data-filter'))
    ).toEqual(['all', 'live_chat']);
    expect(wrapper.find('[data-row="live_chat-4"]').text()).toContain(
      'Always on'
    );
    wrapper.unmount();
  });

  it('SMS disconnected with an old campaign: listed and filterable, but not offered in Nova campanha', async () => {
    const { wrapper } = mountPage({
      inboxes: [{ channel_type: 'Channel::WebWidget' }],
      campaigns: [
        {
          id: 2,
          title: 'Parcela antiga',
          campaign_type: 'one_off',
          campaign_status: 'completed',
          scheduled_at: 1_700_000_000,
          inbox: { name: 'SMS removido', channel_type: 'Channel::Sms' },
        },
      ],
    });
    await flushPromises();

    expect(wrapper.find('[data-row="sms-2"]').text()).toContain(
      'Parcela antiga'
    );
    expect(
      wrapper
        .findAll('[data-filter]')
        .map(chip => chip.attributes('data-filter'))
    ).toEqual(['all', 'sms', 'live_chat']);

    await wrapper.find('[data-test="new-campaign"]').trigger('click');
    expect(
      wrapper
        .findAll('[data-channel]')
        .map(button => button.attributes('data-channel'))
    ).toEqual(['live_chat']);
    wrapper.unmount();
  });
});
