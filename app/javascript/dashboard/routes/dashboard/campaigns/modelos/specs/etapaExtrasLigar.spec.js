import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import EtapaExtras from '../components/criar/EtapaExtras.vue';

// O número do botão "Ligar" no campo de telefone padrão (#1900): país com DDI,
// formato do país ao digitar e o valor em E.164 só quando é válido.
const rascunhoCom = valor => ({
  tipo: 'aviso',
  conteudo: {
    texto: 'Oi',
    topo: { tipo: 'nenhum' },
    rodape: '',
    botoes: [{ tipo: 'ligar', texto: 'Ligar', valor }],
  },
});

let wrapper;
const montar = valor => {
  wrapper = mount(EtapaExtras, {
    props: {
      rascunho: rascunhoCom(valor),
      'onUpdate:rascunho': novo => wrapper.setProps({ rascunho: novo }),
    },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
    attachTo: document.body,
  });
  return wrapper;
};
const numero = () => wrapper.get('[data-numero-do-telefone] input');
const valorDoBotao = () => wrapper.props('rascunho').conteudo.botoes[0].valor;

beforeAll(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => wrapper?.unmount());

describe('EtapaExtras: botão Ligar (#1900)', () => {
  it('começa no Brasil e grava o número completo quando é válido', async () => {
    montar('');
    expect(wrapper.get('[role="combobox"]').text()).toBe('🇧🇷 +55');
    await numero().setValue('1140000000');
    expect(valorDoBotao()).toBe('+551140000000');
  });

  it('número já gravado abre formatado no país dele', () => {
    montar('+5511987654321');
    expect(numero().element.value).toBe('(11) 98765-4321');
  });

  it('site e copiar código seguem com o campo de texto', () => {
    wrapper = mount(EtapaExtras, {
      props: {
        rascunho: {
          tipo: 'divulgacao',
          conteudo: {
            ...rascunhoCom('').conteudo,
            botoes: [
              { tipo: 'site', texto: 'Ver', valor: '' },
              { tipo: 'copiar_codigo', texto: '', valor: '' },
            ],
          },
        },
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
      },
    });
    expect(wrapper.find('[data-numero-do-telefone]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      en.MODELOS_WHATSAPP.TIPOS_DE_BOTAO.site.VALOR
    );
    expect(wrapper.text()).toContain(
      en.MODELOS_WHATSAPP.TIPOS_DE_BOTAO.copiar_codigo.VALOR
    );
  });

  it('número incompleto fica vazio e a conferência avisa', async () => {
    montar('');
    await numero().setValue('1198');
    expect(valorDoBotao()).toBe('');
    expect(wrapper.text()).toContain(
      en.MODELOS_WHATSAPP.EXTRAS.PROBLEMAS_DO_BOTAO.LIGAR_SEM_NUMERO
    );
  });
});
