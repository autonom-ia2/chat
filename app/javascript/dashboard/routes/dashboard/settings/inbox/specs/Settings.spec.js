import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import Settings from '../Settings.vue';

vi.mock('dashboard/api/whatsappHybrid', () => ({
  default: { show: vi.fn().mockResolvedValue({ data: {} }) },
}));
vi.mock('dashboard/api/inboxHealth', () => ({
  default: { getHealthStatus: vi.fn().mockResolvedValue({ data: {} }) },
}));

// Caixa de site: a aba de configurações mostra os quatro campos de escolha (Central de Ajuda, posição e tipo do
// balão, tempo de resposta).
const webWidgetInbox = {
  id: 7,
  name: 'Site',
  channel_type: 'Channel::WebWidget',
  reply_time: 'in_a_few_minutes',
  selected_feature_flags: [],
};

const mountSettings = () => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({ id: 1, accounts: [] }),
      getCurrentCustomRoleId: () => null,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'globalConfig/isOnChatwootCloud': () => false,
      'globalConfig/isMetaMessageSendingDisabled': () => false,
      'inboxes/getUIFlags': () => ({ isFetching: false }),
      'portals/allPortals': () => [],
      'inboxes/getInbox': () => () => webWidgetInbox,
      'inboxes/getInstagramInboxByInstagramId': () => () => null,
    },
    actions: {},
  });
  store.dispatch = vi.fn();
  return shallowMount(Settings, {
    global: {
      plugins: [store],
      renderStubDefaultSlot: true,
      mocks: {
        $t: key => key,
        $route: { params: { inboxId: '7' }, query: {}, name: 'x' },
        $router: { replace: vi.fn(), push: vi.fn() },
      },
    },
  });
};

const computeWhatsappUnauthorized = context =>
  Settings.computed.whatsappUnauthorized.call(context);

describe('Inbox Settings', () => {
  it('shows WhatsApp reauthorization for embedded signup inboxes without checking account feature flags', () => {
    const isFeatureEnabledonAccount = vi.fn(() => false);

    const result = computeWhatsappUnauthorized({
      accountId: 1,
      isAWhatsAppCloudChannel: true,
      isEmbeddedSignupWhatsApp: true,
      isFeatureEnabledonAccount,
      isOnChatwootCloud: true,
      inbox: {
        reauthorization_required: true,
      },
    });

    expect(result).toBe(true);
    expect(isFeatureEnabledonAccount).not.toHaveBeenCalled();
  });

  it('does not show WhatsApp reauthorization for manual WhatsApp inboxes', () => {
    const result = computeWhatsappUnauthorized({
      isAWhatsAppCloudChannel: true,
      isEmbeddedSignupWhatsApp: false,
      inbox: {
        reauthorization_required: true,
      },
    });

    expect(result).toBe(false);
  });

  // #1487: escolha única pelo ChoiceSelect (teclado WAI-ARIA, 44 px), nunca pelo Select antigo.
  it('uses ChoiceSelect for single choices, not the old Select', () => {
    expect(Settings.components.ChoiceSelect).toBeDefined();
    expect(Settings.components.SelectInput).toBeUndefined();
  });

  // #1487: nenhuma escolha da configuração da caixa renderiza <select> nativo.
  it('renders the inbox settings choices without any native select', async () => {
    const wrapper = mountSettings();
    await flushPromises();

    expect(
      wrapper.findAllComponents({ name: 'ChoiceSelect' }).length
    ).toBeGreaterThanOrEqual(4);
    expect(wrapper.find('select').exists()).toBe(false);
  });
});
