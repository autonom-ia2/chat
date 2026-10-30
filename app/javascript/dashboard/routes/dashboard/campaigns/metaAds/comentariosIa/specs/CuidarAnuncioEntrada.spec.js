import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/metaAdsComentariosIa.json';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';
import CuidarAnuncioEntrada from '../CuidarAnuncioEntrada.vue';

// #2212 (B2): a entrada no anúncio por dentro. Leva à tela de cuidar do anúncio e mostra o selo pelo estado guardado.
vi.mock('dashboard/api/comentariosIa', () => ({
  default: { getCuidadosDosAnuncios: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '9' } }),
}));

const montar = async (props = {}) => {
  const wrapper = mount(CuidarAnuncioEntrada, {
    props: { adId: '120', canManage: true, ...props },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ],
      stubs: {
        RouterLink: {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};
const destino = wrapper =>
  JSON.parse(wrapper.find('[data-ia-ad-entry-open]').attributes('data-to'));

describe('CuidarAnuncioEntrada', () => {
  beforeEach(() => vi.clearAllMocks());

  it('desligado, para quem pode mudar: chama para cuidar e leva à tela do anúncio', async () => {
    ComentariosIaAPI.getCuidadosDosAnuncios.mockResolvedValue({
      data: { cuidados: [{ ad_id: '999', care: 'on' }] },
    });
    const wrapper = await montar();

    expect(wrapper.find('[data-ia-ad-entry]').attributes('data-care')).toBe(
      'off'
    );
    expect(wrapper.find('[data-ia-ad-entry-badge]').exists()).toBe(false);
    expect(wrapper.find('[data-ia-ad-entry-open]').text()).toBe(
      'Cuidar dos comentários'
    );
    expect(destino(wrapper)).toEqual({
      name: 'campaigns_meta_ads_cuidar',
      params: { accountId: '9', adId: '120' },
    });
  });

  it('cuidando: mostra o selo e "Ver e mudar"', async () => {
    ComentariosIaAPI.getCuidadosDosAnuncios.mockResolvedValue({
      data: { cuidados: [{ ad_id: '120', care: 'on' }] },
    });
    const wrapper = await montar();

    expect(wrapper.find('[data-ia-ad-entry-badge]').text()).toBe(
      'Cuidando dos comentários'
    );
    expect(wrapper.find('[data-ia-ad-entry-open]').text()).toBe('Ver e mudar');
  });

  it('pausado, para quem só vê: selo de pausado e "Ver"', async () => {
    ComentariosIaAPI.getCuidadosDosAnuncios.mockResolvedValue({
      data: { cuidados: [{ ad_id: '120', care: 'paused' }] },
    });
    const wrapper = await montar({ canManage: false });

    expect(wrapper.find('[data-ia-ad-entry-badge]').text()).toBe('Pausado');
    expect(wrapper.find('[data-ia-ad-entry-open]').text()).toBe('Ver');
  });

  it('falha ao ler o estado: a entrada fica, sem selo', async () => {
    ComentariosIaAPI.getCuidadosDosAnuncios.mockRejectedValue(new Error('x'));
    const wrapper = await montar();

    expect(wrapper.find('[data-ia-ad-entry-badge]').exists()).toBe(false);
    expect(wrapper.find('[data-ia-ad-entry-open]').exists()).toBe(true);
  });
});
