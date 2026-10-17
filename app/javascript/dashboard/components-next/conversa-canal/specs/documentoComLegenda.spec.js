/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import { provideMessageContext } from '../../message/provider.js';
import TextBubble from '../../message/bubbles/Text/Index.vue';
import DocumentoDoWhatsapp from '../midia/DocumentoDoWhatsapp.vue';
import { PELES, fornecerPele } from '../pele';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// O balão em si (cores, hora, remetente) tem os próprios testes; aqui importa o miolo.
vi.mock('next/message/bubbles/Base.vue', () => ({
  default: { template: '<div data-balao><slot /></div>' },
}));
vi.mock('dashboard/composables/useTranslations', () => ({
  useTranslations: () => ({
    hasTranslations: computed(() => false),
    translationContent: computed(() => ''),
  }),
}));

// Teste do Rodrigo em 17/10 (conta 16): PDF com legenda vinha como pílula do Chatwoot
// e a foto mandada como documento sem a miniatura que o WhatsApp mostra.
const PDF = {
  id: 1,
  fileType: 'file',
  extension: 'pdf',
  fileSize: 4 * 1024 * 1024,
  dataUrl: 'https://s3.test/condicoes-gerais-16.pdf',
};
const FOTO = {
  id: 2,
  fileType: 'file',
  extension: 'png',
  fileSize: 20 * 1024,
  dataUrl: 'https://s3.test/foto.png',
  thumbUrl: 'https://s3.test/foto-mini.png',
};

const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en },
    missingWarn: false,
    fallbackWarn: false,
  });

const montar = (filho, { pele = PELES.WHATSAPP, anexos = [PDF] } = {}) =>
  mount(
    defineComponent({
      setup() {
        fornecerPele(computed(() => pele));
        provideMessageContext({
          content: ref('OI'),
          attachments: ref(anexos),
          contentAttributes: ref({}),
          messageType: ref(1),
          status: ref('sent'),
          orientation: ref('right'),
          variant: ref('agent'),
        });
        return () => h(filho);
      },
    }),
    {
      global: {
        plugins: [i18n()],
        stubs: { TranslationToggle: true },
        directives: {
          dompurifyHtml: (el, { value }) => {
            el.innerHTML = value;
          },
        },
      },
    }
  );

describe('documento com legenda (#1702)', () => {
  it('com a pele, o cartão do documento vai em cima e a legenda embaixo, sem a pílula', () => {
    const balao = montar(TextBubble);

    const cartao = balao.find('[data-documento-do-whatsapp]');
    expect(cartao.exists()).toBe(true);
    expect(cartao.text()).toContain('condicoes-gerais-16.pdf');
    const html = balao.html();
    expect(html).toContain('OI');
    expect(html.indexOf('data-documento-do-whatsapp')).toBeLessThan(
      html.indexOf('OI')
    );
    expect(balao.text().match(/condicoes-gerais-16\.pdf/g)).toHaveLength(1);
  });

  it('sem a pele, segue o balão do Chatwoot', () => {
    const balao = montar(TextBubble, { pele: null });

    expect(balao.find('[data-documento-do-whatsapp]').exists()).toBe(false);
  });

  it('foto mandada como documento mostra a miniatura no lugar do ícone', () => {
    const cartao = montar(
      defineComponent({ setup: () => () => h(DocumentoDoWhatsapp) }),
      { anexos: [FOTO] }
    );

    const miniatura = cartao.find('[data-miniatura-do-documento]');
    expect(miniatura.attributes('src')).toBe(FOTO.thumbUrl);
    expect(cartao.find('svg').exists()).toBe(false);
  });

  it('PDF continua com o ícone vermelho, sem miniatura', () => {
    const cartao = montar(
      defineComponent({ setup: () => () => h(DocumentoDoWhatsapp) })
    );

    expect(cartao.find('[data-miniatura-do-documento]').exists()).toBe(false);
    expect(cartao.find('svg').exists()).toBe(true);
  });
});
