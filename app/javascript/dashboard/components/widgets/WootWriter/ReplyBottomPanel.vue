<script>
import { ref } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import FileUpload from 'vue-upload-component';
import * as ActiveStorage from 'activestorage';
import inboxMixin from 'shared/mixins/inboxMixin';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { getAllowedFileTypesByChannel } from '@chatwoot/utils';
import VideoCallButton from '../VideoCallButton.vue';
import RequestContactInfoButton from '../RequestContactInfoButton.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { mapGetters } from 'vuex';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MaisDoWhatsapp from 'dashboard/components-next/conversa-canal/mais/MaisDoWhatsapp.vue';
import BotoesDoEmail from 'dashboard/components-next/conversa-canal/email/BotoesDoEmail.vue';
import BotaoDeAudio from 'dashboard/components-next/conversa-canal/email/BotaoDeAudio.vue';
import MaisDoEmail from 'dashboard/components-next/conversa-canal/email/MaisDoEmail.vue';
import FicarComAConversa from 'dashboard/components-next/conversa-canal/atribuir/FicarComAConversa.vue';
import { useEmailDaConversa } from 'dashboard/components-next/conversa-canal/email/useConversaDeEmail';
import {
  anexarArquivos,
  usePeleDaResposta,
} from 'dashboard/components-next/conversa-canal/usePeleDaResposta';

export default {
  name: 'ReplyBottomPanel',
  components: {
    MaisDoWhatsapp,
    BotoesDoEmail,
    BotaoDeAudio,
    MaisDoEmail,
    FicarComAConversa,
    NextButton,
    FileUpload,
    VideoCallButton,
    RequestContactInfoButton,
  },
  mixins: [inboxMixin],
  props: {
    isNote: {
      type: Boolean,
      default: false,
    },
    onSend: {
      type: Function,
      default: () => {},
    },
    // #1702: envio do "+" do WhatsApp; devolve a promessa para a janela esperar.
    enviarRico: {
      type: Function,
      default: () => Promise.resolve(),
    },
    // #1702: sem texto de verdade (a assinatura não conta) e sem anexo, a direita é o microfone.
    campoVazio: {
      type: Boolean,
      default: false,
    },
    sendButtonText: {
      type: String,
      default: '',
    },
    recordingAudioDurationText: {
      type: String,
      default: '00:00',
    },
    // inbox prop is used in /mixins/inboxMixin,
    // remove this props when refactoring to composable if not needed
    // eslint-disable-next-line vue/no-unused-properties
    inbox: {
      type: Object,
      default: () => ({}),
    },
    showFileUpload: {
      type: Boolean,
      default: false,
    },
    showAudioRecorder: {
      type: Boolean,
      default: false,
    },
    onFileUpload: {
      type: Function,
      default: () => {},
    },
    toggleEmojiPicker: {
      type: Function,
      default: () => {},
    },
    toggleAudioRecorder: {
      type: Function,
      default: () => {},
    },
    toggleAudioRecorderPlayPause: {
      type: Function,
      default: () => {},
    },
    isRecordingAudio: {
      type: Boolean,
      default: false,
    },
    recordingAudioState: {
      type: String,
      default: '',
    },
    isSendDisabled: {
      type: Boolean,
      default: false,
    },
    // #2067: o ícone "ficar com a conversa ao enviar" (null quando não se aplica: a conversa
    // já é minha, ou é nota privada).
    ficar: {
      type: Object,
      default: null,
    },
    // #2067: a flag da conta; desligada, a barra fica como na main.
    ficarNaConta: {
      type: Boolean,
      default: false,
    },
    isOnPrivateNote: {
      type: Boolean,
      default: false,
    },
    enableMultipleFileUpload: {
      type: Boolean,
      default: true,
    },
    enableWhatsAppTemplates: {
      type: Boolean,
      default: false,
    },
    enableContentTemplates: {
      type: Boolean,
      default: false,
    },
    conversationId: {
      type: Number,
      required: true,
    },
    // eslint-disable-next-line vue/no-unused-properties
    message: {
      type: String,
      default: '',
    },
    newConversationModalActive: {
      type: Boolean,
      default: false,
    },
    portalSlug: {
      type: String,
      required: true,
    },
    conversationType: {
      type: String,
      default: '',
    },
    showQuotedReplyToggle: {
      type: Boolean,
      default: false,
    },
    quotedReplyEnabled: {
      type: Boolean,
      default: false,
    },
    isEditorDisabled: {
      type: Boolean,
      default: false,
    },
    // #2211: a conversa vazia da busca (ainda sem conversa): o "+" só anexa e sem vídeo.
    semConversa: {
      type: Boolean,
      default: false,
    },
  },
  emits: [
    'toggleInsertArticle',
    'selectWhatsappTemplate',
    'selectContentTemplate',
    'toggleQuotedReply',
    'requestContactInfoTemplate',
  ],
  setup(props) {
    const { setSignatureFlagForInbox, fetchSignatureFlagFromUISettings } =
      useUISettings();

    const uploadRef = ref(false);

    const keyboardEvents = {
      '$mod+Alt+KeyA': {
        action: () => {
          // Skip if editor is disabled (e.g., WhatsApp 24-hour window expired)
          if (props.isEditorDisabled) return;

          // TODO: This is really hacky, we need to replace the file picker component with
          // a custom one, where the logic and the component markup is isolated.
          // Once we have the custom component, we can remove the hacky logic below.

          const uploadTriggerButton = document.querySelector(
            '#conversationAttachment'
          );
          if (uploadTriggerButton) uploadTriggerButton.click();
        },
        allowOnFocusedInput: true,
      },
    };

    useKeyboardEvents(keyboardEvents);
    // #1702: "+" e Enviar verde na conversa com a cara do WhatsApp.
    // #2079: na conversa do Instagram, a pílula do Direct e o Enviar com o aviãozinho.
    const { ehWhatsapp, ehInstagram, soTexto, classesDaResposta } =
      usePeleDaResposta();
    // #1786: Aa, Modelos e Descartar na resposta da conversa de e-mail nova.
    const emailNovo = useEmailDaConversa().ligado;

    return {
      ehWhatsapp,
      ehInstagram,
      emailNovo,
      soTexto,
      classesDaResposta,
      anexarArquivos,
      setSignatureFlagForInbox,
      fetchSignatureFlagFromUISettings,
      uploadRef,
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      uiFlags: 'integrations/getUIFlags',
    }),
    // #1702: com o campo vazio, o botão redondo da direita é o microfone (como no app).
    // No número reserva (fora das 24 h) áudio não vai: fica o Enviar.
    microfoneNaDireita() {
      return (
        this.ehWhatsapp &&
        !this.isNote &&
        !this.isEditorDisabled &&
        !this.soTexto &&
        this.showAudioRecorderButton &&
        this.campoVazio
      );
    },
    // #2079: no Instagram, o Enviar é o aviãozinho do Direct (a nota segue com o texto).
    enviarComIcone() {
      return this.ehWhatsapp || (this.ehInstagram && !this.isNote);
    },
    wrapClass() {
      return {
        'is-note-mode': this.isNote,
      };
    },
    showAttachButton() {
      if (this.isEditorDisabled) return false;
      return this.showFileUpload || this.isNote;
    },
    showAudioRecorderButton() {
      if (this.isEditorDisabled) return false;
      if (this.isALineChannel || this.isATiktokChannel) {
        return false;
      }
      // Disable audio recorder for safari browser as recording is not supported
      // const isSafari = /^((?!chrome|android|crios|fxios).)*safari/i.test(
      //   navigator.userAgent
      // );

      return (
        this.isFeatureEnabledonAccount(
          this.accountId,
          FEATURE_FLAGS.VOICE_RECORDER
        ) && this.showAudioRecorder
        // !isSafari
      );
    },
    showAudioPlayStopButton() {
      if (this.isEditorDisabled) return false;
      return this.showAudioRecorder && this.isRecordingAudio;
    },
    isInstagramDM() {
      return this.conversationType === 'instagram_direct_message';
    },
    allowedFileTypes() {
      if (this.isOnPrivateNote) {
        return getAllowedFileTypesByChannel();
      }

      let channelType = this.channelType || this.inbox?.channel_type;
      if (this.isAnInstagramChannel || this.isInstagramDM) {
        channelType = INBOX_TYPES.INSTAGRAM;
      }

      return getAllowedFileTypesByChannel({
        channelType,
        medium: this.inbox?.medium,
      });
    },
    enableDragAndDrop() {
      return !this.newConversationModalActive;
    },
    audioRecorderPlayStopIcon() {
      switch (this.recordingAudioState) {
        // playing paused recording stopped inactive destroyed
        case 'playing':
          return 'i-ph-pause';
        case 'paused':
          return 'i-ph-play';
        case 'stopped':
          return 'i-ph-play';
        default:
          return 'i-ph-stop';
      }
    },
    showMessageSignatureButton() {
      if (this.isEditorDisabled) return false;
      return !this.isOnPrivateNote;
    },
    sendWithSignature() {
      // channelType is sourced from inboxMixin
      return this.fetchSignatureFlagFromUISettings(this.channelType);
    },
    signatureToggleTooltip() {
      return this.sendWithSignature
        ? this.$t('CONVERSATION.FOOTER.DISABLE_SIGN_TOOLTIP')
        : this.$t('CONVERSATION.FOOTER.ENABLE_SIGN_TOOLTIP');
    },
    enableInsertArticleInReply() {
      return this.portalSlug;
    },
    isFetchingAppIntegrations() {
      return this.uiFlags.isFetching;
    },
    quotedReplyToggleTooltip() {
      return this.quotedReplyEnabled
        ? this.$t('CONVERSATION.REPLYBOX.QUOTED_REPLY.DISABLE_TOOLTIP')
        : this.$t('CONVERSATION.REPLYBOX.QUOTED_REPLY.ENABLE_TOOLTIP');
    },
  },
  mounted() {
    ActiveStorage.start();
  },
  methods: {
    // #1895: o ReplyBox ancora a janela de emojis na barra que tem o botão do rosto.
    // #2079: no Instagram essa barra não tem caixa própria (display: contents); a âncora
    // é a pílula inteira.
    barraDosEmojis() {
      const barra = this.$refs.barraDaEsquerda;
      return this.ehInstagram ? barra?.closest('.reply-box') || barra : barra;
    },
    toggleMessageSignature() {
      this.setSignatureFlagForInbox(this.channelType, !this.sendWithSignature);
    },
    toggleInsertArticle() {
      this.$emit('toggleInsertArticle');
    },
  },
};
</script>

<template>
  <div
    class="flex justify-between p-3"
    :class="[wrapClass, classesDaResposta.painel]"
    :data-com-texto="!campoVazio || undefined"
  >
    <div ref="barraDaEsquerda" class="left-wrap">
      <BotoesDoEmail v-if="emailNovo && !isNote" parte="esquerda" />
      <MaisDoEmail
        v-if="emailNovo && showAttachButton"
        @arquivos="escolha => anexarArquivos(escolha, onFileUpload)"
      />
      <MaisDoWhatsapp
        v-if="ehWhatsapp && !isOnPrivateNote && !isEditorDisabled"
        :caixa="inbox"
        :enviar="enviarRico"
        :so-arquivos="semConversa"
        @arquivos="escolha => anexarArquivos(escolha, onFileUpload)"
      />
      <NextButton
        v-if="!isEditorDisabled"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_EMOJI_ICON')"
        icon="i-ph-smiley-sticker"
        slate
        faded
        sm
        data-emoji-da-resposta
        @click="toggleEmojiPicker"
      />
      <FileUpload
        v-if="showAttachButton"
        ref="uploadRef"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_ATTACH_ICON')"
        input-id="conversationAttachment"
        :size="4096 * 4096"
        :accept="allowedFileTypes"
        :multiple="enableMultipleFileUpload"
        :drop="enableDragAndDrop"
        :drop-directory="false"
        :data="{
          direct_upload_url: '/rails/active_storage/direct_uploads',
          direct_upload: true,
        }"
        @input-file="onFileUpload"
      >
        <!-- #1786: no e-mail novo o "+" substitui o clipe; o campo fica para arrastar. -->
        <NextButton
          v-if="showAttachButton"
          v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_ATTACH_ICON')"
          :class="{ '!hidden': emailNovo }"
          :icon="ehInstagram ? 'i-woot-midia-do-instagram' : 'i-ph-paperclip'"
          slate
          faded
          sm
        />
      </FileUpload>
      <BotaoDeAudio v-if="emailNovo && !isNote && !isEditorDisabled" />
      <NextButton
        v-if="showAudioRecorderButton && !emailNovo"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
        :icon="!isRecordingAudio ? 'i-ph-microphone' : 'i-ph-microphone-slash'"
        slate
        faded
        sm
        @click="toggleAudioRecorder"
      />
      <NextButton
        v-if="showAudioPlayStopButton"
        :icon="audioRecorderPlayStopIcon"
        slate
        faded
        sm
        :label="recordingAudioDurationText"
        @click="toggleAudioRecorderPlayPause"
      />
      <NextButton
        v-if="showMessageSignatureButton"
        v-tooltip.top-end="signatureToggleTooltip"
        :data-ligado="(emailNovo && sendWithSignature) || undefined"
        icon="i-ph-signature"
        slate
        faded
        sm
        @click="toggleMessageSignature"
      />
      <NextButton
        v-if="showQuotedReplyToggle"
        v-tooltip.top-end="quotedReplyToggleTooltip"
        icon="i-ph-quotes"
        :variant="quotedReplyEnabled ? 'solid' : 'faded'"
        color="slate"
        sm
        :aria-pressed="quotedReplyEnabled"
        @click="$emit('toggleQuotedReply')"
      />
      <NextButton
        v-if="enableWhatsAppTemplates"
        v-tooltip.top-end="$t('CONVERSATION.FOOTER.WHATSAPP_TEMPLATES')"
        icon="i-ph-whatsapp-logo"
        slate
        faded
        sm
        @click="$emit('selectWhatsappTemplate')"
      />
      <RequestContactInfoButton
        v-if="!isOnPrivateNote"
        @request-template="$emit('requestContactInfoTemplate')"
      />
      <NextButton
        v-if="enableContentTemplates"
        v-tooltip.top-end="'Content Templates'"
        icon="i-ph-whatsapp-logo"
        slate
        faded
        sm
        @click="$emit('selectContentTemplate')"
      />
      <VideoCallButton
        v-if="
          (isAWebWidgetInbox || isAPIInbox) &&
          !isOnPrivateNote &&
          !semConversa &&
          !isEditorDisabled
        "
        :conversation-id="conversationId"
      />
      <transition name="modal-fade">
        <div
          v-show="uploadRef && uploadRef.dropActive"
          class="flex fixed top-0 right-0 bottom-0 left-0 z-20 flex-col gap-2 justify-center items-center w-full h-full text-n-slate-12 bg-modal-backdrop-light dark:bg-modal-backdrop-dark"
        >
          <fluent-icon icon="cloud-backup" size="40" />
          <h4 class="text-2xl break-words text-n-slate-12">
            {{ $t('CONVERSATION.REPLYBOX.DRAG_DROP') }}
          </h4>
        </div>
      </transition>
      <NextButton
        v-if="enableInsertArticleInReply"
        v-tooltip.top-end="$t('HELP_CENTER.ARTICLE_SEARCH.OPEN_ARTICLE_SEARCH')"
        icon="i-ph-article-ny-times"
        slate
        faded
        sm
        @click="toggleInsertArticle"
      />
    </div>
    <div class="right-wrap" :class="{ 'items-center gap-1': ficarNaConta }">
      <BotoesDoEmail v-if="emailNovo" parte="direita" />
      <FicarComAConversa v-if="ficar" :ficar="ficar" />
      <button
        v-if="microfoneNaDireita"
        type="button"
        :class="classesDaResposta.microfone"
        :aria-label="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
        :title="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
        data-microfone-do-whatsapp
        @click="toggleAudioRecorder"
      >
        <span class="i-ph-microphone size-6" />
      </button>
      <NextButton
        v-else
        v-tooltip.top-end="enviarComIcone ? sendButtonText : null"
        :label="enviarComIcone ? '' : sendButtonText"
        :icon="
          enviarComIcone
            ? classesDaResposta.iconeEnviar
            : emailNovo && !isNote
              ? 'i-lucide-send-horizontal'
              : ''
        "
        :trailing-icon="emailNovo && !isNote"
        :aria-label="sendButtonText"
        type="submit"
        sm
        :color="isNote ? 'amber' : 'blue'"
        :disabled="isSendDisabled"
        class="flex-shrink-0"
        :class="
          isNote ? classesDaResposta.enviarNota : classesDaResposta.enviar
        "
        @click="onSend"
      />
    </div>
  </div>
</template>

<style lang="scss" scoped>
.left-wrap {
  @apply items-center flex gap-2;
}

.right-wrap {
  @apply flex;
}

:deep(.file-uploads) {
  label {
    @apply cursor-pointer;
  }

  &:hover button {
    @apply enabled:bg-n-slate-9/20;
  }
}
</style>
