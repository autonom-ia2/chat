<script>
import { MESSAGE_TYPE } from 'widget/helpers/constants';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { ATTACHMENT_ICONS } from 'shared/constants/messages';
import { ultimaEFigurinha } from 'dashboard/components-next/conversa-canal/figurinha';
import { ultimaEVisualizacaoUnica } from 'dashboard/components-next/conversa-canal/visualizacaoUnica';
import { usePeleDaMensagem } from 'dashboard/components-next/conversa-canal/usePeleDaConversa';
import { useNotaDoConector } from 'dashboard/components-next/conversa-canal/useNotaDoConector';
import { textoDaMensagem } from 'dashboard/components-next/conversa-canal/ecoDoCelular';

export default {
  name: 'MessagePreview',
  props: {
    message: {
      type: Object,
      required: true,
    },
    showMessageType: {
      type: Boolean,
      default: true,
    },
    defaultEmptyMessage: {
      type: String,
      default: '',
    },
    // #2202: dentro de um <button> (card da lista nova) a prévia precisa ser `span`.
    tag: {
      type: String,
      default: 'div',
    },
  },
  setup(props) {
    const { getPlainText } = useMessageFormatter();
    // #1702: os rótulos do WhatsApp só com a pele; sem ela, a prévia de sempre.
    const pele = usePeleDaMensagem(() => props.message);
    // #1941: a nota técnica antiga do conector WAHA aparece como aviso, com o texto curto.
    const notaDoConector = useNotaDoConector(() => props.message);
    return {
      getPlainText,
      pele,
      notaDoConector,
    };
  },
  computed: {
    messageByAgent() {
      const { message_type: messageType } = this.message;
      return !this.notaDoConector && messageType === MESSAGE_TYPE.OUTGOING;
    },
    isMessageAnActivity() {
      const { message_type: messageType } = this.message;
      return this.notaDoConector || messageType === MESSAGE_TYPE.ACTIVITY;
    },
    isMessagePrivate() {
      const { private: isPrivate } = this.message;
      return !this.notaDoConector && isPrivate;
    },
    // #1941: mandada pelo celular, sem o prefixo do conector WAHA. Sem a marca, o texto de sempre.
    textoDaPrevia() {
      return textoDaMensagem(
        this.message.content,
        this.message.content_attributes
      );
    },
    parsedLastMessage() {
      const { content_attributes: contentAttributes } = this.message;
      const { email: { subject } = {} } = contentAttributes || {};
      return this.getPlainText(subject || this.textoDaPrevia);
    },
    lastMessageFileType() {
      const [{ file_type: fileType } = {}] = this.message.attachments;
      return fileType;
    },
    attachmentIcon() {
      return ATTACHMENT_ICONS[this.lastMessageFileType];
    },
    attachmentMessageContent() {
      // #1702: figurinha do WhatsApp aparece como "Figurinha", não como foto.
      if (this.pele && ultimaEFigurinha(this.message)) {
        return 'CONVERSA_CANAL.MIDIA.FIGURINHA';
      }
      // #1702: visualização única aparece assim na lista, como no WhatsApp.
      if (this.pele && ultimaEVisualizacaoUnica(this.message)) {
        return 'CONVERSA_CANAL.VISUALIZACAO_UNICA.ROTULO';
      }
      return `CHAT_LIST.ATTACHMENTS.${this.lastMessageFileType}.CONTENT`;
    },
    isMessageSticker() {
      return this.message && this.message.content_type === 'sticker';
    },
  },
};
</script>

<template>
  <component :is="tag" class="overflow-hidden text-ellipsis whitespace-nowrap">
    <template v-if="showMessageType">
      <fluent-icon
        v-if="isMessagePrivate"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="lock-closed"
      />
      <fluent-icon
        v-else-if="messageByAgent"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="arrow-reply"
      />
      <fluent-icon
        v-else-if="isMessageAnActivity"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="info"
      />
    </template>
    <span v-if="message.content && isMessageSticker">
      <fluent-icon
        size="16"
        class="-mt-0.5 align-middle inline-block text-n-slate-11"
        icon="image"
      />
      {{ $t('CHAT_LIST.ATTACHMENTS.image.CONTENT') }}
    </span>
    <span v-else-if="notaDoConector">
      {{ $t('CONVERSA_CANAL.NOTA_DO_CONECTOR.AVISO') }}
    </span>
    <span v-else-if="textoDaPrevia">
      {{ parsedLastMessage }}
    </span>
    <span v-else-if="message.attachments">
      <fluent-icon
        v-if="attachmentIcon && showMessageType"
        size="16"
        class="-mt-0.5 align-middle inline-block text-n-slate-11"
        :icon="attachmentIcon"
      />
      {{ $t(`${attachmentMessageContent}`) }}
    </span>
    <span v-else>
      {{ defaultEmptyMessage || $t('CHAT_LIST.NO_CONTENT') }}
    </span>
  </component>
</template>
