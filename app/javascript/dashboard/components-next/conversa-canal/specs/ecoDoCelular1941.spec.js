/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/conversaCanal.json';
import Message from '../../message/Message.vue';
import MessageContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import {
  gettersDaMontagem,
  montagem,
} from '../../message/specs/montarMensagem';
import { PELES, fornecerFuso, fornecerPele, fornecerPrimeiras } from '../pele';
import { continuaASequencia } from '../useSequenciaDaConversa';
import {
  PREFIXO_DO_CELULAR,
  semPrefixoDoCelular,
  textoDaMensagem,
} from '../ecoDoCelular';
import MessagePreview from '../../Conversation/ConversationCard/MessagePreview.vue';
import MessagePreviewAntigo from '../../../components/widgets/conversation/MessagePreview.vue';
import { CAIXA_WHATSAPP, lojaDaLista } from './lojaDaLista';

// #1941, item 3: mensagem que o atendente manda pelo celular (eco do app), nos três
// WhatsApp. Sem prefixo, 📱 ao lado da hora, nome de quem estava atribuído quando chegou
// (c2y_phone_author_id), nunca o remetente. Mensagem do painel não muda.
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

const JOAO = {
  id: 11,
  name: 'João Silva',
  available_name: 'João',
  thumbnail: '',
};
const AGENTES = [JOAO];
const COM_PREFIXO = `${PREFIXO_DO_CELULAR}\n\nBom dia, segue a cotação`;

const loja = () =>
  createStore({
    getters: {
      ...gettersDaMontagem,
      'agents/getAgentById': () => id =>
        AGENTES.find(agente => agente.id === Number(id)) || {},
    },
  });

const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en, pt_BR: ptBR },
    missingWarn: false,
    fallbackWarn: false,
  });

const dica = (el, { value }) => {
  el.dataset.dica = value?.content ?? value ?? '';
};

const montar = (props = {}, { pele = PELES.WHATSAPP } = {}) =>
  mount(
    defineComponent({
      setup() {
        fornecerPele(computed(() => pele));
        fornecerFuso(computed(() => 'America/Sao_Paulo'));
        fornecerPrimeiras(computed(() => new Set([1])));
        return () =>
          h(Message, {
            id: 1,
            messageType: MESSAGE_TYPES.OUTGOING,
            status: MESSAGE_STATUS.DELIVERED,
            content: 'Bom dia, segue a cotação',
            conversationId: 7,
            createdAt: 1760720400,
            currentUserId: 1,
            sender: null,
            ...props,
          });
      },
    }),
    {
      global: {
        ...montagem,
        plugins: [loja(), i18n()],
        directives: { ...montagem.directives, tooltip: dica },
        stubs: { ...montagem.stubs, MessageMeta: false },
      },
    }
  );

const celular = balao => balao.find('[data-eco-do-celular]');

describe('eco do celular no balão com a pele (#1941)', () => {
  it('com autor: nome de quem estava atribuído e 📱 ao lado da hora', () => {
    const balao = montar({
      contentAttributes: { externalEcho: true, c2yPhoneAuthorId: JOAO.id },
    });

    expect(balao.text()).toContain('João');
    expect(celular(balao).exists()).toBe(true);
    expect(celular(balao).text()).toBe('📱');
    expect(celular(balao).attributes('aria-label')).toBe('Sent from the phone');
    expect(celular(balao).attributes('data-dica')).toBe('Sent from the phone');
  });

  it('sem autor (sem atribuição): 📱 e nenhum nome', () => {
    const balao = montar({
      contentAttributes: { externalEcho: true, c2yPhoneAuthorId: null },
    });

    expect(celular(balao).exists()).toBe(true);
    expect(balao.text()).not.toContain('João');
    expect(balao.find('.font-medium.text-\\[12\\.8px\\]').exists()).toBe(false);
  });

  it('eco antigo do WAHA: sem prefixo, sem o dono da chave, com 📱', () => {
    const balao = montar({
      content: COM_PREFIXO,
      contentAttributes: { externalEcho: true },
      sender: { id: 99, name: 'Chat2You Admin', type: 'User' },
      senderId: 99,
      senderType: 'User',
    });

    expect(balao.text()).toContain('Bom dia, segue a cotação');
    expect(balao.text()).not.toContain('Enviado do WhatsApp');
    expect(balao.text()).not.toContain('Chat2You Admin');
    expect(celular(balao).exists()).toBe(true);
  });

  it('copiar (menu) leva o texto sem o prefixo', () => {
    const balao = montar({
      content: COM_PREFIXO,
      contentAttributes: { externalEcho: true },
    });

    const menu = balao.findComponent(MessageContextMenu);
    expect(menu.props('message').content).toBe('Bom dia, segue a cotação');
    expect(menu.props('enabledOptions').copy).toBe(true);
  });

  it('eco que era só o prefixo, sem anexo, não vira balão vazio', () => {
    const balao = montar({
      content: `${PREFIXO_DO_CELULAR}\n\n`,
      contentAttributes: { externalEcho: true },
    });

    expect(balao.find('[data-bubble-name]').exists()).toBe(false);
  });

  it('autor que saiu da conta: nenhum nome', () => {
    const balao = montar({
      contentAttributes: { externalEcho: true, c2yPhoneAuthorId: 404 },
      sender: { id: 99, name: 'Chat2You Admin', type: 'User' },
    });

    expect(balao.text()).not.toContain('Chat2You Admin');
    expect(celular(balao).exists()).toBe(true);
  });

  it('mensagem do painel não muda: nome do remetente, sem 📱, texto inteiro', () => {
    const balao = montar({
      content: COM_PREFIXO,
      contentAttributes: {},
      sender: { id: 5, name: 'Marina', type: 'User' },
      senderId: 5,
      senderType: 'User',
    });

    expect(balao.text()).toContain('Marina');
    expect(balao.text()).toContain('Enviado do WhatsApp');
    expect(celular(balao).exists()).toBe(false);
  });
});

describe('eco do celular no balão sem a pele (#1941)', () => {
  it('com autor: avatar e dica de quem estava atribuído, e 📱', () => {
    const balao = montar(
      {
        content: COM_PREFIXO,
        contentAttributes: { externalEcho: true, c2yPhoneAuthorId: JOAO.id },
      },
      { pele: null }
    );

    const avatar = balao.find('avatar-stub');
    expect(avatar.attributes('name')).toBe('João');
    expect(avatar.element.parentElement.dataset.dica).toBe(
      'Sent by João from the phone'
    );
    expect(balao.text()).not.toContain('Enviado do WhatsApp');
    expect(celular(balao).exists()).toBe(true);
  });

  it('sem autor: nunca o remetente (fica a caixa, como antes)', () => {
    const balao = montar(
      {
        contentAttributes: { externalEcho: true },
        sender: { id: 99, name: 'Chat2You Admin', type: 'User' },
      },
      { pele: null }
    );

    expect(balao.find('avatar-stub').attributes('name')).not.toBe(
      'Chat2You Admin'
    );
    expect(celular(balao).exists()).toBe(true);
  });

  it('mensagem do painel sem a pele: sem 📱', () => {
    const balao = montar(
      { sender: { id: 5, name: 'Marina', type: 'User' } },
      { pele: null }
    );

    expect(balao.find('avatar-stub').attributes('name')).toBe('Marina');
    expect(celular(balao).exists()).toBe(false);
  });
});

describe('sequência da conversa com eco (#1941)', () => {
  const eco = autor => ({
    messageType: MESSAGE_TYPES.OUTGOING,
    status: 'delivered',
    createdAt: 1760720400,
    sender: { id: 99, type: 'User' },
    senderId: 99,
    contentAttributes: { externalEcho: true, c2yPhoneAuthorId: autor },
  });

  it('ecos de autores diferentes abrem sequência (cada um leva o nome)', () => {
    expect(continuaASequencia(eco(11), eco(12), 'UTC')).toBe(false);
    expect(continuaASequencia(eco(11), eco(11), 'UTC')).toBe(true);
  });

  it('eco e mensagem do painel do mesmo remetente não se juntam', () => {
    const painel = { ...eco(11), contentAttributes: {} };
    expect(continuaASequencia(painel, eco(11), 'UTC')).toBe(false);
  });
});

describe('prefixo do conector (#1941)', () => {
  it('sai com as quebras de linha logo depois, sem regex', () => {
    expect(semPrefixoDoCelular(COM_PREFIXO)).toBe('Bom dia, segue a cotação');
    expect(
      semPrefixoDoCelular(`${PREFIXO_DO_CELULAR}\r\n\r\nOi\n\nTchau`)
    ).toBe('Oi\n\nTchau');
    expect(semPrefixoDoCelular(`${PREFIXO_DO_CELULAR}\n\n`)).toBe('');
  });

  it('só tira do eco; o resto fica igual', () => {
    expect(textoDaMensagem(COM_PREFIXO, {})).toBe(COM_PREFIXO);
    expect(textoDaMensagem(COM_PREFIXO, { external_echo: true })).toBe(
      'Bom dia, segue a cotação'
    );
    expect(textoDaMensagem(null, { externalEcho: true })).toBe(null);
    expect(textoDaMensagem('Oi', { externalEcho: true })).toBe('Oi');
  });
});

describe('prévia na lista de conversas (#1941)', () => {
  const montarPrevia = (Previa, message) =>
    mount(Previa, {
      props: { message: { inbox_id: CAIXA_WHATSAPP, ...message } },
      global: {
        plugins: [lojaDaLista({ ligada: true })],
        stubs: { FluentIcon: true },
      },
    });

  it.each([
    ['nova', MessagePreview],
    ['antiga', MessagePreviewAntigo],
  ])('prévia %s do eco sai sem o prefixo', (_, Previa) => {
    const texto = montarPrevia(Previa, {
      message_type: 1,
      content: COM_PREFIXO,
      content_attributes: { external_echo: true },
      attachments: [],
    }).text();

    expect(texto).toContain('Bom dia, segue a cotação');
    expect(texto).not.toContain('Enviado do WhatsApp');
  });

  it.each([
    ['nova', MessagePreview],
    ['antiga', MessagePreviewAntigo],
  ])(
    'prévia %s da foto cujo texto era só o prefixo diz "foto"',
    (_, Previa) => {
      const texto = montarPrevia(Previa, {
        message_type: 1,
        content: `${PREFIXO_DO_CELULAR}\n\n`,
        content_attributes: { external_echo: true },
        attachments: [{ file_type: 'image' }],
      }).text();

      expect(texto).toContain('CHAT_LIST.ATTACHMENTS.image.CONTENT');
      expect(texto).not.toContain('Enviado do WhatsApp');
    }
  );

  it.each([
    ['nova', MessagePreview],
    ['antiga', MessagePreviewAntigo],
  ])('prévia %s da mensagem do painel não muda', (_, Previa) => {
    const texto = montarPrevia(Previa, {
      message_type: 1,
      content: COM_PREFIXO,
      content_attributes: {},
      attachments: [],
    }).text();

    expect(texto).toContain('Enviado do WhatsApp');
  });
});

describe('textos (#1941)', () => {
  it('existe em pt_BR', () => {
    expect(ptBR.CONVERSA_CANAL.ECO_DO_CELULAR.ENVIADA_PELO_CELULAR).toBe(
      'Enviada pelo celular'
    );
    expect(ptBR.CONVERSA_CANAL.ECO_DO_CELULAR.ENVIADA_POR).toBe(
      'Enviada por {nome} pelo celular'
    );
  });
});
