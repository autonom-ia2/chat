import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Message from '../Message.vue';
import ContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';
import { AGORA, gettersDaMontagem, montagem } from './montarMensagem';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../constants';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

// Quem só lê a conversa aberta (#1800): no menu da mensagem, só copiar, copiar o link e baixar o áudio.
const montar = ({ podeOperar, conversaAberta = 7, contentAttributes = {} }) => {
  const store = createStore({
    getters: {
      ...gettersDaMontagem,
      getSelectedChat: () => ({ id: conversaAberta, meta: {} }),
      canOperateConversation: () => () => podeOperar,
    },
  });
  return mount(Message, {
    props: {
      id: 1,
      messageType: MESSAGE_TYPES.INCOMING,
      status: MESSAGE_STATUS.SENT,
      content: 'Quero uma cotação',
      conversationId: 7,
      createdAt: AGORA,
      currentUserId: 1,
      sender: { id: 2, name: 'Cliente', type: 'Contact' },
      inboxSupportsReplyTo: { incoming: true, outgoing: true },
      contentAttributes,
    },
    global: { ...montagem, plugins: [store] },
  });
};

const opcoes = wrapper =>
  wrapper.findComponent(ContextMenu).props('enabledOptions');

describe('mensagem para quem só lê a conversa', () => {
  it('deixa só copiar e copiar o link', () => {
    const enabled = opcoes(montar({ podeOperar: false }));

    expect(enabled.copy).toBe(true);
    expect(enabled.copyLink).toBe(true);
    expect(enabled.delete).toBe(false);
    expect(enabled.translate).toBe(false);
    expect(enabled.replyTo).toBe(false);
  });

  it('quem opera continua com apagar, traduzir e responder', () => {
    const enabled = opcoes(montar({ podeOperar: true }));

    expect(enabled.delete).toBe(true);
    expect(enabled.translate).toBe(true);
    expect(enabled.replyTo).toBe(true);
  });

  // #2113: mensagem apagada (o cliente desfez o envio) não tem mais o que citar.
  it('mensagem apagada não deixa responder citando', () => {
    const enabled = opcoes(
      montar({ podeOperar: true, contentAttributes: { deleted: true } })
    );

    expect(enabled.replyTo).toBe(false);
  });

  it('fora da conversa aberta nada muda', () => {
    const enabled = opcoes(montar({ podeOperar: false, conversaAberta: 99 }));

    expect(enabled.delete).toBe(true);
  });
});
