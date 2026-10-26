<script>
import { ref, provide, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
// composable
import { useLabelSuggestions } from 'dashboard/composables/useLabelSuggestions';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useContactConversationNavigation } from 'dashboard/composables/useContactConversationNavigation';

// components
import ReplyBox from './ReplyBox.vue';
import MessageList from 'next/message/MessageList.vue';
import ConversationLabelSuggestion from './conversation/LabelSuggestion.vue';
import ContactConversationLink from './ContactConversationLink.vue';
import Banner from 'dashboard/components/ui/Banner.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ResizableEditorWrapper from './ResizableEditorWrapper.vue';
import ReferralBubble from 'dashboard/components-next/Conversation/ReferralBubble.vue';

// stores and apis
import { mapGetters } from 'vuex';

// mixins
import inboxMixin, { INBOX_FEATURES } from 'shared/mixins/inboxMixin';

// utils
import { emitter } from 'shared/helpers/mitt';
import { getTypingUsersText } from '../../../helper/commons';
import { calculateScrollTop } from './helpers/scrollTopCalculationHelper';
import { LocalStorage } from 'shared/helpers/localStorage';
import {
  filterDuplicateSourceMessages,
  getReadMessages,
  getUnreadMessages,
} from 'dashboard/helper/conversationHelper';

// constants
import { BUS_EVENTS } from 'shared/constants/busEvents';

import { REPLY_POLICY } from 'shared/constants/links';
import wootConstants, {
  META_RESTRICTION_STATUS_URL,
} from 'dashboard/constants/globals';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { usePeleDaConversa } from 'dashboard/components-next/conversa-canal/usePeleDaConversa';
import {
  CONVERSAS_DO_CONTATO,
  useConversaDeEmail,
} from 'dashboard/components-next/conversa-canal/email/useConversaDeEmail';
import { useConversaDoInstagram } from 'dashboard/components-next/conversa-canal/instagram/useConversaDoInstagram';
import { useImpersonation } from 'dashboard/composables/useImpersonation';
import AvisoJanelaFechada from 'dashboard/components-next/conversa-canal/AvisoJanelaFechada.vue';
import EncaminharDaConversa from 'dashboard/components-next/conversa-canal/encaminhar/EncaminharDaConversa.vue';
import { selecao as selecaoParaEncaminhar } from 'dashboard/components-next/conversa-canal/encaminhar/selecaoParaEncaminhar';
import FaixaDeNaoLidas from 'dashboard/components-next/conversa-canal/FaixaDeNaoLidas.vue';
import { destacarMensagem } from 'dashboard/components-next/conversa-canal/destaqueDaCitada';
import { semDuplicadasNaPele } from 'dashboard/components-next/conversa-canal/midia/contatos';
import {
  agendarFimDaFaixa,
  buscarAteAchar,
  deveDescer,
  faixaDispensada,
  marcoDeNaoLidas,
  naoLidasCarregadas,
  pertoDoFim,
  topoDaFaixa,
} from 'dashboard/components-next/conversa-canal/rolagemDaPele';
import { useAlert } from 'dashboard/composables';

// Até quantos px do fim a lista conta como "no fim" quando a caixa de resposta cresce.
const NO_FIM_DO_PAINEL = 40;

export default {
  components: {
    MessageList,
    ReplyBox,
    Banner,
    ConversationLabelSuggestion,
    ContactConversationLink,
    Spinner,
    ResizableEditorWrapper,
    ReferralBubble,
    AvisoJanelaFechada,
    EncaminharDaConversa,
    FaixaDeNaoLidas,
  },
  mixins: [inboxMixin],
  setup() {
    const conversationPanelRef = ref(null);
    const resizableEditorWrapperRef = ref(null);
    const messagesViewRef = useTemplateRef('messagesViewRef');
    const topBannerRef = useTemplateRef('topBannerRef');
    const { height: containerHeight } = useElementSize(messagesViewRef);
    const { height: topBannerHeight } = useElementSize(topBannerRef);

    const {
      captainTasksEnabled,
      isLabelSuggestionFeatureEnabled,
      getLabelSuggestions,
    } = useLabelSuggestions();

    const { olderConversation, newerConversation, buildConversationPath } =
      useContactConversationNavigation();

    provide('contextMenuElementTarget', conversationPanelRef);
    // #1786: no e-mail novo as vizinhas aparecem no topo do e-mail (EmailsVizinhos).
    provide(CONVERSAS_DO_CONTATO, {
      olderConversation,
      newerConversation,
      buildConversationPath,
    });
    // #1702: conversa com a cara do canal (WhatsApp), atrás da chave da conta.
    const { pele, classesDaLista, classesDaBarra } = usePeleDaConversa();
    // #1786: conversa de e-mail com a cara do Gmail, atrás da chave própria.
    const {
      ligado: emailNovo,
      classesDaLista: classesDoEmail,
      classesDaBarra: classesDaRespostaDoEmail,
    } = useConversaDeEmail();
    // #2079: conversa do Instagram com a cara do Direct, atrás da chave própria.
    const {
      classesDaLista: classesDoInstagram,
      classesDaBarra: classesDaRespostaDoInstagram,
    } = useConversaDoInstagram();
    // #1702: superadmin entrando como o usuário não marca a mensagem como lida no WhatsApp do cliente.
    const { isImpersonating } = useImpersonation();

    return {
      captainTasksEnabled,
      getLabelSuggestions,
      isLabelSuggestionFeatureEnabled,
      olderConversation,
      newerConversation,
      buildConversationPath,
      conversationPanelRef,
      resizableEditorWrapperRef,
      messagesViewRef,
      topBannerRef,
      containerHeight,
      topBannerHeight,
      pele,
      classesDaLista,
      classesDaBarra,
      emailNovo,
      classesDoEmail,
      classesDaRespostaDoEmail,
      classesDoInstagram,
      classesDaRespostaDoInstagram,
      isImpersonating,
      selecaoParaEncaminhar,
    };
  },
  data() {
    return {
      isLoadingPrevious: true,
      heightBeforeLoad: null,
      conversationPanel: null,
      hasUserScrolled: false,
      isProgrammaticScroll: false,
      messageSentSinceOpened: false,
      labelSuggestions: [],
      // #1702: faixa de não lidas da pele; some depois de lida (alguns segundos na tela).
      naoLidasDaPele: null,
      // #2211: a mensagem pedida (?messageId=) que chegou enquanto a conversa ainda abria.
      citadaPendente: null,
      cancelarFimDaFaixa: null,
      ultimaDaPele: null,
    };
  },

  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUserId: 'getCurrentUserID',
      listLoadingStatus: 'getAllMessagesLoaded',
      currentAccountId: 'getCurrentAccountId',
      isMetaMessageSendingDisabled: 'globalConfig/isMetaMessageSendingDisabled',
    }),
    isOpen() {
      return this.currentChat?.status === wootConstants.STATUS_TYPE.OPEN;
    },
    // Quem só lê (#1800) não responde, não aplica etiqueta e não marca como lida: o "lido" é da conversa, de todos.
    canOperate() {
      return this.$store.getters.canOperateConversation(this.currentChat);
    },
    shouldShowLabelSuggestions() {
      return (
        this.canOperate &&
        this.isOpen &&
        this.captainTasksEnabled &&
        this.isLabelSuggestionFeatureEnabled &&
        !this.messageSentSinceOpened
      );
    },
    inboxId() {
      return this.currentChat.inbox_id;
    },
    inbox() {
      return this.$store.getters['inboxes/getInbox'](this.inboxId);
    },
    typingUsersList() {
      const userList = this.$store.getters[
        'conversationTypingStatus/getUserList'
      ](this.currentChat.id);
      return userList;
    },
    isAnyoneTyping() {
      const userList = this.typingUsersList;
      return userList.length !== 0;
    },
    typingUserNames() {
      const userList = this.typingUsersList;
      if (this.isAnyoneTyping) {
        const [i18nKey, params] = getTypingUsersText(userList);
        return this.$t(i18nKey, params);
      }

      return '';
    },
    getMessages() {
      const messages = this.currentChat.messages || [];
      if (this.isAWhatsAppChannel) {
        // #1702: com a pele, os contatos de um mesmo envio (mesmo source_id) ficam.
        return this.pele
          ? semDuplicadasNaPele(messages)
          : filterDuplicateSourceMessages(messages);
      }
      return messages;
    },
    referralData() {
      return this.currentChat?.additional_attributes?.referral || null;
    },
    readMessages() {
      return getReadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    unReadMessages() {
      return getUnreadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    shouldShowSpinner() {
      return (
        (this.currentChat && this.currentChat.dataFetched === undefined) ||
        (!this.listLoadingStatus && this.isLoadingPrevious)
      );
    },
    // Check there is a instagram inbox exists with the same instagram_id
    hasDuplicateInstagramInbox() {
      const instagramId = this.inbox.instagram_id;
      const { additional_attributes: additionalAttributes = {} } = this.inbox;
      const instagramInbox =
        this.$store.getters['inboxes/getInstagramInboxByInstagramId'](
          instagramId
        );

      return (
        this.inbox.channel_type === INBOX_TYPES.FB &&
        additionalAttributes.type === 'instagram_direct_message' &&
        instagramInbox
      );
    },
    isInstagramRestrictionBannerVisible() {
      return this.isMetaMessageSendingDisabled && this.isAnInstagramChannel;
    },
    instagramRestrictionStatusUrl() {
      return META_RESTRICTION_STATUS_URL;
    },
    replyWindowBannerMessage() {
      if (this.isAWhatsAppChannel) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_CAN_REPLY');
      }
      if (this.isAPIInbox) {
        const { additional_attributes: additionalAttributes = {} } = this.inbox;
        if (additionalAttributes) {
          const {
            agent_reply_time_window_message: agentReplyTimeWindowMessage,
            agent_reply_time_window: agentReplyTimeWindow,
          } = additionalAttributes;
          return (
            agentReplyTimeWindowMessage ||
            this.$t('CONVERSATION.API_HOURS_WINDOW', {
              hours: agentReplyTimeWindow,
            })
          );
        }
        return '';
      }
      return this.$t('CONVERSATION.CANNOT_REPLY');
    },
    replyWindowLink() {
      if (this.isAFacebookInbox || this.isAnInstagramChannel) {
        return REPLY_POLICY.FACEBOOK;
      }
      if (this.isAWhatsAppCloudChannel) {
        return REPLY_POLICY.WHATSAPP_CLOUD;
      }
      if (this.isATiktokChannel) {
        return REPLY_POLICY.TIKTOK;
      }
      if (!this.isAPIInbox) {
        return REPLY_POLICY.TWILIO_WHATSAPP;
      }
      return '';
    },
    replyWindowLinkText() {
      if (
        this.isAWhatsAppChannel ||
        this.isAFacebookInbox ||
        this.isAnInstagramChannel
      ) {
        return this.$t('CONVERSATION.24_HOURS_WINDOW');
      }
      if (this.isATiktokChannel) {
        return this.$t('CONVERSATION.48_HOURS_WINDOW');
      }
      if (!this.isAPIInbox) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_24_HOURS_WINDOW');
      }
      return '';
    },
    unreadMessageCount() {
      return this.currentChat.unread_count || 0;
    },
    // #1702: com a pele, a faixa vem do retrato tirado ao abrir; sem ela, do Chatwoot.
    faixaDaPele() {
      const marco = this.naoLidasDaPele;
      return marco?.pronta && marco.conversaId === this.currentChat.id
        ? marco
        : null;
    },
    primeiraNaoLidaDaLista() {
      if (this.pele) return this.faixaDaPele?.primeiraNaoLida ?? null;
      return this.unReadMessages[0]?.id;
    },
    unreadMessageLabel() {
      const count =
        this.unreadMessageCount > 9 ? '9+' : this.unreadMessageCount;
      const label =
        this.unreadMessageCount > 1
          ? 'CONVERSATION.UNREAD_MESSAGES'
          : 'CONVERSATION.UNREAD_MESSAGE';
      return `${count} ${this.$t(label)}`;
    },
    inboxSupportsReplyTo() {
      const incoming = this.inboxHasFeature(INBOX_FEATURES.REPLY_TO);
      const outgoing =
        this.inboxHasFeature(INBOX_FEATURES.REPLY_TO_OUTGOING) &&
        !this.is360DialogWhatsAppChannel;

      return { incoming, outgoing };
    },
  },

  watch: {
    currentChat(newChat, oldChat) {
      if (newChat.id === oldChat.id) {
        return;
      }
      // #2211: pedido de ir à mensagem que a conversa que saiu não usou não vale mais.
      if (this.citadaPendente?.conversaId === oldChat.id) {
        this.citadaPendente = null;
      }
      this.fetchAllAttachmentsFromCurrentChat();
      this.fetchSuggestions();
      this.fetchParticipantsForReading();
      this.messageSentSinceOpened = false;
      this.resetReplyEditorHeight();
    },
    // A lista de participantes chegou e liberou responder: marca como lida o que ficou para trás (#1800).
    canOperate(pode, podia) {
      if (pode && !podia) this.makeMessagesRead();
    },
  },

  created() {
    emitter.on(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    // when a message is sent we set the flag to true this hides the label suggestions,
    // until the chat is changed and the flag is reset in the watch for currentChat
    emitter.on(BUS_EVENTS.MESSAGE_SENT, () => {
      this.messageSentSinceOpened = true;
      // #1702: o atendente respondeu, então leu: a faixa de não lidas sai.
      if (this.pele) this.dispensarFaixaDaPele(this.currentChat?.id);
    });
  },

  mounted() {
    this.addScrollListener();
    // #1702: conversa já carregada não espera o aviso de abrir para achar a faixa.
    if (this.pele) this.$nextTick(() => this.rolarNaPele());
    this.fetchAllAttachmentsFromCurrentChat();
    this.fetchSuggestions();
    this.fetchParticipantsForReading();
  },

  unmounted() {
    this.desmontada = true;
    this.cancelarFimDaFaixa?.();
    this.removeBusListeners();
    this.removeScrollListener();
  },

  methods: {
    // Quem só lê e também atende as em que participa (#1800): a lista de participantes decide se responde aqui.
    fetchParticipantsForReading() {
      if (this.canOperate || !this.currentChat.id) return;
      this.$store.dispatch('conversationWatchers/show', {
        conversationId: this.currentChat.id,
      });
    },
    async fetchSuggestions() {
      // start empty, this ensures that the label suggestions are not shown
      this.labelSuggestions = [];
      if (!this.canOperate) return;

      if (this.isLabelSuggestionDismissed()) {
        return;
      }

      // Early exit if conversation already has labels - no need to suggest more
      const existingLabels = this.currentChat?.labels || [];
      if (existingLabels.length > 0) return;

      if (!this.captainTasksEnabled || !this.isLabelSuggestionFeatureEnabled) {
        return;
      }

      this.labelSuggestions = await this.getLabelSuggestions();

      // once the labels are fetched, we need to scroll to bottom
      // but we need to wait for the DOM to be updated
      // so we use the nextTick method
      this.$nextTick(() => {
        // this param is added to route, telling the UI to navigate to the message
        // it is triggered by the SCROLL_TO_MESSAGE method
        // see setActiveChat on ConversationView.vue for more info
        const { messageId } = this.$route.query;

        // only trigger the scroll to bottom if the user has not scrolled
        // and there's no active messageId that is selected in view
        // #1702: com a pele, a faixa de não lidas aberta perto do topo fica onde está.
        if (
          !messageId &&
          !this.hasUserScrolled &&
          !this.faixaDaPele?.primeiraNaoLida &&
          !this.faixaDaPele?.dispensada
        ) {
          this.scrollToBottom();
        }
      });
    },
    isLabelSuggestionDismissed() {
      return LocalStorage.getFlag(
        LOCAL_STORAGE_KEYS.DISMISSED_LABEL_SUGGESTIONS,
        this.currentAccountId,
        this.currentChat.id
      );
    },
    fetchAllAttachmentsFromCurrentChat() {
      this.$store.dispatch('fetchAllAttachments', this.currentChat.id);
    },
    removeBusListeners() {
      emitter.off(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    },
    onScrollToMessage({ messageId = '', conversationId } = {}) {
      // #2211: o aviso de abrir com ?messageId= diz de qual conversa é; se outra já está na
      // tela (troca rápida), ele não vale para ela.
      if (conversationId && conversationId !== this.currentChat.id) return;
      // #1702: com a pele, a rolagem segue o app (rolarNaPele); sem ela, o Chatwoot.
      if (this.pele) {
        this.rolarNaPele(messageId);
        this.makeMessagesRead();
        return;
      }
      this.$nextTick(() => {
        const messageElement = document.getElementById('message' + messageId);
        if (messageElement) {
          this.isProgrammaticScroll = true;
          messageElement.scrollIntoView({ behavior: 'smooth' });
          this.fetchPreviousMessages();
        } else {
          this.scrollToBottom();
        }
      });
      this.makeMessagesRead();
    },
    // #1702: rolagem com a pele. 1º aviso da conversa aberta: abre na faixa de não
    // lidas; citação: busca a mensagem e a destaca; mensagem nova: só desce quem estava
    // no fim ou quando o atendente enviou.
    async rolarNaPele(messageId) {
      const conversaId = this.currentChat.id;
      // #2211: o pedido de ir à mensagem (link com ?messageId=, da busca) podia chegar com a
      // conversa ainda abrindo (a faixa não pronta) e se perdia: a conversa abria na faixa ou
      // no fim. Fica guardado e quem terminar de abrir leva até ela.
      if (messageId) this.citadaPendente = { conversaId, id: messageId };
      const abrindoAgora = this.naoLidasDaPele?.conversaId !== conversaId;
      if (abrindoAgora) {
        // Antes das mensagens chegarem não há o que contar.
        if (this.currentChat.dataFetched !== true) return;
        await this.abrirNaPele(!this.citadaDestaConversa());
      }
      if (!this.faixaDaPele) return;
      const citada = this.citadaDestaConversa();
      if (citada) {
        this.citadaPendente = null;
        await this.irParaCitada(citada);
        return;
      }
      if (abrindoAgora) return;
      this.acompanharNovas();
    },
    citadaDestaConversa() {
      const pendente = this.citadaPendente;
      return pendente?.conversaId === this.currentChat.id ? pendente.id : null;
    },
    async abrirNaPele(posicionar) {
      const conversaId = this.currentChat.id;
      // A leitura de antes de abrir: marcar como lida (logo depois) não muda a faixa.
      const vistoEm = this.currentChat.agent_last_seen_at;
      this.naoLidasDaPele = { conversaId, pronta: false };
      try {
        // Mais de uma página de não lidas: busca as anteriores para o número exato.
        await buscarAteAchar({
          achou: () => naoLidasCarregadas(this.currentChat.messages, vistoEm),
          temMais: () => !this.listLoadingStatus,
          carregarMais: this.carregarAnterioresNaPele,
        });
      } catch (error) {
        // Sem as páginas antigas (rede), a faixa conta as não lidas que vieram.
      }
      if (this.desmontada || this.currentChat.id !== conversaId) return;
      const { messages } = this.currentChat;
      this.naoLidasDaPele = marcoDeNaoLidas(conversaId, messages, vistoEm);
      this.ultimaDaPele = messages[messages.length - 1]?.id;
      this.agendarFimDaFaixaDaPele(conversaId);
      // #2211: com mensagem pedida, quem abre leva direto até ela, sem passar pela faixa.
      if (!posicionar || this.citadaDestaConversa()) return;
      await this.esperarATela();
      const faixa = this.conversationPanel.querySelector(
        '[data-faixa-nao-lidas]'
      );
      this.isProgrammaticScroll = true;
      if (faixa) {
        this.conversationPanel.scrollTop = topoDaFaixa(faixa.offsetTop);
      } else {
        this.scrollToBottom();
      }
    },
    esperarATela() {
      return new Promise(resolve => {
        this.$nextTick(resolve);
      });
    },
    async carregarAnterioresNaPele() {
      const [maisAntiga] = this.currentChat.messages;
      if (!maisAntiga) return;
      await this.$store.dispatch('fetchPreviousMessages', {
        conversationId: this.currentChat.id,
        before: maisAntiga.id,
      });
      await this.esperarATela();
    },
    agendarFimDaFaixaDaPele(conversaId) {
      this.cancelarFimDaFaixa?.();
      this.cancelarFimDaFaixa = null;
      if (!this.naoLidasDaPele?.quantidade) return;
      this.cancelarFimDaFaixa = agendarFimDaFaixa(() =>
        this.dispensarFaixaDaPele(conversaId)
      );
    },
    async dispensarFaixaDaPele(conversaId) {
      const marco = this.naoLidasDaPele;
      if (marco?.conversaId !== conversaId || !marco.primeiraNaoLida) return;
      this.cancelarFimDaFaixa?.();
      this.cancelarFimDaFaixa = null;
      // A faixa na tela (ou acima dela) sai sem mexer no que a pessoa está lendo.
      const painel = this.conversationPanel;
      const faixa = painel?.querySelector('[data-faixa-nao-lidas]');
      const compensar =
        faixa && faixa.offsetTop < painel.scrollTop + painel.clientHeight;
      const alturaAntes = painel?.scrollHeight ?? 0;
      this.naoLidasDaPele = faixaDispensada(marco);
      if (!compensar) return;
      await this.esperarATela();
      this.isProgrammaticScroll = true;
      painel.scrollTop -= alturaAntes - painel.scrollHeight;
    },
    acompanharNovas() {
      const { messages } = this.currentChat;
      const ultima = messages[messages.length - 1];
      // Medido antes de a mensagem nova entrar na tela.
      const descer = deveDescer({
        estavaNoFim: pertoDoFim(this.conversationPanel),
        ultimaAntes: this.ultimaDaPele,
        ultima,
      });
      this.ultimaDaPele = ultima?.id;
      if (descer) this.$nextTick(() => this.scrollToBottom());
    },
    // Citação de mensagem antiga que ainda não veio: busca as anteriores (com teto),
    // rola até ela e a destaca, como no app.
    async irParaCitada(messageId) {
      const id = Number(messageId);
      // #2211: trocou de conversa ou fechou a tela no meio: para sem aviso.
      const conversaId = this.currentChat.id;
      const naMesma = () =>
        !this.desmontada && this.currentChat.id === conversaId;
      let carregada = false;
      try {
        carregada = await buscarAteAchar({
          achou: () => this.currentChat.messages.some(item => item.id === id),
          temMais: () => naMesma() && !this.listLoadingStatus,
          carregarMais: this.carregarAnterioresNaPele,
        });
      } catch (error) {
        carregada = false;
      }
      if (!naMesma()) return;
      await this.esperarATela();
      if (!naMesma()) return;
      const alvo = carregada && document.getElementById(`message${id}`);
      if (!alvo) {
        useAlert(this.$t('CONVERSA_CANAL.ROLAGEM.CITADA_NAO_ENCONTRADA'));
        return;
      }
      this.isProgrammaticScroll = true;
      alvo.scrollIntoView({ behavior: 'smooth', block: 'center' });
      destacarMensagem(id);
    },
    addScrollListener() {
      this.conversationPanel = this.$el.querySelector('.conversation-panel');
      this.setScrollParams();
      this.conversationPanel.addEventListener('scroll', this.handleScroll);
      // A caixa de resposta cresce (citação, texto de várias linhas) e a lista encolhe:
      // quem estava no fim continua vendo a última mensagem (#2113).
      this.noFimDoPainel = true;
      if (window.ResizeObserver) {
        this.observadorDoPainel = new ResizeObserver(this.manterNoFim);
        this.observadorDoPainel.observe(this.conversationPanel);
      }
      this.$nextTick(() => this.scrollToBottom());
      this.isLoadingPrevious = false;
    },
    removeScrollListener() {
      this.conversationPanel.removeEventListener('scroll', this.handleScroll);
      this.observadorDoPainel?.disconnect();
    },
    manterNoFim() {
      if (this.emailNovo || !this.noFimDoPainel) return;
      this.isProgrammaticScroll = true;
      this.conversationPanel.scrollTop = this.conversationPanel.scrollHeight;
    },
    scrollToBottom() {
      this.isProgrammaticScroll = true;
      // #1786: no e-mail novo o mais recente está no topo; é lá que a conversa abre.
      if (this.emailNovo) {
        this.conversationPanel.scrollTop = 0;
        return;
      }
      let relevantMessages = [];

      // label suggestions are not part of the messages list
      // so we need to handle them separately
      let labelSuggestions =
        this.conversationPanel.querySelector('.label-suggestion');

      // if there are unread messages, scroll to the first unread message
      if (this.unreadMessageCount > 0) {
        // capturing only the unread messages
        relevantMessages =
          this.conversationPanel.querySelectorAll('.message--unread');
      } else if (labelSuggestions) {
        // when scrolling to the bottom, the label suggestions is below the last message
        // so we scroll there if there are no unread messages
        // Unread messages always take the highest priority
        relevantMessages = [labelSuggestions];
      } else {
        // if there are no unread messages or label suggestion, scroll to the last message
        // capturing last message from the messages list
        relevantMessages = Array.from(
          this.conversationPanel.querySelectorAll('.message--read')
        ).slice(-1);
      }

      this.conversationPanel.scrollTop = calculateScrollTop(
        this.conversationPanel.scrollHeight,
        this.$el.scrollHeight,
        relevantMessages
      );
    },
    setScrollParams() {
      this.heightBeforeLoad = this.conversationPanel.scrollHeight;
      this.scrollTopBeforeLoad = this.conversationPanel.scrollTop;
    },

    async fetchPreviousMessages(scrollTop = 0) {
      this.setScrollParams();
      const shouldLoadMoreMessages =
        this.currentChat.dataFetched === true &&
        !this.listLoadingStatus &&
        !this.isLoadingPrevious;

      if (
        scrollTop < 100 &&
        !this.isLoadingPrevious &&
        shouldLoadMoreMessages
      ) {
        this.isLoadingPrevious = true;
        try {
          await this.$store.dispatch('fetchPreviousMessages', {
            conversationId: this.currentChat.id,
            before: this.currentChat.messages[0].id,
          });
          // #1786: no e-mail novo os antigos entram embaixo; a tela não precisa pular.
          const heightDifference = this.emailNovo
            ? 0
            : this.conversationPanel.scrollHeight - this.heightBeforeLoad;
          this.conversationPanel.scrollTop =
            this.scrollTopBeforeLoad + heightDifference;
          this.setScrollParams();
        } catch (error) {
          // Ignore Error
        } finally {
          this.isLoadingPrevious = false;
        }
      }
    },

    handleScroll(e) {
      if (this.isProgrammaticScroll) {
        // Reset the flag
        this.isProgrammaticScroll = false;
        this.hasUserScrolled = false;
      } else {
        this.hasUserScrolled = true;
      }
      emitter.emit(BUS_EVENTS.ON_MESSAGE_LIST_SCROLL);
      // #1786: no e-mail novo os antigos ficam embaixo: carrega perto do fim.
      const alvo = e.target;
      this.noFimDoPainel = pertoDoFim(alvo, NO_FIM_DO_PAINEL);
      this.fetchPreviousMessages(
        this.emailNovo
          ? alvo.scrollHeight - alvo.scrollTop - alvo.clientHeight
          : alvo.scrollTop
      );
    },

    makeMessagesRead() {
      if (!this.canOperate) return;
      this.$store.dispatch('markMessagesRead', {
        id: this.currentChat.id,
        // Recibo de leitura no WhatsApp só com a pele (sem ela, como no main).
        readReceipt: !this.isImpersonating && !!this.pele,
      });
    },
    async handleMessageRetry(message) {
      if (!message) return;
      const payload = useSnakeCase(message);
      await this.$store.dispatch('sendMessageWithData', payload);
    },
    toggleReplyEditorSize() {
      this.resizableEditorWrapperRef?.toggleEditorExpand?.();
    },
    resetReplyEditorHeight() {
      this.resizableEditorWrapperRef?.resetEditorHeight?.();
    },
  },
};
</script>

<template>
  <div
    ref="messagesViewRef"
    class="flex flex-col justify-between flex-grow h-full min-w-0 m-0"
    :class="{ relative: pele }"
    :data-conversa-da-pele="pele ? '' : undefined"
  >
    <div ref="topBannerRef">
      <Banner
        v-if="isInstagramRestrictionBannerVisible"
        color-scheme="warning"
        class="mx-2 mt-2 min-h-12 !h-auto rounded-lg"
        :banner-message="$t('CONVERSATION.INSTAGRAM_RESTRICTION_BANNER')"
        :href-link="instagramRestrictionStatusUrl"
        :href-link-text="$t('CONVERSATION.INSTAGRAM_RESTRICTION_STATUS_LINK')"
      />
      <AvisoJanelaFechada
        v-if="
          canOperate &&
          !currentChat.can_reply &&
          pele &&
          isAWhatsAppCloudChannel
        "
      />
      <Banner
        v-else-if="canOperate && !currentChat.can_reply"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="replyWindowBannerMessage"
        :href-link="replyWindowLink"
        :href-link-text="replyWindowLinkText"
      />
      <!-- Quem só lê (#1800): a regra do cargo, em tom neutro, junto dos outros avisos de "não dá para responder". -->
      <Banner
        v-if="!canOperate"
        color-scheme="secondary"
        class="ms-2 me-16 mt-2 min-h-12 !h-auto overflow-hidden rounded-lg"
        :banner-message="$t('CONVERSATION.SO_LEITURA.TEXTO')"
        data-aviso-so-leitura
      />
      <Banner
        v-if="hasDuplicateInstagramInbox"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="$t('CONVERSATION.OLD_INSTAGRAM_INBOX_REPLY_BANNER')"
      />
    </div>
    <MessageList
      ref="conversationPanelRef"
      class="conversation-panel flex-shrink flex-grow basis-px flex flex-col overflow-y-auto relative h-full m-0 pb-4"
      :class="[classesDaLista, classesDoEmail, classesDoInstagram]"
      :current-user-id="currentUserId"
      :first-unread-id="primeiraNaoLidaDaLista"
      :is-an-email-channel="isAnEmailChannel"
      :inbox-supports-reply-to="inboxSupportsReplyTo"
      :messages="getMessages"
      @retry="handleMessageRetry"
    >
      <template #beforeAll>
        <transition name="slide-up">
          <!-- #1786: no e-mail novo o conteúdo começa no topo (sem first:mt-auto) e o
          espaço do carregando só existe enquanto carrega. -->
          <!-- eslint-disable-next-line vue/require-toggle-inside-transition -->
          <li
            class="min-h-[4rem] flex flex-shrink-0 flex-grow-0 items-center flex-auto justify-center max-w-full mt-0 mr-0 mb-1 ml-0 relative first:mt-auto last:mb-0"
            :class="{
              '!mt-0': emailNovo,
              '!hidden': emailNovo && !shouldShowSpinner,
            }"
          >
            <Spinner v-if="shouldShowSpinner" class="text-n-brand" />
          </li>
        </transition>
        <ContactConversationLink
          v-if="olderConversation && listLoadingStatus && !emailNovo"
          direction="older"
          :conversation="olderConversation"
          :to="buildConversationPath(olderConversation.id)"
        />
        <ReferralBubble v-if="referralData" :referral="referralData" />
      </template>
      <template #unreadBadge>
        <FaixaDeNaoLidas
          v-if="pele && faixaDaPele"
          :quantidade="faixaDaPele.quantidade"
        />
        <li
          v-else
          v-show="unreadMessageCount != 0"
          class="list-none flex justify-center items-center"
        >
          <span
            class="shadow-lg rounded-full bg-n-brand text-white text-xs font-medium my-2.5 mx-auto px-2.5 py-1.5"
          >
            {{ unreadMessageLabel }}
          </span>
        </li>
      </template>
      <template #after>
        <ConversationLabelSuggestion
          v-if="shouldShowLabelSuggestions"
          :suggested-labels="labelSuggestions"
          :chat-labels="currentChat.labels"
          :conversation-id="currentChat.id"
        />
        <ContactConversationLink
          v-if="newerConversation && !emailNovo"
          direction="newer"
          :conversation="newerConversation"
          :to="buildConversationPath(newerConversation.id)"
        />
      </template>
    </MessageList>
    <div
      class="flex relative flex-col bg-n-surface-1"
      :class="[
        classesDaBarra,
        classesDaRespostaDoEmail,
        classesDaRespostaDoInstagram,
      ]"
    >
      <div
        v-if="isAnyoneTyping"
        class="absolute flex items-center w-full h-0 -top-7"
      >
        <div
          class="flex py-2 pr-4 pl-5 shadow-md rounded-full bg-white dark:bg-n-solid-3 text-n-slate-11 text-xs font-semibold my-2.5 mx-auto"
        >
          {{ typingUserNames }}
          <img
            class="w-6 ltr:ml-2 rtl:mr-2"
            src="assets/images/typing.gif"
            alt="Someone is typing"
          />
        </div>
      </div>
      <!-- #1702: modo seleção do encaminhar troca o campo de digitar pela barra. -->
      <EncaminharDaConversa
        v-if="canOperate && pele"
        :conversation-id="currentChat.id"
      />
      <ResizableEditorWrapper
        v-if="canOperate"
        v-show="!(pele && selecaoParaEncaminhar.ativa)"
        ref="resizableEditorWrapperRef"
        :container-height="Math.max(0, containerHeight - topBannerHeight)"
      >
        <ReplyBox @toggle-editor-size="toggleReplyEditorSize" />
      </ResizableEditorWrapper>
    </div>
  </div>
</template>
