import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgentesListaPage from '../../pages/AgentesListaPage.vue';

// #3211 (Tarefa 28, R16) — o "Continuar" do cartão de um rascunho: o contratado termina na própria página (passo 2,
// o acesso), nunca no Construtor, que recusa o contratado com 422. O rascunho comum segue para o Construtor.
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
  return {
    useCanManage: () => computed(() => true),
    usePermissionGranted: () => computed(() => true),
  };
});
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => true) }) };
});
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => true),
      podeEscolherQuemRecebe: computed(() => true),
      crmLigado: computed(() => true),
    }),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const router = vi.hoisted(() => ({
  push: vi.fn(),
  resolve: vi.fn(rota => ({ href: `/app/${rota.name}` })),
}));
vi.mock('vue-router', () => ({
  useRouter: () => router,
  useRoute: () => ({ query: {} }),
  isNavigationFailure: () => false,
}));
const api = vi.hoisted(() => ({
  semana: vi.fn(() => Promise.resolve({ data: { payload: [] } })),
  canaisOcupados: vi.fn(() => Promise.resolve({ data: { payload: [] } })),
  modelosDeRamo: vi.fn(() => Promise.resolve({ data: { modelos: [] } })),
}));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: api }));
// #3211: os agentes prontos para contratar vêm do servidor (passo 2 de atender clientes). Aqui, nenhum.
vi.mock('dashboard/api/autonomia/contratados', () => ({
  default: { lista: vi.fn(() => Promise.resolve({ data: { modelos: [] } })) },
}));
const doPost = vi.hoisted(() => ({
  list: vi.fn(() => Promise.resolve({ data: { payload: [] } })),
  get: vi.fn(),
  anuncios: vi.fn(() => Promise.resolve({ data: { payload: [] } })),
}));
vi.mock('dashboard/api/agentesDoPost', () => ({ default: doPost }));
vi.mock('dashboard/api/seusPosts', () => ({ default: { get: vi.fn() } }));

const rascunho = (id, extra = {}) => ({
  id,
  name: `Rascunho ${id}`,
  status: 'draft',
  enabled: false,
  agent_type: 'sdr',
  actuation: 'external',
  channels_count: 0,
  contratado: null,
  ...extra,
});

const preparar = agentes => {
  store.state = reactive({
    'autonomiaAgents/getRecords': [],
    'autonomiaAgents/getUIFlags': { fetchingList: false },
    'inboxes/getInboxes': [{ id: 10 }],
  });
  store.dispatch.mockImplementation(async acao => {
    if (acao === 'autonomiaAgents/get') {
      store.state['autonomiaAgents/getRecords'] = agentes;
    }
    return null;
  });
};

const montar = async () => {
  const wrapper = mount(AgentesListaPage, { attachTo: document.body });
  await flushPromises();
  return wrapper;
};

describe('Continuar de um rascunho contratado (#3211)', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('opens the hired agent page on its own drawer, never the builder', async () => {
    preparar([
      rascunho(5, {
        name: 'Bia',
        contratado: {
          modelo: 'seguro_viagem_universal',
          nome_agente: 'Bia',
          nome_corretora: 'Corretora Exemplo',
          sobre_corretora: '',
          acesso: null,
        },
      }),
    ]);
    const wrapper = await montar();
    await wrapper.get('[data-continuar]').trigger('click');
    await flushPromises();

    expect(router.push).toHaveBeenCalledTimes(1);
    const [destino] = router.push.mock.calls[0];
    expect(destino).toEqual({
      name: 'autonomia_agent_panel',
      params: { agentId: 5 },
      query: { gaveta: 'contratado' },
    });
    expect(destino.query.gaveta).toBe('contratado');
    expect(router.push).not.toHaveBeenCalledWith(
      expect.objectContaining({ name: 'autonomia_agents_builder' })
    );
    wrapper.unmount();
  });

  it('keeps sending an ordinary draft to the builder', async () => {
    preparar([rascunho(6)]);
    const wrapper = await montar();
    await wrapper.get('[data-continuar]').trigger('click');
    await flushPromises();

    expect(router.push).toHaveBeenCalledWith({
      name: 'autonomia_agents_builder',
      query: { agente: 6 },
    });
    wrapper.unmount();
  });
});
