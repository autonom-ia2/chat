<script>
import { mapGetters } from 'vuex';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { useLayoutExpandidoDaLista } from 'dashboard/components-next/Conversation/ListaDeConversas/useLayoutDaLista';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import { useWindowSize } from '@vueuse/core';
import ConversaVazia from 'dashboard/components-next/Conversation/ListaDeConversas/busca/ConversaVazia.vue';
import { pedidoDeConversaVazia } from 'dashboard/components-next/Conversation/ListaDeConversas/busca/caixasDaConversaVazia';
import { usePodeComecarConversa } from 'dashboard/components-next/NovaConversa/usePodeComecarConversa';
import { useListaNova } from 'dashboard/components-next/Conversation/ListaDeConversas/useListaNova';

export default {
  components: {
    ChatList,
    ConversationBox,
    CmdBarConversationSnooze,
    SidepanelSwitch,
    ConversationSidebar,
    ConversaVazia,
  },
  beforeRouteLeave(to, from, next) {
    // Clear selected state if navigating away from a conversation to a route without a conversationId to prevent stale data issues
    // and resolves timing issues during navigation with conversation view and other screens
    if (this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
    next(); // Continue with navigation
  },
  props: {
    inboxId: {
      type: [String, Number],
      default: 0,
    },
    conversationId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    teamId: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
  },
  setup() {
    const { uiSettings, updateUISettings } = useUISettings();
    // #2202: com a lista nova, o layout é sempre o condensado (a preferência salva fica como está).
    const isOnExpandedLayout = useLayoutExpandidoDaLista();
    // #2211: a conversa vazia pelo resultado da busca da lista (?comecar=<contato> ou
    // ?telefone=<número novo> ou ?email=<e-mail novo>). Quem só lê conversas (#1800) não começa conversa.
    const listaNova = useListaNova();
    const podeComecar = usePodeComecarConversa();
    const { width: larguraDaJanela } = useWindowSize();
    const { accountId } = useAccount();

    return {
      uiSettings,
      updateUISettings,
      isOnExpandedLayout,
      accountId,
      listaNova,
      podeComecar,
      larguraDaJanela,
    };
  },
  data() {
    return {
      showSearchModal: false,
    };
  },
  computed: {
    ...mapGetters({
      chatList: 'getAllConversations',
      currentChat: 'getSelectedChat',
    }),
    conversaVazia() {
      if (!this.listaNova || !this.podeComecar || this.conversationId) {
        return null;
      }
      return pedidoDeConversaVazia(this.$route.query);
    },
    noCelular() {
      return this.larguraDaJanela < wootConstants.SMALL_SCREEN_BREAKPOINT;
    },
    showConversationList() {
      // No celular, a conversa vazia ocupa a tela; o "Voltar" traz a lista de volta como estava.
      if (this.conversaVazia && this.noCelular) return false;
      return this.isOnExpandedLayout ? !this.conversationId : true;
    },
    showMessageView() {
      return this.conversationId ? true : !this.isOnExpandedLayout;
    },
    shouldShowSidebar() {
      if (!this.currentChat.id) {
        return false;
      }

      const { is_contact_sidebar_open: isContactSidebarOpen } = this.uiSettings;
      return isContactSidebarOpen;
    },
  },
  watch: {
    conversationId() {
      this.fetchConversationIfUnavailable();
    },
  },

  created() {
    // Clear selected state early if no conversation is selected
    // This prevents child components from accessing stale data
    // and resolves timing issues during navigation
    // with conversation view and other screens
    if (!this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
  },

  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('portals/index');
    this.initialize();
    this.$watch('$store.state.route', () => this.initialize());
    this.$watch('chatList.length', () => {
      this.setActiveChat();
    });
  },

  methods: {
    onConversationLoad() {
      this.fetchConversationIfUnavailable();
    },
    initialize() {
      this.$store.dispatch('setActiveInbox', this.inboxId);
      this.setActiveChat();
    },
    toggleConversationLayout() {
      const { LAYOUT_TYPES } = wootConstants;
      const {
        conversation_display_type:
          conversationDisplayType = LAYOUT_TYPES.CONDENSED,
      } = this.uiSettings;
      const newViewType =
        conversationDisplayType === LAYOUT_TYPES.CONDENSED
          ? LAYOUT_TYPES.EXPANDED
          : LAYOUT_TYPES.CONDENSED;
      this.updateUISettings({
        conversation_display_type: newViewType,
        previously_used_conversation_display_type: newViewType,
      });
    },
    fetchConversationIfUnavailable() {
      if (!this.conversationId) {
        return;
      }
      const chat = this.findConversation();
      if (!chat) {
        this.$store.dispatch('getConversation', this.conversationId);
      }
    },
    findConversation() {
      const conversationId = parseInt(this.conversationId, 10);
      const [chat] = this.chatList.filter(c => c.id === conversationId);
      return chat;
    },
    setActiveChat() {
      if (this.conversationId) {
        const selectedConversation = this.findConversation();
        // If conversation doesn't exist or selected conversation is same as the active
        // conversation, don't set active conversation.
        if (
          !selectedConversation ||
          selectedConversation.id === this.currentChat.id
        ) {
          return;
        }
        const { messageId } = this.$route.query;
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            // #2211: diz de qual conversa é o pedido; se já trocaram, a tela ignora.
            emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
              messageId,
              conversationId: selectedConversation.id,
            });
          });
      } else {
        this.$store.dispatch('clearSelectedState');
      }
    },
    voltarDaConversaNova() {
      const { comecar, telefone, email, livre, ...resto } = this.$route.query;
      this.$router.replace({ query: resto });
    },
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
  },
};
</script>

<template>
  <section class="flex w-full h-full min-w-0">
    <ChatList
      :show-conversation-list="showConversationList"
      :conversation-inbox="inboxId"
      :label="label"
      :team-id="teamId"
      :conversation-type="conversationType"
      :folders-id="foldersId"
      :is-on-expanded-layout="isOnExpandedLayout"
      @conversation-load="onConversationLoad"
    />
    <ConversaVazia
      v-if="conversaVazia"
      :contato-id="conversaVazia.contatoId"
      :telefone="conversaVazia.telefone"
      :email="conversaVazia.email"
      :caixas-livres="conversaVazia.caixasLivres"
      :caixas-permitidas="conversaVazia.caixasPermitidas"
      @voltar="voltarDaConversaNova"
    />
    <ConversationBox
      v-else-if="showMessageView"
      :inbox-id="inboxId"
      :is-on-expanded-layout="isOnExpandedLayout"
    >
      <SidepanelSwitch v-if="currentChat.id" />
    </ConversationBox>
    <ConversationSidebar v-if="shouldShowSidebar" :current-chat="currentChat" />
    <CmdBarConversationSnooze />
  </section>
</template>
