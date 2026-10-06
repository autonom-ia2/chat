import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  fromCampaign,
  isValidPageUrl,
  toCampaignPayload,
} from 'dashboard/components-next/CampaignJourney/liveChatCampaign';

// #993 / #1008 (PRD §6.8, M5): Quando aparece → Mensagem → Ativar; edit and pause.
const route = vi.hoisted(() => ({ value: null }));
const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => route.value,
  useRouter: () => ({ push }),
}));
const alert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alert(...args),
}));

const { default: LiveChatJourneyPage } = await import(
  '../LiveChatJourneyPage.vue'
);

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const EXISTING = {
  id: 4,
  title: 'Boas-vindas',
  message: 'Oi! Posso ajudar?',
  enabled: true,
  inbox: { id: 1 },
  sender: null,
  trigger_only_during_business_hours: true,
  trigger_rules: { url: 'https://site.com.br/planos', time_on_page: 20 },
};

const mountPage = (params = {}) => {
  route.value = { params, query: {} };
  const create = vi.fn();
  const update = vi.fn();
  const store = createStore({
    modules: {
      inboxes: {
        namespaced: true,
        getters: { getWebsiteInboxes: () => [{ id: 1, name: 'Site' }] },
        actions: { get: vi.fn() },
      },
      inboxMembers: {
        namespaced: true,
        actions: {
          get: () => ({ data: { payload: [{ id: 7, name: 'Ana' }] } }),
        },
      },
      campaigns: {
        namespaced: true,
        getters: { getAllCampaigns: () => [EXISTING] },
        actions: { get: vi.fn(), create, update },
      },
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: enJourney },
  });
  const wrapper = mount(LiveChatJourneyPage, {
    attachTo: document.body,
    global: {
      plugins: [store, i18n],
      stubs: { 'router-link': { template: '<a><slot /></a>' } },
    },
  });
  return { wrapper, create, update };
};

beforeEach(() => {
  push.mockClear();
  alert.mockClear();
});

describe('Chat ao vivo (M5)', () => {
  it('walks Quando aparece → Mensagem → Ativar and creates an ongoing campaign', async () => {
    const { wrapper, create } = mountPage();
    await flushPromises();

    expect(
      wrapper.find('[data-live-step="1"]').attributes('aria-current')
    ).toBe('step');
    wrapper.findAllComponents(ChoiceSelect)[0].vm.$emit('update:modelValue', 1);
    await wrapper
      .find('[data-test="live-chat-url"] input, input[type="url"]')
      .setValue('site.com.br');
    expect(wrapper.text()).toContain(
      'Use a full address starting with https://'
    );
    expect(
      wrapper.find('[data-test="live-chat-next"]').attributes('disabled')
    ).toBeDefined();
    await wrapper
      .find('input[type="url"]')
      .setValue('https://site.com.br/planos');
    await wrapper.find('[data-test="live-chat-hours"]').trigger('click');
    await wrapper.find('[data-test="live-chat-next"]').trigger('click');

    await wrapper
      .find('[data-test="live-chat-message"] input[type="text"]')
      .setValue('Boas-vindas nos planos');
    await wrapper
      .find('[data-test="live-chat-text"]')
      .setValue('Oi! Posso ajudar?');
    expect(wrapper.find('[data-test="live-chat-preview"]').text()).toContain(
      'Oi! Posso ajudar?'
    );
    expect(wrapper.text()).toContain('Campaign: Boas-vindas nos planos');
    await wrapper.find('[data-test="live-chat-next-2"]').trigger('click');
    await wrapper.find('[data-test="live-chat-save"]').trigger('click');
    await flushPromises();

    expect(create).toHaveBeenCalledWith(expect.anything(), {
      title: 'Boas-vindas nos planos',
      message: 'Oi! Posso ajudar?',
      inbox_id: 1,
      sender_id: null,
      enabled: true,
      trigger_only_during_business_hours: true,
      trigger_rules: { url: 'https://site.com.br/planos', time_on_page: 10 },
    });
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_index',
      query: { channel: 'live_chat' },
    });
    wrapper.unmount();
  });

  it('edits an existing message and pauses it', async () => {
    const { wrapper, update } = mountPage({ campaignId: '4' });
    await flushPromises();

    expect(wrapper.find('[data-test="live-chat-status"]').text()).toBe(
      'Always on'
    );
    await wrapper.find('[data-live-step="3"]').trigger('click');
    await wrapper.find('[data-test="live-chat-toggle"]').trigger('click');
    await flushPromises();

    expect(update).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ id: 4, enabled: false, title: 'Boas-vindas' })
    );
    expect(wrapper.find('[data-test="live-chat-status"]').text()).toBe(
      'Paused'
    );
    wrapper.unmount();
  });
});

describe('liveChatCampaign helpers', () => {
  it('validates the page address without regular expressions', () => {
    expect(isValidPageUrl('https://site.com.br/planos')).toBe(true);
    expect(isValidPageUrl('site.com.br')).toBe(false);
    expect(isValidPageUrl('ftp://site.com.br')).toBe(false);
  });

  it('round-trips the ongoing campaign fields', () => {
    const form = fromCampaign(EXISTING);
    expect(toCampaignPayload(form)).toEqual({
      title: 'Boas-vindas',
      message: 'Oi! Posso ajudar?',
      inbox_id: 1,
      sender_id: null,
      enabled: true,
      trigger_only_during_business_hours: true,
      trigger_rules: { url: 'https://site.com.br/planos', time_on_page: 20 },
    });
  });
});
