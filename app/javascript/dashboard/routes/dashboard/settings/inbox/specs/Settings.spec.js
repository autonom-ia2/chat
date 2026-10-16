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

const mountSettings = ({ porCaixa = false, robos = false } = {}) => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      'accounts/getAccount': () => () => ({
        id: 1,
        autonomia_agente_ia_por_caixa: porCaixa,
      }),
      getCurrentUser: () => ({ id: 1, accounts: [] }),
      getCurrentCustomRoleId: () => null,
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        robos && flag === 'agent_bots',
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
  // #1648 — a aba "Agente de IA" por caixa só com a chave da conta; desligada, as abas da main.
  describe('AI agent tab per inbox', () => {
    const aba = (wrapper, chave) =>
      wrapper.vm.tabs.find(tab => tab.key === chave)?.name;
    const abrirAbaDoRobo = async wrapper => {
      wrapper.vm.selectedTabIndex = wrapper.vm.tabs.findIndex(
        tab => tab.key === 'bot-configuration'
      );
      await flushPromises();
    };

    it('off: the Bot tab with the original BotConfiguration and the Collaborators tab, as on main', async () => {
      const wrapper = mountSettings({ robos: true });
      await flushPromises();

      expect(aba(wrapper, 'bot-configuration')).toBe(
        'INBOX_MGMT.TABS.BOT_CONFIGURATION'
      );
      expect(aba(wrapper, 'collaborators')).toBe(
        'INBOX_MGMT.TABS.COLLABORATORS'
      );
      await abrirAbaDoRobo(wrapper);
      expect(wrapper.findComponent({ name: 'BotConfiguration' }).exists()).toBe(
        true
      );
      expect(wrapper.findComponent({ name: 'AbaAgenteDeIa' }).exists()).toBe(
        false
      );
    });

    it('on: the AI agent tab and the Users tab', async () => {
      const wrapper = mountSettings({ robos: true, porCaixa: true });
      await flushPromises();

      expect(aba(wrapper, 'bot-configuration')).toBe(
        'AGENTS.CAIXA_AGENTE_IA.ABA'
      );
      expect(aba(wrapper, 'collaborators')).toBe('AGENTS.CAIXA_USUARIOS.ABA');
      await abrirAbaDoRobo(wrapper);
      expect(wrapper.findComponent({ name: 'AbaAgenteDeIa' }).exists()).toBe(
        true
      );
    });
  });
});
