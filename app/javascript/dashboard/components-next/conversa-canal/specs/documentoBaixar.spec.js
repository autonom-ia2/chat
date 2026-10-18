/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import { provideMessageContext } from '../../message/provider.js';
import { PELES, fornecerPele } from '../pele';
import DocumentoDoWhatsapp from '../midia/DocumentoDoWhatsapp.vue';
import AudioDoWhatsapp from '../audio/AudioDoWhatsapp.vue';
import {
  baixarPeloLink,
  doActiveStorage,
  enderecoParaBaixar,
} from '../midia/enderecoParaBaixar';
import { baixarAudio } from '../audio/useAudioParaBaixar';

// Produção (17/10): baixar dava erro. O bucket não tem CORS, e o fetch do painel
// falhava depois do redirect do Active Storage. Agora é link direto para o Active
// Storage com `disposition=attachment`: o próprio armazenamento entrega como download.
const DO_STORAGE =
  'https://app.test/rails/active_storage/blobs/redirect/abc--1/boleto%20maio.pdf';
const DE_FORA = 'https://cdn.externo.test/arquivo.pdf';

const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en },
    missingWarn: false,
    fallbackWarn: false,
  });

describe('endereço para baixar (#1702)', () => {
  it('pede o download ao Active Storage', () => {
    const endereco = new URL(enderecoParaBaixar(DO_STORAGE));
    expect(endereco.pathname).toBe(
      '/rails/active_storage/blobs/redirect/abc--1/boleto%20maio.pdf'
    );
    expect(endereco.searchParams.get('disposition')).toBe('attachment');
  });

  it('mantém o que já vinha no endereço e não repete o parâmetro', () => {
    const endereco = new URL(
      enderecoParaBaixar(`${DO_STORAGE}?t=1&disposition=inline`)
    );
    expect(endereco.searchParams.get('t')).toBe('1');
    expect(endereco.searchParams.getAll('disposition')).toEqual(['attachment']);
  });

  it('endereço relativo do Active Storage também vira download', () => {
    expect(
      enderecoParaBaixar('/rails/active_storage/blobs/proxy/x/a.ogg')
    ).toContain('disposition=attachment');
  });

  it('endereço de fora fica como está', () => {
    expect(enderecoParaBaixar(DE_FORA)).toBe(DE_FORA);
    expect(doActiveStorage(DE_FORA)).toBe(false);
  });

  it('sem endereço, nada', () => {
    expect(enderecoParaBaixar('')).toBe('');
    expect(enderecoParaBaixar(undefined)).toBe('');
    expect(doActiveStorage(null)).toBe(false);
  });
});

describe('baixar pelo link, sem fetch (#1702)', () => {
  let clicados;

  beforeEach(() => {
    clicados = [];
    global.fetch = vi.fn();
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
      function registrar() {
        clicados.push({
          href: this.href,
          download: this.download,
          target: this.target,
        });
      }
    );
  });

  afterEach(() => vi.restoreAllMocks());

  it('do Active Storage: baixa com o nome, na mesma aba', () => {
    baixarPeloLink({ url: DO_STORAGE, nome: 'boleto maio.pdf' });

    expect(global.fetch).not.toHaveBeenCalled();
    expect(clicados).toHaveLength(1);
    expect(clicados[0].href).toContain('disposition=attachment');
    expect(clicados[0].download).toBe('boleto maio.pdf');
    expect(clicados[0].target).toBe('');
    expect(document.querySelector('a[download]')).toBeNull();
  });

  it('de fora: abre noutra aba', () => {
    baixarPeloLink({ url: DE_FORA, nome: 'arquivo.pdf' });

    expect(clicados[0].href).toBe(DE_FORA);
    expect(clicados[0].target).toBe('_blank');
  });

  it('o "Baixar" do menu do áudio usa o mesmo link', () => {
    baixarAudio({
      dataUrl: 'https://app.test/rails/active_storage/blobs/redirect/x/voz.ogg',
      fileType: 'audio',
    });

    expect(global.fetch).not.toHaveBeenCalled();
    expect(clicados[0].href).toContain('disposition=attachment');
    expect(clicados[0].download).toBe('voz.ogg');
  });
});

describe('cartão do documento (#1702)', () => {
  const montar = anexo =>
    mount(
      defineComponent({
        setup() {
          provideMessageContext({
            orientation: ref('right'),
            attachments: ref([{ fileType: 'file', fileSize: 2048, ...anexo }]),
          });
          return () => h(DocumentoDoWhatsapp);
        },
      }),
      { global: { plugins: [i18n()] } }
    );

  it('o botão de baixar é um link direto para o Active Storage com o nome', () => {
    const link = montar({ dataUrl: DO_STORAGE, extension: 'pdf' }).find(
      'a[data-baixar-documento]'
    );

    expect(link.attributes('href')).toContain('disposition=attachment');
    expect(link.attributes('download')).toBe('boleto maio.pdf');
    expect(link.attributes('target')).toBeUndefined();
    expect(link.attributes('aria-label')).toBe('Download boleto maio.pdf');
  });

  it('arquivo de fora abre noutra aba', () => {
    const link = montar({ dataUrl: DE_FORA, extension: 'pdf' }).find(
      'a[data-baixar-documento]'
    );

    expect(link.attributes('href')).toBe(DE_FORA);
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(link.attributes('download')).toBeUndefined();
  });

  it('PDF com prévia: a 1ª página em cima e a faixa com nome e "PDF • tamanho"', () => {
    const cartao = montar({
      dataUrl: DO_STORAGE,
      extension: 'pdf',
      thumbUrl: 'https://app.test/rails/active_storage/representations/p.png',
    });

    const previa = cartao.find('[data-previa-do-pdf]');
    expect(previa.attributes('src')).toBe(
      'https://app.test/rails/active_storage/representations/p.png'
    );
    const raiz = cartao.find('[data-documento-do-whatsapp]').element;
    expect(raiz.firstElementChild).toBe(previa.element);
    expect(cartao.text()).toContain('boleto maio.pdf');
    expect(cartao.text()).toContain('PDF • 2 KB');
    expect(cartao.find('svg').exists()).toBe(true);
  });

  it('prévia que não carrega some e fica o cartão sem prévia', async () => {
    const cartao = montar({
      dataUrl: DO_STORAGE,
      extension: 'pdf',
      thumbUrl: 'https://app.test/rails/active_storage/representations/p.png',
    });

    await cartao.find('[data-previa-do-pdf]').trigger('error');

    expect(cartao.find('[data-previa-do-pdf]').exists()).toBe(false);
    expect(cartao.find('a[data-baixar-documento]').exists()).toBe(true);
    expect(cartao.text()).toContain('PDF • 2 KB');
  });

  it('PDF sem thumbUrl e outro documento com thumbUrl não mostram prévia', () => {
    expect(
      montar({ dataUrl: DO_STORAGE, extension: 'pdf' })
        .find('[data-previa-do-pdf]')
        .exists()
    ).toBe(false);
    expect(
      montar({
        dataUrl:
          'https://app.test/rails/active_storage/blobs/redirect/y/a.docx',
        extension: 'docx',
        thumbUrl: 'https://app.test/t.png',
      })
        .find('[data-previa-do-pdf]')
        .exists()
    ).toBe(false);
  });
});

describe('áudio enviando (#1702)', () => {
  const montarAudio = status =>
    mount(
      defineComponent({
        setup() {
          fornecerPele(computed(() => PELES.WHATSAPP));
          provideMessageContext({
            sender: ref({ name: 'Ana' }),
            orientation: ref('right'),
            contentAttributes: ref({}),
            status: ref(status),
          });
          return () =>
            h(AudioDoWhatsapp, {
              attachment: { dataUrl: 'https://x.test/a.ogg' },
            });
        },
      }),
      {
        global: {
          plugins: [createStore({ getters: {} }), i18n()],
          stubs: { Avatar: true },
        },
      }
    );

  it('subindo: o anel girando com o relógio no lugar do play', () => {
    const audio = montarAudio('progress');

    const enviando = audio.find('[data-audio-enviando]');
    expect(enviando.exists()).toBe(true);
    expect(enviando.attributes('aria-label')).toBe('Sending audio');
    expect(enviando.find('.animate-spin').exists()).toBe(true);
    expect(enviando.find('.i-ph-clock').exists()).toBe(true);
    expect(audio.find('[data-tocar-audio]').exists()).toBe(false);
  });

  it('enviado: volta o play', () => {
    const audio = montarAudio('sent');

    expect(audio.find('[data-audio-enviando]').exists()).toBe(false);
    expect(audio.find('[data-tocar-audio]').exists()).toBe(true);
  });
});
