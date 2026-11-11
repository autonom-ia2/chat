import { mount } from '@vue/test-utils';
import AutomacaoPorta from '../components/AutomacaoPorta.vue';

// #2889 — os modelos da porta: o modelo vai ao Guia pelo estado da navegação, o destaque não se repete no grupo e o
// filtro por objetivo mostra só o grupo escolhido. A pergunta do topo tem spec própria (useIrAoGuia).
const { routerPush, camadas } = vi.hoisted(() => ({
  routerPush: vi.fn(),
  camadas: { value: [] },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave}|${valores.titulo}|${valores.texto}` : chave,
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 7 } }),
  useRouter: () => ({ push: routerPush }),
}));
vi.mock('../usePorta', () => ({
  usePorta: () => ({ ligada: { value: true }, camadas }),
}));

const ModeloDetalheStub = {
  name: 'ModeloDetalhe',
  props: ['modelo', 'desabilitado'],
  emits: ['usar'],
  methods: { open() {} },
  template: '<div data-detalhe-stub />',
};

const montar = () =>
  mount(AutomacaoPorta, {
    global: {
      mocks: { $t: chave => chave },
      stubs: { ModeloDetalhe: ModeloDetalheStub },
    },
  });

const idsEm = (wrapper, seletor) =>
  wrapper
    .findAll(`${seletor} [data-modelo]`)
    .map(no => no.attributes('data-modelo'));

describe('AutomacaoPorta', () => {
  beforeEach(() => {
    routerPush.mockClear();
    camadas.value = [];
  });

  it('mostra os 20 modelos uma vez só: destaque e grupos sem repetir', () => {
    const wrapper = montar();
    const destaque = idsEm(wrapper, '[data-destaque]');
    const grupos = idsEm(wrapper, '[data-grupo-lista]');
    expect(destaque).toEqual(['M02', 'M10', 'M14', 'M03', 'M06', 'M20']);
    expect(grupos.filter(id => destaque.includes(id))).toEqual([]);
    expect(new Set([...destaque, ...grupos]).size).toBe(20);
  });

  it('a corretora vê o destaque do ramo', () => {
    camadas.value = ['seguros', 'seguros/corretora'];
    const wrapper = montar();
    expect(idsEm(wrapper, '[data-destaque]')[0]).toBe('M01');
    expect(wrapper.find('[data-destaque] h3').text()).toContain(
      'AUTOMACAO_MODELOS.DESTAQUE_RAMO'
    );
  });

  it('o filtro mostra só o grupo escolhido, sem o destaque', async () => {
    const wrapper = montar();
    await wrapper.find('[data-grupo="EQUIPE"]').trigger('click');
    expect(wrapper.find('[data-destaque]').exists()).toBe(false);
    const grupos = wrapper
      .findAll('[data-grupo-lista]')
      .map(no => no.attributes('data-grupo-lista'));
    expect(grupos).toEqual(['EQUIPE']);
    expect(idsEm(wrapper, '[data-grupo-lista]')).toEqual(['M17', 'M18']);
    expect(
      wrapper.find('[data-grupo="EQUIPE"]').attributes('aria-pressed')
    ).toBe('true');
  });

  it('usar o modelo leva título e texto dele ao Guia', async () => {
    const wrapper = montar();
    await wrapper.find('[data-modelo="M10"]').trigger('click');
    const detalhe = wrapper.findComponent(ModeloDetalheStub);
    expect(detalhe.props('modelo').id).toBe('M10');
    detalhe.vm.$emit('usar', detalhe.props('modelo'));
    expect(routerPush.mock.calls[0][0].state).toEqual({
      pedidoAutomacao:
        'AUTOMACAO_MODELOS.PEDIDO|AUTOMACAO_MODELOS.ITENS.M10.TITULO|AUTOMACAO_MODELOS.ITENS.M10.TEXTO',
    });
  });
});
