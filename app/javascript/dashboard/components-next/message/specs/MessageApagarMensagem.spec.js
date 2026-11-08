import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Message from '../Message.vue';
import ContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';
import { AGORA, gettersDaMontagem, montagem } from './montarMensagem';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../constants';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

// Apagar mensagem (#1893): quem tem cargo só vê "Apagar" com a chave conversation_message_delete.
const montar = ({ customRoleId = null, permissions = [] } = {}) => {
  const store = createStore({
    getters: {
      ...gettersDaMontagem,
      getCurrentAccountId: () => 1,
      getCurrentCustomRoleId: () => customRoleId,
      getCurrentUser: () => ({ accounts: [{ id: 1, permissions }] }),
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
    },
    global: { ...montagem, plugins: [store] },
  });
};

const podeApagar = wrapper =>
  wrapper.findComponent(ContextMenu).props('enabledOptions').delete;

describe('apagar mensagem e a chave do cargo', () => {
  it('cargo sem a chave não vê apagar, mas segue respondendo', () => {
    const wrapper = montar({
      customRoleId: 5,
      permissions: ['conversation_participating_manage'],
    });

    expect(podeApagar(wrapper)).toBe(false);
    expect(
      wrapper.findComponent(ContextMenu).props('enabledOptions').replyTo
    ).toBe(true);
  });

  it('cargo com a chave vê apagar', () => {
    const wrapper = montar({
      customRoleId: 5,
      permissions: [
        'conversation_participating_manage',
        'conversation_message_delete',
      ],
    });

    expect(podeApagar(wrapper)).toBe(true);
  });

  it('sem cargo (administrador ou agente) segue vendo apagar', () => {
    expect(podeApagar(montar())).toBe(true);
  });
});
