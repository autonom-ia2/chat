/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import { provideMessageContext } from '../../message/provider.js';
import BotoesDoModelo from '../BotoesDoModelo.vue';
import { PELES, fornecerPele } from '../pele';
import { enderecoDoBotao } from '../useModeloDaMensagem';

// Teste do Rodrigo em 17/10 (conta 16): "Ver meu horário" e "Parar avisos" não
// clicavam. Decisão (B2, opção A): o botão de link abre o endereço que o cliente
// recebeu; a resposta rápida só mostra, com a dica.
const MODELO = {
  name: 'agendamento_1_hora_antes_v2',
  language: 'pt_BR',
  components: [
    {
      type: 'BUTTONS',
      buttons: [
        {
          type: 'URL',
          text: 'Ver meu horário',
          url: 'https://chat.hub2you.ai/b/{{1}}',
        },
        { type: 'QUICK_REPLY', text: 'Parar avisos' },
      ],
    },
  ],
};

const montar = (processedParams = {}) =>
  mount(
    defineComponent({
      setup() {
        fornecerPele(computed(() => PELES.WHATSAPP));
        provideMessageContext({
          inboxId: ref(1),
          status: ref('sent'),
          additionalAttributes: ref({
            templateParams: {
              name: MODELO.name,
              language: 'pt_BR',
              processedParams,
            },
          }),
        });
        return () => h(BotoesDoModelo, { parte: 'botoes' });
      },
    }),
    {
      global: {
        plugins: [
          createStore({
            getters: {
              'inboxes/getInbox': () => () => ({ message_templates: [MODELO] }),
            },
          }),
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en },
            missingWarn: false,
            fallbackWarn: false,
          }),
        ],
      },
    }
  );

describe('botões do modelo (#1702, B2)', () => {
  it('o botão de link abre o endereço com o final que foi na mensagem, em outra aba', () => {
    const botoes = montar({
      buttons: [
        { type: 'url', parameter: 'XUReedXQ' },
        { type: 'quick_reply', payload: 'stop_notices' },
      ],
    });

    const link = botoes.find('a[data-tipo-do-botao="URL"]');
    expect(link.attributes('href')).toBe('https://chat.hub2you.ai/b/XUReedXQ');
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toContain('noopener');
  });

  it('a resposta rápida não é link e mostra a dica', () => {
    const botoes = montar({
      buttons: [{ type: 'url', parameter: 'XUReedXQ' }],
    });

    const resposta = botoes.find('[data-tipo-do-botao="QUICK_REPLY"]');
    expect(resposta.element.tagName).toBe('DIV');
    expect(resposta.attributes('title')).toBe(
      en.CONVERSA_CANAL.MODELO.SO_NO_CELULAR
    );
  });

  it('sem o final variável gravado, o botão de link só mostra', () => {
    const botoes = montar();

    expect(botoes.find('a').exists()).toBe(false);
    expect(botoes.text()).toContain('Ver meu horário');
  });
});

describe('enderecoDoBotao', () => {
  it('endereço fixo vale como está', () => {
    expect(enderecoDoBotao('https://loja.test/catalogo')).toBe(
      'https://loja.test/catalogo'
    );
  });

  it('recusa o que não é http(s)', () => {
    expect(enderecoDoBotao('data:text/html,oi')).toBe('');
    expect(enderecoDoBotao('{{1}}', 'ftp://x.test/arquivo')).toBe('');
  });

  it('sem modelo ou sem o final, nada', () => {
    expect(enderecoDoBotao(undefined, 'abc')).toBe('');
    expect(enderecoDoBotao('https://x.test/b/{{1}}', '')).toBe('');
  });
});
