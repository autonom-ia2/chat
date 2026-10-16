import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import AgenteOutroSistemaPage from '../pages/AgenteOutroSistemaPage.vue';
import AgenteConectarPage from '../pages/AgenteConectarPage.vue';
import GavetaAlterarOutro from '../components/GavetaAlterarOutro.vue';
import AgentBotsAPI from 'dashboard/api/agentBots';

// #1648 — agente de outro sistema (AgentBot webhook) na jornada de Agentes: a
// página dele (no padrão das nossas), a gaveta "Alterar" e "Conectar agente de
// outro sistema" em página inteira, em três etapas.
const estado = vi.hoisted(() => ({ admin: true }));
const store = vi.hoisted(() => ({ dispatch: vi.fn(), state: null }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => computed(() => store.state[nome]),
  };
});
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => estado.admin) }) };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
const router = vi.hoisted(() => ({
  push: vi.fn(),
  resolve: vi.fn(rota => ({ href: `/app/${rota.name}` })),
}));
vi.mock('vue-router', () => ({ useRouter: () => router }));
const jornada = vi.hoisted(() => ({ canaisOcupados: vi.fn() }));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: jornada }));
vi.mock('dashboard/api/agentBots', () => ({ default: { show: vi.fn() } }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(),
}));

const BOT = {
  id: 31,
  name: 'Automação Vendas',
  description: 'Responde dúvidas de preço.',
  outgoing_url: 'https://automacao.example.com/hook',
  access_token: 'chave-de-teste',
  thumbnail: '',
  system_bot: false,
};

const prepararStore = (bots = [BOT]) => {
  store.state = reactive({ 'agentBots/getBots': [] });
  store.dispatch.mockImplementation(async acao => {
    if (acao === 'agentBots/get') store.state['agentBots/getBots'] = bots;
    if (acao === 'agentBots/create') return { id: 40, access_token: 'nova' };
    return null;
  });
};

const ocupacao = canais =>
  jornada.canaisOcupados.mockResolvedValue({ data: { payload: canais } });

const montarPagina = async (botId = '31') => {
  const wrapper = mount(AgenteOutroSistemaPage, {
    props: { botId },
    attachTo: document.body,
    global: {
      stubs: {
        teleport: true,
        'router-link': {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('agente de outro sistema', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  beforeEach(() => {
    vi.useRealTimers();
    estado.admin = true;
    prepararStore();
    alerta.mockReset();
    router.push.mockReset();
    AgentBotsAPI.show.mockReset();
    ocupacao([
      {
        inbox_id: 14,
        name: 'WhatsApp Parceiro',
        occupied_by: { kind: 'external', agent_bot_id: 31, operating: true },
      },
      {
        inbox_id: 15,
        name: 'Site',
        occupied_by: { kind: 'external', agent_bot_id: 31, operating: false },
      },
      {
        inbox_id: 10,
        name: 'WhatsApp Vendas',
        occupied_by: { kind: 'agent', agent_id: 31, agent_name: 'Sofia' },
      },
    ]);
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe('AgenteOutroSistemaPage', () => {
    it('shows what it does, how it connects, the key and where it answers first', async () => {
      const wrapper = await montarPagina();

      expect(wrapper.get('[data-heroi]').text()).toContain('Automação Vendas');
      expect(wrapper.get('[data-linha="faz"]').text()).toContain(
        'Responde dúvidas de preço.'
      );
      expect(wrapper.get('[data-endereco]').text()).toBe(
        'https://automacao.example.com/hook'
      );
      expect(wrapper.find('[data-chave]').exists()).toBe(true);
      const canais = wrapper.findAll('[data-canal]');
      expect(canais.map(c => c.text())).toEqual([
        expect.stringContaining('WhatsApp Parceiro'),
      ]);
      expect(JSON.parse(canais[0].get('a').attributes('data-to'))).toEqual({
        name: 'settings_inbox_show',
        params: { inboxId: 14, tab: 'bot-configuration' },
      });
    });

    it('without an active inbox it is stopped and says so', async () => {
      ocupacao([]);
      const wrapper = await montarPagina();

      expect(wrapper.find('[data-canal]').exists()).toBe(false);
      expect(wrapper.get('[data-linha="onde"]').text()).toContain(
        'AGENTS.OUTRO_SISTEMA.PAGINA.ONDE_NENHUM'
      );
    });

    it('who is not an administrator sees it, but no key and nothing to change', async () => {
      estado.admin = false;
      const wrapper = await montarPagina();

      expect(wrapper.find('[data-chave]').exists()).toBe(false);
      expect(wrapper.find('[data-alterar]').exists()).toBe(false);
      expect(wrapper.find('[data-mais]').exists()).toBe(false);
    });

    it('goes back to the list when the agent does not exist (deleted, other account or a mirror)', async () => {
      AgentBotsAPI.show.mockRejectedValue({ response: { status: 404 } });
      const wrapper = await montarPagina('99');

      expect(AgentBotsAPI.show).toHaveBeenCalledWith('99');
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_index',
      });
      wrapper.unmount();
    });

    it('never shows a read error: keeps loading and tries again', async () => {
      vi.useFakeTimers();
      prepararStore([]);
      AgentBotsAPI.show.mockRejectedValueOnce(new Error('rede'));
      const wrapper = await montarPagina();

      expect(wrapper.find('[data-esqueleto]').exists()).toBe(true);
      store.dispatch.mockImplementation(async acao => {
        if (acao === 'agentBots/get') store.state['agentBots/getBots'] = [BOT];
      });
      await vi.advanceTimersByTimeAsync(3000);
      await flushPromises();

      expect(wrapper.get('[data-heroi]').text()).toContain('Automação Vendas');
      expect(router.push).not.toHaveBeenCalled();
      wrapper.unmount();
    });

    it('a system bot is not an agent of the account: back to the list', async () => {
      prepararStore([{ ...BOT, system_bot: true }]);
      AgentBotsAPI.show.mockResolvedValue({ data: { system_bot: true } });
      const wrapper = await montarPagina();

      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_index',
      });
      wrapper.unmount();
    });

    it('deletes from the "more" menu and goes back to the list', async () => {
      const wrapper = await montarPagina();

      await wrapper.get('[data-mais]').trigger('click');
      await wrapper.get('[data-item="apagar"]').trigger('click');
      await wrapper.get('[data-confirmar]').trigger('click');
      await flushPromises();

      expect(store.dispatch).toHaveBeenCalledWith('agentBots/delete', 31);
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_index',
      });
    });
  });

  describe('GavetaAlterarOutro', () => {
    const montarGaveta = campo =>
      mount(GavetaAlterarOutro, {
        props: { agente: BOT, campo },
        attachTo: document.body,
        global: { stubs: { teleport: true } },
      });

    it('saves the section field and keeps the others as they are', async () => {
      const wrapper = montarGaveta('conexao');
      await wrapper
        .get('#outro-endereco')
        .setValue('https://novo.example.com/hook');
      await wrapper.get('form').trigger('submit');
      await flushPromises();

      expect(store.dispatch).toHaveBeenCalledWith('agentBots/update', {
        id: 31,
        data: {
          name: 'Automação Vendas',
          description: 'Responde dúvidas de preço.',
          outgoing_url: 'https://novo.example.com/hook',
          avatar: null,
        },
      });
      expect(wrapper.emitted('fechar')).toBeTruthy();
    });

    it('does not save an empty name, and warns when saving fails', async () => {
      const wrapper = montarGaveta('nome-foto');
      await wrapper.get('#outro-nome').setValue('  ');
      await wrapper.get('form').trigger('submit');
      expect(store.dispatch).not.toHaveBeenCalledWith(
        'agentBots/update',
        expect.anything()
      );

      store.dispatch.mockRejectedValueOnce(new Error('422'));
      await wrapper.get('#outro-nome').setValue('Novo nome');
      await wrapper.get('form').trigger('submit');
      await flushPromises();

      expect(alerta).toHaveBeenCalledWith('AGENTS.OUTRO_SISTEMA.SALVAR_ERRO');
      expect(wrapper.emitted('fechar')).toBeFalsy();
    });
  });

  describe('AgenteConectarPage', () => {
    const montarConectar = async () => {
      const wrapper = mount(AgenteConectarPage, { attachTo: document.body });
      await flushPromises();
      return wrapper;
    };

    it('connects in three steps: who, address, then the key, and opens the agent page', async () => {
      const wrapper = await montarConectar();

      expect(wrapper.get('[data-continuar]').attributes('disabled')).toBe('');
      await wrapper.get('#conectar-nome').setValue('Automação Pós-venda');
      await wrapper.get('#conectar-descricao').setValue('Pós-venda.');
      await wrapper.get('[data-continuar]').trigger('click');
      await flushPromises();

      expect(wrapper.find('#conectar-endereco').exists()).toBe(true);
      await wrapper
        .get('#conectar-endereco')
        .setValue('https://automacao.example.com/pos-venda');
      await wrapper.get('[data-conectar]').trigger('click');
      await flushPromises();

      expect(store.dispatch).toHaveBeenCalledWith('agentBots/create', {
        name: 'Automação Pós-venda',
        description: 'Pós-venda.',
        outgoing_url: 'https://automacao.example.com/pos-venda',
        bot_type: 'webhook',
        avatar: null,
      });
      expect(wrapper.get('[data-chave]').text()).not.toContain('nova');
      expect(wrapper.find('[data-voltar-lista]').exists()).toBe(false);

      await wrapper.get('[data-concluir]').trigger('click');
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agent_panel',
        params: { agentId: 40 },
        query: { origem: 'webhook' },
      });
    });

    it('stays on the address step and warns when connecting fails', async () => {
      store.dispatch.mockRejectedValueOnce(new Error('422'));
      const wrapper = await montarConectar();
      await wrapper.get('#conectar-nome').setValue('Automação');
      await wrapper.get('[data-continuar]').trigger('click');
      await flushPromises();
      await wrapper.get('#conectar-endereco').setValue('https://x.example.com');
      await wrapper.get('[data-conectar]').trigger('click');
      await flushPromises();

      expect(alerta).toHaveBeenCalledWith(
        'AGENTS.OUTRO_SISTEMA.CONECTAR_PAGINA.ERRO'
      );
      expect(wrapper.find('#conectar-endereco').exists()).toBe(true);
    });

    it('goes back to the list from the first step', async () => {
      const wrapper = await montarConectar();
      await wrapper.get('[data-voltar-lista]').trigger('click');

      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_index',
      });
    });
  });
});
