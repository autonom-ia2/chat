/* eslint-disable vue/one-component-per-file */
import { defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import { provideMessageContext } from '../../message/provider.js';
import AnexosDoEmail from '../email/AnexosDoEmail.vue';
import { tocaNoNavegador } from '../email/videoNoNavegador';

// Produção, conversa 320 (#1869): resposta do Mail do iPhone com um .mov de 9,5 MB.
// O cartão não abria nem baixava.
const STORAGE = `${window.location.origin}/rails/active_storage/blobs/redirect/abc--1`;
const MOV = {
  id: 1,
  fileType: 'video',
  extension: 'mov',
  fileSize: 9961472,
  dataUrl: `${STORAGE}/IMG_4021.MOV`,
};
const MP4 = { ...MOV, id: 2, extension: 'mp4', dataUrl: `${STORAGE}/a.mp4` };
const FOTO = {
  id: 3,
  fileType: 'image',
  fileSize: 2048,
  dataUrl: `${STORAGE}/foto.jpg`,
  thumbUrl: `${window.location.origin}/rails/active_storage/representations/t.jpg`,
};
const PDF = { id: 4, fileType: 'file', dataUrl: `${STORAGE}/proposta.pdf` };
const DE_FORA = { id: 5, fileType: 'file', dataUrl: 'https://cdn.test/x.zip' };

// O Chrome responde "" para QuickTime e "maybe" para MP4.
const comoChrome = () =>
  vi
    .spyOn(HTMLMediaElement.prototype, 'canPlayType')
    .mockImplementation(tipo => (tipo === 'video/mp4' ? 'maybe' : ''));

const montar = anexos =>
  mount(
    defineComponent({
      setup() {
        provideMessageContext({ attachments: ref(anexos) });
        return () => h(AnexosDoEmail, { anexos });
      },
    }),
    {
      global: {
        plugins: [
          createStore({ getters: { getSelectedChatAttachments: () => [] } }),
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en },
            missingWarn: false,
            fallbackWarn: false,
          }),
        ],
        stubs: {
          GalleryView: {
            props: ['attachment'],
            template: '<div data-galeria>{{ attachment.data_url }}</div>',
          },
        },
      },
    }
  );

const baixar = (wrapper, id) =>
  wrapper.findAll('[data-baixar-anexo]').at(id - 1);

describe('anexos do e-mail (#1869)', () => {
  afterEach(() => vi.restoreAllMocks());

  it('pergunta ao navegador se toca; tipo desconhecido tenta', () => {
    comoChrome();
    expect(tocaNoNavegador('mov')).toBe(false);
    expect(tocaNoNavegador('MP4')).toBe(true);
    expect(tocaNoNavegador('xyz')).toBe(true);
  });

  it('.mov no Chrome: cartão de arquivo com ícone de vídeo, nome, tamanho e Baixar', () => {
    comoChrome();
    const wrapper = montar([MOV]);

    expect(wrapper.find('video').exists()).toBe(false);
    const abrir = wrapper.find('a[data-abrir-anexo]');
    expect(abrir.attributes('href')).toBe(MOV.dataUrl);
    expect(abrir.attributes('target')).toBe('_blank');
    expect(abrir.find('.i-lucide-file-play').exists()).toBe(true);
    expect(wrapper.text()).toContain('IMG_4021.MOV');
    expect(wrapper.text()).toContain('9.5 MB');

    const link = baixar(wrapper, 1);
    expect(link.attributes('href')).toContain('disposition=attachment');
    expect(link.attributes('download')).toBe('IMG_4021.MOV');
    expect(link.attributes('target')).toBeUndefined();
    expect(link.classes()).toContain('size-11');
  });

  it('vídeo que toca: primeira imagem e, ao tocar, abre na galeria', async () => {
    comoChrome();
    const wrapper = montar([MP4]);

    expect(wrapper.find('video').attributes('src')).toBe(
      `${MP4.dataUrl}#t=0.1`
    );
    await wrapper.find('button[data-abrir-video]').trigger('click');
    expect(wrapper.find('[data-galeria]').text()).toBe(MP4.dataUrl);
    expect(baixar(wrapper, 1).attributes('href')).toContain(
      'disposition=attachment'
    );
  });

  it('vídeo que dá erro ao carregar vira cartão de arquivo', async () => {
    comoChrome();
    const wrapper = montar([MP4]);

    await wrapper.find('video').trigger('error');
    expect(wrapper.find('video').exists()).toBe(false);
    expect(wrapper.find('a[data-abrir-anexo]').attributes('href')).toBe(
      MP4.dataUrl
    );
  });

  it('foto abre na galeria e baixa pelo Active Storage', async () => {
    const wrapper = montar([FOTO]);

    await wrapper.find('[data-anexo="foto"] button').trigger('click');
    expect(wrapper.find('[data-galeria]').text()).toBe(FOTO.dataUrl);
    const link = baixar(wrapper, 1);
    expect(link.attributes('href')).toContain('disposition=attachment');
    expect(link.attributes('download')).toBe('foto.jpg');
  });

  it('arquivo de fora do Active Storage: Baixar abre noutra aba', () => {
    const wrapper = montar([PDF, DE_FORA]);

    expect(baixar(wrapper, 1).attributes('download')).toBe('proposta.pdf');
    const deFora = baixar(wrapper, 2);
    expect(deFora.attributes('href')).toBe(DE_FORA.dataUrl);
    expect(deFora.attributes('target')).toBe('_blank');
    expect(deFora.attributes('download')).toBeUndefined();
  });

  it('o clique direito nos anexos fica com o menu do navegador', async () => {
    const pai = vi.fn();
    const wrapper = mount(
      defineComponent({
        setup() {
          provideMessageContext({ attachments: ref([PDF]) });
          return () =>
            h('div', { onContextmenu: pai }, [
              h(AnexosDoEmail, { anexos: [PDF] }),
            ]);
        },
      }),
      {
        global: {
          plugins: [
            createStore({ getters: { getSelectedChatAttachments: () => [] } }),
            createI18n({ legacy: false, locale: 'en', messages: { en } }),
          ],
        },
      }
    );

    await wrapper
      .find('a[data-abrir-anexo] svg, a[data-abrir-anexo] span')
      .trigger('contextmenu');
    expect(pai).not.toHaveBeenCalled();
  });
});
