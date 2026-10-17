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
// recebeu; a resposta rápida só mostra, com a dica. O endereço vem da foto do envio
// (#1717), no formato que a API de mensagens entrega (sem processed_params).
const AGENDAMENTO = {
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
const LOJA = {
  name: 'loja',
  language: 'pt_BR',
  components: [
    {
      type: 'BUTTONS',
      buttons: [
        { type: 'URL', text: 'Catálogo', url: 'https://loja.test/catalogo' },
        { type: 'URL', text: 'Pedido', url: 'https://loja.test/p/{{1}}' },
      ],
    },
  ],
};
const CARROSSEL = {
  name: 'vitrine',
  language: 'pt_BR',
  components: [
    {
      type: 'CAROUSEL',
      cards: [
        {
          components: [
            { type: 'BODY', text: 'Tênis' },
            {
              type: 'BUTTONS',
              buttons: [
                {
                  type: 'URL',
                  text: 'Comprar',
                  url: 'https://loja.test/{{1}}',
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};

const montar = ({ modelo = AGENDAMENTO, enviado, parte = 'botoes' } = {}) =>
  mount(
    defineComponent({
      setup() {
        fornecerPele(computed(() => PELES.WHATSAPP));
        provideMessageContext({
          inboxId: ref(1),
          status: ref('sent'),
          additionalAttributes: ref({
            templateParams: { name: modelo.name, language: 'pt_BR', enviado },
          }),
        });
        return () => h(BotoesDoModelo, { parte });
      },
    }),
    {
      global: {
        plugins: [
          createStore({
            getters: {
              'inboxes/getInbox': () => () => ({
                message_templates: [AGENDAMENTO, LOJA, CARROSSEL],
              }),
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

const ENVIADO_AGENDAMENTO = {
  versao: 1,
  botoes: [
    {
      tipo: 'url',
      texto: 'Ver meu horário',
      url: 'https://chat.hub2you.ai/b/XUReedXQ',
    },
    { tipo: 'quick_reply', texto: 'Parar avisos' },
  ],
};

describe('botões do modelo (#1702, B2)', () => {
  it('o botão de link abre, em outra aba, o endereço da foto do envio', () => {
    const botoes = montar({ enviado: ENVIADO_AGENDAMENTO });

    const link = botoes.find('a[data-tipo-do-botao="URL"]');
    expect(link.attributes('href')).toBe('https://chat.hub2you.ai/b/XUReedXQ');
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toContain('noopener');
  });

  it('a resposta rápida não é link e mostra a dica', () => {
    const botoes = montar({ enviado: ENVIADO_AGENDAMENTO });

    const resposta = botoes.find('[data-tipo-do-botao="QUICK_REPLY"]');
    expect(resposta.element.tagName).toBe('DIV');
    expect(resposta.attributes('title')).toBe(
      en.CONVERSA_CANAL.MODELO.SO_NO_CELULAR
    );
  });

  it('mensagem anterior à foto do envio: o botão de link só mostra', () => {
    const botoes = montar();

    expect(botoes.find('a').exists()).toBe(false);
    expect(botoes.text()).toContain('Ver meu horário');
  });

  it('cada botão de link pega o endereço da própria posição (fixo antes do variável)', () => {
    const botoes = montar({
      modelo: LOJA,
      enviado: {
        versao: 1,
        botoes: [
          { tipo: 'url', url: 'https://loja.test/catalogo' },
          { tipo: 'url', url: 'https://loja.test/p/123' },
        ],
      },
    });

    expect(botoes.findAll('a').map(a => a.attributes('href'))).toEqual([
      'https://loja.test/catalogo',
      'https://loja.test/p/123',
    ]);
  });

  it('modelo editado com os links trocados de lugar: cada rótulo não abre o link do outro', () => {
    const botoes = montar({
      modelo: LOJA,
      enviado: {
        versao: 1,
        botoes: [
          { tipo: 'url', texto: 'Pedido', url: 'https://loja.test/p/123' },
          { tipo: 'url', texto: 'Catálogo', url: 'https://loja.test/catalogo' },
        ],
      },
    });

    expect(botoes.find('a').exists()).toBe(false);
  });

  it('posição que no envio era outro tipo não vira link', () => {
    const botoes = montar({
      enviado: { versao: 1, botoes: [{ tipo: 'quick_reply' }] },
    });

    expect(botoes.find('a').exists()).toBe(false);
  });

  it('no carrossel, o botão de link do cartão também abre', () => {
    const carrossel = montar({
      modelo: CARROSSEL,
      parte: 'carrossel',
      enviado: {
        versao: 1,
        cartoes: [
          { botoes: [{ tipo: 'url', url: 'https://loja.test/tenis' }] },
        ],
      },
    });

    expect(carrossel.find('a').attributes('href')).toBe(
      'https://loja.test/tenis'
    );
  });
});

describe('enderecoDoBotao', () => {
  it('aceita http(s)', () => {
    expect(enderecoDoBotao('https://loja.test/x')).toBe('https://loja.test/x');
  });

  it('recusa o que não é http(s) e o que não é endereço', () => {
    expect(enderecoDoBotao('data:text/html,oi')).toBe('');
    expect(enderecoDoBotao('ftp://x.test/arquivo')).toBe('');
    expect(enderecoDoBotao('não é endereço')).toBe('');
    expect(enderecoDoBotao(undefined)).toBe('');
  });
});
