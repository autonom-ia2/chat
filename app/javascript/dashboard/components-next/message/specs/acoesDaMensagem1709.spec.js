/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import Message from '../Message.vue';
import MessageList from '../MessageList.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../constants';
import { AGORA, montagem } from './montarMensagem';
import { PELES, fornecerFuso, fornecerPele } from '../../conversa-canal/pele';
import { useAlbunsDaConversa } from '../../conversa-canal/album/useAlbuns';
import MessageContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';

// chat#1709 × pele (#1702): o que a lista entrega ao álbum, o "Reagir" único e o "Apagar para todos".
withFullI18n();

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));
vi.mock('../../conversa-canal/album/useAlbuns', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    useAlbunsDaConversa: vi.fn(original.useAlbunsDaConversa),
  };
});

// O menu de verdade é teleportado; aqui ele desenha no lugar, para ler os itens.
const MENU_NO_LUGAR = { ContextMenu: { template: '<div><slot /></div>' } };

const comPele = (pele, filho) =>
  defineComponent({
    setup() {
      fornecerPele(computed(() => pele));
      fornecerFuso(computed(() => 'America/Sao_Paulo'));
      return () => filho();
    },
  });

const storeCom = conversa =>
  createStore({
    getters: {
      'inboxes/getInbox': () => () => ({}),
      'inboxes/getInboxById': () => () => ({}),
      'globalConfig/get': () => ({}),
      'globalConfig/isOnChatwootCloud': () => false,
      'accounts/getAccount': () => () => ({}),
      getSelectedChat: () => conversa,
      getSelectedChatAttachments: () => [],
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({}),
      getCurrentRole: () => 'agent',
      getUISettings: () => ({}),
    },
    actions: { deleteMessage: vi.fn() },
  });

describe('álbum do WAHA na lista (marcador escondido)', () => {
  const base = {
    inbox_id: 3,
    conversation_id: 7,
    content_type: 'text',
    status: 'sent',
    private: false,
    created_at: AGORA,
    sender: { id: 9, name: 'Maria', type: 'contact' },
  };
  const marcador = {
    ...base,
    id: 50,
    message_type: MESSAGE_TYPES.ACTIVITY,
    content: 'Álbum',
    content_attributes: {
      c2y_hidden: true,
      waha_album: { expected_images: 2, expected_videos: 0 },
    },
  };
  const voto = {
    ...base,
    id: 51,
    message_type: MESSAGE_TYPES.INCOMING,
    content: 'Votou',
    content_attributes: { c2y_hidden: true, poll_vote_applied_to: 40 },
  };
  const foto = { ...base, id: 52, message_type: MESSAGE_TYPES.INCOMING };

  // Os ids que a lista entregou ao agrupamento de álbuns da pele (useAlbunsDaConversa).
  const entregues = pele => {
    useAlbunsDaConversa.mockClear();
    mount(
      comPele(pele, () =>
        h(MessageList, {
          currentUserId: 1,
          messages: [marcador, voto, foto],
        })
      ),
      { global: { ...montagem, plugins: [storeCom({})] } }
    );
    const [mensagens] = useAlbunsDaConversa.mock.calls.at(-1);
    return mensagens.value.map(mensagem => mensagem.id);
  };

  it('com a pele, o marcador escondido com waha_album chega ao álbum; o resto escondido não', () => {
    expect(entregues(PELES.WHATSAPP)).toEqual([50, 52]);
  });

  it('sem a pele, o marcador some como as outras escondidas', () => {
    expect(entregues(null)).toEqual([52]);
  });
});

describe('"Reagir" do #1709 com a pele', () => {
  // A conversa diz que o motor da caixa sabe reagir.
  const conversa = { id: 7, whatsapp_api_message_actions: ['react'] };

  const opcoesDoMenu = pele => {
    const wrapper = mount(
      comPele(pele, () =>
        h(Message, {
          id: 1,
          messageType: MESSAGE_TYPES.INCOMING,
          status: MESSAGE_STATUS.SENT,
          content: 'Olá',
          conversationId: 7,
          createdAt: AGORA,
          currentUserId: 1,
          sender: { id: 7, name: 'Maria', type: 'Contact' },
        })
      ),
      { global: { ...montagem, plugins: [storeCom(conversa)] } }
    );
    return wrapper.findComponent(MessageContextMenu).props('enabledOptions');
  };

  it('com a pele, o menu não oferece o "Reagir" do #1709 (vale o da pele)', () => {
    expect(opcoesDoMenu(PELES.WHATSAPP).react).toBe(false);
  });

  it('sem a pele, com a caixa que sabe reagir, oferece', () => {
    expect(opcoesDoMenu(null).react).toBe(true);
  });

  it('o menu só desenha o "Reagir" do #1709 quando a opção vem ligada', () => {
    const montarMenu = enabledOptions =>
      mount(MessageContextMenu, {
        props: {
          message: { id: 1, conversationId: 7 },
          enabledOptions,
          isOpen: true,
          hideButton: true,
        },
        global: { plugins: [storeCom({})], stubs: MENU_NO_LUGAR },
      });
    expect(montarMenu({ react: false, copy: true }).text()).not.toContain(
      'React'
    );
    expect(montarMenu({ react: true, copy: true }).text()).toContain('React');
  });
});

describe('"Apagar para todos" (c2y_revocable)', () => {
  const montarMenu = message =>
    mount(MessageContextMenu, {
      props: {
        message,
        enabledOptions: { delete: true },
        isOpen: true,
        hideButton: true,
      },
      global: { plugins: [storeCom({})], stubs: MENU_NO_LUGAR },
    });

  it('com c2y_revocable, o item e o aviso dizem que some também do WhatsApp do cliente', async () => {
    const wrapper = montarMenu({
      id: 1,
      conversationId: 7,
      c2y_revocable: true,
    });
    expect(wrapper.vm.deleteLabel).toBe('Delete for everyone');
    expect(wrapper.vm.deleteConfirmationMessage).toContain(
      "customer's WhatsApp"
    );
    expect(wrapper.text()).toContain('Delete for everyone');
  });

  it('sem c2y_revocable, os textos de sempre', () => {
    const wrapper = montarMenu({ id: 1, conversationId: 7 });
    expect(wrapper.vm.deleteLabel).toBe('Delete');
    expect(wrapper.vm.deleteConfirmationMessage).toBe(
      'You cannot undo this action'
    );
    expect(wrapper.text()).not.toContain('Delete for everyone');
  });
});
