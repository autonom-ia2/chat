<script>
import { getCurrentInstance, useTemplateRef, watch } from 'vue';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useTrack } from 'dashboard/composables';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';

import ReplyToMessage from './ReplyToMessage.vue';
import CitacaoNaResposta from 'dashboard/components-next/conversa-canal/CitacaoNaResposta.vue';
import { FORA_DA_REGUA } from 'dashboard/components-next/conversa-canal/email/visualEmail';
import MenuDaIaDoEmail from 'dashboard/components-next/conversa-canal/email/MenuDaIaDoEmail.vue';
import AvisoDaSugestao from 'dashboard/components-next/conversa-canal/email/AvisoDaSugestao.vue';
import {
  useIaDoEmail,
  respostaComIa,
  assinaturaNoTexto,
} from 'dashboard/components-next/conversa-canal/email/useIaDoEmail';
import CrmReplySubject from './CrmReplySubject.vue';
import CrmRepasseDoAssunto from './CrmRepasseDoAssunto.vue';
import AttachmentPreview from 'dashboard/components/widgets/AttachmentsPreview.vue';
import ReplyTopPanel from 'dashboard/components/widgets/WootWriter/ReplyTopPanel.vue';
import ReplyEmailHead from './ReplyEmailHead.vue';
import ReplyBottomPanel from 'dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue';
import CopilotReplyBottomPanel from 'dashboard/components/widgets/WootWriter/CopilotReplyBottomPanel.vue';
import ArticleSearchPopover from 'dashboard/routes/dashboard/helpcenter/components/ArticleSearch/SearchPopover.vue';
import CopilotEditorSection from './CopilotEditorSection.vue';
import MessageSignatureMissingAlert from './MessageSignatureMissingAlert.vue';
import AvisoDeAssinatura from 'dashboard/components-next/conversa-canal/email/AvisoDeAssinatura.vue';
import ReplyBoxBanner from './ReplyBoxBanner.vue';
import WhatsappApiReplyHint from './WhatsappApiReplyHint.vue';
import DevolverParaIa from 'dashboard/components-next/conversa-canal/atribuir/DevolverParaIa.vue';
import {
  camposDoEnvio,
  useFicarComAConversa,
} from 'dashboard/components-next/conversa-canal/atribuir/useFicarComAConversa';
import QuotedEmailPreview from './QuotedEmailPreview.vue';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import AudioRecorder from 'dashboard/components/widgets/WootWriter/AudioRecorder.vue';
import { AUDIO_FORMATS } from 'shared/constants/messages';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { CMD_AI_ASSIST } from 'dashboard/helper/commandbar/events';
import {
  getMessageVariables,
  getUndefinedVariablesInMessage,
} from '@chatwoot/utils';
import WhatsappTemplates from './WhatsappTemplates/Modal.vue';
import ContentTemplates from './ContentTemplates/ContentTemplatesModal.vue';
import { MESSAGE_MAX_LENGTH } from 'shared/helpers/MessageTypeHelper';
import inboxMixin, { INBOX_FEATURES } from 'shared/mixins/inboxMixin';
import { trimContent, debounce, getRecipients } from '@chatwoot/utils';
import { semQuemSaiuDaCopia } from 'dashboard/helper/semQuemSaiuDaCopia';
import {
  humanAssigneeId,
  isAssignedToUser,
} from 'dashboard/helper/assigneeHelper';
import wootConstants from 'dashboard/constants/globals';
import {
  extractQuotedEmailText,
  buildQuotedEmailHeader,
  truncatePreviewText,
  appendQuotedTextToMessage,
} from 'dashboard/helper/quotedEmailHelper';
import {
  CONVERSATION_EVENTS,
  CAPTAIN_EVENTS,
} from '../../../helper/AnalyticsHelper/events';
import fileUploadMixin from 'dashboard/mixins/fileUploadMixin';
import {
  appendSignature,
  removeSignature,
  getEffectiveChannelType,
  getAgentVariables,
  getContactVariables,
  resolveVariablesInMessage,
} from 'dashboard/helper/editorHelper';
import { useCopilotReply } from 'dashboard/composables/useCopilotReply';
import { useMacroExecution } from 'dashboard/composables/useMacroExecution';
import {
  indicesDeDocumento,
  usePeleDaResposta,
} from 'dashboard/components-next/conversa-canal/usePeleDaResposta';
import { useInstagramDaConversa } from 'dashboard/components-next/conversa-canal/instagram/useConversaDoInstagram';
import { GRAVADOR_DO_INSTAGRAM } from 'dashboard/components-next/conversa-canal/instagram/visualInstagram';
import { ABRIR_MODELOS_DO_WHATSAPP } from 'dashboard/components-next/conversa-canal/pele';
import GravadorDoWhatsapp from 'dashboard/components-next/conversa-canal/GravadorDoWhatsapp.vue';
import CabecaDaResposta from 'dashboard/components-next/conversa-canal/email/CabecaDaResposta.vue';
import TopoDaResposta from 'dashboard/components-next/conversa-canal/email/TopoDaResposta.vue';
import CitacaoDaResposta from 'dashboard/components-next/conversa-canal/email/CitacaoDaResposta.vue';
import ModeloDaResposta from 'dashboard/components-next/conversa-canal/email/ModeloDaResposta.vue';
import JanelaDeEmojis from 'dashboard/components-next/emoji/JanelaDeEmojis.vue';
import ModelosDeEmailAPI from 'dashboard/api/modelosDeEmail';
import {
  montarModelo,
  preencherModelo,
  textoDoModelo,
} from 'dashboard/components-next/conversa-canal/email/modeloDeEmail';
import {
  DESCARTAR_EMAIL,
  MODELO_DE_CAMPANHA,
  MODELOS_DO_EMAIL,
  MODOS_DE_RESPOSTA,
  RESPONDER_EMAIL,
  useEmailDaConversa,
} from 'dashboard/components-next/conversa-canal/email/useConversaDeEmail';
import { lerEndereco } from 'dashboard/components-next/conversa-canal/email/dadosDoEmail';
import { montarRespostaDoEmail } from 'dashboard/components-next/conversa-canal/email/respostaDoEmail';
import { validEmailsByComma } from './helpers/emailHeadHelper';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { createPendingMessage } from 'dashboard/helper/commons';
import { isFileTypeAllowedForChannel } from 'shared/helpers/FileHelper';

import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { LocalStorage } from 'shared/helpers/localStorage';
import { emitter } from 'shared/helpers/mitt';

export default {
  components: {
    ArticleSearchPopover,
    AttachmentPreview,
    AudioRecorder,
    GravadorDoWhatsapp,
    CabecaDaResposta,
    TopoDaResposta,
    CitacaoDaResposta,
    ModeloDaResposta,
    JanelaDeEmojis,
    ReplyBoxBanner,
    WhatsappApiReplyHint,
    DevolverParaIa,
    MessageSignatureMissingAlert,
    AvisoDeAssinatura,
    ReplyBottomPanel,
    ReplyEmailHead,
    ReplyToMessage,
    CitacaoNaResposta,
    CrmReplySubject,
    CrmRepasseDoAssunto,
    ReplyTopPanel,
    ContentTemplates,
    WhatsappTemplates,
    WootMessageEditor,
    QuotedEmailPreview,
    CopilotEditorSection,
    CopilotReplyBottomPanel,
    MenuDaIaDoEmail,
    AvisoDaSugestao,
    ConversationResolveAttributesModal,
  },
  mixins: [inboxMixin, fileUploadMixin],
  emits: ['toggleEditorSize'],
  setup() {
    const {
      isEditorHotKeyEnabled,
      fetchSignatureFlagFromUISettings,
      setQuotedReplyFlagForInbox,
      fetchQuotedReplyFlagFromUISettings,
    } = useUISettings();

    const messageEditor = useTemplateRef('messageEditor');
    const macroExecution = useMacroExecution();
    const shortcutKey = useKbd(['$mod', '+', 'enter']);
    // #1702: barra e campo do WhatsApp na conversa com a cara do canal.
    const { classesDaResposta, textoDoCampo, ehWhatsapp } = usePeleDaResposta();
    // #1786: na conversa de e-mail nova, Responder / Responder a todos / Encaminhar.
    const { ligado: emailNovo, fecharResposta: fecharRespostaDoEmail } =
      useEmailDaConversa();
    // #2079: na conversa do Instagram, o "Mensagem..." do Direct (a pílula vem de usePeleDaResposta).
    const { ligado: instagram } = useInstagramDaConversa();
    // #2067: ficar com a conversa ao enviar (com a flag da conta, no lugar da faixa
    // "Atribuir a mim").
    const ficar = useFicarComAConversa();

    // Options API state and methods live on the instance proxy
    const { proxy } = getCurrentInstance();
    // #1872: no e-mail novo o ✨ usa a IA do cliente (copiloto da Autonom.ia), nunca o Captain;
    // nos outros canais segue o do Chatwoot. A assinatura não vai para a IA e volta ao aceitar.
    const iaDoEmail = useIaDoEmail({
      ativo: () => emailNovo.value,
      conversaId: () => proxy.conversationId,
      rascunho: () => proxy.message,
      assinatura: () =>
        assinaturaNoTexto({
          ligada: !proxy.isPrivate && proxy.sendWithSignature,
          texto: proxy.messageSignature,
          channelType: proxy.channelType,
          medium: proxy.inbox?.medium,
        }),
    });
    const copilot = respostaComIa(emailNovo, useCopilotReply(), iaDoEmail);
    // #1895: com o copiloto ativo a barra de baixo (âncora da janela de emojis) some.
    watch(copilot.isActive, ativo => {
      if (ativo) proxy.hideEmojiPicker();
    });
    useKeyboardEvents({
      Escape: {
        action: () => proxy.hideEmojiPicker(),
        allowOnFocusedInput: true,
      },
      '$mod+KeyK': {
        action: e => {
          e.preventDefault();
          const ninja = document.querySelector('ninja-keys');
          ninja.open();
        },
        allowOnFocusedInput: true,
      },
      Enter: {
        action: e => {
          if (proxy.isAValidEvent('enter')) {
            proxy.onSendReply();
            e.preventDefault();
          }
        },
        allowOnFocusedInput: true,
      },
      '$mod+Enter': {
        action: () => {
          if (copilot.isActive.value && proxy.isFocused) {
            proxy.onSubmitCopilotReply();
          } else if (proxy.isAValidEvent('cmd_enter')) {
            proxy.onSendReply();
          }
        },
        allowOnFocusedInput: true,
      },
    });

    return {
      isEditorHotKeyEnabled,
      fetchSignatureFlagFromUISettings,
      setQuotedReplyFlagForInbox,
      fetchQuotedReplyFlagFromUISettings,
      messageEditor,
      copilot,
      iaDoEmail,
      shortcutKey,
      macroExecution,
      instagram,
      GRAVADOR_DO_INSTAGRAM,
      classesDaResposta,
      ehWhatsapp,
      emailNovo,
      fecharRespostaDoEmail,
      textoDoCampo,
      FORA_DA_REGUA,
      ficar,
    };
  },
  data() {
    return {
      message: '',
      inReplyTo: {},
      crmSubjectCardId: null,
      isFocused: false,
      showEmojiPicker: false,
      attachedFiles: [],
      isRecordingAudio: false,
      recordingAudioState: '',
      recordingAudioDurationText: '',
      replyType: REPLY_EDITOR_MODES.REPLY,
      draftConversationId: null,
      draftReplyMode: null,
      bccEmails: '',
      ccEmails: '',
      toEmails: '',
      doAutoSaveDraft: () => {},
      showWhatsAppTemplatesModal: false,
      requestContactInfoTemplatesOnly: false,
      showContentTemplatesModal: false,
      updateEditorSelectionWith: '',
      undefinedVariableMessage: '',
      showMentions: false,
      showUserMentions: false,
      showCannedMenu: false,
      showVariablesMenu: false,
      showMacrosMenu: false,
      newConversationModalActive: false,
      showArticleSearchPopover: false,
      hasRecordedAudio: false,
      modoDoEmail: MODOS_DE_RESPOSTA.TODOS,
      // #1786: o que vai junto da resposta de e-mail (histórico ou encaminhado) e a
      // escolha de não mandar o histórico, só desta resposta.
      citacaoDoEmail: null,
      historicoDesligado: false,
      // #1786: modelo de e-mail das Campanhas escolhido no "+" e os valores dos campos.
      modeloDoEmail: null,
      valoresDoModelo: {},
      // #1786: o último pedido de modelo (descarta resposta atrasada) e os destinatários
      // que a resposta montou (para a troca de tipo não apagar o que foi editado à mão).
      pedidoDoModelo: 0,
      destinatariosMontados: {},
      // #1702: a seta do gravador do WhatsApp para e envia; o envio sai quando o áudio vira anexo.
      enviarAudioAoAnexar: false,
      copilotAcceptedMessages: {},
    };
  },
  computed: {
    // Só pessoa responsável (#2249): o repasse do assunto não aparece para robô com o meu id.
    pessoaResponsavelId() {
      return humanAssigneeId(this.currentChat);
    },
    ...mapGetters({
      currentChat: 'getSelectedChat',
      messageSignature: 'getMessageSignature',
      currentUser: 'getCurrentUser',
      lastEmail: 'getLastEmailInSelectedChat',
      globalConfig: 'globalConfig/get',
      isMetaMessageSendingDisabled: 'globalConfig/isMetaMessageSendingDisabled',
      accountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    isMacrosEnabled() {
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.MACROS
      );
    },
    currentContact() {
      const senderId = this.currentChat?.meta?.sender?.id;
      if (!senderId) return {};
      return this.$store.getters['contacts/getContact'](senderId);
    },
    crmReplySubjectEnabled() {
      return (
        Boolean(this.currentChat?.id) &&
        (this.globalConfig?.crmKanbanEnabled === true ||
          window.globalConfig?.CRM_KANBAN_ENABLED === 'true')
      );
    },
    shouldShowReplyToMessage() {
      return (
        this.inReplyTo?.id &&
        !this.isPrivate &&
        this.inboxHasFeature(INBOX_FEATURES.REPLY_TO) &&
        !this.is360DialogWhatsAppChannel &&
        !this.copilot.isActive.value
      );
    },
    showWhatsappTemplates() {
      // We support templates for API channels if someone updates templates manually via API
      // That's why we don't explicitly check for channel type here
      const templates = this.$store.getters['inboxes/getWhatsAppTemplates'](
        this.inboxId
      );
      return !!(templates && templates.length) && !this.isPrivate;
    },
    showContentTemplates() {
      return this.isATwilioWhatsAppChannel && !this.isPrivate;
    },
    isWithinMessagingWindow() {
      return !!(
        this.currentChat?.can_reply ||
        this.isAWhatsAppChannel ||
        this.isAPIInbox
      );
    },
    canSendPublicReply() {
      return (
        this.isWithinMessagingWindow &&
        !this.isBotOwnedPendingConversation &&
        !this.isInstagramReplyRestricted
      );
    },
    isInstagramReplyRestricted() {
      return this.isMetaMessageSendingDisabled && this.isAnInstagramChannel;
    },
    isPrivate() {
      return (
        !this.canSendPublicReply || this.replyType === REPLY_EDITOR_MODES.NOTE
      );
    },
    isOnPrivateNote() {
      if (this.isInstagramReplyRestricted) {
        return true;
      }

      return this.isBotOwnedPendingConversation
        ? this.isPrivate
        : this.replyType === REPLY_EDITOR_MODES.NOTE;
    },
    effectiveReplyMode() {
      return this.isOnPrivateNote
        ? REPLY_EDITOR_MODES.NOTE
        : REPLY_EDITOR_MODES.REPLY;
    },
    hasMeaningfulEditorContent() {
      const body = this.message || '';
      // Only strip the signature when it's actually being auto-appended.
      // If the toggle is off, the agent's text might happen to match their
      // saved signature and we'd incorrectly treat it as empty.
      const shouldStripSignature =
        !this.isPrivate && this.sendWithSignature && !!this.messageSignature;
      if (!shouldStripSignature) return !!body.trim();
      const stripped = removeSignature(
        body,
        this.messageSignature,
        getEffectiveChannelType(this.channelType, this.inbox?.medium || '')
      );
      return !!stripped.trim();
    },
    // #2067: o ícone aparece mesmo sem nada digitado (o modelo e o áudio também ficam com a
    // conversa), nunca na nota privada nem na conversa que já é minha.
    mostrarFicarComAConversa() {
      return this.ficar.aplica && !this.isOnPrivateNote;
    },
    // #2067: a flag da conta; desligada, a tela fica como antes (faixa "Atribuir a mim").
    ficarLigadoNaConta() {
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.FICAR_COM_A_CONVERSA_AO_ENVIAR
      );
    },
    isBotOwnedPendingConversation() {
      return (
        this.currentChat?.status === wootConstants.STATUS_TYPE.PENDING &&
        this.currentChat?.meta?.assignee_type === 'AgentBot'
      );
    },
    inboxId() {
      return this.currentChat.inbox_id;
    },
    inbox() {
      return this.$store.getters['inboxes/getInbox'](this.inboxId);
    },
    messagePlaceHolder() {
      if (this.isEditorDisabled) {
        // #1702: o aviso acima já explica as 24 h; o campo só diz o que fazer.
        if (this.textoDoCampo && this.isAWhatsAppCloudChannel) {
          return this.$t('CONVERSA_CANAL.CAIXA.SO_MODELO');
        }
        if (this.isAWhatsAppChannel) {
          return this.$t('CONVERSATION.FOOTER.MESSAGING_RESTRICTED_WHATSAPP');
        }
        if (this.isAPIInbox) {
          return this.$t('CONVERSATION.FOOTER.MESSAGING_RESTRICTED_API');
        }
        return this.$t('CONVERSATION.FOOTER.MESSAGING_RESTRICTED');
      }
      if (!this.isPrivate && this.textoDoCampo) return this.textoDoCampo;
      if (!this.isPrivate && this.instagram) {
        return this.$t('CONVERSA_CANAL.INSTAGRAM.CAMPO');
      }
      // #1786: no e-mail novo, uma frase simples no lugar do atalho técnico.
      if (!this.isPrivate && this.emailNovo) {
        return this.$t('CONVERSA_CANAL.EMAIL.ESCREVA');
      }
      return this.isPrivate
        ? this.$t('CONVERSATION.FOOTER.PRIVATE_MSG_INPUT')
        : this.$t('CONVERSATION.FOOTER.MSG_INPUT');
    },
    isMessageLengthReachingThreshold() {
      return this.message.length > this.maxLength - 50;
    },
    charactersRemaining() {
      return this.maxLength - this.message.length;
    },
    isReplyButtonDisabled() {
      if (this.isEditorDisabled) return true;
      if (this.isATwitterInbox) return true;
      // #1786: endereço errado, ou Encaminhar sem Para (o envio cairia no cliente).
      if (this.emailNovo && !this.isPrivate && !this.destinatariosDoEmailOk)
        return true;
      if (this.hasAttachments || this.hasRecordedAudio) return false;
      // #1786: com um modelo de e-mail, dá para enviar só o modelo.
      if (this.emailNovo && this.modeloDoEmail && !this.isPrivate) {
        return this.message.length > this.maxLength;
      }

      return (
        this.isMessageEmpty ||
        this.message.length === 0 ||
        this.message.length > this.maxLength
      );
    },
    encaminhandoEmail() {
      return this.modoDoEmail === MODOS_DE_RESPOSTA.ENCAMINHAR;
    },
    destinatariosDoEmailOk() {
      const campos = [this.toEmails, this.ccEmails, this.bccEmails];
      if (!campos.every(campo => validEmailsByComma(String(campo || ''))))
        return false;
      if (!this.encaminhandoEmail) return true;
      return String(this.toEmails || '')
        .split(',')
        .some(item => item.trim());
    },
    sender() {
      return {
        name: this.currentUser.name,
        thumbnail: this.currentUser.avatar_url,
      };
    },
    conversationType() {
      const { additional_attributes: additionalAttributes } = this.currentChat;
      const type = additionalAttributes ? additionalAttributes.type : '';
      return type || '';
    },
    maxLength() {
      if (this.isPrivate) {
        return MESSAGE_MAX_LENGTH.GENERAL;
      }
      if (this.isAFacebookInbox) {
        return MESSAGE_MAX_LENGTH.FACEBOOK;
      }
      if (this.isAnInstagramChannel) {
        return MESSAGE_MAX_LENGTH.INSTAGRAM;
      }
      if (this.isATelegramChannel) {
        return MESSAGE_MAX_LENGTH.TELEGRAM;
      }
      if (this.isATiktokChannel) {
        return MESSAGE_MAX_LENGTH.TIKTOK;
      }
      if (this.isATwilioWhatsAppChannel) {
        return MESSAGE_MAX_LENGTH.TWILIO_WHATSAPP;
      }
      if (this.isAWhatsAppCloudChannel) {
        return MESSAGE_MAX_LENGTH.WHATSAPP_CLOUD;
      }
      if (this.isASmsInbox) {
        return MESSAGE_MAX_LENGTH.TWILIO_SMS;
      }
      if (this.isAnEmailChannel) {
        return MESSAGE_MAX_LENGTH.EMAIL;
      }
      if (this.isATwilioSMSChannel) {
        return MESSAGE_MAX_LENGTH.TWILIO_SMS;
      }
      if (this.isAWhatsAppChannel) {
        return MESSAGE_MAX_LENGTH.WHATSAPP_CLOUD;
      }
      return MESSAGE_MAX_LENGTH.GENERAL;
    },
    showFileUpload() {
      const { image_send: imageSend } =
        this.currentChat?.additional_attributes?.tiktok_capabilities ?? {};
      const tiktokAttachmentSupported = imageSend ?? true;

      return (
        this.isAWebWidgetInbox ||
        this.isAFacebookInbox ||
        this.isAWhatsAppChannel ||
        this.isAPIInbox ||
        this.isAnEmailChannel ||
        this.isASmsInbox ||
        this.isATelegramChannel ||
        this.isALineChannel ||
        this.isAnInstagramChannel ||
        (this.isATiktokChannel && tiktokAttachmentSupported)
      );
    },
    replyButtonLabel() {
      // #1786: no e-mail novo o botão diz o destino ("Enviar para Marina") ou "Salvar nota".
      if (this.emailNovo) return this.rotuloDoEnvioDoEmail;
      let sendMessageText = this.$t('CONVERSATION.REPLYBOX.SEND');
      if (this.isPrivate) {
        sendMessageText = this.$t('CONVERSATION.REPLYBOX.CREATE');
      }
      const keyLabel = this.isEditorHotKeyEnabled('cmd_enter')
        ? `(${this.shortcutKey})`
        : '(↵)';
      return `${sendMessageText} ${keyLabel}`;
    },
    modoDoTopoDoEmail() {
      return this.isPrivate ? MODOS_DE_RESPOSTA.NOTA : this.modoDoEmail;
    },
    mensagemCitadaDoEmail() {
      const id = this.citacaoDoEmail?.mensagemId;
      return id
        ? this.currentChat?.messages?.find(item => item.id === id)
        : null;
    },
    rotuloDoEnvioDoEmail() {
      if (this.isPrivate) return this.$t('CONVERSA_CANAL.EMAIL.SALVAR_NOTA');
      const lista = campo =>
        String(campo || '')
          .split(',')
          .map(item => item.trim())
          .filter(Boolean);
      const primeiro = lista(this.toEmails)[0];
      if (!primeiro) return this.$t('CONVERSA_CANAL.EMAIL.ENVIAR');
      // Com Cc/Cco ou vários no Para: "Enviar para Marina e mais 1".
      const outros =
        lista(this.toEmails).length +
        lista(this.ccEmails).length +
        lista(this.bccEmails).length -
        1;
      const contato = this.currentChat?.meta?.sender || {};
      const { endereco } = lerEndereco(primeiro);
      const nome =
        endereco.toLowerCase() === String(contato.email || '').toLowerCase()
          ? String(contato.name || '').split(' ')[0]
          : endereco;
      return outros > 0
        ? this.$t('CONVERSA_CANAL.EMAIL.ENVIAR_PARA_VARIOS', {
            nome,
            total: outros,
          })
        : this.$t('CONVERSA_CANAL.EMAIL.ENVIAR_PARA', { nome });
    },
    replyBoxClass() {
      return {
        [this.classesDaResposta.caixa]: true,
        [this.classesDaResposta.soResposta]: !this.isPrivate,
        [this.classesDaResposta.nota]: this.isPrivate,
        [this.classesDaResposta.gravando]:
          !this.isPrivate && this.showAudioRecorderEditor,
        'is-private': this.isPrivate,
        'is-focused': this.isFocused || this.hasAttachments,
      };
    },
    hasAttachments() {
      return this.attachedFiles.length;
    },
    showAudioRecorder() {
      return !this.isOnPrivateNote && this.showFileUpload;
    },
    showAudioRecorderEditor() {
      return this.showAudioRecorder && this.isRecordingAudio;
    },
    isMessageEmpty() {
      if (!this.message) {
        return true;
      }
      return !this.message.trim().replace(/\n/g, '').length;
    },
    showReplyHead() {
      return !this.isOnPrivateNote && this.isAnEmailChannel;
    },
    enableMultipleFileUpload() {
      return (
        this.isAnEmailChannel ||
        this.isAWebWidgetInbox ||
        this.isAPIInbox ||
        this.isAWhatsAppChannel ||
        this.isATelegramChannel
      );
    },
    isSignatureEnabledForInbox() {
      return !this.isPrivate && this.sendWithSignature;
    },
    isSignatureAvailable() {
      return !!this.messageSignature;
    },
    sendWithSignature() {
      return this.fetchSignatureFlagFromUISettings(this.channelType);
    },
    conversationId() {
      return this.currentChat.id;
    },
    conversationIdByRoute() {
      return this.conversationId;
    },
    editorStateId() {
      return `draft-${this.conversationIdByRoute}-${this.effectiveReplyMode}`;
    },
    audioRecordFormat() {
      if (this.isAWhatsAppCloudChannel) {
        return AUDIO_FORMATS.OGG;
      }
      if (this.isAWhatsAppChannel || this.isATelegramChannel) {
        return AUDIO_FORMATS.MP3;
      }
      if (this.isAPIInbox) {
        return AUDIO_FORMATS.MP3;
      }
      return AUDIO_FORMATS.WAV;
    },
    messageVariables() {
      const variables = getMessageVariables({
        conversation: this.currentChat,
        contact: this.currentContact,
        inbox: this.inbox,
      });
      // Match the backend drops: names are Ruby-capitalized and
      // {{agent.*}} is the message sender, not the assignee.
      return {
        ...variables,
        ...getContactVariables(this.currentContact),
        ...getAgentVariables(this.currentUser),
      };
    },
    connectedPortalSlug() {
      const { help_center: portal = {} } = this.inbox;
      const { slug = '' } = portal;
      return slug;
    },
    quotedReplyPreference() {
      if (!this.isAnEmailChannel) {
        return false;
      }

      return !!this.fetchQuotedReplyFlagFromUISettings(this.channelType);
    },
    lastEmailWithQuotedContent() {
      if (!this.isAnEmailChannel) {
        return null;
      }

      const lastEmail = this.lastEmail;
      if (!lastEmail || lastEmail.private) {
        return null;
      }

      return lastEmail;
    },
    quotedEmailText() {
      return extractQuotedEmailText(this.lastEmailWithQuotedContent);
    },
    quotedEmailPreviewText() {
      return truncatePreviewText(this.quotedEmailText, 80);
    },
    shouldShowQuotedReplyToggle() {
      // #1786: no e-mail novo o histórico é o cartão embaixo do texto (vai por padrão).
      return this.isAnEmailChannel && !this.isOnPrivateNote && !this.emailNovo;
    },
    shouldShowQuotedPreview() {
      return (
        this.shouldShowQuotedReplyToggle &&
        this.quotedReplyPreference &&
        !!this.quotedEmailText
      );
    },
    isDefaultEditorMode() {
      return !this.showAudioRecorderEditor && !this.copilot.isActive.value;
    },
    isEditorDisabled() {
      return (
        (this.isAWhatsAppChannel || this.isAPIInbox) &&
        !this.isOnPrivateNote &&
        !this.currentChat.can_reply
      );
    },
  },
  watch: {
    currentChat(conversation, oldConversation) {
      if (oldConversation && oldConversation.id !== conversation.id) {
        // Only update email fields when switching to a completely different conversation (by ID)
        // This prevents overwriting user input (e.g., CC/BCC fields) when performing actions
        // like self-assign or other updates that do not actually change the conversation context
        this.setCCAndToEmailsFromLastChat();
        // Reset Copilot editor state (includes cancelling ongoing generation)
        this.copilot.reset();
      }

      if (this.isInstagramReplyRestricted) {
        this.replyType = REPLY_EDITOR_MODES.NOTE;
        return;
      }

      if (this.isOnPrivateNote) {
        return;
      }

      this.replyType = this.isWithinMessagingWindow
        ? REPLY_EDITOR_MODES.REPLY
        : REPLY_EDITOR_MODES.NOTE;

      this.fetchAndSetReplyTo();
    },
    // When moving from one conversation to another, the store may not have the
    // list of all the messages. A fetch is subsequently made to get the messages.
    // This watcher handles two main cases:
    // 1. When switching conversations and messages are fetched/updated, ensures CC/BCC fields are set from the latest OUTGOING/INCOMING email (not activity/private messages).
    // 2. Fixes and issue where CC/BCC fields could be reset/lost after assignment/activity actions or message mutations that did not represent a true email context change.
    lastEmail: {
      handler(lastEmail) {
        if (!lastEmail) return;
        // #1786: no e-mail novo quem monta os destinatários é o responderEmail; aqui só
        // se completa a resposta aberta antes de o e-mail chegar.
        if (this.emailNovo) {
          this.completarRespostaDoEmail(lastEmail);
          return;
        }
        this.setCCAndToEmailsFromLastChat();
      },
      deep: true,
    },
    conversationIdByRoute(conversationId, oldConversationId) {
      if (conversationId !== oldConversationId) {
        this.switchDraftContext(conversationId, this.effectiveReplyMode);
        this.resetRecorderAndClearAttachments();
        this.zerarRespostaDoEmail();
      }
    },
    message() {
      // Autosave the current message draft.
      this.doAutoSaveDraft();
    },
    showWhatsappTemplates(isAvailable) {
      if (!isAvailable) this.hideWhatsappTemplatesModal();
    },
    showContentTemplates(isAvailable) {
      if (!isAvailable) this.hideContentTemplatesModal();
    },
    effectiveReplyMode(updatedReplyType) {
      this.$store.dispatch('draftMessages/setReplyEditorMode', {
        mode: updatedReplyType,
      });
      this.switchDraftContext(this.conversationIdByRoute, updatedReplyType);
    },
  },

  mounted() {
    if (this.isInstagramReplyRestricted) {
      this.replyType = REPLY_EDITOR_MODES.NOTE;
    }

    this.$store.dispatch('draftMessages/setReplyEditorMode', {
      mode: this.effectiveReplyMode,
    });
    this.switchDraftContext(
      this.conversationIdByRoute,
      this.effectiveReplyMode
    );
    // Bound directly rather than through useKeyboardEvents, because this has to
    // keep working even while the editor is focussed.
    document.addEventListener('paste', this.onPaste);
    this.setCCAndToEmailsFromLastChat();
    this.doAutoSaveDraft = debounce(
      () => {
        this.saveDraft(this.conversationIdByRoute, this.effectiveReplyMode);
      },
      500,
      true
    );

    this.fetchAndSetReplyTo();
    emitter.on(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.onReplyToMessage);
    emitter.on(ABRIR_MODELOS_DO_WHATSAPP, this.openWhatsappTemplateModal);
    emitter.on(RESPONDER_EMAIL, this.responderEmail);
    emitter.on(DESCARTAR_EMAIL, this.descartarEmail);
    emitter.on(MODELOS_DO_EMAIL, this.inserirModeloDoEmail);
    emitter.on(MODELO_DE_CAMPANHA, this.carregarModeloDeCampanha);

    // A hacky fix to solve the drag and drop
    // Is showing on top of new conversation modal drag and drop
    // TODO need to find a better solution
    emitter.on(
      BUS_EVENTS.NEW_CONVERSATION_MODAL,
      this.onNewConversationModalActive
    );
    emitter.on(CMD_AI_ASSIST, this.executeCopilotAction);
  },
  unmounted() {
    document.removeEventListener('paste', this.onPaste);
    emitter.off(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.onReplyToMessage);
    emitter.off(ABRIR_MODELOS_DO_WHATSAPP, this.openWhatsappTemplateModal);
    emitter.off(RESPONDER_EMAIL, this.responderEmail);
    emitter.off(DESCARTAR_EMAIL, this.descartarEmail);
    emitter.off(MODELOS_DO_EMAIL, this.inserirModeloDoEmail);
    emitter.off(MODELO_DE_CAMPANHA, this.carregarModeloDeCampanha);
    emitter.off(
      BUS_EVENTS.NEW_CONVERSATION_MODAL,
      this.onNewConversationModalActive
    );
    emitter.off(CMD_AI_ASSIST, this.executeCopilotAction);
  },
  methods: {
    openContactInfoTemplateModal() {
      this.requestContactInfoTemplatesOnly = true;
      this.showWhatsAppTemplatesModal = true;
    },
    getDraftKey(
      conversationId = this.conversationIdByRoute,
      replyType = this.effectiveReplyMode
    ) {
      return `draft-${conversationId}-${replyType}`;
    },
    getCopilotAcceptedMessage(replyType = this.effectiveReplyMode) {
      const key = this.getDraftKey(this.conversationIdByRoute, replyType);
      return this.copilotAcceptedMessages[key] || '';
    },
    setCopilotAcceptedMessage(message, replyType = this.effectiveReplyMode) {
      const key = this.getDraftKey(this.conversationIdByRoute, replyType);
      this.copilotAcceptedMessages[key] = trimContent(
        message || '',
        this.maxLength
      );
    },
    clearCopilotAcceptedMessage(replyType = this.effectiveReplyMode) {
      const key = this.getDraftKey(this.conversationIdByRoute, replyType);
      delete this.copilotAcceptedMessages[key];
    },
    handleInsert(article) {
      const { url, title } = article;
      // Removing empty lines from the title
      const lines = title.split('\n');
      const nonEmptyLines = lines.filter(line => line.trim() !== '');
      const filteredMarkdown = nonEmptyLines.join(' ');
      emitter.emit(
        BUS_EVENTS.INSERT_INTO_RICH_EDITOR,
        `[${filteredMarkdown}](${url})`
      );

      useTrack(CONVERSATION_EVENTS.INSERT_ARTICLE_LINK);
    },
    toggleQuotedReply() {
      if (!this.isAnEmailChannel) {
        return;
      }

      const nextValue = !this.quotedReplyPreference;
      this.setQuotedReplyFlagForInbox(this.channelType, nextValue);
    },
    shouldIncludeQuotedEmail() {
      return (
        this.quotedReplyPreference &&
        this.shouldShowQuotedReplyToggle &&
        !!this.quotedEmailText
      );
    },
    getMessageWithQuotedEmailText(message) {
      // #1786: no e-mail novo o histórico vai pelo servidor, formatado (email_citacao).
      if (this.emailNovo) return message;
      if (!this.shouldIncludeQuotedEmail()) {
        return message;
      }

      const quotedText = this.quotedEmailText || '';
      const header = buildQuotedEmailHeader(
        this.lastEmailWithQuotedContent,
        this.currentContact,
        this.inbox
      );

      return appendQuotedTextToMessage(message, quotedText, header);
    },
    resetRecorderAndClearAttachments() {
      // Reset audio recorder UI state
      this.resetAudioRecorderInput();
      // Reset attached files
      this.attachedFiles = [];
    },
    saveDraft(conversationId, replyType) {
      if (this.message || this.message === '') {
        const key = this.getDraftKey(conversationId, replyType);
        const draftToSave = trimContent(this.message || '', this.maxLength);

        this.$store.dispatch('draftMessages/set', {
          key,
          message: draftToSave,
        });
      }
    },
    setToDraft(conversationId, replyType) {
      this.saveDraft(conversationId, replyType);
      this.message = '';
    },
    switchDraftContext(conversationId, replyMode) {
      if (
        this.draftConversationId === conversationId &&
        this.draftReplyMode === replyMode
      ) {
        return;
      }

      if (this.draftConversationId) {
        this.setToDraft(this.draftConversationId, this.draftReplyMode);
      }

      this.draftConversationId = conversationId;
      this.draftReplyMode = replyMode;
      this.getFromDraft();
    },
    getFromDraft() {
      if (this.conversationIdByRoute) {
        const key = this.getDraftKey();
        const messageFromStore =
          this.$store.getters['draftMessages/get'](key) || '';

        // ensure that the message has signature set based on the ui setting
        this.message = this.toggleSignatureForDraft(messageFromStore);
      }
    },
    toggleSignatureForDraft(message) {
      if (this.isPrivate) {
        return message;
      }

      // Even when editor is disabled (e.g. WhatsApp/API can't reply), we must
      // still normalize stale signatures out of drafts when signature is off.
      if (this.isEditorDisabled && this.sendWithSignature) {
        return message;
      }

      const effectiveChannelType = getEffectiveChannelType(
        this.channelType,
        this.inbox?.medium || ''
      );

      return this.sendWithSignature
        ? appendSignature(message, this.messageSignature, effectiveChannelType)
        : removeSignature(message, this.messageSignature, effectiveChannelType);
    },
    removeFromDraft() {
      if (this.conversationIdByRoute) {
        const key = this.getDraftKey();
        this.$store.dispatch('draftMessages/delete', { key });
      }
    },
    isAValidEvent(selectedKey) {
      return (
        !this.showUserMentions &&
        !this.showMentions &&
        !this.showCannedMenu &&
        !this.showVariablesMenu &&
        !this.showMacrosMenu &&
        this.isFocused &&
        this.isEditorHotKeyEnabled(selectedKey)
      );
    },
    onPaste(e) {
      // Don't handle paste if compose new conversation modal is open
      if (this.newConversationModalActive) return;

      // Don't handle paste if editor is disabled
      if (this.isEditorDisabled) return;
      if (!this.showFileUpload && !this.isOnPrivateNote) return;

      // Filter valid files (non-zero size)
      Array.from(e.clipboardData.files)
        .filter(file => file.size > 0)
        .filter(file => {
          const isAllowed = isFileTypeAllowedForChannel(file, {
            channelType: this.channelType || this.inbox?.channel_type,
            medium: this.inbox?.medium,
            conversationType: this.conversationType,
            isInstagramChannel: this.isAnInstagramChannel,
            isOnPrivateNote: this.isOnPrivateNote,
          });

          if (!isAllowed) {
            useAlert(
              this.$t('CONVERSATION.FILE_TYPE_NOT_SUPPORTED', {
                fileName: file.name,
              })
            );
          }

          return isAllowed;
        })
        .forEach(file => {
          const { name, type, size } = file;
          this.onFileUpload({ name, type, size, file });
        });
    },
    toggleUserMention(currentMentionState) {
      this.showUserMentions = currentMentionState;
    },
    toggleCannedMenu(value) {
      this.showCannedMenu = value;
    },
    toggleVariablesMenu(value) {
      this.showVariablesMenu = value;
    },
    toggleMacrosMenu(value) {
      this.showMacrosMenu = value;
    },
    onExecuteMacro(macro) {
      const pending = this.macroExecution.execute(macro, this.currentChat.id);
      if (pending) {
        this.$refs.resolveAttributesModal?.open(
          pending.missing,
          pending.customAttributes
        );
      }
    },
    openWhatsappTemplateModal() {
      this.requestContactInfoTemplatesOnly = false;
      this.showWhatsAppTemplatesModal = true;
    },
    hideWhatsappTemplatesModal() {
      this.showWhatsAppTemplatesModal = false;
      this.requestContactInfoTemplatesOnly = false;
    },
    openContentTemplateModal() {
      this.showContentTemplatesModal = true;
    },
    hideContentTemplatesModal() {
      this.showContentTemplatesModal = false;
    },
    confirmOnSendReply() {
      if (this.isReplyButtonDisabled) {
        return;
      }
      if (!this.showMentions) {
        // #2067: uma decisão de "ficar com a conversa" para todas as partes deste envio.
        const decisao = this.ficar.decidir({ privada: this.isPrivate });
        let envios;
        const copilotAcceptedMessage = this.getCopilotAcceptedMessage();
        const isOnWhatsApp =
          this.isATwilioWhatsAppChannel ||
          this.isAWhatsAppCloudChannel ||
          this.is360DialogWhatsAppChannel;
        // Instagram and TikTok do not support sending text and attachments in the same message.
        // For Instagram, combining them causes duplicate messages due to separate echo events per component.
        // For TikTok, the API rejects messages that mix text and media.
        // To handle both cases, text and attachments are always sent as separate messages.
        const isOnInstagram = this.isAnInstagramChannel;
        const isOnTiktok = this.isATiktokChannel;
        if ((isOnWhatsApp || isOnInstagram || isOnTiktok) && !this.isPrivate) {
          envios = this.sendMessageAsMultipleMessages(
            this.message,
            copilotAcceptedMessage,
            decisao
          );
        } else {
          const messagePayload = this.getMessagePayload(this.message);
          envios = [
            this.sendMessage(
              messagePayload,
              this.message,
              copilotAcceptedMessage,
              decisao
            ),
          ];
        }
        this.depoisDoEnvio(decisao, envios);

        if (!this.isPrivate) {
          this.clearEmailField();
        }

        this.clearMessage();
        this.hideEmojiPicker();
      }
    },
    // #2067: devolve os envios (promessas), para decidir uma vez depois de todas as partes.
    sendMessageAsMultipleMessages(
      message,
      copilotAcceptedMessage = '',
      decisao = null
    ) {
      const messages = this.getMultipleMessagesPayload(message);
      return messages.map(messagePayload =>
        this.sendMessage(
          messagePayload,
          messagePayload.message || '',
          copilotAcceptedMessage,
          decisao
        )
      );
    },
    sendMessageAnalyticsData(
      isPrivate,
      { editorMessage = '', copilotAcceptedMessage = '' } = {}
    ) {
      const normalizeForComparison = message => {
        let normalizedMessage = message || '';

        if (this.sendWithSignature && this.messageSignature && !isPrivate) {
          const effectiveChannelType = getEffectiveChannelType(
            this.channelType,
            this.inbox?.medium || ''
          );
          normalizedMessage = removeSignature(
            normalizedMessage,
            this.messageSignature,
            effectiveChannelType
          );
        }

        return trimContent(normalizedMessage);
      };

      const normalizedAcceptedMessage = normalizeForComparison(
        copilotAcceptedMessage
      );
      const normalizedEditorMessage = normalizeForComparison(editorMessage);

      if (normalizedAcceptedMessage && normalizedEditorMessage) {
        useTrack(CAPTAIN_EVENTS.AI_ASSISTED_MESSAGE_SENT, {
          conversationId: this.conversationIdByRoute,
          channelType: this.channelType,
          editedBeforeSend:
            normalizedAcceptedMessage !== normalizedEditorMessage,
          isPrivate,
        });
      }

      // Analytics data for message signature is enabled or not in channels
      return isPrivate
        ? useTrack(CONVERSATION_EVENTS.SENT_PRIVATE_NOTE)
        : useTrack(CONVERSATION_EVENTS.SENT_MESSAGE, {
            channelType: this.channelType,
            signatureEnabled: this.sendWithSignature,
            hasReplyTo: !!this.inReplyTo?.id,
          });
    },
    async onSendReply() {
      const undefinedVariables = getUndefinedVariablesInMessage({
        message: this.message,
        variables: this.messageVariables,
      });
      if (undefinedVariables.length > 0) {
        const undefinedVariablesCount =
          undefinedVariables.length > 1 ? undefinedVariables.length : 1;
        this.undefinedVariableMessage = this.$t(
          'CONVERSATION.REPLYBOX.UNDEFINED_VARIABLES.MESSAGE',
          {
            undefinedVariablesCount,
            undefinedVariables: undefinedVariables.join(', '),
          }
        );

        const ok = await this.$refs.confirmDialog.showConfirmation();
        if (ok) {
          this.confirmOnSendReply();
        }
      } else {
        this.confirmOnSendReply();
      }
    },
    // `decisao` (#2067): a de "ficar com a conversa" do envio de que esta mensagem é parte
    // (todas as partes levam o mesmo pedido: saem em paralelo, e qualquer uma que chegue
    // primeiro fica). Sem ela (modelo, mensagem pronta), o envio decide sozinho. Devolve
    // { ok, data }.
    async sendMessage(
      messagePayload,
      editorMessage = '',
      copilotAcceptedMessage = '',
      decisao = undefined
    ) {
      const sozinho = decisao === undefined;
      const daqui = sozinho
        ? this.ficar.decidir({ privada: messagePayload.private })
        : decisao;
      const envio = this.enviarParte(
        { ...messagePayload, ...camposDoEnvio(daqui) },
        editorMessage,
        copilotAcceptedMessage
      );
      if (sozinho) this.depoisDoEnvio(daqui, [envio]);
      return envio;
    },
    // Como na main: dispara o envio e, na hora (sem esperar o servidor), rola, avisa que a
    // mensagem saiu, apaga o rascunho desta conversa (chave tirada antes: trocar de conversa
    // durante um envio lento não apaga o rascunho de outra) e manda a métrica. Só depois
    // espera a resposta, para o #2067 saber se saiu ({ ok, data }). A falha do servidor só
    // vira aviso com a flag ligada; desligada, fica como na main (a bolha mostra a falha).
    async enviarParte(messagePayload, editorMessage, copilotAcceptedMessage) {
      const chaveDoRascunho = this.conversationIdByRoute
        ? this.getDraftKey()
        : null;
      let envio;
      try {
        envio = this.$store.dispatch(
          'createPendingMessageAndSend',
          this.setCrmSubjectInPayload(messagePayload)
        );
      } catch (error) {
        this.avisarFalhaDoEnvio(error);
        return { ok: false };
      }
      emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
      emitter.emit(BUS_EVENTS.MESSAGE_SENT);
      if (chaveDoRascunho) {
        this.$store.dispatch('draftMessages/delete', { key: chaveDoRascunho });
      }
      this.sendMessageAnalyticsData(messagePayload.private, {
        editorMessage,
        copilotAcceptedMessage,
      });
      try {
        return { ok: true, data: await envio };
      } catch (error) {
        if (this.ficarLigadoNaConta) this.avisarFalhaDoEnvio(error);
        return { ok: false };
      }
    },
    avisarFalhaDoEnvio(error) {
      useAlert(
        error?.response?.data?.error || this.$t('CONVERSATION.MESSAGE_ERROR')
      );
    },
    // #2067: depois de todas as partes de um envio. Alguma não saiu: a escolha do ícone
    // volta. Pediu para ficar e o servidor não conseguiu em NENHUMA parte: avisa (uma parte
    // que ficou basta; as outras acham a conversa já minha). Ficou: a tela mostra o dono
    // novo pelo evento ao vivo; se ele ainda não chegou, relê a conversa uma vez.
    async depoisDoEnvio(decisao, envios) {
      if (!decisao) return;
      const conversationId = this.currentChat?.id;
      const resultados = await Promise.all(envios);
      if (resultados.some(({ ok }) => !ok)) {
        this.ficar.restaurar(decisao);
        return;
      }
      if (!decisao.fica) return;
      if (resultados.every(({ data }) => data?.ficar_com_a_conversa_nao_deu)) {
        useAlert(this.$t('CONVERSA_CANAL.FICAR.NAO_DEU'));
        return;
      }
      this.relerSeODonoNaoChegou(conversationId);
    },
    async relerSeODonoNaoChegou(conversationId) {
      const conversa = this.$store.getters.getConversationById(conversationId);
      const jaEMinha = isAssignedToUser(conversa, this.currentUser?.id);
      if (!conversationId || jaEMinha) return;
      try {
        await this.$store.dispatch('getConversation', conversationId);
      } catch {
        // O evento ao vivo da troca de dono ainda atualiza a tela.
      }
    },
    // #1702: o "+" manda localização, contato, botão de link, opções e formulário pelo
    // envio do robô (#1473), com resposta citada e assunto do CRM como o texto. Espera o
    // servidor: a janela só fecha quando a mensagem foi aceita e mostra a recusa.
    async onSendRichMessage({ content, richMessage }) {
      const decisao = this.ficar.decidir();
      const payload = this.setReplyToInPayload({
        conversationId: this.currentChat.id,
        message: content,
        private: false,
        sender: this.sender,
        contentAttributes: { rich_message: richMessage },
        ...camposDoEnvio(decisao),
      });
      let data;
      try {
        data = await this.$store.dispatch(
          'sendMessageWithData',
          createPendingMessage(this.setCrmSubjectInPayload(payload))
        );
      } catch (error) {
        this.ficar.restaurar(decisao);
        throw error;
      }
      this.depoisDoEnvio(decisao, [{ ok: true, data }]);
      this.resetReplyToMessage();
      emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
      emitter.emit(BUS_EVENTS.MESSAGE_SENT);
    },
    async onSendWhatsAppReply(messagePayload) {
      this.sendMessage({
        conversationId: this.currentChat.id,
        ...messagePayload,
      });
      this.hideWhatsappTemplatesModal();
    },
    async onSendContentTemplateReply(messagePayload) {
      this.sendMessage({
        conversationId: this.currentChat.id,
        ...messagePayload,
      });
      this.hideContentTemplatesModal();
    },
    setReplyMode(mode = REPLY_EDITOR_MODES.REPLY) {
      // Clear attachments when switching between private note and reply modes
      // This is to prevent from breaking the upload rules
      if (this.attachedFiles.length > 0) this.attachedFiles = [];

      this.$store.dispatch('draftMessages/setReplyEditorMode', { mode });
      if (this.canSendPublicReply) this.replyType = mode;
      if (this.isRecordingAudio) {
        this.toggleAudioRecorder();
      }
    },
    clearEditorSelection() {
      this.updateEditorSelectionWith = '';
    },
    addIntoEditor(content) {
      this.updateEditorSelectionWith = content;
      this.onFocus();
    },
    executeCopilotAction(action, data) {
      this.copilot.execute(action, data);
    },
    clearMessage() {
      this.message = '';
      this.modeloDoEmail = null;
      this.valoresDoModelo = {};
      this.clearCopilotAcceptedMessage();
      if (this.sendWithSignature && !this.isPrivate) {
        // if signature is enabled, append it to the message
        const effectiveChannelType = getEffectiveChannelType(
          this.channelType,
          this.inbox?.medium || ''
        );
        this.message = appendSignature(
          this.message,
          this.messageSignature,
          effectiveChannelType
        );
      }
      this.attachedFiles = [];
      this.isRecordingAudio = false;
      this.resetReplyToMessage();
      this.resetAudioRecorderInput();
    },
    clearEmailField() {
      this.ccEmails = '';
      this.bccEmails = '';
      this.toEmails = '';
    },

    toggleEmojiPicker() {
      this.showEmojiPicker = !this.showEmojiPicker;
    },
    toggleAudioRecorder() {
      this.isRecordingAudio = !this.isRecordingAudio;
      if (!this.isRecordingAudio) {
        this.resetAudioRecorderInput();
      }
    },
    cancelarGravacao() {
      this.toggleAudioRecorder();
    },
    enviarGravacao() {
      this.enviarAudioAoAnexar = true;
      this.$refs.audioRecorderInput?.stopRecording();
    },
    // #1702: o áudio da seta só sai se ainda for a mesma conversa em que foi gravado.
    enviarSeForAGravacao(file, chatId) {
      if (!file?.isVoiceMessage || !this.enviarAudioAoAnexar) return;
      this.enviarAudioAoAnexar = false;
      if (chatId !== this.currentChat.id) return;
      this.$nextTick(() => this.onSendReply());
    },
    semMicrofone() {
      this.toggleAudioRecorder();
      useAlert(this.$t('CONVERSA_CANAL.GRAVACAO.SEM_MICROFONE'));
    },
    toggleAudioRecorderPlayPause() {
      if (!this.$refs.audioRecorderInput) return;
      if (!this.recordingAudioState) {
        this.$refs.audioRecorderInput.stopRecording();
      } else {
        this.$refs.audioRecorderInput.playPause();
      }
    },
    hideEmojiPicker() {
      if (this.showEmojiPicker) {
        this.toggleEmojiPicker();
      }
    },
    onTypingOn() {
      this.toggleTyping('on');
    },
    onTypingOff() {
      this.toggleTyping('off');
    },
    onBlur() {
      this.isFocused = false;
      this.saveDraft(this.conversationIdByRoute, this.effectiveReplyMode);
    },
    onFocus() {
      this.isFocused = true;
    },
    onRecordProgressChanged(duration) {
      this.recordingAudioDurationText = duration;
    },
    onFinishRecorder(file) {
      this.recordingAudioState = 'stopped';
      this.hasRecordedAudio = true;
      // Added a new key isVoiceMessage to the file to identify recorded audio
      // Because to filter and show only non recorded audio and other attachments
      const autoRecordedFile = {
        ...file,
        isVoiceMessage: true,
      };
      return file && this.onFileUpload(autoRecordedFile);
    },
    onRecordError() {
      this.toggleAudioRecorder();
      useAlert(this.$t('CONVERSATION.REPLYBOX.AUDIO_CONVERSION_FAILED'));
    },
    toggleTyping(status) {
      const conversationId = this.currentChat.id;
      const isPrivate = this.isPrivate;

      if (!conversationId) {
        return;
      }

      this.$store.dispatch('conversationTypingStatus/toggleTyping', {
        status,
        conversationId,
        isPrivate,
      });
    },
    attachFile({ blob, file }) {
      if (!this.showFileUpload && !this.isOnPrivateNote) return;

      const reader = new FileReader();
      reader.readAsDataURL(file.file);
      const chatId = this.currentChat.id;
      reader.onloadend = () => {
        this.attachedFiles.push({
          currentChatId: this.currentChat.id,
          resource: blob || file,
          isPrivate: this.isPrivate,
          thumb: reader.result,
          blobSignedId: blob ? blob.signed_id : undefined,
          isVoiceMessage: file?.isVoiceMessage || false,
          comoDocumento: file?.comoDocumento || false,
        });
        this.enviarSeForAGravacao(file, chatId);
      };
    },
    removeAttachment(attachments) {
      this.attachedFiles = attachments;
    },
    // Assunto do envio (#1143): com mais de um assunto aberto, a mensagem leva o card escolhido na caixa de resposta.
    // Aplicado em sendMessage, o ponto por onde passam texto, anexos, notas e templates.
    setCrmSubjectInPayload(payload) {
      if (!this.crmSubjectCardId) return payload;

      return {
        ...payload,
        contentAttributes: {
          ...payload.contentAttributes,
          crm_card_id: this.crmSubjectCardId,
        },
      };
    },
    setReplyToInPayload(payload) {
      if (this.inReplyTo?.id) {
        return {
          ...payload,
          contentAttributes: {
            ...payload.contentAttributes,
            in_reply_to: this.inReplyTo.id,
          },
        };
      }

      return payload;
    },
    getMultipleMessagesPayload(message) {
      const multipleMessagePayload = [];

      if (this.attachedFiles && this.attachedFiles.length) {
        let caption =
          this.isAnInstagramChannel || this.isATiktokChannel ? '' : message;
        this.attachedFiles.forEach(attachment => {
          const attachedFile = this.globalConfig.directUploadsEnabled
            ? attachment.blobSignedId
            : attachment.resource.file;
          let attachmentPayload = {
            conversationId: this.currentChat.id,
            files: [attachedFile],
            private: false,
            message: caption,
            sender: this.sender,
            isVoiceMessage: attachment.isVoiceMessage || false,
            documentIndexes: indicesDeDocumento([attachment]),
          };

          attachmentPayload = this.setReplyToInPayload(attachmentPayload);
          multipleMessagePayload.push(attachmentPayload);
          // For WhatsApp, only the first attachment gets a caption
          if (!this.isAnInstagramChannel) caption = '';
        });
      }

      const hasNoAttachments =
        !this.attachedFiles || !this.attachedFiles.length;
      // For Instagram and TikTok, text must always be sent as a separate message (no captions on attachments).
      // For WhatsApp, we only need a text message if there are no attachments.
      if (
        ((this.isAnInstagramChannel || this.isATiktokChannel) &&
          this.message) ||
        (!(this.isAnInstagramChannel || this.isATiktokChannel) &&
          hasNoAttachments)
      ) {
        let messagePayload = {
          conversationId: this.currentChat.id,
          message,
          private: false,
          sender: this.sender,
        };

        messagePayload = this.setReplyToInPayload(messagePayload);

        multipleMessagePayload.push(messagePayload);
      }

      return multipleMessagePayload;
    },
    getMessagePayload(message) {
      const messageWithQuote = this.getMessageWithQuotedEmailText(message);

      let messagePayload = {
        conversationId: this.currentChat.id,
        message: messageWithQuote,
        private: this.isPrivate,
        sender: this.sender,
      };
      messagePayload = this.setReplyToInPayload(messagePayload);

      if (this.attachedFiles && this.attachedFiles.length) {
        messagePayload.files = [];
        this.attachedFiles.forEach(attachment => {
          if (this.globalConfig.directUploadsEnabled) {
            messagePayload.files.push(attachment.blobSignedId);
            if (attachment.isVoiceMessage) {
              messagePayload.isVoiceMessage = true;
            }
          } else {
            messagePayload.files.push(attachment.resource.file);
          }
        });
      }

      const documentos = indicesDeDocumento(this.attachedFiles);
      if (documentos.length) messagePayload.documentIndexes = documentos;

      if (this.ccEmails && !this.isOnPrivateNote) {
        messagePayload.ccEmails = this.ccEmails;
      }

      if (this.bccEmails && !this.isOnPrivateNote) {
        messagePayload.bccEmails = this.bccEmails;
      }

      if (this.toEmails && !this.isOnPrivateNote) {
        messagePayload.toEmails = this.toEmails;
      }
      return this.comModeloDoEmail(this.comCitacaoDoEmail(messagePayload));
    },
    // #1786: as ações da conversa de e-mail nova montam os destinatários (e o texto do
    // encaminhado) a partir do e-mail escolhido, e o envio segue o de sempre.
    responderEmail({ modo, mensagemId, trocaDeTipo = false } = {}) {
      // A caixa acabou de aparecer: o foco vem depois de ela ser desenhada.
      const focar = () => {
        this.$nextTick(() => {
          requestAnimationFrame(() =>
            this.messageEditor?.focusEditorInputField('start')
          );
        });
      };
      // Trocar só entre nota e resposta: o Chatwoot tira os anexos nessa troca (regras
      // de envio diferentes); reabrir no mesmo modo mantém os anexos.
      if (modo === MODOS_DE_RESPOSTA.NOTA) {
        if (!this.isPrivate) this.setReplyMode(REPLY_EDITOR_MODES.NOTE);
        focar();
        return;
      }
      const mensagem =
        this.currentChat?.messages?.find(item => item.id === mensagemId) ||
        this.lastEmail;
      const resposta = montarRespostaDoEmail({
        modo,
        mensagem,
        contato: this.currentChat?.meta?.sender?.email,
        caixa: this.inbox,
      });
      this.modoDoEmail = modo;
      if (this.isPrivate) this.setReplyMode(REPLY_EDITOR_MODES.REPLY);
      this.aplicarDestinatarios(resposta, trocaDeTipo);
      // O histórico vai junto por padrão; o encaminhado mostra o original embaixo.
      // O servidor monta o HTML (ConversaCanal::CitacaoDoEmail).
      this.citacaoDoEmail = mensagem?.id
        ? {
            tipo:
              modo === MODOS_DE_RESPOSTA.ENCAMINHAR
                ? 'encaminhado'
                : 'historico',
            mensagemId: mensagem.id,
          }
        : null;
      if (!trocaDeTipo) this.historicoDesligado = false;
      focar();
    },
    // #1786: a resposta foi aberta logo depois de trocar de conversa, antes de o e-mail
    // chegar (Para e Cc saíram sem ele). Quando ele chega, monta os endereços e o
    // histórico, só enquanto a pessoa não mexeu nos endereços e a resposta é a esse
    // mesmo e-mail (ou a nenhum). Um e-mail novo do cliente no meio da resposta não troca
    // nada, e o encaminhado e a nota não têm o que completar.
    completarRespostaDoEmail(lastEmail) {
      const montados = this.destinatariosMontados;
      if (!Object.keys(montados).length || this.isPrivate) return;
      if (this.modoDoEmail === MODOS_DE_RESPOSTA.ENCAMINHAR) return;
      const citado = this.citacaoDoEmail?.mensagemId;
      if (citado && citado !== lastEmail.id) return;
      const editou = ['toEmails', 'ccEmails', 'bccEmails'].some(
        campo => (this[campo] || '') !== (montados[campo] || '')
      );
      if (editou) return;
      this.aplicarDestinatarios(
        montarRespostaDoEmail({
          modo: this.modoDoEmail,
          mensagem: lastEmail,
          contato: this.currentChat?.meta?.sender?.email,
          caixa: this.inbox,
        }),
        false
      );
      this.citacaoDoEmail = { tipo: 'historico', mensagemId: lastEmail.id };
    },
    // #1786: o menu do topo troca o tipo da MESMA resposta: continua no e-mail que
    // estava sendo respondido, e o que o atendente escreveu nos endereços fica.
    trocarTipoDoEmail(modo) {
      this.responderEmail({
        modo,
        mensagemId: this.citacaoDoEmail?.mensagemId,
        trocaDeTipo: true,
      });
    },
    // Na troca de tipo, um campo editado à mão (diferente do que foi montado) fica.
    aplicarDestinatarios(resposta, preservarEditados) {
      const novos = {
        toEmails: resposta.para,
        ccEmails: resposta.cc,
        bccEmails: resposta.cco,
      };
      const montados = this.destinatariosMontados;
      Object.entries(novos).forEach(([campo, valor]) => {
        const editado = (this[campo] || '') !== (montados[campo] || '');
        if (preservarEditados && editado) return;
        this[campo] = valor;
      });
      this.destinatariosMontados = novos;
    },
    // #1786: o estado da resposta de e-mail é da conversa: ao trocar, nada passa para a
    // outra (o modelo preenchido com os dados de um contato iria para outro).
    zerarRespostaDoEmail() {
      this.modeloDoEmail = null;
      this.valoresDoModelo = {};
      this.citacaoDoEmail = null;
      this.modoDoEmail = MODOS_DE_RESPOSTA.TODOS;
      this.historicoDesligado = false;
      this.destinatariosMontados = {};
      this.pedidoDoModelo += 1;
    },
    // #1786: pede ao servidor o histórico ou o encaminhado formatado junto da resposta.
    comCitacaoDoEmail(payload) {
      const citacao = this.citacaoDoEmail;
      if (!this.emailNovo || this.isPrivate || !citacao) return payload;
      if (citacao.tipo === 'historico' && this.historicoDesligado)
        return payload;
      return {
        ...payload,
        contentAttributes: {
          ...payload.contentAttributes,
          email_citacao: { tipo: citacao.tipo, message_id: citacao.mensagemId },
        },
      };
    },
    // #1786: o modelo escolhido no "+" chega com os campos já preenchidos pelo contato e
    // pela IA; o navegador compila o MJML sem o rodapé de descadastro.
    // Só vale a resposta do último pedido, na mesma conversa: trocar de modelo ou de
    // conversa no meio do caminho descarta a que chegar atrasada.
    async carregarModeloDeCampanha(id) {
      this.pedidoDoModelo += 1;
      const pedido = this.pedidoDoModelo;
      const conversaId = this.currentChat.id;
      const valeAinda = () =>
        pedido === this.pedidoDoModelo && this.currentChat?.id === conversaId;
      try {
        const { data } = await ModelosDeEmailAPI.abrir(id, conversaId);
        const html = await montarModelo({ mjml: data.mjml, html: data.html });
        if (!valeAinda()) return;
        if (!html) throw new Error('modelo vazio');
        this.modeloDoEmail = {
          id: data.id,
          nome: data.nome,
          html,
          campos: data.campos,
        };
        this.valoresDoModelo = Object.fromEntries(
          data.campos.map(campo => [campo.chave, campo.valor])
        );
      } catch {
        if (valeAinda())
          useAlert(this.$t('CONVERSA_CANAL.EMAIL.MODELO_FALHOU'));
      }
    },
    // #1786/#1895: a janela de emojis abre em cima da barra de baixo da caixa.
    ancoraDosEmojis() {
      return this.$refs.painelDeBaixo?.barraDosEmojis?.() || null;
    },
    atualizarCampoDoModelo(chave, valor) {
      this.valoresDoModelo = { ...this.valoresDoModelo, [chave]: valor };
    },
    tirarModeloDoEmail() {
      this.modeloDoEmail = null;
      this.valoresDoModelo = {};
    },
    // #1786: o modelo preenchido vai junto; sem texto do atendente, sai só o modelo (o
    // conteúdo da mensagem vira o texto do modelo, que o CRM e a IA leem).
    comModeloDoEmail(payload) {
      if (!this.emailNovo || this.isPrivate || !this.modeloDoEmail)
        return payload;
      const html = preencherModelo(
        this.modeloDoEmail.html,
        this.valoresDoModelo
      );
      const soModelo = !String(payload.message || '').trim();
      return {
        ...payload,
        message: soModelo ? textoDoModelo(html) : payload.message,
        contentAttributes: {
          ...payload.contentAttributes,
          email_modelo: {
            template_id: this.modeloDoEmail.id,
            html,
            so_modelo: soModelo,
          },
        },
      };
    },
    // #1786: Descartar apaga o rascunho e os anexos e fecha a caixa do e-mail novo.
    descartarEmail() {
      this.clearMessage();
      this.attachedFiles = [];
      this.removeFromDraft();
      this.fecharRespostaDoEmail();
    },
    // #1786: a resposta pronta escolhida na lista entra no ponto do cursor, com as
    // variáveis trocadas e a formatação (o mesmo caminho do "/").
    inserirModeloDoEmail(conteudo) {
      emitter.emit(
        BUS_EVENTS.INSERT_INTO_RICH_EDITOR,
        resolveVariablesInMessage(conteudo, this.messageVariables)
      );
    },
    setCcEmails(value) {
      this.bccEmails = value.bccEmails;
      this.ccEmails = value.ccEmails;
    },
    setCCAndToEmailsFromLastChat() {
      const conversationContact = this.currentChat?.meta?.sender?.email || '';
      const { email: inboxEmail, forward_to_email: forwardToEmail } =
        this.inbox;

      // #1828: quem pediu para sair da cópia desta conversa não volta no preenchimento.
      const { cc, bcc, to } = semQuemSaiuDaCopia(
        getRecipients(
          this.lastEmail,
          conversationContact,
          inboxEmail,
          forwardToEmail
        ),
        this.isFeatureEnabledonAccount(
          this.accountId,
          FEATURE_FLAGS.EMAIL_AUTORIA
        )
          ? this.currentChat?.additional_attributes?.email_saiu_da_copia
          : undefined,
        conversationContact
      );

      this.toEmails = to.join(', ');
      this.ccEmails = cc.join(', ');
      this.bccEmails = bcc.join(', ');
    },
    fetchAndSetReplyTo() {
      const replyStorageKey = LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO;
      const replyToMessageId = LocalStorage.getFromJsonStore(
        replyStorageKey,
        this.conversationId
      );

      this.inReplyTo = this.currentChat?.messages?.find(message => {
        if (message.id === replyToMessageId) {
          return true;
        }
        return false;
      });
    },
    onReplyToMessage() {
      this.fetchAndSetReplyTo();
      if (this.inReplyTo) {
        this.$nextTick(() => {
          const pos = this.isSignatureEnabledForInbox ? 'start' : 'end';
          this.messageEditor?.focusEditorInputField(pos);
        });
      }
    },
    resetReplyToMessage() {
      const replyStorageKey = LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO;
      LocalStorage.deleteFromJsonStore(replyStorageKey, this.conversationId);
      emitter.emit(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE);
    },
    onNewConversationModalActive(isActive) {
      // Issue is if the new conversation modal is open and we drag and drop the file
      // then the file is not getting attached to the new conversation modal
      // and it is getting attached to the current conversation reply box
      // so to fix this we are removing the drag and drop event listener from the current conversation reply box
      // When new conversation modal is open
      this.newConversationModalActive = isActive;
    },
    onSearchPopoverClose() {
      this.showArticleSearchPopover = false;
    },
    toggleInsertArticle() {
      this.showArticleSearchPopover = !this.showArticleSearchPopover;
    },
    resetAudioRecorderInput() {
      this.enviarAudioAoAnexar = false;
      this.recordingAudioDurationText = '00:00';
      this.isRecordingAudio = false;
      this.recordingAudioState = '';
      this.hasRecordedAudio = false;
      // Only clear the recorded audio when we click toggle button.
      this.attachedFiles = this.attachedFiles.filter(
        file => !file?.isVoiceMessage
      );
    },
    toggleEditorSize() {
      this.$emit('toggleEditorSize');
      this.$nextTick(() => this.messageEditor?.focusEditorInputField());
    },
    onSubmitCopilotReply() {
      const acceptedMessage = this.copilot.accept();
      this.message = acceptedMessage;
      this.setCopilotAcceptedMessage(acceptedMessage);
    },
  },
};
</script>

<template>
  <ReplyBoxBanner
    :message="message"
    :is-on-private-note="isOnPrivateNote"
    :ficar-ao-enviar="ficarLigadoNaConta"
  />
  <CrmRepasseDoAssunto
    v-if="crmReplySubjectEnabled"
    :conversation-id="currentChat.id"
    :assignee-id="pessoaResponsavelId"
  />
  <WhatsappApiReplyHint
    :conversation="currentChat"
    :is-on-private-note="isOnPrivateNote"
  />
  <DevolverParaIa :conversation="currentChat" />
  <div class="reply-box" :class="replyBoxClass">
    <TopoDaResposta
      v-if="emailNovo"
      :modo="modoDoTopoDoEmail"
      @trocar-modo="trocarTipoDoEmail"
    />
    <ReplyTopPanel
      v-else
      :mode="replyType"
      :conversation-id="conversationId"
      :is-reply-restricted="!canSendPublicReply"
      :disabled="
        (copilot.isActive.value && copilot.isButtonDisabled.value) ||
        showAudioRecorderEditor
      "
      :is-editor-disabled="isEditorDisabled"
      :is-message-length-reaching-threshold="isMessageLengthReachingThreshold"
      :characters-remaining="charactersRemaining"
      :editor-content="message"
      :has-content="hasMeaningfulEditorContent"
      @set-reply-mode="setReplyMode"
      @toggle-editor-size="toggleEditorSize"
      @toggle-copilot="copilot.toggleEditor"
      @execute-copilot-action="executeCopilotAction"
    />
    <!-- #2113: no Instagram, a citação numa linha própria no topo da pílula; dentro do campo, ela desalinhava o emoji. -->
    <ReplyToMessage
      v-if="shouldShowReplyToMessage && instagram"
      :message="inReplyTo"
      data-resposta-do-instagram
      @dismiss="resetReplyToMessage"
    />
    <ArticleSearchPopover
      v-if="showArticleSearchPopover && connectedPortalSlug"
      :selected-portal-slug="connectedPortalSlug"
      @insert="handleInsert"
      @close="onSearchPopoverClose"
    />
    <Transition
      mode="out-in"
      enter-active-class="transition-all duration-300 ease-out"
      enter-from-class="opacity-0 translate-y-2 scale-[0.98]"
      enter-to-class="opacity-100 translate-y-0 scale-100"
      leave-active-class="transition-all duration-200 ease-in"
      leave-from-class="opacity-100 translate-y-0 scale-100"
      leave-to-class="opacity-0 translate-y-2 scale-[0.98]"
    >
      <div
        :key="copilot.editorTransitionKey.value"
        class="reply-box__top"
        :class="classesDaResposta.campo"
      >
        <CrmReplySubject
          v-if="crmReplySubjectEnabled"
          v-model:card-id="crmSubjectCardId"
          :conversation-id="currentChat.id"
        />
        <!-- #1702: com a pele, a citação do WhatsApp em cima do campo. -->
        <CitacaoNaResposta
          v-if="shouldShowReplyToMessage && ehWhatsapp"
          :message="inReplyTo"
          @dismiss="resetReplyToMessage"
        />
        <ReplyToMessage
          v-else-if="shouldShowReplyToMessage && !instagram"
          :message="inReplyTo"
          @dismiss="resetReplyToMessage"
        />
        <!-- #1786/#1895: a janela própria em todos os canais (flutua; a caixa com rolagem cortava a do Chatwoot). -->
        <JanelaDeEmojis
          v-if="showEmojiPicker"
          :ancora="ancoraDosEmojis()"
          @escolher="addIntoEditor"
          @fechar="hideEmojiPicker"
        />
        <CabecaDaResposta
          v-if="showReplyHead && isDefaultEditorMode && emailNovo"
          v-model:cc-emails="ccEmails"
          v-model:bcc-emails="bccEmails"
          v-model:to-emails="toEmails"
          :encaminhar="encaminhandoEmail"
        />
        <ReplyEmailHead
          v-else-if="showReplyHead && isDefaultEditorMode"
          v-model:cc-emails="ccEmails"
          v-model:bcc-emails="bccEmails"
          v-model:to-emails="toEmails"
        />
        <GravadorDoWhatsapp
          v-if="
            showAudioRecorderEditor && (textoDoCampo || instagram) && !isPrivate
          "
          ref="audioRecorderInput"
          :audio-record-format="audioRecordFormat"
          :duracao="recordingAudioDurationText"
          :visual="instagram ? GRAVADOR_DO_INSTAGRAM : null"
          @recorder-progress-changed="onRecordProgressChanged"
          @finish-record="onFinishRecorder"
          @record-error="onRecordError"
          @mic-error="semMicrofone"
          @cancelar="cancelarGravacao"
          @enviar="enviarGravacao"
        />
        <AudioRecorder
          v-else-if="showAudioRecorderEditor"
          ref="audioRecorderInput"
          :audio-record-format="audioRecordFormat"
          @recorder-progress-changed="onRecordProgressChanged"
          @finish-record="onFinishRecorder"
          @record-error="onRecordError"
          @play="recordingAudioState = 'playing'"
          @pause="recordingAudioState = 'paused'"
        />
        <CopilotEditorSection
          v-if="copilot.isActive.value && !showAudioRecorderEditor"
          :show-copilot-editor="copilot.showEditor.value"
          :is-generating-content="copilot.isGenerating.value"
          :generated-content="copilot.generatedContent.value"
          :placeholder="$t('CONVERSATION.FOOTER.COPILOT_MSG_INPUT')"
          @focus="onFocus"
          @blur="onBlur"
          @clear-selection="clearEditorSelection"
          @close="copilot.showEditor.value = false"
          @content-ready="copilot.setContentReady"
          @send="copilot.sendFollowUp"
        />
        <WootMessageEditor
          v-else-if="!showAudioRecorderEditor"
          ref="messageEditor"
          v-model="message"
          :conversation-id="conversationId"
          :editor-id="editorStateId"
          class="input popover-prosemirror-menu"
          :is-private="isOnPrivateNote"
          :placeholder="messagePlaceHolder"
          :reload-on-placeholder-change="emailNovo || instagram"
          :hidden-menu-options="emailNovo ? FORA_DA_REGUA : []"
          :copilot-available="emailNovo ? iaDoEmail.disponivel.value : null"
          :update-selection-with="updateEditorSelectionWith"
          :min-height="4"
          :disabled="isEditorDisabled"
          enable-insert-events
          :enable-macros="isMacrosEnabled"
          enable-variables
          :variables="messageVariables"
          :signature="messageSignature"
          allow-signature
          :channel-type="channelType"
          :medium="inbox.medium"
          @typing-off="onTypingOff"
          @typing-on="onTypingOn"
          @focus="onFocus"
          @blur="onBlur"
          @toggle-user-mention="toggleUserMention"
          @toggle-canned-menu="toggleCannedMenu"
          @toggle-variables-menu="toggleVariablesMenu"
          @toggle-macros-menu="toggleMacrosMenu"
          @execute-macro="onExecuteMacro"
          @clear-selection="clearEditorSelection"
          @execute-copilot-action="executeCopilotAction"
        >
          <template
            v-if="emailNovo"
            #copilot-menu="{ hasContent, run, close, root }"
          >
            <MenuDaIaDoEmail
              :tem-texto="hasContent"
              :editor="root"
              tem-conversa
              @executar="run"
              @fechar="close"
            />
          </template>
        </WootMessageEditor>
        <AvisoDaSugestao
          v-if="emailNovo && iaDoEmail.avisoDasVariaveis.value"
          :texto="iaDoEmail.avisoDasVariaveis.value"
        />

        <ModeloDaResposta
          v-if="emailNovo && !isPrivate && modeloDoEmail && isDefaultEditorMode"
          :modelo="modeloDoEmail"
          :valores="valoresDoModelo"
          @campo="atualizarCampoDoModelo"
          @tirar="tirarModeloDoEmail"
        />
        <CitacaoDaResposta
          v-if="
            emailNovo &&
            !isPrivate &&
            citacaoDoEmail &&
            mensagemCitadaDoEmail &&
            isDefaultEditorMode
          "
          :mensagem="mensagemCitadaDoEmail"
          :tipo="citacaoDoEmail.tipo"
          :desligado="historicoDesligado"
          @alternar="historicoDesligado = !historicoDesligado"
        />
        <QuotedEmailPreview
          v-else-if="
            shouldShowQuotedPreview && isDefaultEditorMode && !emailNovo
          "
          :quoted-email-text="quotedEmailText"
          :preview-text="quotedEmailPreviewText"
          class="mb-2"
          @toggle="toggleQuotedReply"
        />

        <div
          v-if="hasAttachments && isDefaultEditorMode"
          class="bg-transparent py-0 mb-2"
          @paste="onPaste"
        >
          <AttachmentPreview
            class="mt-2"
            :attachments="attachedFiles"
            @remove-attachment="removeAttachment"
          />
        </div>
        <AvisoDeAssinatura
          v-if="
            emailNovo &&
            isSignatureEnabledForInbox &&
            !isSignatureAvailable &&
            isDefaultEditorMode
          "
        />
        <MessageSignatureMissingAlert
          v-else-if="
            isSignatureEnabledForInbox &&
            !isSignatureAvailable &&
            isDefaultEditorMode
          "
          class="mb-2"
        />
      </div>
    </Transition>

    <Transition
      mode="out-in"
      enter-active-class="transition-all duration-300 ease-out"
      enter-from-class="opacity-0 translate-y-2 scale-[0.98]"
      enter-to-class="opacity-100 translate-y-0 scale-100"
      leave-active-class="transition-all duration-200 ease-in"
      leave-from-class="opacity-100 translate-y-0 scale-100"
      leave-to-class="opacity-0 translate-y-2 scale-[0.98]"
    >
      <CopilotReplyBottomPanel
        v-if="copilot.isActive.value"
        key="copilot-bottom-panel"
        :is-generating-content="copilot.isButtonDisabled.value"
        @submit="onSubmitCopilotReply"
        @cancel="copilot.reset"
      />
      <ReplyBottomPanel
        v-else
        ref="painelDeBaixo"
        key="reply-bottom-panel"
        :conversation-id="conversationId"
        :enable-multiple-file-upload="enableMultipleFileUpload"
        :enable-whats-app-templates="showWhatsappTemplates"
        :enable-content-templates="showContentTemplates"
        :inbox="inbox"
        :is-on-private-note="isOnPrivateNote"
        :is-recording-audio="isRecordingAudio"
        :is-send-disabled="isReplyButtonDisabled"
        :is-note="isPrivate"
        :is-editor-disabled="isEditorDisabled"
        :on-file-upload="onFileUpload"
        :on-send="onSendReply"
        :conversation-type="conversationType"
        :recording-audio-duration-text="recordingAudioDurationText"
        :recording-audio-state="recordingAudioState"
        :send-button-text="replyButtonLabel"
        :show-audio-recorder="showAudioRecorder"
        :show-emoji-picker="showEmojiPicker"
        :show-file-upload="showFileUpload"
        :show-quoted-reply-toggle="shouldShowQuotedReplyToggle"
        :quoted-reply-enabled="quotedReplyPreference"
        :toggle-audio-recorder-play-pause="toggleAudioRecorderPlayPause"
        :toggle-audio-recorder="toggleAudioRecorder"
        :toggle-emoji-picker="toggleEmojiPicker"
        :message="message"
        :portal-slug="connectedPortalSlug"
        :new-conversation-modal-active="newConversationModalActive"
        :enviar-rico="onSendRichMessage"
        :campo-vazio="!hasMeaningfulEditorContent && !hasAttachments"
        :ficar="mostrarFicarComAConversa ? ficar : null"
        :ficar-na-conta="ficarLigadoNaConta"
        @select-whatsapp-template="openWhatsappTemplateModal"
        @select-content-template="openContentTemplateModal"
        @toggle-insert-article="toggleInsertArticle"
        @toggle-quoted-reply="toggleQuotedReply"
        @request-contact-info-template="openContactInfoTemplateModal"
      />
    </Transition>

    <WhatsappTemplates
      :inbox-id="inbox.id"
      :show="showWhatsAppTemplatesModal"
      :send-rendered-content="isAPIInbox"
      :request-contact-info-only="requestContactInfoTemplatesOnly"
      @close="hideWhatsappTemplatesModal"
      @on-send="onSendWhatsAppReply"
      @cancel="hideWhatsappTemplatesModal"
    />

    <ContentTemplates
      :inbox-id="inbox.id"
      :show="showContentTemplatesModal"
      @close="hideContentTemplatesModal"
      @on-send="onSendContentTemplateReply"
      @cancel="hideContentTemplatesModal"
    />

    <ConversationResolveAttributesModal
      ref="resolveAttributesModal"
      @submit="macroExecution.submitPendingAttributes"
      @close="macroExecution.dismissPendingAttributes"
    />

    <woot-confirm-modal
      ref="confirmDialog"
      :title="$t('CONVERSATION.REPLYBOX.UNDEFINED_VARIABLES.TITLE')"
      :description="undefinedVariableMessage"
    />
  </div>
</template>

<style lang="scss" scoped>
.send-button {
  @apply mb-0;
}

.reply-box {
  @apply relative mb-2 mx-2 border border-n-weak rounded-xl bg-n-solid-1;

  &.is-private {
    @apply bg-n-solid-amber dark:border-n-amber-3/10 border-n-amber-12/5;
  }
}

.send-button {
  @apply mb-0;
}

.reply-box__top {
  @apply relative py-0 px-3 -mt-px;
}
</style>
