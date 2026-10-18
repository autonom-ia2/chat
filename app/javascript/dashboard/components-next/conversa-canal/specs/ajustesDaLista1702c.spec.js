/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createPinia } from 'pinia';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import { domPurifyConfig } from 'shared/helpers/HTMLSanitizer.js';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import Message from '../../message/Message.vue';
import CitacaoDoWhatsapp from '../CitacaoDoWhatsapp.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerFuso, fornecerPele } from '../pele';
import { previaDoAnexoCitado } from '../citacaoDoAnexo';
import { apagadaParaTodos } from '../apagadaDoWhatsapp';
import {
  buscarAteAchar,
  marcoDeNaoLidas,
  naoLidasCarregadas,
  novasDoCliente,
} from '../rolagemDaPele';

// Ajustes da lista e do balão (#1702c): o "pai" do álbum não conta como não lida,
// conversa nunca lida não busca páginas antigas, nome de documento citado sai
// escapado e o aviso da apagada segue o que a caixa faz no WhatsApp.
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en },
    missingWarn: false,
    fallbackWarn: false,
  });

// O álbum como a loja entrega (snake_case): o marcador da Cloud (não suportada,
// unsupported_kind 'unknown') e as fotos logo depois.
const daLoja = (id, criadaEm, extra = {}) => ({
  id,
  conversation_id: 7,
  message_type: MESSAGE_TYPES.INCOMING,
  created_at: criadaEm,
  content_attributes: {},
  ...extra,
});
const marcador = id =>
  daLoja(id, 1001, {
    content: null,
    content_attributes: { is_unsupported: true, unsupported_kind: 'unknown' },
  });
const foto = (id, criadaEm) =>
  daLoja(id, criadaEm, {
    attachments: [{ id, file_type: 'image', data_url: `https://x/${id}.jpg` }],
  });

describe('álbum na contagem de não lidas (achado 8)', () => {
  const lidaEm = 1000;
  const conversa = [
    daLoja(1, 900, { content: 'oi' }),
    marcador(2),
    foto(3, 1002),
    foto(4, 1003),
    daLoja(5, 1010, { content: 'viu as fotos?' }),
  ];

  it('a faixa não abre no marcador escondido nem conta ele', () => {
    expect(marcoDeNaoLidas(7, conversa, lidaEm)).toEqual({
      conversaId: 7,
      pronta: true,
      primeiraNaoLida: 3,
      quantidade: 3,
    });
  });

  it('o selo do botão de descer também não conta o marcador (camelCase)', () => {
    const daLista = [
      { id: 1, messageType: 0, contentAttributes: {} },
      {
        id: 2,
        messageType: 0,
        contentAttributes: { isUnsupported: true, unsupportedKind: 'unknown' },
      },
      { id: 3, messageType: 0, contentAttributes: {} },
      { id: 4, messageType: 0, contentAttributes: {} },
    ];
    expect(novasDoCliente(daLista, 2)).toBe(2);
  });

  it('não suportada de outro tipo (enquete) continua contando', () => {
    const enquete = daLoja(6, 1020, {
      content_attributes: { is_unsupported: true, unsupported_kind: 'poll' },
    });
    expect(marcoDeNaoLidas(7, [enquete], lidaEm).quantidade).toBe(1);
  });
});

describe('conversa nunca lida ao abrir (achado 13)', () => {
  it('sem agent_last_seen_at não busca páginas antigas nem monta faixa (abre no fim)', async () => {
    const mensagens = [daLoja(1, 900), daLoja(2, 901)];
    const carregarMais = vi.fn(async () => {});
    await buscarAteAchar({
      achou: () => naoLidasCarregadas(mensagens, null),
      temMais: () => true,
      carregarMais,
    });
    expect(carregarMais).not.toHaveBeenCalled();
    expect(marcoDeNaoLidas(7, mensagens, null)).toMatchObject({
      primeiraNaoLida: null,
      quantidade: 0,
    });
  });

  it('com leitura, segue buscando até alcançar a última lida', async () => {
    const mensagens = [daLoja(5, 1005)];
    const carregarMais = vi.fn(async () => {
      mensagens.unshift(daLoja(4, 990));
    });
    await buscarAteAchar({
      achou: () => naoLidasCarregadas(mensagens, 1000),
      temMais: () => true,
      carregarMais,
    });
    expect(carregarMais).toHaveBeenCalledTimes(1);
  });
});

describe('nome do documento citado (achado 9)', () => {
  const t = chave => chave;
  // O endereço do Active Storage traz o nome codificado.
  const documento = {
    attachments: [
      {
        file_type: 'file',
        data_url:
          "https://x/rails/active_storage/blobs/redirect/abc/%3Cb%3Econtrato%3C%2Fb%3E%20%26%20%22cia%22%20d'o.pdf",
      },
    ],
  };

  it('sai escapado (& < > " \')', () => {
    expect(previaDoAnexoCitado(documento, t)).toBe(
      '&lt;b&gt;contrato&lt;/b&gt; &amp; &quot;cia&quot; d&#039;o.pdf'
    );
  });

  it('na citação, a pessoa lê o nome como foi escrito, sem virar negrito', () => {
    const wrapper = mount(CitacaoDoWhatsapp, {
      props: {
        mensagem: {
          id: 9,
          messageType: MESSAGE_TYPES.INCOMING,
          sender: { name: 'Maria' },
        },
        previa: previaDoAnexoCitado(documento, t),
      },
      global: {
        plugins: [i18n(), [VueDOMPurifyHTML, domPurifyConfig]],
      },
    });
    expect(wrapper.find('b').exists()).toBe(false);
    expect(wrapper.text()).toContain('<b>contrato</b> & "cia" d\'o.pdf');
  });
});

describe('apagada pela equipe conforme a caixa (achado 4)', () => {
  const CAIXAS = {
    1: { id: 1, channel_type: 'Channel::Whatsapp', provider: 'whatsapp_cloud' },
    2: { id: 2, channel_type: 'Channel::Whatsapp', provider: 'default' },
    3: { id: 3, channel_type: 'Channel::Api', waha_provider: true },
    4: { id: 4, channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
  };
  const loja = () =>
    createStore({
      getters: {
        'inboxes/getInbox': () => id => CAIXAS[id] || {},
        'inboxes/getInboxById': () => id => CAIXAS[id] || {},
        'globalConfig/get': () => ({}),
        'globalConfig/isOnChatwootCloud': () => false,
        'accounts/getAccount': () => () => ({}),
        getSelectedChat: () => ({}),
        getSelectedChatAttachments: () => [],
        getCurrentAccountId: () => 1,
        getCurrentUser: () => ({}),
        getUISettings: () => ({}),
      },
    });

  const montar = props =>
    mount(
      defineComponent({
        setup() {
          fornecerPele(computed(() => PELES.WHATSAPP));
          fornecerFuso(computed(() => 'America/Sao_Paulo'));
          return () =>
            h(Message, {
              id: 1,
              messageType: MESSAGE_TYPES.OUTGOING,
              status: MESSAGE_STATUS.SENT,
              content: 'Olá',
              conversationId: 7,
              createdAt: 1760720400,
              currentUserId: 1,
              sender: { id: 1, name: 'Ana', type: 'User' },
              ...props,
            });
        },
      }),
      {
        global: {
          ...montagem,
          plugins: [loja(), i18n(), createPinia()],
          stubs: { ...montagem.stubs, NovaConversaEntrada: true },
        },
      }
    );
  const aviso = wrapper => wrapper.find('[data-apagada-pela-equipe]');

  it.each([
    ['Cloud API', 1],
    ['360dialog', 2],
  ])('%s: só aqui, o cliente ainda vê', (_, inboxId) => {
    const wrapper = montar({ inboxId, contentAttributes: { deleted: true } });
    expect(aviso(wrapper).text()).toBe(
      'You deleted this message only here. The customer still sees it.'
    );
    expect(aviso(wrapper).attributes()).toHaveProperty('data-apagada-so-aqui');
  });

  it('WAHA: o conector apaga no WhatsApp, texto do app', () => {
    const wrapper = montar({
      inboxId: 3,
      contentAttributes: { deleted: true },
    });
    expect(aviso(wrapper).text()).toBe('You deleted this message');
    expect(aviso(wrapper).attributes()).not.toHaveProperty(
      'data-apagada-so-aqui'
    );
  });

  it('revogada_no_canal: texto do app em qualquer caixa', () => {
    const wrapper = montar({
      inboxId: 1,
      contentAttributes: { deleted: true, revogadaNoCanal: true },
    });
    expect(aviso(wrapper).text()).toBe('You deleted this message');
  });

  it('a regra pura: Twilio e caixa desconhecida contam como só aqui', () => {
    expect(apagadaParaTodos({ caixa: CAIXAS[4], contentAttributes: {} })).toBe(
      false
    );
    expect(apagadaParaTodos({ caixa: undefined, contentAttributes: {} })).toBe(
      false
    );
    expect(apagadaParaTodos({ caixa: CAIXAS[3], contentAttributes: {} })).toBe(
      true
    );
    expect(
      apagadaParaTodos({
        caixa: CAIXAS[4],
        contentAttributes: { revogadaNoCanal: true },
      })
    ).toBe(true);
  });
});
