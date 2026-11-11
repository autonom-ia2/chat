import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import AutomacaoConversaPage from '../pages/AutomacaoConversaPage.vue';
import catalogoReal from '../../../../../../../lib/operator_guide/automacao-passos.json';

// #2889 parte 2 — com a porta (automacao_porta + automacao_editor), o Guia monta
// no motor novo: criou → a tela vai para a automação dele; a tela mostra
// Quando/Só se/Faça com as frases do editor; Ligar leva a versão que a tela
// mostrou. Sem a porta, o POST do motor novo não mexe na tela.
const { rota, routerPush, routerReplace, flags } = vi.hoisted(() => ({
  rota: { name: 'automacoes_nova', params: { accountId: 1 }, query: {} },
  routerPush: vi.fn(),
  routerReplace: vi.fn(),
  flags: { value: {} },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt_BR' } }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: routerPush, replace: routerReplace }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref: criarRef } = await import('vue');
  const podeMudarRef = criarRef(true);
  return {
    useCanManage: () => podeMudarRef,
    usePermissionGranted: () => podeMudarRef,
    podeMudar: podeMudarRef,
  };
});
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: getter => {
    if (getter === 'getCurrentAccountId') return ref(1);
    if (getter === 'globalConfig/get') return ref({});
    if (getter === 'accounts/getAccount') {
      return ref(() => ({
        autonomia_guide_available: true,
        features: flags.value,
      }));
    }
    return ref([]);
  },
}));
vi.mock('dashboard/api/automation', () => ({
  default: { show: vi.fn(), update: vi.fn(), ensaio: vi.fn() },
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: {
    show: vi.fn(),
    passos: vi.fn(),
    ligar: vi.fn(),
    desligar: vi.fn(),
    ensaiar: vi.fn(),
  },
}));

const GuiaFalso = {
  name: 'AutonomiaGuideContainer',
  props: {
    embutido: Boolean,
    sugestoes: { type: Array, default: null },
    introducao: { type: String, default: '' },
    pedidoInicial: { type: String, default: '' },
    semTelas: Boolean,
    respostasRapidas: { type: Array, default: () => [] },
    comecarPorVoz: Boolean,
    anexosIniciais: { type: Array, default: () => [] },
    automacaoId: { type: Number, default: null },
    automacaoDoMotor: Boolean,
  },
  emits: ['execucao', 'pedidoInicialEnviado', 'respostaRapida'],
  template: '<div data-guia-falso />',
};

const automacao = (extra = {}) => ({
  id: 7,
  nome: 'Agradecer',
  ativa: false,
  origem: 'guia',
  versao: {
    id: 70,
    numero: 1,
    receita: {
      gatilho: { tipo: 'conversa.resolvida' },
      passos: [{ id: 'p1', tipo: 'mensagem', texto: ['Obrigado!'] }],
    },
  },
  ...extra,
});

const montar = () =>
  mount(AutomacaoConversaPage, {
    attachTo: document.body,
    global: {
      mocks: { $t: key => key },
      stubs: { AutonomiaGuideContainer: GuiaFalso, RouterLink: true },
    },
  });

const abrirNoMotor = id => {
  rota.name = 'automacoes_guia_editar';
  rota.params = { accountId: 1, id: String(id) };
};

describe('AutomacaoConversaPage no motor novo', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    rota.name = 'automacoes_nova';
    rota.params = { accountId: 1 };
    rota.query = {};
    flags.value = { automacao_porta: true, automacao_editor: true };
    AutomacoesAPI.passos.mockResolvedValue({ data: catalogoReal });
    AutomacoesAPI.show.mockResolvedValue({ data: automacao() });
  });

  it('o Guia criou no motor novo: a tela passa a ser a da automação', async () => {
    const wrapper = montar();
    await flushPromises();
    wrapper.findComponent(GuiaFalso).vm.$emit('execucao', {
      passos: [{ ok: true, acao: 'POST autonomia/automacoes', registro: 7 }],
    });
    expect(routerReplace).toHaveBeenCalledWith({
      name: 'automacoes_guia_editar',
      params: { accountId: 1, id: 7 },
    });
  });

  it('sem a porta, criar no motor novo não troca a tela', async () => {
    flags.value = {};
    const wrapper = montar();
    await flushPromises();
    wrapper.findComponent(GuiaFalso).vm.$emit('execucao', {
      passos: [{ ok: true, acao: 'POST autonomia/automacoes', registro: 7 }],
    });
    expect(routerReplace).not.toHaveBeenCalled();
  });

  it('mostra a automação em frase, com o id e o motor para o Guia', async () => {
    abrirNoMotor(7);
    const wrapper = montar();
    await flushPromises();
    expect(AutomacoesAPI.show).toHaveBeenCalledWith(7);
    expect(wrapper.find('h1').text()).toBe('Agradecer');
    expect(wrapper.find('[data-gatilho]').text()).toContain(
      'AUTOMACAO_LIVRE.GATILHOS.CONVERSA_RESOLVIDA'
    );
    const guia = wrapper.findComponent(GuiaFalso);
    expect(guia.props('automacaoId')).toBe(7);
    expect(guia.props('automacaoDoMotor')).toBe(true);
    expect(guia.props('pedidoInicial')).toBe('');
  });

  it('Ligar leva a versão que a tela mostrou', async () => {
    abrirNoMotor(7);
    AutomacoesAPI.ligar.mockResolvedValue({
      data: { id: 7, ativa: true, versao: { id: 70 } },
    });
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-ligar]').trigger('click');
    await flushPromises();
    expect(AutomacoesAPI.ligar).toHaveBeenCalledWith(7, 70);
    expect(wrapper.find('[data-ligada]').exists()).toBe(true);
    expect(useAlert).toHaveBeenCalledWith('AUTOMACOES.LISTA.LIGOU');
  });

  it('outra pessoa salvou no meio: lê de novo e avisa', async () => {
    abrirNoMotor(7);
    AutomacoesAPI.ligar.mockRejectedValue({ response: { status: 409 } });
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-ligar]').trigger('click');
    await flushPromises();
    expect(AutomacoesAPI.show).toHaveBeenCalledTimes(2);
    expect(useAlert).toHaveBeenCalledWith(
      'AUTOMACAO_MODELOS.GUIA.VERSAO_MUDOU'
    );
  });

  it('o Guia ajustou: o resumo é lido de novo', async () => {
    abrirNoMotor(7);
    const wrapper = montar();
    await flushPromises();
    wrapper.findComponent(GuiaFalso).vm.$emit('execucao', {
      passos: [
        { ok: true, acao: 'PATCH autonomia/automacoes/:id', registro: 7 },
      ],
    });
    await flushPromises();
    expect(AutomacoesAPI.show).toHaveBeenCalledTimes(2);
  });

  it('o modo manual abre esta automação no editor', async () => {
    abrirNoMotor(7);
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-modo-manual]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'automacoes_livre_editar',
      params: { accountId: 1, id: 7 },
    });
  });
});
