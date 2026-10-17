/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import AlbumDoWhatsapp from '../album/AlbumDoWhatsapp.vue';
import { useAlbunsDaConversa } from '../album/useAlbuns';
import { PELES, fornecerFuso, fornecerPele } from '../pele';
import { provideMessageContext } from '../../message/provider.js';
import en from '../../../i18n/locale/en/conversaCanal.json';

const BASE = Date.UTC(2026, 9, 16, 18, 0) / 1000;
const item = (id, fileType = 'image', extras = {}) => ({
  id,
  messageType: 0,
  senderId: 7,
  senderType: 'Contact',
  createdAt: BASE + id,
  status: 'sent',
  content: null,
  contentAttributes: {},
  attachments: [
    { id: id * 10, fileType, dataUrl: `https://x.test/${id}.${fileType}` },
  ],
  ...extras,
});

// A lista calcula os álbuns (como a MessageList) e o balão do 1º item desenha o mosaico.
const montar = (mensagens, { pele = PELES.WHATSAPP } = {}) => {
  const contexto = {};
  const Balao = defineComponent({
    setup() {
      provideMessageContext({
        id: ref(mensagens[0].id),
        createdAt: ref(mensagens[0].createdAt),
        status: ref(mensagens[0].status),
      });
      return () => h(AlbumDoWhatsapp);
    },
  });
  const Conversa = defineComponent({
    setup() {
      const { escondida } = useAlbunsDaConversa(
        computed(() => mensagens),
        computed(() => null)
      );
      contexto.escondida = escondida;
      return () => h(Balao);
    },
  });
  // A pele vem da tela da conversa (acima da lista), como no painel.
  const Tela = defineComponent({
    setup() {
      fornecerPele(computed(() => pele));
      fornecerFuso(computed(() => 'America/Sao_Paulo'));
      return () => h(Conversa);
    },
  });
  const store = createStore({
    getters: { getSelectedChatAttachments: () => [] },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en },
  });
  const wrapper = mount(Tela, {
    global: {
      plugins: [store, i18n],
      stubs: {
        BaseBubble: { template: '<div data-balao><slot /></div>' },
        GalleryView: {
          props: ['attachment'],
          template: '<div data-galeria>{{ attachment.data_url }}</div>',
        },
      },
    },
  });
  return { wrapper, contexto };
};

const quadros = wrapper => wrapper.findAll('[data-quadro-do-album]');

describe('AlbumDoWhatsapp (#1702)', () => {
  it('3 fotos: um balão só, a 1ª grande em cima e duas embaixo', () => {
    const { wrapper, contexto } = montar([item(1), item(2), item(3)]);
    expect(quadros(wrapper)).toHaveLength(3);
    expect(quadros(wrapper)[0].classes()).toContain('col-span-2');
    expect(quadros(wrapper)[1].classes()).toContain('aspect-square');
    expect(contexto.escondida(1)).toBe(false);
    expect(contexto.escondida(2)).toBe(true);
    expect(contexto.escondida(3)).toBe(true);
  });

  it('2 itens lado a lado; 4 em grade 2x2', () => {
    const dois = montar([item(1), item(2)]).wrapper;
    expect(quadros(dois).map(q => q.classes('aspect-[3/4]'))).toEqual([
      true,
      true,
    ]);
    const quatro = montar([1, 2, 3, 4].map(id => item(id))).wrapper;
    expect(quadros(quatro)).toHaveLength(4);
    expect(quadros(quatro).every(q => q.classes('aspect-square'))).toBe(true);
    expect(quatro.text()).not.toContain('+');
  });

  it('mais de 4: mostra 4 e "+N" escurecido sobre o 4º', () => {
    const { wrapper } = montar([1, 2, 3, 4, 5, 6].map(id => item(id)));
    expect(quadros(wrapper)).toHaveLength(4);
    expect(quadros(wrapper)[3].text()).toBe('+3');
    expect(quadros(wrapper)[3].attributes('aria-label')).toBe(
      '3 more photos and videos. Tap to open'
    );
  });

  it('cada quadro é um botão com rótulo; vídeo diz que é vídeo', () => {
    const { wrapper } = montar([item(1), item(2, 'video')]);
    const [primeiro, segundo] = quadros(wrapper);
    expect(primeiro.element.tagName).toBe('BUTTON');
    expect(primeiro.attributes('type')).toBe('button');
    expect(primeiro.attributes('aria-label')).toBe('Photo 1 of 2. Tap to open');
    expect(segundo.attributes('aria-label')).toBe('Video 2 of 2. Tap to open');
    expect(segundo.find('video').exists()).toBe(true);
    expect(wrapper.find('[role=group]').attributes('aria-label')).toBe(
      'Album with 2 photos and videos'
    );
  });

  it('clicar num quadro abre a galeria naquele item', async () => {
    const { wrapper } = montar([item(1), item(2), item(3)]);
    expect(wrapper.find('[data-galeria]').exists()).toBe(false);
    await quadros(wrapper)[2].trigger('click');
    expect(wrapper.find('[data-galeria]').text()).toBe(
      'https://x.test/3.image'
    );
  });

  it('sem pele não há álbum: nenhum item fica escondido', () => {
    const { contexto } = montar([item(1), item(2)], { pele: null });
    expect(contexto.escondida(2)).toBe(false);
  });
});
