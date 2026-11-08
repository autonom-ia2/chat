<script setup>
import { computed, reactive } from 'vue';
import Message from './Message.vue';
import { MESSAGE_TYPES } from './constants.js';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useMapGetter } from 'dashboard/composables/store.js';
import MessageApi from 'dashboard/api/inbox/message.js';
import SeparadorDeDia from '../conversa-canal/SeparadorDeDia.vue';
import BotoesDoModelo from '../conversa-canal/BotoesDoModelo.vue';
import BotaoDeDescer from '../conversa-canal/BotaoDeDescer.vue';
import { useSequenciaDaConversa } from '../conversa-canal/useSequenciaDaConversa';
import { useAlbunsDaConversa } from '../conversa-canal/album/useAlbuns';
import {
  paraOBalao,
  temMarcaDoWaha,
} from '../conversa-canal/album/albumDoWaha';
import { usePele } from '../conversa-canal/pele';
import TopoDoEmail from '../conversa-canal/email/TopoDoEmail.vue';
import AcoesDoEmail from '../conversa-canal/email/AcoesDoEmail.vue';
import { useEmailDaConversa } from '../conversa-canal/email/useConversaDeEmail';
import {
  useInstagramDaConversa,
  fornecerSequencia,
} from '../conversa-canal/instagram/useConversaDoInstagram';
import {
  mensagensDoInstagram,
  sequenciaDoInstagram,
  vistoDaConversa,
} from '../conversa-canal/instagram/sequenciaDoInstagram';
import HorarioDoInstagram from '../conversa-canal/instagram/HorarioDoInstagram.vue';
import VistoDoInstagram from '../conversa-canal/instagram/VistoDoInstagram.vue';
import {
  ocultaNaPele,
  primeiraNaoLidaVisivel,
} from '../conversa-canal/marcasDaMensagem';

/**
 * Props definition for the component
 * @typedef {Object} Props
 * @property {Array} readMessages - Array of read messages
 * @property {Array} unReadMessages - Array of unread messages
 * @property {Number} currentUserId - ID of the current user
 * @property {Boolean} isAnEmailChannel - Whether this is an email channel
 * @property {Object} inboxSupportsReplyTo - Inbox reply support configuration
 * @property {Array} messages - Array of all messages [These are not in camelcase]
 */
const props = defineProps({
  currentUserId: {
    type: Number,
    required: true,
  },
  firstUnreadId: {
    type: Number,
    default: null,
  },
  isAnEmailChannel: {
    type: Boolean,
    default: false,
  },
  inboxSupportsReplyTo: {
    type: Object,
    default: () => ({ incoming: false, outgoing: false }),
  },
  messages: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['retry']);

// fork chat#1709 (fase 3): o registro escondido de reação, edição, voto retirado e toque de ligação (atividade com
// `c2y_hidden`) não aparece na conversa; a mudança já está na mensagem a que ele se refere. Também se esconde a
// mensagem RECEBIDA com a chave: o voto na enquete e a resposta ao convite (turno do cliente para a IA; o voto aparece
// agregado na enquete) e o aviso de visualização única trocado pela mídia. Mensagem nossa (saída) nunca se esconde. O
// servidor só grava a chave nesses casos (a API não a forja).
const HIDDEN_TYPES = [MESSAGE_TYPES.ACTIVITY, MESSAGE_TYPES.INCOMING];
const isHidden = message =>
  HIDDEN_TYPES.includes(message.message_type) &&
  message.content_attributes?.c2y_hidden === true;

// #1702: com a pele, mensagem absorvida pela apresentação nova (c2y_hidden, reação
// que o agente da Autonomia leu) também sai da lista antes de tudo, para não quebrar
// sequência, dia nem álbum. O isHidden (#1709) vale sempre; o ocultaNaPele soma por cima.
// Exceção, só com a pele: o marcador de álbum do WAHA (`waha_album`, escondido) passa,
// porque é ele que junta as fotos no álbum (useAlbunsDaConversa); a pele o esconde ao
// desenhar. Sem a pele, ele some como as outras escondidas. #1831: o marcador entra como
// balão do contato (sequência, álbum e tela), pelo paraOBalao.
const peleDaLista = usePele();
const currentChat = useMapGetter('getSelectedChat');
const contatoDaConversa = computed(() => currentChat.value?.meta?.sender);
const temAlbumDoWaha = atributos => {
  const album = atributos?.waha_album ?? atributos?.wahaAlbum;
  return Boolean(album) && typeof album === 'object';
};
// #1786: assunto no topo e Responder / Responder a todos / Encaminhar no fim.
const emailNovo = useEmailDaConversa().ligado;
// #2079/#2113: conversa do Instagram com a cara do Direct (sem a pele do WhatsApp).
const instagram = useInstagramDaConversa().ligado;
const allMessages = computed(() => {
  const comPele = Boolean(peleDaLista.value);
  const passa = message =>
    !isHidden(message) ||
    (comPele && temAlbumDoWaha(message.content_attributes));
  const mensagens = useCamelCase(props.messages.filter(passa), {
    deep: true,
    stopPaths: [
      'content_attributes.translations',
      'content_attributes.whatsapp_flow_response.response_json',
    ],
  });
  if (instagram.value) return mensagensDoInstagram(mensagens);
  if (!comPele) return mensagens;
  return mensagens
    .filter(mensagem => !ocultaNaPele(mensagem) || temMarcaDoWaha(mensagem))
    .map(mensagem => paraOBalao(mensagem, contatoDaConversa.value));
});

// #1786: na conversa de e-mail nova o mais recente fica no topo (Rodrigo, 18/10).
const mensagensNaOrdem = computed(() =>
  emailNovo.value ? [...allMessages.value].reverse() : allMessages.value
);

// A faixa de não lidas não pode sumir quando a 1ª não lida é uma das escondidas:
// desce para a próxima que aparece.
const naoLidaDaLista = computed(() =>
  primeiraNaoLidaVisivel(props.messages, allMessages.value, props.firstUnreadId)
);

// Cache for fetched reply messages to avoid duplicate API calls
const fetchedReplyMessages = reactive(new Map());

/**
 * Fetches a specific message from the API by trying to get messages around it
 * @param {number} messageId - The ID of the message to fetch
 * @param {number} conversationId - The ID of the conversation
 * @returns {Promise<Object|null>} - The fetched message or null if not found/error
 */
const fetchReplyMessage = async (messageId, conversationId) => {
  // Return cached result if already fetched
  if (fetchedReplyMessages.has(messageId)) {
    return fetchedReplyMessages.get(messageId);
  }

  try {
    const response = await MessageApi.getPreviousMessages({
      conversationId,
      before: messageId + 100,
      after: messageId - 100,
    });

    const messages = response.data?.payload || [];
    const targetMessage = messages.find(msg => msg.id === messageId);

    if (targetMessage) {
      const camelCaseMessage = useCamelCase(targetMessage);
      fetchedReplyMessages.set(messageId, camelCaseMessage);
      return camelCaseMessage;
    }

    // Cache null result to avoid repeated API calls
    fetchedReplyMessages.set(messageId, null);
    return null;
  } catch (error) {
    fetchedReplyMessages.set(messageId, null);
    return null;
  }
};

/**
 * Determines if a message should be grouped with the next message
 * @param {Number} index - Index of the current message
 * @param {Array} searchList - Array of messages to check
 * @returns {Boolean} - Whether the message should be grouped with next
 */
const shouldGroupWithNext = (index, searchList) => {
  if (index === searchList.length - 1) return false;

  const current = searchList[index];
  const next = searchList[index + 1];

  if (next.status === 'failed') return false;

  const nextSenderId = next.senderId ?? next.sender?.id;
  const currentSenderId = current.senderId ?? current.sender?.id;
  const hasSameSender = nextSenderId === currentSenderId;

  const nextMessageType = next.messageType;
  const currentMessageType = current.messageType;

  const areBothTemplates =
    nextMessageType === MESSAGE_TYPES.TEMPLATE &&
    currentMessageType === MESSAGE_TYPES.TEMPLATE;

  if (!hasSameSender || areBothTemplates) return false;

  if (currentMessageType !== nextMessageType) return false;

  // Check if messages are in the same minute by rounding down to nearest minute
  return Math.floor(next.createdAt / 60) === Math.floor(current.createdAt / 60);
};

// #2079: na conversa do Instagram, horário entre os blocos, grupos e o "Visto".
const sequenciaInstagram = computed(() =>
  instagram.value ? sequenciaDoInstagram(allMessages.value) : new Map()
);
fornecerSequencia(sequenciaInstagram);
const vistoInstagram = computed(() =>
  instagram.value ? vistoDaConversa(allMessages.value) : null
);
const horarioInstagram = id =>
  Boolean(sequenciaInstagram.value.get(id)?.horario);

// #1702: com a pele do canal, bico no 1º balão da sequência e etiqueta do dia.
const { abreODia, pele } = useSequenciaDaConversa(allMessages);
// #1702: fotos e vídeos mandados juntos aparecem no mosaico do 1º item.
const { escondida } = useAlbunsDaConversa(allMessages, naoLidaDaLista);

/**
 * Gets the message that was replied to
 * @param {Object} parentMessage - The message containing the reply reference
 * @returns {Object|null} - The message being replied to, or null if not found
 */
const getInReplyToMessage = parentMessage => {
  if (!parentMessage) return null;

  const inReplyToMessageId =
    parentMessage.contentAttributes?.inReplyTo ??
    parentMessage.content_attributes?.in_reply_to;

  if (!inReplyToMessageId) return null;

  // Try to find in current messages first
  let replyMessage = props.messages?.find(msg => msg.id === inReplyToMessageId);

  // Then try store messages
  if (!replyMessage && currentChat.value?.messages) {
    replyMessage = currentChat.value.messages.find(
      msg => msg.id === inReplyToMessageId
    );
  }

  // Then check fetch cache
  if (!replyMessage && fetchedReplyMessages.has(inReplyToMessageId)) {
    replyMessage = fetchedReplyMessages.get(inReplyToMessageId);
  }

  // If still not found and we have conversation context, fetch it
  if (!replyMessage && currentChat.value?.id) {
    fetchReplyMessage(inReplyToMessageId, currentChat.value.id);
    return null; // Let UI handle loading state
  }

  return replyMessage ? useCamelCase(replyMessage) : null;
};
</script>

<template>
  <ul class="px-4 bg-n-surface-1">
    <slot name="beforeAll" />
    <TopoDoEmail v-if="emailNovo" :mensagens="mensagensNaOrdem" />
    <template v-for="(message, index) in mensagensNaOrdem" :key="message.id">
      <HorarioDoInstagram
        v-if="instagram && horarioInstagram(message.id)"
        :quando="message.createdAt"
      />
      <SeparadorDeDia v-else-if="abreODia(index)" :quando="message.createdAt" />
      <!-- #1786: com o mais recente no topo, a faixa "não lida" cairia no lugar errado. -->
      <slot
        v-if="naoLidaDaLista && message.id === naoLidaDaLista && !emailNovo"
        name="unreadBadge"
      />
      <Message
        v-if="!escondida(message.id)"
        v-bind="message"
        :is-email-inbox="isAnEmailChannel"
        :in-reply-to="getInReplyToMessage(message)"
        :group-with-next="shouldGroupWithNext(index, mensagensNaOrdem)"
        :inbox-supports-reply-to="inboxSupportsReplyTo"
        :current-user-id="currentUserId"
        data-clarity-mask="True"
        @retry="emit('retry', message)"
      />
      <BotoesDoModelo v-if="pele" parte="carrossel" :message="message" />
      <VistoDoInstagram v-if="instagram && message.id === vistoInstagram" />
    </template>
    <AcoesDoEmail v-if="emailNovo && allMessages.length" />
    <slot name="after" />
    <BotaoDeDescer
      v-if="pele"
      :mensagens="allMessages"
      :primeira-nao-lida="naoLidaDaLista"
    />
  </ul>
</template>
