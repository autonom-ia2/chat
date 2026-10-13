import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Message from '../Message.vue';
import { MESSAGE_TYPES, MESSAGE_STATUS } from '../constants';

// Monta a mensagem inteira (Message.vue) como a conversa do painel faz, com a loja e a rota mínimas.
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

const store = createStore({
  getters: {
    'inboxes/getInbox': () => () => ({}),
    'inboxes/getInboxById': () => () => ({}),
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

export const AGORA = Math.floor(Date.now() / 1000);

export const montarMensagem = (props = {}) =>
  mount(Message, {
    props: {
      id: 1,
      messageType: MESSAGE_TYPES.OUTGOING,
      status: MESSAGE_STATUS.SENT,
      content: 'Olá, tudo bem?',
      conversationId: 7,
      createdAt: AGORA,
      currentUserId: 1,
      sender: { id: 1, name: 'Marina', type: 'User' },
      ...props,
    },
    global: {
      plugins: [store],
      directives: {
        dompurifyHtml: (el, { value }) => {
          el.innerHTML = value;
        },
      },
      stubs: { MessageMeta: true, ContextMenu: true, Avatar: true },
    },
  });
