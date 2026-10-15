import { reactive, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgentesListaPage from '../pages/AgentesListaPage.vue';

const estado = vi.hoisted(() => ({
  podeGerenciar: true,
  podeConectarCanal: true,
  admin: true,
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
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => estado.admin) }) };
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
    estado.admin = true;
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

    it('counts helpers apart and shows them as "Ajudando" with who they help (tema 14)', async () => {
      prepararStore({
        agentes: [
          ...AGENTES,
          agente(6, {
            name: 'Duda',
            actuation: 'internal',
            channels_count: 0,
            tem_onde_trabalhar: true,
            ajudante: true,
            ajuda: [{ id: 3, name: 'Bia' }],
          }),
        ],
      });
      const wrapper = await montar();
      expect(wrapper.get('[data-contagem]').text()).toContain(
        'AGENTS.JORNADA.LISTA.CONTAGEM_AJUDANDO'
      );
      const nomes = wrapper.findAll('[data-cartao] h2').map(n => n.text());
      expect(nomes).toEqual(['Bia', 'Duda', 'Leo', 'Rascunho']);
      const cartao = wrapper.findAll('[data-cartao]')[1];
      expect(cartao.text()).toContain('AGENTS.JORNADA.STATUS.AJUDANDO');
      expect(cartao.get('[data-ajuda]').text()).toBe(
        'AGENTS.JORNADA.ONDE.AJUDA'
      );
      wrapper.unmount();
    });

    it('has no helper count when there is no helper', async () => {
      const wrapper = await montar();
      expect(wrapper.get('[data-contagem]').text()).not.toContain(
        'CONTAGEM_AJUDANDO'
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

    it('shows the external agent with the photo of its inbox, and the others with their own', async () => {
      prepararStore({
        agentes: [
          agente(3, { name: 'Bia', avatar_url: 'https://x/propria.png' }),
          agente(4, {
            name: 'Copiloto',
            actuation: 'internal',
            channels_count: 0,
            avatar_url: 'https://x/copiloto.png',
          }),
        ],
      });
      store.state['inboxes/getInboxes'] = [
        { id: 10, avatar_url: 'https://x/whats.png' },
      ];
      const wrapper = await montar();
      const fotos = wrapper
        .findAll('[data-cartao] [data-avatar] img')
        .map(img => img.attributes('src'));
      expect(fotos).toEqual(['https://x/whats.png', 'https://x/copiloto.png']);
      wrapper.unmount();
    });

    it('keeps the own photo on the card when the inbox names cannot be read', async () => {
      prepararStore({
        agentes: [
          agente(3, { name: 'Bia', avatar_url: 'https://x/propria.png' }),
        ],
      });
      store.state['inboxes/getInboxes'] = [
        { id: 10, avatar_url: 'https://x/whats.png' },
      ];
      api.canaisOcupados.mockRejectedValue(new Error('500'));
      const wrapper = await montar();
      expect(
        wrapper.get('[data-cartao] [data-avatar] img').attributes('src')
      ).toBe('https://x/propria.png');
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

    // #1504 — quem saiu do Confira por "Fazer ajustes avançados" fica parado e sem canal: o cartão
    // diz "Parado" e abre a página do agente (não volta para a criação).
    it('shows an agent paused from the creation as "Parado", without inbox, opening its page', async () => {
      prepararStore({
        agentes: [
          agente(7, {
            status: 'paused',
            enabled: false,
            channels_count: 0,
            name: 'Duda',
          }),
          agente(8, {
            status: 'paused',
            enabled: false,
            channels_count: 0,
            actuation: 'internal',
            name: 'Copiloto',
          }),
        ],
      });
      const wrapper = await montar();
      const cartoes = wrapper.findAll('[data-cartao]');
      expect(cartoes).toHaveLength(2);
      cartoes.forEach(cartao => {
        expect(cartao.text()).toContain('AGENTS.JORNADA.STATUS.PARADO');
        expect(cartao.text()).not.toContain(
          'AGENTS.JORNADA.STATUS.FALTA_TERMINAR'
        );
        expect(cartao.find('[data-continuar]').exists()).toBe(false);
      });
      expect(cartoes[0].text()).toContain(
        'AGENTS.JORNADA.CARTAO.PARADO_SEM_CANAL'
      );
      expect(cartoes[1].text()).toContain('AGENTS.JORNADA.CARTAO.PARADO');
      expect(cartoes[1].text()).not.toContain('PARADO_SEM_CANAL');

      await cartoes[0].get('[data-abrir]').trigger('click');
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agent_panel',
        params: { agentId: 7 },
      });
      wrapper.unmount();
    });

    // #1525 — a cotação leva à página do agente já na escolha de canal, não ao módulo (que voltava para cá).
    it('opens the quote agent page on the channel choice', async () => {
      prepararStore({
        agentes: [
          agente(9, {
            name: 'Lia',
            agent_type: 'insurance_quote',
            status: 'paused',
            enabled: false,
            channels_count: 0,
            tem_onde_trabalhar: false,
          }),
        ],
      });
      const wrapper = await montar();
      const rota = {
        name: 'autonomia_agent_panel',
        params: { agentId: 9, tab: 'channels' },
      };
      expect(router.resolve).toHaveBeenCalledWith(rota);
      await wrapper.get('[data-abrir]').trigger('click');
      expect(router.push).toHaveBeenCalledWith(rota);
      expect(wrapper.text()).toContain(
        'AGENTS.JORNADA.CARTAO.PARADO_SEM_CANAL'
      );
      wrapper.unmount();
    });

    it('opens the quote agent page without the channel choice when it has a channel', async () => {
      prepararStore({
        agentes: [
          agente(9, {
            name: 'Lia',
            agent_type: 'insurance_quote',
            tem_onde_trabalhar: true,
          }),
        ],
      });
      const wrapper = await montar();
      await wrapper.get('[data-abrir]').trigger('click');
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agent_panel',
        params: { agentId: 9 },
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

    // #1369 — o primeiro clique em "Continuar" ou no "⋯" não respondia logo depois de abrir a lista:
    // os cartões apareciam antes da L1/L2 e cresciam quando elas chegavam, empurrando o rascunho
    // (sempre por último) para baixo do ponteiro. Agora os cartões só aparecem completos.
    it('keeps the placeholders until the week numbers and inbox names arrive (#1369)', async () => {
      let responderSemana;
      let responderCanais;
      api.semana.mockReturnValue(
        new Promise(resolve => {
          responderSemana = resolve;
        })
      );
      api.canaisOcupados.mockReturnValue(
        new Promise(resolve => {
          responderCanais = resolve;
        })
      );
      const wrapper = await montar();
      expect(wrapper.find('[data-cartao]').exists()).toBe(false);
      expect(wrapper.findAll('[data-esqueleto]').length).toBeGreaterThan(0);
      expect(wrapper.find('[data-contagem]').exists()).toBe(false);

      responderSemana({
        data: { payload: [{ agent_id: 3, answered: 12, handed: 3 }] },
      });
      await flushPromises();
      expect(wrapper.find('[data-cartao]').exists()).toBe(false);

      responderCanais({ data: { payload: [] } });
      await flushPromises();
      expect(wrapper.find('[data-esqueleto]').exists()).toBe(false);
      expect(wrapper.find('[data-semana]').exists()).toBe(true);

      // Os cartões chegam completos: o primeiro clique já age.
      await wrapper.get('[data-continuar]').trigger('click');
      expect(router.push).toHaveBeenCalledTimes(1);
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_builder',
        query: { agente: 1 },
      });
      await wrapper.get('[aria-haspopup="menu"]').trigger('click');
      expect(wrapper.find('[role="menu"]').exists()).toBe(true);
      wrapper.unmount();
    });

    it('shows "Continuar" busy while the builder loads, and ignores a second click', async () => {
      let terminar;
      router.push.mockReturnValueOnce(
        new Promise(resolve => {
          terminar = resolve;
        })
      );
      const wrapper = await montar();
      const botao = wrapper.get('[data-continuar]');
      await botao.trigger('click');
      expect(botao.attributes('aria-busy')).toBe('true');
      await botao.trigger('click');
      expect(router.push).toHaveBeenCalledTimes(1);
      terminar();
      await flushPromises();
      expect(botao.attributes('aria-busy')).toBeUndefined();
      wrapper.unmount();
    });

    it('shows the cards anyway after 2.5 s when a reading hangs, and fills them in later (#1369)', async () => {
      vi.useFakeTimers();
      let responderSemana;
      api.semana.mockReturnValue(
        new Promise(resolve => {
          responderSemana = resolve;
        })
      );
      const wrapper = mount(AgentesListaPage, { attachTo: document.body });
      await vi.advanceTimersByTimeAsync(0);
      expect(wrapper.find('[data-cartao]').exists()).toBe(false);

      await vi.advanceTimersByTimeAsync(2500);
      expect(wrapper.find('[data-esqueleto]').exists()).toBe(false);
      expect(wrapper.findAll('[data-cartao]')).toHaveLength(3);
      expect(wrapper.find('[data-semana]').exists()).toBe(false);

      responderSemana({
        data: { payload: [{ agent_id: 3, answered: 12, handed: 3 }] },
      });
      await vi.advanceTimersByTimeAsync(0);
      expect(wrapper.find('[data-semana]').exists()).toBe(true);
      wrapper.unmount();
    });

    it('frees "Continuar" after 8 s when the navigation never ends (#1369)', async () => {
      vi.useFakeTimers();
      const nuncaTermina = () => new Promise(() => {});
      router.push
        .mockReturnValueOnce(nuncaTermina())
        .mockReturnValueOnce(nuncaTermina());
      const wrapper = mount(AgentesListaPage, { attachTo: document.body });
      await vi.advanceTimersByTimeAsync(2500);
      const botao = wrapper.get('[data-continuar]');

      await botao.trigger('click');
      expect(botao.attributes('aria-busy')).toBe('true');
      await vi.advanceTimersByTimeAsync(7999);
      expect(botao.attributes('aria-busy')).toBe('true');
      await vi.advanceTimersByTimeAsync(1);
      expect(botao.attributes('aria-busy')).toBeUndefined();

      await botao.trigger('click');
      expect(router.push).toHaveBeenCalledTimes(2);
      const relogiosComOBotao = vi.getTimerCount();
      wrapper.unmount();
      // Ao sair da tela, o relógio do botão não fica para trás.
      expect(vi.getTimerCount()).toBe(relogiosComOBotao - 1);
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

    it('opens the full "Criar agente" page, not a drawer, from the hero, the phone bar and "Ver modelos prontos" (#1543)', async () => {
      const wrapper = await montar();
      const pagina = { name: 'autonomia_agents_builder' };

      await wrapper.get('[data-criar]').trigger('click');
      expect(router.push).toHaveBeenLastCalledWith(pagina);
      await wrapper.get('[data-criar-celular]').trigger('click');
      expect(router.push).toHaveBeenLastCalledWith(pagina);
      await wrapper.get('[data-ver-modelos]').trigger('click');
      expect(router.push).toHaveBeenLastCalledWith(pagina);

      expect(router.push).toHaveBeenCalledTimes(3);
      await nextTick();
      expect(document.querySelector('[role="dialog"]')).toBeNull();
      wrapper.unmount();
    });

    it('shows a view only seat the list without any writing action', async () => {
      estado.podeGerenciar = false;
      const wrapper = await montar();
      expect(wrapper.find('[data-criar]').exists()).toBe(false);
      expect(wrapper.find('[data-ver-modelos]').exists()).toBe(false);
      expect(wrapper.find('[data-criar-celular]').exists()).toBe(false);
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
      expect(wrapper.find('[data-copiloto]').exists()).toBe(true);
      expect(wrapper.find('[data-sem-canal]').exists()).toBe(false);
      wrapper.unmount();
    });

    it('opens the team copilot from the big hero (#1494)', async () => {
      const wrapper = await montar();
      const copiloto = wrapper.get('[data-copiloto]');
      expect(copiloto.text()).toBe('AGENTS.JORNADA.MODELOS.COPILOTO');
      expect(wrapper.text()).toContain('AGENTS.JORNADA.MODELOS.COPILOTO_TEXTO');
      await copiloto.trigger('click');
      await flushPromises();
      expect(router.push).toHaveBeenLastCalledWith({
        name: 'autonomia_agents_builder',
        query: { atuacao: 'interno' },
      });
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
      expect(wrapper.find('[data-copiloto]').exists()).toBe(false);
      expect(textoDosBotoes(wrapper)).toEqual([]);
      wrapper.unmount();
    });
  });

  // #1648 — agentes de outro sistema (AgentBot webhook) na mesma lista, sem seção à parte.
  describe('agentes de outro sistema', () => {
    const BOTS = [
      { id: 31, name: 'Automação Vendas', system_bot: false },
      { id: 32, name: 'Atendimento Parceiro', system_bot: false },
      { id: 33, name: 'Robô do sistema', system_bot: true },
    ];
    const canal = (inboxId, nome, ocupadoPor) => ({
      inbox_id: inboxId,
      name: nome,
      occupied_by: ocupadoPor,
    });

    beforeEach(() => {
      store.state['agentBots/getBots'] = BOTS;
      api.canaisOcupados.mockResolvedValue({
        data: {
          payload: [
            canal(10, 'WhatsApp do Centro', {
              kind: 'agent',
              agent_id: 3,
              agent_name: 'Bia',
            }),
            canal(14, 'WhatsApp Parceiro', {
              kind: 'external',
              agent_bot_id: 31,
              operating: true,
            }),
            canal(15, 'Site', {
              kind: 'external',
              agent_bot_id: 32,
              operating: false,
            }),
          ],
        },
      });
    });

    it('lists them among our agents: answering with an active inbox, stopped without one, never system bots', async () => {
      const wrapper = await montar();
      const cartoes = wrapper.findAll('[data-cartao]');
      const nomes = cartoes.map(c => c.text());

      expect(store.dispatch).toHaveBeenCalledWith('agentBots/get');
      expect(nomes.findIndex(n => n.includes('Automação Vendas'))).toBe(1);
      expect(nomes.some(n => n.includes('Robô do sistema'))).toBe(false);
      const automacao = wrapper.get('[data-outro-sistema]');
      expect(automacao.text()).toContain('AGENTS.JORNADA.CARTAO.ONDE_CANAL');
      expect(automacao.get('a').attributes('href')).toBe(
        '/app/autonomia_agent_panel'
      );
      const parceiro = wrapper.findAll('[data-outro-sistema]')[1];
      expect(parceiro.text()).toContain('Atendimento Parceiro');
      expect(parceiro.text()).toContain('AGENTS.JORNADA.CARTAO.ONDE_NENHUM');
      wrapper.unmount();
    });

    it('opens the agent page with origem=webhook', async () => {
      const wrapper = await montar();
      await wrapper.get('[data-outro-sistema] a').trigger('click');

      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agent_panel',
        params: { agentId: 31 },
        query: { origem: 'webhook' },
      });
      wrapper.unmount();
    });

    it('connects a new one on a full page, only for administrators', async () => {
      const wrapper = await montar();
      await wrapper.get('[data-conectar-outro]').trigger('click');

      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_builder',
        query: { conectar: 'outro' },
      });
      wrapper.unmount();

      estado.admin = false;
      const semAdmin = await montar();
      expect(semAdmin.find('[data-conectar-outro]').exists()).toBe(false);
      semAdmin.unmount();
    });

    it('is not an empty list when the account only has agents from another system', async () => {
      prepararStore({ agentes: [] });
      store.state['agentBots/getBots'] = BOTS;
      const wrapper = await montar();

      expect(wrapper.findAll('[data-outro-sistema]')).toHaveLength(2);
      expect(wrapper.find('[data-usar]').exists()).toBe(false);
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
