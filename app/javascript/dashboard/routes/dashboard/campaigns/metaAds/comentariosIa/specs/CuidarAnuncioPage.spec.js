import { flushPromises, shallowMount } from '@vue/test-utils';
import { lerGestao } from '../../gestaoDoAnuncio';
import CuidarAnuncioPage from '../CuidarAnuncioPage.vue';
import CuidarComentarios from '../CuidarComentarios.vue';

// #2212 (B2): a página põe a tela de cuidar no endereço do anúncio e volta para ele no painel.
vi.mock('../../gestaoDoAnuncio', () => ({ lerGestao: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: () => true,
}));
const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '9', adId: '120' } }),
  useRouter: () => ({ push }),
}));

describe('CuidarAnuncioPage', () => {
  beforeEach(() => vi.clearAllMocks());

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
});
