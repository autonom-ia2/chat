import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enCrm from 'dashboard/i18n/locale/en/crm.json';

// #1593 — "Passar para…": só com a Fase 2 na conta; o selo e a origem vêm do servidor quando a pessoa abre o botão;
// a recusa vira linguagem simples pelo código.
const api = vi.hoisted(() => ({ quemPodeReceber: vi.fn(), passar: vi.fn() }));
vi.mock('dashboard/api/passarPara', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    name: 'Dialog',
    setup(_, { expose }) {
      expose({ open: () => {}, close: () => {} });
    },
    template: '<div><slot /><slot name="footer" /></div>',
  },
}));
vi.mock('next/avatar/Avatar.vue', () => ({
  default: { name: 'Avatar', template: '<span />' },
}));

const { default: PassarParaButton } = await import('../PassarParaButton.vue');

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const ANA = { id: 7, name: 'Ana Souza', thumbnail: '' };
const BRUNO = { id: 8, name: 'Bruno Lima', thumbnail: '' };

const retrato = (extra = {}) => ({
  fase2: true,
  sem_robo: false,
  agentes: [{ id: 4, name: 'Lia', com_a_conversa: false }],
  com_ia: null,
  origem: null,
  ...extra,
});

const COM_A_LIA = {
  assignee: { id: 90, name: 'Lia' },
  assignee_type: 'AgentBot',
};

const montar = (
  meta = { assignee: ANA, assignee_type: 'User' },
  { fase2 = true } = {}
) => {
  const store = createStore({
    getters: {
      getCurrentUser: () => ANA,
      getCurrentAccountId: () => 1,
      'accounts/getAccount': () => () => ({ autonomia_agents_fase2: fase2 }),
      'inboxAssignableAgents/getAssignableAgents': () => () => [ANA, BRUNO],
    },
    actions: {
      'inboxAssignableAgents/fetch': () => {},
      setCurrentChatAssignee: vi.fn(),
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: enCrm },
  });
  return mount(PassarParaButton, {
    props: { conversation: { id: 31, inbox_id: 2, meta } },
    global: { plugins: [store, i18n] },
  });
};

describe('PassarParaButton', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.quemPodeReceber.mockResolvedValue({ data: retrato() });
  });

  it('sem a Fase 2 na conta: nem botão nem pedido ao servidor', async () => {
    // Arrange / Act
    const wrapper = montar(COM_A_LIA, { fase2: false });
    await flushPromises();

    // Assert
    expect(wrapper.find('[data-passar-para]').exists()).toBe(false);
    expect(api.quemPodeReceber).not.toHaveBeenCalled();
  });

  it('abrir a conversa não pede nada ao servidor, nem com um robô nela', async () => {
    // Arrange / Act
    const wrapper = montar(COM_A_LIA);
    await flushPromises();

    // Assert
    expect(wrapper.find('[data-passar-para]').exists()).toBe(true);
    expect(api.quemPodeReceber).not.toHaveBeenCalled();
    expect(wrapper.find('[data-com-ia]').exists()).toBe(false);
  });

  it('com a Lia na conversa: selo "passed by" e "Give back to" no topo', async () => {
    // Arrange
    api.quemPodeReceber.mockResolvedValue({
      data: retrato({
        com_ia: { id: 4, name: 'Lia' },
        origem: {
          tipo: 'pessoa',
          id: 7,
          name: 'Ana Souza',
          pode_receber: true,
        },
        agentes: [{ id: 4, name: 'Lia', com_a_conversa: true }],
      }),
    });

    // Act
    const wrapper = montar(COM_A_LIA);
    await flushPromises();
    await wrapper.find('[data-passar-para]').trigger('click');
    await flushPromises();

    // Assert
    expect(wrapper.find('[data-com-ia]').text()).toContain(
      'With Lia · passed by Ana'
    );
    expect(wrapper.find('[data-devolver]').text()).toContain(
      'Give back to Ana'
    );
    expect(wrapper.findAll('[data-opcao-pessoa]')).toHaveLength(1);
  });

  it('origem que não pode mais receber: sem "Give back to"', async () => {
    // Arrange
    api.quemPodeReceber.mockResolvedValue({
      data: retrato({
        com_ia: { id: 4, name: 'Lia' },
        origem: {
          tipo: 'pessoa',
          id: 7,
          name: 'Ana Souza',
          pode_receber: false,
        },
      }),
    });

    // Act
    const wrapper = montar(COM_A_LIA);
    await wrapper.find('[data-passar-para]').trigger('click');
    await flushPromises();

    // Assert
    expect(wrapper.find('[data-devolver]').exists()).toBe(false);
  });

  it('passada por robô de outro sistema: "external agent", sem "Give back to"', async () => {
    // Arrange
    api.quemPodeReceber.mockResolvedValue({
      data: retrato({
        com_ia: { id: 4, name: 'Lia' },
        origem: {
          tipo: 'ia',
          classe: 'AgentBot',
          id: 3,
          name: 'Gabriela',
          pode_receber: false,
        },
      }),
    });

    // Act
    const wrapper = montar(COM_A_LIA);
    await wrapper.find('[data-passar-para]').trigger('click');
    await flushPromises();

    // Assert
    expect(wrapper.find('[data-com-ia]').text()).toContain(
      'With Lia · passed by external agent Gabriela'
    );
    expect(wrapper.find('[data-devolver]').exists()).toBe(false);
  });

  it('passa para a Lia com tipo "ia" e o id do agente', async () => {
    // Arrange
    api.passar.mockResolvedValue({
      data: retrato({ com_ia: { id: 4, name: 'Lia' } }),
    });
    const wrapper = montar();
    await wrapper.find('[data-passar-para]').trigger('click');
    await flushPromises();

    // Act
    await wrapper.find('[data-opcao-ia] input').setValue(true);
    await wrapper.find('[data-confirmar]').trigger('click');
    await flushPromises();

    // Assert
    expect(api.passar).toHaveBeenCalledWith(31, { tipo: 'ia', id: 4 });
    expect(wrapper.find('[data-com-ia]').text()).toContain('Lia');
  });

  it('recusa do servidor vira a frase do código', async () => {
    // Arrange
    api.passar.mockRejectedValue({
      response: { data: { codigo: 'nao_atende_cliente' } },
    });
    const wrapper = montar();
    await wrapper.find('[data-passar-para]').trigger('click');
    await flushPromises();

    // Act
    await wrapper.find('[data-opcao-ia] input').setValue(true);
    await wrapper.find('[data-confirmar]').trigger('click');
    await flushPromises();

    // Assert
    expect(wrapper.find('[data-recusa]').text()).toBe(
      'Lia is paused. Choose another person or another agent.'
    );
  });

  it('código desconhecido: a frase genérica', async () => {
    // Arrange
    api.passar.mockRejectedValue(new Error('rede'));
    const wrapper = montar();
    await wrapper.find('[data-passar-para]').trigger('click');
    await flushPromises();

    // Act
    await wrapper.findAll('[data-opcao-pessoa] input')[1].setValue(true);
    await wrapper.find('[data-confirmar]').trigger('click');
    await flushPromises();

    // Assert
    expect(wrapper.find('[data-recusa]').text()).toBe(
      'Could not pass it right now. Try again.'
    );
  });
});
