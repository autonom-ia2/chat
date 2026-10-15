import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { computed, reactive } from 'vue';
import BotConfiguration from '../BotConfiguration.vue';
import QuemAtendeAPI from 'dashboard/api/autonomia/quemAtende';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/agents.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/agents.json';

// #1648 — a aba "Agente externo" da caixa: A1 caixa com principal e equipe,
// A2 caixa só com agente da equipe, A3 caixa sem agente da plataforma.
const estado = reactive({});
const dispatch = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch,
    getters: new Proxy({}, { get: (_alvo, nome) => estado[nome] }),
  }),
  useMapGetter: nome => computed(() => estado[nome]),
}));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref } = await import('vue');
  return { useCanManage: () => ref(true) };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomia/quemAtende', () => ({
  default: { daCaixa: vi.fn() },
}));

const BOTS = [
  { id: 31, name: 'Automação Vendas' },
  { id: 32, name: 'Atendimento Parceiro' },
];

const render = async (agentes, ativo = undefined) => {
  Object.assign(estado, {
    'agentBots/getBots': BOTS,
    'agentBots/getUIFlags': { isFetching: false, isFetchingAgentBot: false },
    'agentBots/getActiveAgentBot': () => ativo,
    getCurrentAccountId: 1,
  });
  QuemAtendeAPI.daCaixa.mockResolvedValue({ data: { agentes } });
  const wrapper = mount(BotConfiguration, {
    props: { inbox: { id: 10, name: 'WhatsApp Vendas' } },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          fallbackLocale: false,
          messages: { en: { ...en }, pt_BR: { ...pt_BR } },
        }),
      ],
      stubs: { 'router-link': { template: '<a><slot /></a>' } },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('BotConfiguration', () => {
  beforeEach(() => {
    dispatch.mockReset();
    QuemAtendeAPI.daCaixa.mockReset();
    useAlert.mockReset();
  });

  it('reads who serves the inbox from its own endpoint', async () => {
    await render([]);

    expect(QuemAtendeAPI.daCaixa).toHaveBeenCalledWith(10);
  });

  it('A1: main and team agents lock the choice with the reason', async () => {
    const wrapper = await render([
      { id: 3, name: 'Sofia', papel: 'porta' },
      { id: 7, name: 'Bia', papel: 'area' },
    ]);

    expect(wrapper.find('[data-caixa-da-plataforma]').exists()).toBe(true);
    expect(wrapper.find('[data-caixa-livre]').exists()).toBe(false);
    const linhas = wrapper.findAll('[data-agente-da-caixa]');
    expect(linhas.map(item => item.find('span + div > span').text())).toEqual([
      'Sofia atende primeiro',
      'Bia recebe quando alguém passar',
    ]);
    expect(linhas.map(item => item.find('[data-abrir-agente]').text())).toEqual(
      ['Abrir agente', 'Abrir agente']
    );
    expect(wrapper.find('[data-motivo]').text()).toBe(
      pt_BR.AGENTS.CAIXA_EXTERNO.TRAVADO_TUDO
    );
    expect(wrapper.find('[role="combobox"]').attributes()).toHaveProperty(
      'disabled'
    );
  });

  it('A2: only a team agent locks the choice with its own reason', async () => {
    const wrapper = await render([{ id: 7, name: 'Bia', papel: 'area' }]);

    expect(wrapper.findAll('[data-agente-da-caixa]')).toHaveLength(1);
    expect(wrapper.find('[data-motivo]').text()).toBe(
      pt_BR.AGENTS.CAIXA_EXTERNO.TRAVADO_EQUIPE
    );
  });

  it('A3: an inbox without platform agents chooses among external agents', async () => {
    const wrapper = await render([], BOTS[0]);

    expect(wrapper.find('[data-caixa-da-plataforma]').exists()).toBe(false);
    expect(wrapper.find('[data-caixa-livre]').exists()).toBe(true);
    expect(wrapper.find('[role="combobox"]').text()).toContain(
      'Automação Vendas'
    );
    expect(wrapper.find('select').exists()).toBe(false);

    await wrapper.find('form').trigger('submit');

    expect(dispatch).toHaveBeenCalledWith('agentBots/setAgentBotInbox', {
      inboxId: 10,
      botId: 31,
    });
  });

  it('a refused save (422) alerts the lock reason, never "try again"', async () => {
    const wrapper = await render([], BOTS[0]);
    dispatch.mockImplementation(async acao => {
      if (acao === 'agentBots/setAgentBotInbox') throw new Error('recusado');
    });
    QuemAtendeAPI.daCaixa.mockResolvedValue({
      data: { agentes: [{ id: 3, name: 'Sofia', papel: 'porta' }] },
    });

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.find('[data-motivo]').text()).toBe(
      pt_BR.AGENTS.CAIXA_EXTERNO.TRAVADO_PRINCIPAL
    );
    expect(useAlert).toHaveBeenCalledWith(
      pt_BR.AGENTS.CAIXA_EXTERNO.TRAVADO_PRINCIPAL
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      pt_BR.AGENTS.CAIXA_EXTERNO.FALHOU
    );
  });

  it('a failed save on a still free inbox keeps the generic message', async () => {
    const wrapper = await render([], BOTS[0]);
    dispatch.mockImplementation(async acao => {
      if (acao === 'agentBots/setAgentBotInbox') throw new Error('rede');
    });

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(pt_BR.AGENTS.CAIXA_EXTERNO.FALHOU);
    expect(wrapper.find('[data-caixa-livre]').exists()).toBe(true);
  });

  it('a refused disconnect (422) alerts the lock reason', async () => {
    const wrapper = await render([], BOTS[0]);
    dispatch.mockImplementation(async acao => {
      if (acao === 'agentBots/disconnectBot') throw new Error('recusado');
    });
    QuemAtendeAPI.daCaixa.mockResolvedValue({
      data: { agentes: [{ id: 7, name: 'Bia', papel: 'area' }] },
    });

    await wrapper.find('[data-desconectar]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      pt_BR.AGENTS.CAIXA_EXTERNO.TRAVADO_EQUIPE
    );
  });

  it('a failed read keeps the choice locked with "Try again", never the free inbox', async () => {
    QuemAtendeAPI.daCaixa.mockRejectedValueOnce(new Error('500'));
    const wrapper = await render([], BOTS[0]);

    expect(wrapper.find('[data-erro-de-leitura]').exists()).toBe(true);
    expect(wrapper.find('[data-caixa-livre]').exists()).toBe(false);
    expect(wrapper.find('[role="alert"]').text()).toBe(
      pt_BR.AGENTS.CAIXA_EXTERNO.ERRO_LEITURA
    );
    expect(wrapper.find('[role="combobox"]').attributes()).toHaveProperty(
      'disabled'
    );

    await wrapper.find('[data-tentar-de-novo]').trigger('click');
    await flushPromises();

    expect(QuemAtendeAPI.daCaixa).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-erro-de-leitura]').exists()).toBe(false);
    expect(wrapper.find('[data-caixa-livre]').exists()).toBe(true);
  });
});
