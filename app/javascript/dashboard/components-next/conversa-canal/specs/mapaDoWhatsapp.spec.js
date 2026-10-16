/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { PELES, fornecerPele } from '../pele';
import MapaDoWhatsapp from '../midia/MapaDoWhatsapp.vue';

// Monta a miniatura dentro de uma conversa com (ou sem) a pele do WhatsApp.
const montar = ({
  pele = PELES.WHATSAPP,
  ponto = '-23.5613,-46.6565',
} = {}) => {
  const Conversa = defineComponent({
    setup() {
      fornecerPele(computed(() => pele));
      return () => h(MapaDoWhatsapp, { ponto });
    },
  });
  return mount(Conversa);
};

describe('MapaDoWhatsapp', () => {
  afterEach(() => {
    delete window.chatwootConfig;
  });

  it('mostra o mapa estático do Google no ponto, com a chave de navegador', () => {
    window.chatwootConfig = { googleMapsBrowserApiKey: 'chave-navegador' };
    const img = montar().find('[data-mapa-do-whatsapp] img');
    const url = new URL(img.attributes('src'));
    expect(url.origin + url.pathname).toBe(
      'https://maps.googleapis.com/maps/api/staticmap'
    );
    expect(url.searchParams.get('center')).toBe('-23.5613,-46.6565');
    expect(url.searchParams.get('key')).toBe('chave-navegador');
  });

  it('sem chave, sem pele ou sem ponto não mostra nada (fica o mapa desenhado)', () => {
    window.chatwootConfig = {};
    expect(montar().find('img').exists()).toBe(false);
    window.chatwootConfig = { googleMapsBrowserApiKey: 'chave-navegador' };
    expect(montar({ pele: null }).find('img').exists()).toBe(false);
    expect(montar({ ponto: '' }).find('img').exists()).toBe(false);
  });

  it('imagem recusada pelo Google some e deixa o mapa desenhado', async () => {
    window.chatwootConfig = { googleMapsBrowserApiKey: 'chave-navegador' };
    const wrapper = montar();
    await wrapper.find('img').trigger('error');
    await nextTick();
    expect(wrapper.find('img').exists()).toBe(false);
  });
});
