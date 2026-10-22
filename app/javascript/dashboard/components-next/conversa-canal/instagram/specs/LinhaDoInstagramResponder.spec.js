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
const montar = ({ podeOperar = true, privada = false } = {}) => {
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
      content: 'Tem a bolsa em preto?',
      contentAttributes: {},
      conversationId: 7,
      createdAt: AGORA,
      currentUserId: 1,
      private: privada,
      sender: { id: 2, name: 'Cliente', type: 'Contact' },
      inboxSupportsReplyTo: { incoming: true, outgoing: true },
    },
    global: { ...montagem, plugins: [store] },
  });
};

const botaoResponder = wrapper =>
  wrapper.find('[aria-label="CONVERSA_CANAL.INSTAGRAM.RESPONDER"]');

describe('Responder na linha do Instagram', () => {
  it('quem opera a conversa vê o Responder', () => {
    const wrapper = montar();

    expect(wrapper.findComponent({ name: 'LinhaDoInstagram' }).exists()).toBe(
      true
    );
    expect(botaoResponder(wrapper).exists()).toBe(true);
  });

  it('quem só lê a conversa não vê o Responder', () => {
    const wrapper = montar({ podeOperar: false });

    expect(wrapper.findComponent({ name: 'LinhaDoInstagram' }).exists()).toBe(
      true
    );
    expect(botaoResponder(wrapper).exists()).toBe(false);
  });
});
