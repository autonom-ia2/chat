import { flushPromises, shallowMount } from '@vue/test-utils';
import { lerGestao } from '../../gestaoDoAnuncio';
import CuidarAnuncioPage from '../CuidarAnuncioPage.vue';
import CuidarComentarios from '../CuidarComentarios.vue';

// #2212 (B2): a página põe a tela de cuidar no endereço do anúncio e volta para ele no painel.
vi.mock('../../gestaoDoAnuncio', () => ({ lerGestao: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: () => true,
}));
// #2520: a tela abre sem a gestão; só com ela lê o anúncio na gestão.
const flags = vi.hoisted(() => ({ ligadas: ['meta_ads_gestao'] }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flags.ligadas.includes(flag),
  }),
}));
const push = vi.fn();
const rota = vi.hoisted(() => ({
  params: { accountId: '9', adId: '120' },
  query: {},
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));

describe('CuidarAnuncioPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    rota.query = {};
    flags.ligadas = ['meta_ads_gestao'];
  });

  it('sem meta_ads_gestao: abre a tela sem perguntar à gestão, e sem cabeçalho (#2520)', async () => {
    flags.ligadas = [];
    const wrapper = shallowMount(CuidarAnuncioPage);
    await flushPromises();

    expect(lerGestao).not.toHaveBeenCalled();
    expect(wrapper.findComponent(CuidarComentarios).props('post')).toBeNull();
  });

  it('o alvo é o anúncio, com o post da gestão no cabeçalho e a caixa vinda do servidor', async () => {
    lerGestao.mockResolvedValue({
      name: 'Video 2',
      post: { message: 'E-book' },
    });
    const wrapper = shallowMount(CuidarAnuncioPage);
    await flushPromises();

    const tela = wrapper.findComponent(CuidarComentarios);
    expect(lerGestao).toHaveBeenCalledWith('120');
    expect(tela.props()).toMatchObject({
      target: { kind: 'ad', id: '120' },
      post: { text: 'E-book' },
      origin: 'anuncio',
      canManage: true,
    });
    expect(tela.props('inboxPathOf')(7)).toBe('/app/accounts/9/inbox/7');
  });

  it('voltar leva ao anúncio aberto no painel', async () => {
    lerGestao.mockResolvedValue(null);
    const wrapper = shallowMount(CuidarAnuncioPage);
    await flushPromises();

    expect(wrapper.findComponent(CuidarComentarios).props('post')).toBeNull();
    wrapper.findComponent(CuidarComentarios).vm.$emit('back');

    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_meta_ads_index',
      params: { accountId: '9' },
      query: { aba: 'resultado', anuncio: '120' },
    });
  });

  // #2479: aberto pelo "Qual post?" de Agentes, o "Voltar" leva a Agentes; "Ver no post" segue indo ao anúncio.
  it('aberto de Agentes: voltar leva a Agentes, com o texto dizendo isso; responder vai ao anúncio', async () => {
    rota.query = { de: 'agentes' };
    lerGestao.mockResolvedValue(null);
    const wrapper = shallowMount(CuidarAnuncioPage);
    await flushPromises();

    const tela = wrapper.findComponent(CuidarComentarios);
    expect(tela.props('backLabel')).toBe(
      'AGENTS.AGENTE_DO_POST.CRIAR.VOLTAR_AGENTES'
    );
    tela.vm.$emit('back');
    expect(push).toHaveBeenLastCalledWith({
      name: 'autonomia_agents_index',
      params: { accountId: '9' },
    });

    tela.vm.$emit('reply');
    expect(push).toHaveBeenLastCalledWith({
      name: 'campaigns_meta_ads_index',
      params: { accountId: '9' },
      query: { aba: 'resultado', anuncio: '120' },
    });
  });
});
