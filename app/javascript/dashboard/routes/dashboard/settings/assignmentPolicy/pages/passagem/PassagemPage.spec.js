import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import PassagemPage from './PassagemPage.vue';
import PassagemAvisos from './PassagemAvisos.vue';

// #1385 — para onde a tela de um funil volta: a seta, o X e o "Fechar" vão para o mesmo lugar, a origem.
const estado = vi.hoisted(() => ({
  push: vi.fn(),
  alerta: vi.fn(),
  query: {},
  alterado: false,
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: estado.push }),
  useRoute: () => ({
    query: estado.query,
    params: { accountId: '16', pipelineId: '6' },
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: estado.alerta }));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(true) }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ref(() => true),
}));
vi.mock('./usePassagem', () => ({
  usePassagem: () => ({
    carregando: ref(false),
    falhou: ref(false),
    salvando: ref(false),
    salvoAgora: ref(false),
    funis: ref([{ id: 6, name: 'Email Comercial' }]),
    caixas: ref([{ id: 1 }]),
    equipe: ref([]),
    iaDoFunilLigada: ref(true),
    regra: ref({ enabled: true }),
    etapas: ref([]),
    alterado: ref(estado.alterado),
    regrasIncompletas: ref([]),
    carregar: vi.fn(),
    salvar: vi.fn(),
    guardarCopia: vi.fn(),
    descartarCopia: vi.fn(),
    restaurarCopia: vi.fn(),
  }),
}));

const montar = async () => {
  const pagina = mount(PassagemPage, {
    global: {
      stubs: {
        PassagemResumo: true,
        PassagemLado: true,
        PassagemAvisos: true,
      },
    },
  });
  await flushPromises();
  return pagina;
};

const sairPelos = async pagina => {
  await pagina.find('[data-passagem-voltar]').trigger('click');
  await pagina.find('[data-passagem-fechar]').trigger('click');
  await pagina.find('[data-passagem-principal]').trigger('click');
  return estado.push.mock.calls.map(([destino]) => destino);
};

beforeEach(() => {
  estado.push.mockReset();
  estado.alerta.mockReset();
  estado.query = {};
  estado.alterado = false;
});

describe('PassagemPage: a volta', () => {
  it('aberta pela lista: seta, X e Fechar voltam para "Todos os funis"', async () => {
    const pagina = await montar();
    expect(pagina.find('[data-passagem-voltar]').text()).toBe(
      'CRM_KANBAN.PASSAGEM.HEROI.TODOS_OS_FUNIS'
    );
    expect(await sairPelos(pagina)).toEqual(
      Array(3).fill({ name: 'crm_handoff_settings_index' })
    );
  });

  it('aberta pelo Kanban: seta, X e Fechar voltam ao Kanban no mesmo funil', async () => {
    estado.query = { from: 'crm' };
    const pagina = await montar();
    expect(pagina.find('[data-passagem-voltar]').text()).toBe(
      'CRM_KANBAN.PASSAGEM.HEROI.VOLTAR_KANBAN'
    );
    expect(await sairPelos(pagina)).toEqual(
      Array(3).fill({
        name: 'crm_kanban_index',
        query: { pipeline_id: '6' },
      })
    );
  });

  it('com alteração sem salvar: não sai e pede para salvar ou cancelar', async () => {
    estado.alterado = true;
    const pagina = await montar();
    await pagina.find('[data-passagem-fechar]').trigger('click');
    expect(estado.push).not.toHaveBeenCalled();
    expect(estado.alerta).toHaveBeenCalledWith(
      'CRM_KANBAN.PASSAGEM.SALVE_ANTES_DE_SAIR'
    );
  });
});

describe('PassagemAvisos: "Abrir o funil"', () => {
  const montarAviso = props =>
    mount(PassagemAvisos, {
      props: { iaLigada: false, ...props },
      global: { mocks: { $router: { push: estado.push } } },
    });

  it('abre o Kanban já no funil', async () => {
    await montarAviso({ funilId: 6 }).find('button').trigger('click');
    expect(estado.push).toHaveBeenCalledWith({
      name: 'crm_kanban_index',
      query: { pipeline_id: '6' },
    });
  });

  it('sem funil: abre o Kanban', async () => {
    await montarAviso().find('button').trigger('click');
    expect(estado.push).toHaveBeenCalledWith({ name: 'crm_kanban_index' });
  });
});
