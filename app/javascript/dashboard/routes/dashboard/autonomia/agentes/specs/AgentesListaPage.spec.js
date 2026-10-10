import { reactive, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgentesListaPage from '../pages/AgentesListaPage.vue';

const estado = vi.hoisted(() => ({
  podeGerenciar: true,
  podeConectarCanal: true,
}));

const store = vi.hoisted(() => ({ dispatch: vi.fn(), state: null }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => computed(() => store.state[nome]),
  };
});
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => estado.podeGerenciar) };
});
vi.mock('../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => estado.podeConectarCanal),
      podeEscolherQuemRecebe: computed(() => true),
      crmLigado: computed(() => true),
    }),
  };
});

const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const router = vi.hoisted(() => ({
  push: vi.fn(),
  resolve: vi.fn(rota => ({ href: `/app/${rota.name}` })),
}));
vi.mock('vue-router', () => ({ useRouter: () => router }));

const api = vi.hoisted(() => ({ semana: vi.fn(), canaisOcupados: vi.fn() }));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: api }));

const agente = (id, extra = {}) => ({
  id,
  name: `Agente ${id}`,
  status: 'active',
  enabled: true,
  agent_type: 'support',
  actuation: 'external',
  channels_count: 1,
  ...extra,
});

const AGENTES = [
  agente(1, { status: 'draft', name: 'Rascunho' }),
  agente(2, { status: 'paused', name: 'Leo' }),
  agente(3, { name: 'Bia' }),
];

// O get do autonomiaAgents enche a lista da store, como a factory faz.
const prepararStore = ({ agentes = AGENTES, falhaGet = false } = {}) => {
  store.state = reactive({
    'autonomiaAgents/getRecords': [],
    'autonomiaAgents/getUIFlags': { fetchingList: false },
    'inboxes/getInboxes': [{ id: 10 }],
  });
  store.dispatch.mockImplementation(async acao => {
    if (acao === 'autonomiaAgents/get') {
      if (falhaGet) throw new Error('500');
      store.state['autonomiaAgents/getRecords'] = agentes;
    }
    if (acao === 'autonomiaAgents/delete') return null;
    return null;
  });
};

const montar = async () => {
  const wrapper = mount(AgentesListaPage, { attachTo: document.body });
  await flushPromises();
  return wrapper;
};

const textoDosBotoes = wrapper => wrapper.findAll('button').map(b => b.text());

describe('AgentesListaPage', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  beforeEach(() => {
    vi.useRealTimers();
    estado.podeGerenciar = true;
    estado.podeConectarCanal = true;
    prepararStore();
    api.semana.mockResolvedValue({
      data: { payload: [{ agent_id: 3, answered: 12, handed: 3 }] },
    });
    api.canaisOcupados.mockResolvedValue({
      data: {
        payload: [
          {
            inbox_id: 10,
            name: 'WhatsApp do Centro',
            occupied_by: { kind: 'agent', agent_id: 3, agent_name: 'Bia' },
          },
        ],
      },
    });
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe('T02 · lista com agentes', () => {
    it('orders the cards: answering, stopped, then not finished', async () => {
      const wrapper = await montar();
      const nomes = wrapper.findAll('[data-cartao] h2').map(n => n.text());
      expect(nomes).toEqual(['Bia', 'Leo', 'Rascunho']);
      wrapper.unmount();
    });

    it('has a single navy block, the compact hero with the counts', async () => {
      const wrapper = await montar();
      expect(wrapper.findAll('[data-heroi]')).toHaveLength(1);
      expect(wrapper.get('h1').text()).toBe('AGENTS.JORNADA.LISTA.TITULO');
      expect(wrapper.get('[data-contagem]').text()).toContain(
        'AGENTS.JORNADA.LISTA.CONTAGEM_ATENDENDO'
      );
      wrapper.unmount();
    });

    it('reads the week numbers and the inbox names once', async () => {
      const wrapper = await montar();
      expect(api.semana).toHaveBeenCalledTimes(1);
      expect(api.canaisOcupados).toHaveBeenCalledTimes(1);
      expect(wrapper.find('[data-semana]').exists()).toBe(true);
      expect(wrapper.get('[data-onde]').text()).toBe(
        'AGENTS.JORNADA.CARTAO.ONDE_CANAL'
      );
      wrapper.unmount();
    });

    it('drops the week line when the numbers cannot be read (t02-semnumeros)', async () => {
      api.semana.mockRejectedValue(new Error('500'));
      const wrapper = await montar();
      expect(wrapper.find('[data-semana]').exists()).toBe(false);
      expect(wrapper.find('[data-cartao]').exists()).toBe(true);
      wrapper.unmount();
    });

    it('counts the inboxes when their names cannot be read (t02-semnomecanal)', async () => {
      api.canaisOcupados.mockRejectedValue(new Error('500'));
      const wrapper = await montar();
      expect(wrapper.get('[data-onde]').text()).toBe(
        'AGENTS.JORNADA.CARTAO.ONDE_N_CANAIS'
      );
      wrapper.unmount();
    });

    it('opens the agent page from the card', async () => {
      const wrapper = await montar();
      await wrapper.get('[data-abrir]').trigger('click');
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agent_panel',
        params: { agentId: 3 },
      });
      wrapper.unmount();
    });

    it('continues a draft in the builder', async () => {
      const wrapper = await montar();
      await wrapper.get('[data-continuar]').trigger('click');
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_builder',
        query: { agente: 1 },
      });
      wrapper.unmount();
    });

    it('deletes a draft only after the confirmation', async () => {
      const wrapper = await montar();
      await wrapper.get('[aria-haspopup="menu"]').trigger('click');
      await wrapper.get('[role="menuitem"]').trigger('click');
      expect(store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaAgents/delete',
        1
      );

      const confirmar = [
        ...document.body.querySelectorAll('[data-botoes] button'),
      ].pop();
      confirmar.click();
      await flushPromises();

      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/delete', 1);
      expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.EXCLUIR.FEITO');
      wrapper.unmount();
    });

    it('says nothing changed when the delete fails', async () => {
      const wrapper = await montar();
      store.dispatch.mockRejectedValueOnce(new Error('500'));
      await wrapper.get('[aria-haspopup="menu"]').trigger('click');
      await wrapper.get('[role="menuitem"]').trigger('click');
      [...document.body.querySelectorAll('[data-botoes] button')].pop().click();
      await flushPromises();

      expect(alerta).toHaveBeenCalledWith(
        'AGENTS.JORNADA.ERRO.EXCLUIR AGENTS.JORNADA.ERRO.EXCLUIR_GARANTIA'
      );
      wrapper.unmount();
    });

    it('opens the templates drawer from "Criar agente" and "Ver modelos prontos"', async () => {
      const wrapper = await montar();
      await wrapper.get('[data-criar]').trigger('click');
      await nextTick();
      // A gaveta vai para o body (TeleportWithDirection).
      let gaveta = document.querySelector('[role="dialog"]');
      expect(gaveta.textContent).toContain('AGENTS.JORNADA.MENU.CRIAR_AGENTE');
      expect(gaveta.querySelectorAll('[data-usar]')).toHaveLength(3);
      gaveta.querySelector('[data-fechar]').click();
      await nextTick();
      expect(document.querySelector('[role="dialog"]')).toBeNull();

      await wrapper.get('[data-ver-modelos]').trigger('click');
      await nextTick();
      gaveta = document.querySelector('[role="dialog"]');
      expect(gaveta.textContent).toContain('AGENTS.JORNADA.MODELOS.ROTULO');
      wrapper.unmount();
    });

    it('shows a view only seat the list without any writing action', async () => {
      estado.podeGerenciar = false;
      const wrapper = await montar();
      expect(wrapper.find('[data-criar]').exists()).toBe(false);
      expect(wrapper.find('[data-ver-modelos]').exists()).toBe(false);
      expect(wrapper.find('[data-continuar]').exists()).toBe(false);
      expect(wrapper.find('[aria-haspopup="menu"]').exists()).toBe(false);
      expect(wrapper.text()).toContain('AGENTS.JORNADA.LISTA.SO_VER');
      // Abrir o agente continua (ver e testar).
      expect(wrapper.find('[data-abrir]').exists()).toBe(true);
      wrapper.unmount();
    });
  });

  describe('carregando e erro', () => {
    it('announces the loading and shows placeholders (t02-carregando)', async () => {
      store.dispatch.mockImplementation(() => new Promise(() => {}));
      const wrapper = mount(AgentesListaPage);
      await nextTick();
      expect(wrapper.get('[role="status"]').text()).toBe(
        'AGENTS.JORNADA.LISTA.CARREGANDO'
      );
      expect(wrapper.findAll('[data-esqueleto]').length).toBeGreaterThan(0);
      expect(wrapper.find('[data-contagem]').exists()).toBe(false);
      wrapper.unmount();
    });

    it('shows the error card with the guarantee and retries (t02-erro)', async () => {
      vi.useFakeTimers();
      prepararStore({ falhaGet: true });
      const wrapper = mount(AgentesListaPage);
      await vi.runAllTimersAsync();

      const erro = wrapper.get('[role="alert"]');
      expect(erro.text()).toContain('AGENTS.JORNADA.ERRO.LISTA');
      expect(erro.text()).toContain('AGENTS.JORNADA.ERRO.LISTA_GARANTIA');
      expect(wrapper.find('[data-cartao]').exists()).toBe(false);

      prepararStore();
      await erro.get('button').trigger('click');
      await vi.runAllTimersAsync();
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
      expect(wrapper.findAll('[data-cartao]')).toHaveLength(3);
      wrapper.unmount();
    });
  });

  describe('T01 · lista vazia', () => {
    beforeEach(() => prepararStore({ agentes: [] }));

    it('shows the big hero with three templates and "Do meu jeito"', async () => {
      const wrapper = await montar();
      expect(wrapper.findAll('[data-heroi]')).toHaveLength(1);
      expect(wrapper.get('h1').text()).toBe('AGENTS.JORNADA.HEROI.TITULO');
      expect(wrapper.text()).toContain('AGENTS.JORNADA.MODELOS.ESCOLHA');
      expect(wrapper.findAll('[data-usar]')).toHaveLength(3);
      expect(wrapper.find('[data-do-meu-jeito]').exists()).toBe(true);
      expect(wrapper.find('[data-sem-canal]').exists()).toBe(false);
      wrapper.unmount();
    });

    it('goes to the builder with the chosen template', async () => {
      const wrapper = await montar();
      await wrapper.findAll('[data-usar]')[1].trigger('click');
      await flushPromises();
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_builder',
        query: { modelo: 'sdr' },
      });

      await wrapper.get('[data-do-meu-jeito]').trigger('click');
      expect(router.push).toHaveBeenLastCalledWith({
        name: 'autonomia_agents_builder',
        query: { modelo: 'custom' },
      });
      wrapper.unmount();
    });

    it('shows the failure under the template when it cannot start (t01-falha)', async () => {
      router.push.mockRejectedValueOnce(new Error('falhou'));
      const wrapper = await montar();
      await wrapper.findAll('[data-usar]')[0].trigger('click');
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toContain(
        'AGENTS.JORNADA.ERRO.COMECAR_MODELO_GARANTIA'
      );
      wrapper.unmount();
    });

    it('warns about the missing channel without blocking (t01-semcanal)', async () => {
      store.state['inboxes/getInboxes'] = [];
      const wrapper = await montar();
      const aviso = wrapper.get('[data-sem-canal]');
      expect(aviso.text()).toContain('AGENTS.JORNADA.HEROI.SEM_CANAL');
      expect(aviso.get('a').attributes('href')).toBe('/app/settings_inbox_new');
      expect(wrapper.findAll('[data-usar]')).toHaveLength(3);
      wrapper.unmount();
    });

    it('asks for an administrator when the seat cannot connect a channel', async () => {
      store.state['inboxes/getInboxes'] = [];
      estado.podeConectarCanal = false;
      const wrapper = await montar();
      const aviso = wrapper.get('[data-sem-canal]');
      expect(aviso.find('a').exists()).toBe(false);
      expect(aviso.text()).toContain(
        'AGENTS.JORNADA.HEROI.SEM_CANAL_SEM_PERMISSAO'
      );
      wrapper.unmount();
    });

    it('explains the screen to a view only seat, without templates to use', async () => {
      estado.podeGerenciar = false;
      const wrapper = await montar();
      expect(wrapper.text()).toContain('AGENTS.JORNADA.HEROI.SO_VER');
      expect(wrapper.find('[data-usar]').exists()).toBe(false);
      expect(wrapper.find('[data-do-meu-jeito]').exists()).toBe(false);
      expect(textoDosBotoes(wrapper)).toEqual([]);
      wrapper.unmount();
    });
  });

  it('never renders a native select nor the brand color with white text', async () => {
    const wrapper = await montar();
    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.html()).not.toContain('bg-n-brand');
    wrapper.unmount();
  });
});
