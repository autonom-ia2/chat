import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import CriarEmPassos from '../../components/CriarEmPassos.vue';
import AgenteCriarEmPassosPage from '../../pages/AgenteCriarEmPassosPage.vue';

// #3219 — "Criar agente" em dois passos: 1. o que ele vai fazer; 2. como começar. O passo 2 mora na URL
// (`?papel=atender|copiloto`); a escolha final abre a criação na mesma rota, e a falha não trava nada.
const estado = vi.hoisted(() => ({ podeGerenciar: true }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => estado.podeGerenciar) };
});

const store = vi.hoisted(() => ({ dispatch: vi.fn(), state: null }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => computed(() => store.state[nome]),
  };
});

vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => true),
    }),
  };
});

const api = vi.hoisted(() => ({ modelosDeRamo: vi.fn() }));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: api }));
// #3211: os agentes prontos para contratar vêm do servidor (passo 2 de atender clientes). Aqui, nenhum.
vi.mock('dashboard/api/autonomia/contratados', () => ({
  default: { lista: vi.fn(() => Promise.resolve({ data: { modelos: [] } })) },
}));

const FALHA = { falhaDeNavegacao: true };
const rota = vi.hoisted(() => ({ atual: null }));
const router = vi.hoisted(() => ({
  push: vi.fn(),
  resolve: vi.fn(destino => ({ href: `/app/${destino.name}` })),
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota.atual,
  useRouter: () => router,
  isNavigationFailure: valor => Boolean(valor?.falhaDeNavegacao),
}));

const CRIAR = 'autonomia_agents_builder';
// Um agente que o ajudante pode ajudar: fala com o cliente e não é rascunho.
const CLIENTE = { id: 1, status: 'active', actuation: 'external' };
const NS = 'AGENTS.JORNADA.CRIAR_EM_PASSOS';

const prepararStore = ({
  fase2 = false,
  porCaixa = false,
  agentes = [],
  caixas = [{ id: 10 }],
} = {}) => {
  store.state = reactive({
    getCurrentAccountId: 1,
    'accounts/getAccount': () => ({
      autonomia_agents_fase2: fase2,
      autonomia_agente_ia_por_caixa: porCaixa,
    }),
    'autonomiaAgents/getRecords': [],
    'inboxes/getInboxes': caixas,
  });
  store.dispatch.mockImplementation(async acao => {
    if (acao === 'autonomiaAgents/get') {
      store.state['autonomiaAgents/getRecords'] = agentes;
    }
  });
};

const montar = async (props = {}) => {
  const wrapper = mount(CriarEmPassos, { props, attachTo: document.body });
  await flushPromises();
  return wrapper;
};

const papeisNaTela = wrapper =>
  wrapper.findAll('[data-papel]').map(no => no.attributes('data-papel'));

describe('CriarEmPassos (#3219)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    estado.podeGerenciar = true;
    rota.atual = reactive({ query: {} });
    prepararStore();
    api.modelosDeRamo.mockResolvedValue({ data: { modelos: [] } });
    // Como o vue-router: navegar na mesma rota troca a consulta.
    router.push.mockImplementation(async ({ query }) => {
      rota.atual.query = query;
    });
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe('passo 1 · o que ele vai fazer', () => {
    it('shows the question, the customer agent highlighted and the Team copilot, without Phase 2', async () => {
      const wrapper = await montar();
      expect(wrapper.get('h1').text()).toBe(`${NS}.PAPEL.TITULO`);
      expect(wrapper.text()).toContain(`${NS}.PAPEL.TEXTO`);
      expect(papeisNaTela(wrapper)).toEqual(['atender', 'copiloto']);
      expect(wrapper.get('[data-escolher-papel]').text()).toContain(
        `${NS}.PAPEL.ESCOLHER`
      );
      // Uma só alternativa: o título fica no singular.
      expect(wrapper.text()).toContain(`${NS}.PAPEL.OUTRO`);
      expect(wrapper.find('select').exists()).toBe(false);
      wrapper.unmount();
    });

    it('shows the list name tag under the copilot, team agent and helper titles', async () => {
      prepararStore({ fase2: true, agentes: [CLIENTE] });
      const wrapper = await montar();
      expect(
        wrapper.findAll('[data-nome-na-lista]').map(n => n.text())
      ).toEqual([
        `${NS}.PAPEIS.COPILOTO.NOME`,
        `${NS}.PAPEIS.EQUIPE.NOME`,
        `${NS}.PAPEIS.AJUDANTE.NOME`,
      ]);
      wrapper.unmount();
    });

    it('shows the five roles with Phase 2, the per inbox agent and agents on the account', async () => {
      prepararStore({ fase2: true, porCaixa: true, agentes: [CLIENTE] });
      const wrapper = await montar();
      expect(papeisNaTela(wrapper)).toEqual([
        'atender',
        'copiloto',
        'equipe',
        'ajudante',
        'conectar',
      ]);
      expect(wrapper.text()).toContain(`${NS}.PAPEL.OUTROS`);
      wrapper.unmount();
    });

    it('hides the helper when the account has no agent', async () => {
      prepararStore({ fase2: true, agentes: [] });
      const wrapper = await montar();
      expect(papeisNaTela(wrapper)).toEqual(['atender', 'copiloto', 'equipe']);
      wrapper.unmount();
    });

    it('reads the agents once and shows a placeholder until they arrive, so the cards do not jump', async () => {
      prepararStore({ fase2: true, agentes: [CLIENTE] });
      let responder;
      store.dispatch.mockImplementation(
        () =>
          new Promise(resolve => {
            responder = () => {
              store.state['autonomiaAgents/getRecords'] = [CLIENTE];
              resolve();
            };
          })
      );
      const wrapper = mount(CriarEmPassos, { attachTo: document.body });
      await flushPromises();
      expect(store.dispatch).toHaveBeenCalledTimes(1);
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/get');
      expect(wrapper.find('[data-esqueleto-papeis]').exists()).toBe(true);
      expect(wrapper.find('[data-papel]').exists()).toBe(false);

      responder();
      await flushPromises();
      expect(wrapper.find('[data-esqueleto-papeis]').exists()).toBe(false);
      expect(papeisNaTela(wrapper)).toContain('ajudante');
      wrapper.unmount();
    });

    it('hides the helper when no agent can be helped (only the copilot, a draft or another helper)', async () => {
      prepararStore({
        fase2: true,
        agentes: [
          { id: 1, status: 'active', actuation: 'internal' },
          { id: 2, status: 'draft', actuation: 'external' },
          { id: 3, status: 'active', actuation: 'internal', ajudante: true },
        ],
      });
      const wrapper = await montar();
      expect(papeisNaTela(wrapper)).toEqual(['atender', 'copiloto', 'equipe']);
      wrapper.unmount();
    });

    it('keeps the helper with Phase 2 when the agents cannot be read, and lets the creation decide', async () => {
      prepararStore({ fase2: true });
      store.dispatch.mockRejectedValue(new Error('500'));
      const wrapper = await montar();
      expect(papeisNaTela(wrapper)).toEqual([
        'atender',
        'copiloto',
        'equipe',
        'ajudante',
      ]);
      wrapper.unmount();
    });

    it('on the empty list (inicio) keeps the strong question, reads nothing and never offers the helper', async () => {
      prepararStore({ fase2: true, agentes: [CLIENTE] });
      const wrapper = await montar({ inicio: true });
      expect(store.dispatch).not.toHaveBeenCalled();
      expect(wrapper.get('h1').text()).toBe('AGENTS.JORNADA.HEROI.TITULO');
      expect(wrapper.text()).toContain(`${NS}.PAPEL.TEXTO_INICIO`);
      expect(papeisNaTela(wrapper)).not.toContain('ajudante');
      // O exemplo de conversa no cartão em destaque.
      expect(wrapper.text()).toContain('AGENTS.JORNADA.MODELOS.SUPPORT.AGENTE');
      wrapper.unmount();
    });

    it.each([
      ['atender', '[data-escolher-papel]'],
      ['copiloto', '[data-papel="copiloto"]'],
    ])('opens step 2 of %s on "Criar agente"', async (papel, seletor) => {
      const wrapper = await montar();
      await wrapper.get(seletor).trigger('click');
      expect(router.push).toHaveBeenCalledWith({
        name: CRIAR,
        query: { papel },
      });
      wrapper.unmount();
    });

    it.each([
      ['equipe', { papel: 'area' }],
      ['ajudante', { papel: 'ajudante' }],
      ['conectar', { conectar: 'outro' }],
    ])(
      'opens %s straight, without a step 2, and tells who uses it',
      async (papel, query) => {
        prepararStore({ fase2: true, porCaixa: true, agentes: [CLIENTE] });
        const wrapper = await montar();
        await wrapper.get(`[data-papel="${papel}"]`).trigger('click');
        await flushPromises();
        expect(router.push).toHaveBeenCalledWith({ name: CRIAR, query });
        expect(wrapper.emitted('escolher')).toEqual([[query]]);
        wrapper.unmount();
      }
    );

    it('shows the failure when a role without step 2 cannot open, and tries again', async () => {
      prepararStore({ fase2: true });
      router.push.mockResolvedValueOnce(FALHA);
      const wrapper = await montar();
      await wrapper.get('[data-papel="equipe"]').trigger('click');
      await flushPromises();
      const erro = wrapper.get('[data-erro-ao-comecar]');
      expect(erro.text()).toContain(`${NS}.COMO.ERRO`);
      await erro.get('button').trigger('click');
      await flushPromises();
      expect(router.push).toHaveBeenCalledTimes(2);
      expect(wrapper.find('[data-erro-ao-comecar]').exists()).toBe(false);
      wrapper.unmount();
    });

    it('gives a view only seat the explanation and no action', async () => {
      estado.podeGerenciar = false;
      const wrapper = await montar();
      expect(wrapper.text()).toContain('AGENTS.JORNADA.HEROI.SO_VER');
      expect(wrapper.findAll('button')).toHaveLength(0);
      wrapper.unmount();
    });

    it('shows the failure and tries again when step 2 does not open', async () => {
      router.push.mockResolvedValueOnce(FALHA);
      const wrapper = await montar();
      await wrapper.get('[data-papel="copiloto"]').trigger('click');
      await flushPromises();

      const erro = wrapper.get('[data-erro-ao-comecar]');
      expect(
        wrapper.get('[data-criar-em-passos]').attributes('data-passo')
      ).toBe('1');
      expect(wrapper.emitted('escolher')).toBeUndefined();

      await erro.get('button').trigger('click');
      await flushPromises();
      expect(router.push).toHaveBeenLastCalledWith({
        name: CRIAR,
        query: { papel: 'copiloto' },
      });
      expect(
        wrapper.get('[data-criar-em-passos]').attributes('data-passo')
      ).toBe('2');
      expect(wrapper.find('[data-erro-ao-comecar]').exists()).toBe(false);
      wrapper.unmount();
    });
  });

  describe('passo 2 · como começar', () => {
    it('shows the chosen role on top, with "Trocar" going back to step 1', async () => {
      rota.atual.query = { papel: 'copiloto' };
      const wrapper = await montar();
      expect(wrapper.get('h1').text()).toBe(`${NS}.COMO.TITULO`);
      expect(wrapper.get('[data-papel-escolhido]').text()).toContain(
        `${NS}.PAPEIS.COPILOTO.TITULO`
      );
      await wrapper.get('[data-trocar-papel]').trigger('click');
      expect(router.push).toHaveBeenCalledWith({ name: CRIAR, query: {} });
      wrapper.unmount();
    });

    it('moves the focus to the title when the step changes', async () => {
      const wrapper = await montar();
      await wrapper.get('[data-escolher-papel]').trigger('click');
      await flushPromises();
      expect(wrapper.get('[data-heroi]').attributes('data-passo')).toBe('2');
      expect(document.activeElement).toBe(wrapper.get('h1').element);
      expect(wrapper.get('h1').attributes('tabindex')).toBe('-1');
      wrapper.unmount();
    });

    it('opens the steps (not the creation) for a role the URL names but that has no step 2', async () => {
      rota.atual.query = { papel: 'area' };
      const wrapper = await montar();
      expect(wrapper.get('[data-heroi]').attributes('data-passo')).toBe('1');
      wrapper.unmount();
    });

    it('offers the three templates and, below, talking with the AI and writing it myself, for the customer agent', async () => {
      rota.atual.query = { papel: 'atender' };
      const wrapper = await montar();
      expect(wrapper.text()).toContain(`${NS}.COMO.TEXTO_ATENDER`);
      expect(wrapper.findAll('[data-usar]')).toHaveLength(3);
      expect(wrapper.text()).toContain(`${NS}.COMO.DO_ZERO`);
      expect(wrapper.find('[data-opcao="conversar"]').exists()).toBe(true);
      expect(wrapper.find('[data-opcao="escrever"]').exists()).toBe(true);
      expect(wrapper.find('[data-ramos]').exists()).toBe(false);
      expect(wrapper.find('[data-sem-canal]').exists()).toBe(false);
      wrapper.unmount();
    });

    it('with insurance lines, shows them first and the general templates as rows in "Não achou o seu seguro?"', async () => {
      api.modelosDeRamo.mockResolvedValue({
        data: { modelos: ['seguro_auto', 'seguro_vida'] },
      });
      rota.atual.query = { papel: 'atender' };
      const wrapper = await montar();
      expect(wrapper.text()).toContain(`${NS}.COMO.TEXTO_RAMOS`);
      expect(wrapper.findAll('[data-ramo]').length).toBeGreaterThan(0);
      expect(wrapper.find('[data-usar]').exists()).toBe(false);
      expect(wrapper.text()).toContain(`${NS}.COMO.OUTRO_JEITO`);
      ['support', 'sdr', 'reception', 'conversar', 'escrever'].forEach(
        chave => {
          expect(wrapper.find(`[data-opcao="${chave}"]`).exists()).toBe(true);
        }
      );
      wrapper.unmount();
    });

    it('warns about the missing channel only on step 2 of the customer agent', async () => {
      prepararStore({ caixas: [] });
      rota.atual.query = { papel: 'atender' };
      const wrapper = await montar();
      const aviso = wrapper.get('[data-sem-canal]');
      expect(aviso.text()).toContain('AGENTS.JORNADA.HEROI.SEM_CANAL');
      expect(aviso.get('a').attributes('href')).toBe('/app/settings_inbox_new');
      wrapper.unmount();

      rota.atual.query = { papel: 'copiloto' };
      const copiloto = await montar();
      expect(copiloto.find('[data-sem-canal]').exists()).toBe(false);
      copiloto.unmount();
    });

    it('offers the Team copilot two cards of the same size, talking with the AI as the easiest', async () => {
      rota.atual.query = { papel: 'copiloto' };
      const wrapper = await montar();
      expect(wrapper.text()).toContain(`${NS}.COMO.TEXTO_OUTROS`);
      const cartoes = wrapper.findAll('[data-opcao]');
      expect(cartoes.map(c => c.attributes('data-opcao'))).toEqual([
        'conversar',
        'escrever',
      ]);
      expect(cartoes[0].find('[data-mais-facil]').exists()).toBe(true);
      expect(cartoes[1].find('[data-mais-facil]').exists()).toBe(false);
      expect(cartoes[0].get('[data-usar-opcao]').classes()).toContain(
        'bg-n-blue-11'
      );
      expect(wrapper.find('[data-usar]').exists()).toBe(false);
      wrapper.unmount();
    });

    it.each([
      ['atender', '[data-usar]', { modelo: 'support' }],
      ['atender', '[data-opcao="conversar"]', { modelo: 'custom' }],
      [
        'atender',
        '[data-opcao="escrever"]',
        { escrever: '1', papel: 'atender' },
      ],
      [
        'copiloto',
        '[data-opcao="conversar"] [data-usar-opcao]',
        { atuacao: 'interno' },
      ],
      [
        'copiloto',
        '[data-opcao="escrever"] [data-usar-opcao]',
        { escrever: '1', papel: 'copiloto' },
      ],
    ])('%s: %s opens the creation with %o', async (papel, seletor, query) => {
      rota.atual.query = { papel };
      const wrapper = await montar();
      await wrapper.get(seletor).trigger('click');
      await flushPromises();
      expect(router.push).toHaveBeenCalledWith({ name: CRIAR, query });
      expect(wrapper.emitted('escolher')).toEqual([[query]]);
      wrapper.unmount();
    });

    it('opens an insurance line with ?ramo=', async () => {
      api.modelosDeRamo.mockResolvedValue({
        data: { modelos: ['seguro_auto'] },
      });
      rota.atual.query = { papel: 'atender' };
      const wrapper = await montar();
      await wrapper.get('[data-usar-ramo]').trigger('click');
      await flushPromises();
      expect(router.push).toHaveBeenCalledWith({
        name: CRIAR,
        query: { ramo: 'seguro_auto' },
      });
      wrapper.unmount();
    });

    it('shows the failure, frees the buttons and tries again when the creation does not open', async () => {
      rota.atual.query = { papel: 'copiloto' };
      router.push.mockResolvedValueOnce(FALHA);
      const wrapper = await montar();
      await wrapper
        .get('[data-opcao="conversar"] [data-usar-opcao]')
        .trigger('click');
      await flushPromises();

      const erro = wrapper.get('[data-erro-ao-comecar]');
      expect(erro.text()).toContain(`${NS}.COMO.ERRO`);
      expect(wrapper.text()).not.toContain('AGENTS.JORNADA.COMUM.COMECANDO');
      wrapper
        .findAll('[data-usar-opcao]')
        .forEach(botao => expect(botao.attributes('disabled')).toBeUndefined());

      await erro.get('button').trigger('click');
      await flushPromises();
      expect(router.push).toHaveBeenLastCalledWith({
        name: CRIAR,
        query: { atuacao: 'interno' },
      });
      expect(wrapper.find('[data-erro-ao-comecar]').exists()).toBe(false);
      wrapper.unmount();
    });

    it('also treats a thrown navigation as a failure', async () => {
      rota.atual.query = { papel: 'atender' };
      router.push.mockRejectedValueOnce(new Error('chunk'));
      const wrapper = await montar();
      await wrapper.get('[data-opcao="escrever"]').trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-erro-ao-comecar]').exists()).toBe(true);
      wrapper.unmount();
    });

    it('keeps every action at least 44 px tall', async () => {
      rota.atual.query = { papel: 'copiloto' };
      const wrapper = await montar();
      expect(wrapper.get('[data-trocar-papel]').classes()).toContain(
        'min-h-11'
      );
      wrapper
        .findAll('[data-usar-opcao]')
        .forEach(botao => expect(botao.classes()).toContain('min-h-12'));
      wrapper.unmount();
    });
  });
});

describe('AgenteCriarEmPassosPage (#3219)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    estado.podeGerenciar = true;
    prepararStore();
    api.modelosDeRamo.mockResolvedValue({ data: { modelos: [] } });
    router.push.mockResolvedValue(undefined);
  });

  it('goes back to Agents from step 1', async () => {
    rota.atual = reactive({ query: {} });
    const wrapper = mount(AgenteCriarEmPassosPage);
    await flushPromises();
    const voltar = wrapper.get('[data-voltar-lista]');
    expect(voltar.text()).toBe('AGENTS.JORNADA.CRIAR.VOLTAR');
    await voltar.trigger('click');
    expect(router.push).toHaveBeenCalledWith({
      name: 'autonomia_agents_index',
    });
  });

  it('says "Voltar" on step 2 and goes back to step 1', async () => {
    rota.atual = reactive({ query: { papel: 'atender' } });
    const wrapper = mount(AgenteCriarEmPassosPage);
    await flushPromises();
    const voltar = wrapper.get('[data-voltar-lista]');
    expect(voltar.text()).toBe(`${NS}.COMO.VOLTAR`);
    await voltar.trigger('click');
    expect(router.push).toHaveBeenCalledWith({ query: {} });
  });
});
