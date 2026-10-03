import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import AutomationAPI from 'dashboard/api/automation';
import { podeMudar } from 'dashboard/composables/useCanManage';
import AutomacaoConversaPage from '../pages/AutomacaoConversaPage.vue';

// #859 — a tela nova/editar: conversa do Guia embutida, resumo, teste, Ligar e
// modo manual. Estados: carregando, erro, Guia desligado, só leitura.
const { rota, routerPush, routerReplace, guiaLigado } = vi.hoisted(() => ({
  rota: { name: 'automacoes_nova', params: { accountId: 1 }, query: {} },
  routerPush: vi.fn(),
  routerReplace: vi.fn(),
  guiaLigado: { value: true },
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: routerPush, replace: routerReplace }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// O interruptor de permissão é um ref de verdade: o template só desembrulha ref.
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref: criarRef } = await import('vue');
  const podeMudarRef = criarRef(true);
  return { useCanManage: () => podeMudarRef, podeMudar: podeMudarRef };
});
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: getter => {
    if (getter === 'getCurrentAccountId') return ref(1);
    if (getter === 'globalConfig/get') return ref({});
    if (getter === 'accounts/getAccount') {
      return ref(() => ({ autonomia_guide_available: guiaLigado.value }));
    }
    return ref([]);
  },
}));
vi.mock('dashboard/api/automation', () => ({
  default: { show: vi.fn(), update: vi.fn(), ensaio: vi.fn() },
}));
vi.mock('dashboard/api/autonomia/decisores', () => ({
  default: { get: vi.fn(() => Promise.resolve({ data: { decisores: [] } })) },
}));

const GuiaFalso = {
  name: 'AutonomiaGuideContainer',
  props: {
    embutido: Boolean,
    sugestoes: { type: Array, default: null },
    introducao: { type: String, default: '' },
    pedidoInicial: { type: String, default: '' },
  },
  emits: ['execucao', 'pedidoInicialEnviado'],
  template: '<div data-guia-falso />',
};

const regra = (extra = {}) => ({
  id: 42,
  name: 'Sinistros',
  active: false,
  event_name: 'message_created',
  conditions: [],
  actions: [{ action_name: 'add_label', action_params: ['sinistro'] }],
  ...extra,
});

const montar = () =>
  mount(AutomacaoConversaPage, {
    global: {
      mocks: { $t: key => key },
      stubs: { AutonomiaGuideContainer: GuiaFalso, RouterLink: true },
    },
  });

const abrirRegra = id => {
  rota.name = 'automacoes_editar';
  rota.params = { accountId: 1, id: String(id) };
  rota.query = {};
};

describe('AutomacaoConversaPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    rota.name = 'automacoes_nova';
    rota.params = { accountId: 1 };
    rota.query = {};
    podeMudar.value = true;
    guiaLigado.value = true;
  });

  it('nova: conversa embutida com os modelos e o resumo esperando o Guia', async () => {
    rota.query = { modelo: 'AGRADECER' };
    const wrapper = montar();
    await flushPromises();

    const guia = wrapper.findComponent(GuiaFalso);
    expect(guia.props('embutido')).toBe(true);
    expect(guia.props('sugestoes')).toHaveLength(3);
    expect(guia.props('pedidoInicial')).toBe(
      'AUTOMACOES.MODELOS.AGRADECER.PEDIDO'
    );
    expect(wrapper.find('[data-resumo-vazio]').exists()).toBe(true);
    expect(AutomationAPI.show).not.toHaveBeenCalled();
  });

  // Revisão #859: a página é montada de novo quando o Guia muda a conta (e ao
  // recarregar). Com o modelo ainda na URL, a tela nova mandava o pedido outra vez.
  it('nova: o modelo sai da URL quando o pedido sai, e a tela montada de novo não repete', async () => {
    rota.query = { modelo: 'AGRADECER', origem: 'lista' };
    routerReplace.mockImplementation(destino => {
      rota.query = destino.query;
    });
    const wrapper = montar();
    await flushPromises();

    wrapper.findComponent(GuiaFalso).vm.$emit('pedidoInicialEnviado');
    expect(routerReplace).toHaveBeenCalledWith({
      name: 'automacoes_nova',
      params: { accountId: 1 },
      query: { origem: 'lista' },
    });

    wrapper.unmount();
    const denovo = montar();
    await flushPromises();
    expect(denovo.findComponent(GuiaFalso).props('pedidoInicial')).toBe('');
  });

  it('nova: modelo desconhecido na URL não vira pergunta', async () => {
    rota.query = { modelo: 'APAGAR_TUDO' };
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.findComponent(GuiaFalso).props('pedidoInicial')).toBe('');
  });

  it('quando o Guia cria a automação, a tela passa a ser a dela', async () => {
    const wrapper = montar();
    await flushPromises();

    wrapper.findComponent(GuiaFalso).vm.$emit('execucao', {
      passos: [{ acao: 'POST automation_rules', ok: true, registro: 42 }],
    });

    expect(routerReplace).toHaveBeenCalledWith({
      name: 'automacoes_editar',
      params: { accountId: 1, id: 42 },
    });
  });

  it('editar: esqueleto enquanto carrega', () => {
    abrirRegra(42);
    AutomationAPI.show.mockReturnValue(new Promise(() => {}));
    const wrapper = montar();

    expect(wrapper.find('[data-carregando]').exists()).toBe(true);
  });

  it('editar: erro diz que não encontrou e leva de volta', async () => {
    abrirRegra(42);
    AutomationAPI.show.mockRejectedValue(new Error('404'));
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-erro]').text()).toContain(
      'AUTOMACOES.CONVERSA.ERRO'
    );
    await wrapper.find('[data-erro] button').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'automacoes_lista',
      params: { accountId: 1 },
    });
  });

  it('editar: mostra o resumo, liga com o botão primário e abre o modo manual', async () => {
    abrirRegra(42);
    AutomationAPI.show.mockResolvedValue({ data: { payload: regra() } });
    AutomationAPI.update.mockResolvedValue({});
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-quando]').text()).toBe(
      'AUTOMACOES.QUANDO.MESSAGE_CREATED'
    );
    expect(wrapper.find('[data-situacao]').text()).toBe(
      'AUTOMACOES.CONVERSA.DESLIGADA_AVISO'
    );

    await wrapper.find('[data-ligar]').trigger('click');
    await flushPromises();
    expect(AutomationAPI.update).toHaveBeenCalledWith(42, { active: true });
    expect(useAlert).toHaveBeenCalledWith('AUTOMACOES.LISTA.LIGOU');
    expect(wrapper.find('[data-situacao]').text()).toBe(
      'AUTOMACOES.CONVERSA.LIGADA_AVISO'
    );
    expect(wrapper.find('[data-desligar]').exists()).toBe(true);

    await wrapper.find('[data-modo-manual]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'automation_list',
      params: { accountId: 1 },
      query: { editar: 42 },
    });
  });

  it('editar: o Guia mexeu na automação → o resumo é lido de novo', async () => {
    abrirRegra(42);
    AutomationAPI.show.mockResolvedValue({ data: { payload: regra() } });
    const wrapper = montar();
    await flushPromises();

    wrapper.findComponent(GuiaFalso).vm.$emit('execucao', {
      passos: [{ acao: 'PATCH automation_rules/:id', ok: true, registro: 42 }],
    });
    await flushPromises();

    expect(AutomationAPI.show).toHaveBeenCalledTimes(2);
    expect(routerReplace).not.toHaveBeenCalled();
  });

  it('Guia desligado na conta: oferece o modo manual', async () => {
    guiaLigado.value = false;
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.findComponent(GuiaFalso).exists()).toBe(false);
    expect(wrapper.find('[data-guia-fora]').text()).toContain(
      'AUTOMACOES.CONVERSA.GUIA_FORA'
    );
  });

  it('quem só pode ver testa, mas não liga', async () => {
    podeMudar.value = false;
    abrirRegra(42);
    AutomationAPI.show.mockResolvedValue({ data: { payload: regra() } });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-ligar]').exists()).toBe(false);
    expect(wrapper.text()).toContain('AUTOMACOES.CONVERSA.SO_LEITURA');
    expect(wrapper.find('[data-testar]').exists()).toBe(true);
  });
});
