import { computed } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Message from 'dashboard/components-next/message/Message.vue';
import {
  AGORA,
  gettersDaMontagem,
  montagem,
} from 'dashboard/components-next/message/specs/montarMensagem';
import {
  MESSAGE_STATUS,
  MESSAGE_TYPES,
} from 'dashboard/components-next/message/constants';
import { INBOX_FEATURE_MAP } from 'dashboard/composables/useInbox';
import {
  INBOX_FEATURE_MAP as MAPA_DA_TELA,
  INBOX_FEATURES,
} from 'shared/mixins/inboxMixin';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));
vi.mock('../useConversaDoInstagram', async original => ({
  ...(await original()),
  useInstagramDaConversa: () => ({
    ligado: computed(() => true),
    fuso: computed(() => undefined),
    contato: computed(() => null),
  }),
  useSequenciaDoInstagram: () => computed(() => new Map()),
}));

// #2079: o "Responder" ao lado do balão do Direct segue a regra do menu da mensagem.
// #2113: a caixa do Instagram envia a resposta citando (reply_to da Meta), na recebida e na enviada.
// A conversa (MessagesView, ReplyBox) lê o mapa do mixin; o composable tem a mesma lista.
const instagramResponde = (feature, mapa = MAPA_DA_TELA) =>
  mapa[feature].includes(INBOX_TYPES.INSTAGRAM);
const montar = ({
  podeOperar = true,
  canalResponde = true,
  content = 'Tem a bolsa em preto?',
  contentAttributes = {},
} = {}) => {
  const store = createStore({
    getters: {
      ...gettersDaMontagem,
      getSelectedChat: () => ({ id: 7, meta: {} }),
      canOperateConversation: () => () => podeOperar,
    },
  });
  return mount(Message, {
    props: {
      id: 1,
      messageType: MESSAGE_TYPES.INCOMING,
      status: MESSAGE_STATUS.SENT,
      content,
      contentAttributes,
      conversationId: 7,
      createdAt: AGORA,
      currentUserId: 1,
      sender: { id: 2, name: 'Cliente', type: 'Contact' },
      inboxSupportsReplyTo: {
        incoming: canalResponde && instagramResponde(INBOX_FEATURES.REPLY_TO),
        outgoing:
          canalResponde && instagramResponde(INBOX_FEATURES.REPLY_TO_OUTGOING),
      },
    },
    global: { ...montagem, plugins: [store] },
  });
};

const botaoResponder = wrapper =>
  wrapper.find('[aria-label="CONVERSA_CANAL.INSTAGRAM.RESPONDER"]');

describe('Responder na linha do Instagram', () => {
  it('a caixa do Instagram responde citando, na recebida e na enviada', () => {
    expect(instagramResponde(INBOX_FEATURES.REPLY_TO)).toBe(true);
    expect(instagramResponde(INBOX_FEATURES.REPLY_TO_OUTGOING)).toBe(true);
    expect(instagramResponde(INBOX_FEATURES.REPLY_TO, INBOX_FEATURE_MAP)).toBe(
      true
    );
    expect(
      instagramResponde(INBOX_FEATURES.REPLY_TO_OUTGOING, INBOX_FEATURE_MAP)
    ).toBe(true);
  });

  it('quem opera a conversa do Instagram vê o Responder', () => {
    const wrapper = montar();

    expect(wrapper.findComponent({ name: 'LinhaDoInstagram' }).exists()).toBe(
      true
    );
    expect(botaoResponder(wrapper).exists()).toBe(true);
  });

  it('canal que não envia a citação não mostra o Responder', () => {
    const wrapper = montar({ canalResponde: false });

    expect(wrapper.findComponent({ name: 'LinhaDoInstagram' }).exists()).toBe(
      true
    );
    expect(botaoResponder(wrapper).exists()).toBe(false);
  });

  it('quem só lê a conversa não vê o Responder', () => {
    const wrapper = montar({ podeOperar: false });

    expect(wrapper.findComponent({ name: 'LinhaDoInstagram' }).exists()).toBe(
      true
    );
    expect(botaoResponder(wrapper).exists()).toBe(false);
  });

  it('mensagem que o cliente apagou mostra o aviso, não a tradução do texto apagado', () => {
    const wrapper = montar({
      content: 'Esta mensagem foi apagada',
      contentAttributes: {
        deleted: true,
        translations: { pt_BR: 'Você tem a bolsa em preto?' },
      },
    });

    expect(wrapper.text()).toContain('Esta mensagem foi apagada');
    expect(wrapper.text()).not.toContain('Você tem a bolsa em preto?');
  });
});
