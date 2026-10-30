<script setup>
import { onMounted, computed, ref, toRefs } from 'vue';
import { useTimeoutFn } from '@vueuse/core';
import { provideMessageContext } from './provider.js';
import { useTrack } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { emitter } from 'shared/helpers/mitt';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { LocalStorage } from 'shared/helpers/localStorage';
import { ACCOUNT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { getInboxIconByType, tipoDoIconeDaCaixa } from 'dashboard/helper/inbox';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  MESSAGE_TYPES,
  ATTACHMENT_TYPES,
  MESSAGE_VARIANTS,
  SENDER_TYPES,
  ORIENTATION,
  MESSAGE_STATUS,
  CONTENT_TYPES,
} from './constants';

import Avatar from 'next/avatar/Avatar.vue';

import TextBubble from './bubbles/Text/Index.vue';
import ActivityBubble from './bubbles/Activity.vue';
import ImageBubble from './bubbles/Image.vue';
import FileBubble from './bubbles/File.vue';
import AudioBubble from './bubbles/Audio.vue';
import VideoBubble from './bubbles/Video.vue';
import EmbedBubble from './bubbles/Embed.vue';
import FallbackBubble from './bubbles/Fallback.vue';
import InstagramStoryBubble from './bubbles/InstagramStory.vue';
import EmailBubble from './bubbles/Email/Index.vue';
import UnsupportedBubble from './bubbles/Unsupported.vue';
import ContactBubble from './bubbles/Contact.vue';
import DyteBubble from './bubbles/Dyte.vue';
import LocationBubble from './bubbles/Location.vue';
import CSATBubble from './bubbles/CSAT.vue';
import FormBubble from './bubbles/Form.vue';
import VoiceCallBubble from './bubbles/VoiceCall.vue';
import WhatsappFlowResponseBubble from './bubbles/WhatsappFlowResponse.vue';
import WhatsappReferral from './bubbles/Text/WhatsappReferral.vue';
import { richMessageBubbleFor } from './bubbles/RichMessage/registry.js';
import CampaignMessageLabel from 'dashboard/components-next/CampaignJourney/CampaignMessageLabel.vue';
import { campaignRefFor } from 'dashboard/components-next/CampaignJourney/useCampaignNames';

import MessageError from './MessageError.vue';
import ContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';
// fork chat#1709 (fase 3): reações coladas na mensagem, selo "editada" e reagir/editar pela caixa WAHA comum.
import MessageReactions from './actions/MessageReactions.vue';
import EditedMark from './actions/EditedMark.vue';
import MessageActionDialogs from './actions/MessageActionDialogs.vue';
import { canEdit, canReact } from './actions/messageActions.js';
import { useAudioParaBaixar } from 'dashboard/components-next/conversa-canal/audio/useAudioParaBaixar';
import AlbumDoWhatsapp from 'dashboard/components-next/conversa-canal/album/AlbumDoWhatsapp.vue';
import {
  useAlbumDaMensagem,
  useContatosDaMensagem,
} from 'dashboard/components-next/conversa-canal/album/useAlbuns';
import ContatosDoWhatsapp from 'dashboard/components-next/conversa-canal/midia/ContatosDoWhatsapp.vue';
import { usePele } from 'dashboard/components-next/conversa-canal/pele';
import { mensagemDestacada } from 'dashboard/components-next/conversa-canal/destaqueDaCitada';
import { balaoDaPele } from 'dashboard/components-next/conversa-canal/balaoDaPele';
import LigacaoDoWhatsapp from 'dashboard/components-next/conversa-canal/ligacao/LigacaoDoWhatsapp.vue';
import {
  ligacaoDaCloudNoCartao,
  resumoDaLigacao,
} from 'dashboard/components-next/conversa-canal/ligacao/ligacao';
import AvisoDeTemporarias from 'dashboard/components-next/conversa-canal/temporarias/AvisoDeTemporarias.vue';
import { avisoDeTemporarias } from 'dashboard/components-next/conversa-canal/temporarias/temporarias';
import BotaoDeReagir from 'dashboard/components-next/conversa-canal/BotaoDeReagir.vue';
import { useReacaoDoAtendente } from 'dashboard/components-next/conversa-canal/useReacaoDoAtendente';
import BotaoDeEncaminhar from 'dashboard/components-next/conversa-canal/encaminhar/BotaoDeEncaminhar.vue';
import MarcaDeEncaminhar from 'dashboard/components-next/conversa-canal/encaminhar/MarcaDeEncaminhar.vue';
import { useEncaminharDaMensagem } from 'dashboard/components-next/conversa-canal/encaminhar/useEncaminharDaMensagem';
import { useBranding } from 'shared/composables/useBranding';
import { ehNotaDoConector } from 'dashboard/components-next/conversa-canal/notaDoConector';
import { textoDaMensagem } from 'dashboard/components-next/conversa-canal/ecoDoCelular';
import { useEcoDoCelular } from 'dashboard/components-next/conversa-canal/useEcoDoCelular';
import LinhaDoInstagram from 'dashboard/components-next/conversa-canal/instagram/LinhaDoInstagram.vue';
import { useInstagramDaConversa } from 'dashboard/components-next/conversa-canal/instagram/useConversaDoInstagram';
import { balaoDoInstagram } from 'dashboard/components-next/conversa-canal/instagram/balaoDoInstagram';

/**
 * @typedef {Object} Attachment
 * @property {number} id - Unique identifier for the attachment
 * @property {number} messageId - ID of the associated message
 * @property {'image'|'audio'|'video'|'file'|'location'|'fallback'|'share'|'story_mention'|'contact'|'ig_reel'} fileType - Type of the attachment (file or image)
 * @property {number} accountId - ID of the associated account
 * @property {string|null} extension - File extension
 * @property {string} dataUrl - URL to access the full attachment data
 * @property {string} thumbUrl - URL to access the thumbnail version
 * @property {number} fileSize - Size of the file in bytes
 * @property {number|null} width - Width of the image if applicable
 * @property {number|null} height - Height of the image if applicable
 */

/**
 * @typedef {Object} Sender
 * @property {Object} additional_attributes - Additional attributes of the sender
 * @property {Object} custom_attributes - Custom attributes of the sender
 * @property {string} email - Email of the sender
 * @property {number} id - ID of the sender
 * @property {string|null} identifier - Identifier of the sender
 * @property {string} name - Name of the sender
 * @property {string|null} phone_number - Phone number of the sender
 * @property {string} thumbnail - Thumbnail URL of the sender
 * @property {string} type - Type of sender
 */

/**
 * @typedef {Object} ContentAttributes
 * @property {string} externalError - an error message to be shown if the message failed to send
 */

/**
 * @typedef {Object} Props
 * @property {('sent'|'delivered'|'read'|'failed'|'progress')} status - The delivery status of the message
 * @property {ContentAttributes} [contentAttributes={}] - Additional attributes of the message content
 * @property {Attachment[]} [attachments=[]] - The attachments associated with the message
 * @property {Sender|null} [sender=null] - The sender information
 * @property {boolean} [private=false] - Whether the message is private
 * @property {number|null} [senderId=null] - The ID of the sender
 * @property {number} createdAt - Timestamp when the message was created
 * @property {number} currentUserId - The ID of the current user
 * @property {number} id - The unique identifier for the message
 * @property {number} messageType - The type of message (must be one of MESSAGE_TYPES)
 * @property {string|null} [error=null] - Error message if the message failed to send
 * @property {string|null} [senderType=null] - The type of the sender
 * @property {string} content - The message content
 * @property {boolean} [groupWithNext=false] - Whether the message should be grouped with the next message
 * @property {Object|null} [inReplyTo=null] - The message to which this message is a reply
 * @property {boolean} [isEmailInbox=false] - Whether the message is from an email inbox
 * @property {number} conversationId - The ID of the conversation to which the message belongs
 * @property {number} inboxId - The ID of the inbox to which the message belongs
 */

// eslint-disable-next-line vue/define-macros-order
const props = defineProps({
  id: { type: Number, required: true },
  messageType: {
    type: Number,
    required: true,
    validator: value => Object.values(MESSAGE_TYPES).includes(value),
  },
  status: {
    type: String,
    required: true,
    validator: value => Object.values(MESSAGE_STATUS).includes(value),
  },
  attachments: { type: Array, default: () => [] },
  call: { type: Object, default: null }, // eslint-disable-line vue/no-unused-properties
  content: { type: String, default: null },
  contentAttributes: { type: Object, default: () => ({}) },
  // chat#1709: apagar no painel apaga também no WhatsApp do cliente ("Apagar para todos").
  c2yRevocable: { type: Boolean, default: false },
  contentType: {
    type: String,
    default: 'text',
    validator: value => Object.values(CONTENT_TYPES).includes(value),
  },
  conversationId: { type: Number, required: true },
  createdAt: { type: Number, required: true }, // eslint-disable-line vue/no-unused-properties
  currentUserId: { type: Number, required: true },
  groupWithNext: { type: Boolean, default: false },
  inboxId: { type: Number, default: null }, // eslint-disable-line vue/no-unused-properties
  inboxSupportsReplyTo: { type: Object, default: () => ({}) },
  inReplyTo: { type: Object, default: null }, // eslint-disable-line vue/no-unused-properties
  isEmailInbox: { type: Boolean, default: false },
  private: { type: Boolean, default: false },
  additionalAttributes: { type: Object, default: () => ({}) }, // eslint-disable-line vue/no-unused-properties
  sender: { type: Object, default: null },
  senderId: { type: Number, default: null },
  senderType: { type: String, default: null },
  sourceId: { type: String, default: '' }, // eslint-disable-line vue/no-unused-properties
});

const emit = defineEmits(['retry']);

const contextMenuPosition = ref({});
const showBackgroundHighlight = ref(false);
const showContextMenu = ref(false);
const { t } = useI18n();
const route = useRoute();
const inboxGetter = useMapGetter('inboxes/getInbox');
const inbox = computed(() => inboxGetter.value(props.inboxId) || {});
// #1941: a nota técnica antiga do conector WAHA aparece como a linha de aviso.
const notaDoConector = computed(() =>
  ehNotaDoConector({
    caixa: inbox.value,
    privada: props.private,
    conteudo: props.content,
  })
);
const isOnChatwootCloud = useMapGetter('globalConfig/isOnChatwootCloud');
const { replaceInstallationName } = useBranding();

// #1941: mandada pelo app do celular (eco). O texto sai sem o prefixo do conector WAHA
// (inclusive no histórico) e o nome é o de quem estava atribuído quando chegou.
const eco = useEcoDoCelular(computed(() => props.contentAttributes));
const conteudo = computed(() =>
  textoDaMensagem(props.content, props.contentAttributes)
);

// fork chat#1709 (fase 3): reagir e editar pelo painel, só com a ação no campo da conversa.
// Também serve ao "só leitura" do #1800, mais abaixo.
const selectedChat = useMapGetter('getSelectedChat');
const messageActionDialogs = ref(null);
const isReactable = computed(() => canReact(selectedChat.value, props));
// A janela de edição é conferida na hora em que o menu abre (o computed não anda sozinho com o relógio).
const menuOpenedAt = ref(Date.now() / 1000);
// Só o autor ou um administrador edita, como o servidor confere.
const currentRole = useMapGetter('getCurrentRole');
const isEditable = computed(() =>
  canEdit(selectedChat.value, props, menuOpenedAt.value, {
    userId: props.currentUserId,
    isAdmin: currentRole.value === 'administrator',
  })
);
const messageReactions = computed(() =>
  Array.isArray(props.contentAttributes?.reactions)
    ? props.contentAttributes.reactions
    : []
);
const isEdited = computed(() => !!props.contentAttributes?.editedAt);
const hasMessageExtras = computed(
  () => messageReactions.value.length > 0 || isEdited.value
);

const isCaptainMessage = computed(() => {
  const senderType = props.sender?.type ?? props.senderType;
  return senderType === SENDER_TYPES.CAPTAIN_ASSISTANT;
});

// #284 — outgoing message posted by an Autonomia agent (the fork stamps every
// reply of the mirror AgentBot with `autonomia_agent_id`). Enables "wrong reply".
const isAutonomiaAgentMessage = computed(
  () =>
    props.messageType === MESSAGE_TYPES.OUTGOING &&
    !!props.contentAttributes?.autonomiaAgentId
);

/**
 * Computes the message variant based on props
 * @type {import('vue').ComputedRef<'user'|'agent'|'activity'|'private'|'bot'|'template'>}
 */
const variant = computed(() => {
  if (notaDoConector.value) return MESSAGE_VARIANTS.ACTIVITY;
  if (props.private) return MESSAGE_VARIANTS.PRIVATE;

  if (props.isEmailInbox) {
    const emailInboxTypes = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING];
    if (emailInboxTypes.includes(props.messageType)) {
      return MESSAGE_VARIANTS.EMAIL;
    }
  }

  if (props.contentType === CONTENT_TYPES.INCOMING_EMAIL) {
    return MESSAGE_VARIANTS.EMAIL;
  }

  if (props.status === MESSAGE_STATUS.FAILED) return MESSAGE_VARIANTS.ERROR;
  if (props.contentAttributes?.isUnsupported)
    return MESSAGE_VARIANTS.UNSUPPORTED;

  if (props.contentAttributes?.externalEcho) {
    return MESSAGE_VARIANTS.AGENT;
  }

  const isBot =
    props.sender?.type === SENDER_TYPES.AGENT_BOT ||
    props.senderType === SENDER_TYPES.AGENT_BOT ||
    (!props.sender && !props.additionalAttributes?.senderName);
  if (isBot && props.messageType === MESSAGE_TYPES.OUTGOING) {
    return MESSAGE_VARIANTS.BOT;
  }

  const variants = {
    [MESSAGE_TYPES.INCOMING]: MESSAGE_VARIANTS.USER,
    [MESSAGE_TYPES.ACTIVITY]: MESSAGE_VARIANTS.ACTIVITY,
    [MESSAGE_TYPES.OUTGOING]: MESSAGE_VARIANTS.AGENT,
    [MESSAGE_TYPES.TEMPLATE]: MESSAGE_VARIANTS.TEMPLATE,
  };

  return variants[props.messageType] || MESSAGE_VARIANTS.USER;
});

const isBotOrAgentMessage = computed(() => {
  if (props.messageType === MESSAGE_TYPES.ACTIVITY) {
    return false;
  }
  // if an outgoing message is still processing, then it's definitely a
  // message sent by the current user
  if (
    props.status === MESSAGE_STATUS.PROGRESS &&
    props.messageType === MESSAGE_TYPES.OUTGOING
  ) {
    return true;
  }
  const senderId = props.senderId ?? props.sender?.id;
  const senderType = props.sender?.type ?? props.senderType;

  if (!senderType || !senderId) {
    return true;
  }

  if (
    [SENDER_TYPES.AGENT_BOT, SENDER_TYPES.CAPTAIN_ASSISTANT].includes(
      senderType
    )
  ) {
    return true;
  }

  return senderType.toLowerCase() === SENDER_TYPES.USER.toLowerCase();
});

/**
 * Computes the message orientation based on sender type and message type
 * @returns {import('vue').ComputedRef<'left'|'right'|'center'>} The computed orientation
 */
const orientation = computed(() => {
  if (notaDoConector.value) return ORIENTATION.CENTER;
  if (isBotOrAgentMessage.value) {
    return ORIENTATION.RIGHT;
  }

  if (props.messageType === MESSAGE_TYPES.ACTIVITY) return ORIENTATION.CENTER;

  return ORIENTATION.LEFT;
});

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const gridClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'grid grid-cols-1fr',
    [ORIENTATION.RIGHT]: 'grid grid-cols-[1fr_24px]',
  };

  return map[orientation.value];
});

const gridTemplate = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: `
      "bubble"
      "meta"
    `,
    [ORIENTATION.RIGHT]: `
      "bubble avatar"
      "meta spacer"
    `,
  };

  return map[orientation.value];
});

const shouldGroupWithNext = computed(() => {
  if (props.status === MESSAGE_STATUS.FAILED) return false;

  return props.groupWithNext;
});

const shouldShowAvatar = computed(() => {
  if (props.messageType === MESSAGE_TYPES.ACTIVITY) return false;
  if (orientation.value === ORIENTATION.LEFT) return false;

  return true;
});

// chat#1473: formato rico enviado ao cliente (botão de link e os próximos tipos).
// Tipo sem bolha própria devolve null e a mensagem segue pelo caminho de antes.
const richMessageBubble = computed(() => richMessageBubbleFor(props));
// #1702: com a pele do WhatsApp, fotos e vídeos mandados juntos viram um álbum.
const album = useAlbumDaMensagem(computed(() => props.id));
// #1702: contatos mandados de uma vez (uma mensagem por contato) viram um cartão só.
const contatosJuntos = useContatosDaMensagem(computed(() => props.id));
// #1702: enquete, pedido, vários contatos, só emoji e aviso por tipo (só com a pele).
const pele = usePele();
const balaoDoWhatsapp = computed(() =>
  pele.value ? balaoDaPele(props) : null
);
// #2079: na conversa do Instagram com a cara do Direct, a linha inteira é a do app.
// Tipo sem balão do Direct (arquivo, não suportada) segue no balão de sempre, e a
// mensagem que falhou também: lá fica o erro e o "Tentar de novo".
const instagram = useInstagramDaConversa();
const linhaDoInstagram = computed(
  () =>
    instagram.ligado.value &&
    !props.private &&
    ![MESSAGE_VARIANTS.ACTIVITY, MESSAGE_VARIANTS.ERROR].includes(
      variant.value
    ) &&
    !props.contentAttributes?.externalError &&
    balaoDoInstagram(props) !== null
);
// #1702/#2211: a citação ou o link com ?messageId= levou até aqui: a linha fica destacada
// 3 s em âmbar (só com a pele).
const destacadaPelaCitacao = computed(
  () => !!pele.value && mensagemDestacada.value === props.id
);
// #1702: o aviso de ligação vira o cartão de ligação do app (só com a pele).
const ligacao = computed(
  () => !!pele.value && !!resumoDaLigacao(props.contentAttributes)
);
// #1709: o aviso de mensagens temporárias vira a frase do app (só com a pele).
const temporarias = computed(
  () => !!pele.value && !!avisoDeTemporarias(props.contentAttributes)
);

const componentToRender = computed(() => {
  if (props.isEmailInbox && !props.private) {
    const emailInboxTypes = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING];
    if (emailInboxTypes.includes(props.messageType)) return EmailBubble;
  }

  if (props.contentAttributes?.whatsappFlowResponse) {
    return WhatsappFlowResponseBubble;
  }

  if (contatosJuntos.value) return ContatosDoWhatsapp;

  // #1831: o álbum desenhado no balão do marcador (não suportada): o da Cloud chegando
  // ainda sem foto e o do WAHA, do começo ao fim.
  if (album.value && props.contentAttributes?.isUnsupported) {
    return AlbumDoWhatsapp;
  }

  if (balaoDoWhatsapp.value) return balaoDoWhatsapp.value;

  if (richMessageBubble.value) return richMessageBubble.value;

  if (props.contentType === CONTENT_TYPES.INPUT_CSAT) {
    return CSATBubble;
  }

  if (
    [CONTENT_TYPES.INPUT_SELECT, CONTENT_TYPES.FORM].includes(props.contentType)
  ) {
    return FormBubble;
  }

  if (props.contentType === CONTENT_TYPES.VOICE_CALL) {
    // #1702: com a pele, a ligação encerrada da Cloud vira o cartão do app (ligacao.js).
    const noCartao =
      pele.value &&
      ligacaoDaCloudNoCartao({
        chamada: props.call,
        enviada: props.messageType === MESSAGE_TYPES.OUTGOING,
        anexos: props.attachments,
      });
    return noCartao ? LigacaoDoWhatsapp : VoiceCallBubble;
  }

  if (props.contentType === CONTENT_TYPES.INCOMING_EMAIL) {
    return EmailBubble;
  }

  if (props.contentAttributes?.isUnsupported) {
    return UnsupportedBubble;
  }

  if (props.contentAttributes.type === 'dyte') {
    return DyteBubble;
  }

  const instagramSharedTypes = [
    ATTACHMENT_TYPES.STORY_MENTION,
    ATTACHMENT_TYPES.IG_STORY,
    ATTACHMENT_TYPES.IG_STORY_REPLY,
    ATTACHMENT_TYPES.IG_POST,
  ];
  if (instagramSharedTypes.includes(props.contentAttributes.imageType)) {
    return InstagramStoryBubble;
  }

  if (album.value) return AlbumDoWhatsapp;

  if (Array.isArray(props.attachments) && props.attachments.length === 1) {
    const fileType = props.attachments[0].fileType;

    if (fileType === ATTACHMENT_TYPES.FALLBACK) return FallbackBubble;
    // fork chat#1709: a localização ao vivo do WhatsApp pode vir com legenda no content; o cartão de mapa a mostra.
    if (
      fileType === ATTACHMENT_TYPES.LOCATION &&
      props.contentAttributes?.sharedLocation
    )
      return LocationBubble;

    // #1941: foto mandada pelo celular cujo texto era só o prefixo do conector.
    if (!conteudo.value) {
      if (fileType === ATTACHMENT_TYPES.IMAGE) return ImageBubble;
      if (fileType === ATTACHMENT_TYPES.FILE) return FileBubble;
      if (fileType === ATTACHMENT_TYPES.AUDIO) return AudioBubble;
      if (fileType === ATTACHMENT_TYPES.VIDEO) return VideoBubble;
      if (fileType === ATTACHMENT_TYPES.IG_REEL) return VideoBubble;
      if (fileType === ATTACHMENT_TYPES.EMBED) return EmbedBubble;
      if (fileType === ATTACHMENT_TYPES.LOCATION) return LocationBubble;
    }
    // Attachment content is the name of the contact
    if (fileType === ATTACHMENT_TYPES.CONTACT) return ContactBubble;
  }

  return TextBubble;
});

const shouldShowContextMenu = computed(() => {
  return !props.contentAttributes?.isUnsupported;
});

const isBubble = computed(() => {
  return props.messageType !== MESSAGE_TYPES.ACTIVITY && !notaDoConector.value;
});

const isMessageDeleted = computed(() => {
  return props.contentAttributes?.deleted;
});

// Campaign label (#1002, P2): messages sent by a campaign keep its id.
const isCampaignMessage = computed(
  () => !!campaignRefFor(props.additionalAttributes)
);

const shouldShowWhatsappReferral = computed(
  () =>
    variant.value === MESSAGE_VARIANTS.USER &&
    !!props.contentAttributes?.referral
);
// #1702: com a pele, o anúncio é citação dentro do balão (OrigemDaMensagem), e o
// cartão de fora some (sem ele, a linha não vira coluna e reagir/encaminhar ficam ao lado).
// A citação mora no Base.vue: balão que não passa por ele (o cartão de ligação) não a
// desenha, e o anúncio continua no cartão de fora para não sumir.
const BALOES_SEM_ORIGEM = [LigacaoDoWhatsapp];
const anuncioForaDoBalao = computed(
  () =>
    shouldShowWhatsappReferral.value &&
    (!pele.value || BALOES_SEM_ORIGEM.includes(componentToRender.value))
);

// #1702: com a pele do WhatsApp, "Baixar" do áudio fica no menu da mensagem.
const audioParaBaixar = useAudioParaBaixar(computed(() => props.attachments));

// #1702: com a pele do WhatsApp, o atendente reage ao balão (botão ao lado e menu).
const reacaoDoAtendente = useReacaoDoAtendente(
  computed(() => ({
    id: props.id,
    messageType: props.messageType,
    isPrivate: props.private,
    status: props.status,
    sourceId: props.sourceId,
    contentAttributes: props.contentAttributes,
    conversationId: props.conversationId,
    inboxId: props.inboxId,
  }))
);

// #1702: encaminhar como no WhatsApp Web (menu, botão ao lado da mídia, modo seleção).
const mensagemParaEncaminhar = computed(() => ({
  id: props.id,
  conversationId: props.conversationId,
  messageType: props.messageType,
  contentType: props.contentType,
  status: props.status,
  private: props.private,
  content: conteudo.value,
  contentAttributes: props.contentAttributes,
  additionalAttributes: props.additionalAttributes,
  attachments: props.attachments,
}));
// O álbum leva os itens dele; só os encaminháveis entram (o composable filtra).
const encaminhar = useEncaminharDaMensagem(
  mensagemParaEncaminhar,
  computed(() => album.value || [mensagemParaEncaminhar.value])
);

const payloadForContextMenu = computed(() => {
  return {
    audioParaBaixar: audioParaBaixar.value,
    // #1702: no álbum (e nos contatos do mesmo envio), apagar age em todos os itens.
    idsDoAlbum:
      (album.value || contatosJuntos.value)?.map(item => item.id) || null,
    id: props.id,
    content_attributes: props.contentAttributes,
    content: conteudo.value,
    conversation_id: props.conversationId,
    c2y_revocable: props.c2yRevocable,
  };
});

// Quem tem cargo só apaga com a chave (#1893); administrador e agente sem cargo seguem apagando.
const canDeleteMessage = useCanManage('conversation_message_delete');

const allContextMenuOptions = computed(() => {
  const hasText = !!conteudo.value;
  const hasAttachments = !!(props.attachments && props.attachments.length > 0);

  const isOutgoing = props.messageType === MESSAGE_TYPES.OUTGOING;
  const isFailedOrProcessing =
    props.status === MESSAGE_STATUS.FAILED ||
    props.status === MESSAGE_STATUS.PROGRESS;

  return {
    copy: hasText,
    delete:
      (hasText || hasAttachments) &&
      !isFailedOrProcessing &&
      !isMessageDeleted.value &&
      canDeleteMessage.value,
    cannedResponse: isOutgoing && hasText && !isMessageDeleted.value,
    copyLink: !isFailedOrProcessing,
    translate: !isFailedOrProcessing && !isMessageDeleted.value && hasText,
    replyTo:
      !props.private &&
      props.inboxSupportsReplyTo.outgoing &&
      !isFailedOrProcessing &&
      !isMessageDeleted.value,
    report:
      isOnChatwootCloud.value &&
      isCaptainMessage.value &&
      !isMessageDeleted.value,
    reportAgent: isAutonomiaAgentMessage.value && !isMessageDeleted.value,
    baixarAudio: !!audioParaBaixar.value && !isMessageDeleted.value,
    reagir:
      reacaoDoAtendente.visivel.value && !reacaoDoAtendente.bloqueado.value,
    encaminhar: encaminhar.noMenu.value,
    // #1709: com a pele vale o "Reagir" dela (acima); o "Editar" do #1709 vale sempre.
    react: isReactable.value && !pele.value,
    edit: isEditable.value,
  };
});

// Quem só lê a conversa (#1800) copia, copia o link e baixa o áudio; o resto escreve e o servidor recusa.
// Fora da conversa aberta (outras telas que mostram mensagens) nada muda. `selectedChat` é o mesmo do #1709, acima.
const canOperateConversation = useMapGetter('canOperateConversation');
const isReadOnly = computed(
  () =>
    selectedChat.value?.id === props.conversationId &&
    !canOperateConversation.value(selectedChat.value)
);
const READ_ONLY_OPTIONS = ['copy', 'copyLink', 'baixarAudio'];

const contextMenuEnabledOptions = computed(() => {
  const options = allContextMenuOptions.value;
  if (!isReadOnly.value) return options;
  return Object.fromEntries(
    Object.entries(options).map(([key, enabled]) => [
      key,
      enabled && READ_ONLY_OPTIONS.includes(key),
    ])
  );
});

const shouldRenderMessage = computed(() => {
  const hasAttachments = !!(props.attachments && props.attachments.length > 0);
  const isEmailContentType = props.contentType === CONTENT_TYPES.INCOMING_EMAIL;
  const isUnsupported = props.contentAttributes?.isUnsupported;
  const isAnIntegrationMessage =
    props.contentType === CONTENT_TYPES.INTEGRATIONS;
  const hasWhatsappFlowResponse =
    !!props.contentAttributes?.whatsappFlowResponse;
  const isFailedMessage = props.status === MESSAGE_STATUS.FAILED;
  const hasExternalError = !!props.contentAttributes?.externalError;

  return (
    hasAttachments ||
    conteudo.value ||
    isEmailContentType ||
    isUnsupported ||
    isAnIntegrationMessage ||
    hasWhatsappFlowResponse ||
    !!richMessageBubble.value ||
    !!balaoDoWhatsapp.value ||
    shouldShowWhatsappReferral.value ||
    isFailedMessage ||
    hasExternalError
  );
});

function openContextMenu(e) {
  const shouldSkipContextMenu =
    e.target?.classList.contains('skip-context-menu') ||
    ['a', 'img'].includes(e.target?.tagName.toLowerCase());
  if (shouldSkipContextMenu || getSelection().toString()) {
    return;
  }

  e.preventDefault();
  if (e.type === 'contextmenu') {
    useTrack(ACCOUNT_EVENTS.OPEN_MESSAGE_CONTEXT_MENU);
  }
  menuOpenedAt.value = Date.now() / 1000;
  contextMenuPosition.value = {
    x: e.pageX || e.clientX,
    y: e.pageY || e.clientY,
  };
  showContextMenu.value = true;
}

function closeContextMenu() {
  showContextMenu.value = false;
  contextMenuPosition.value = { x: null, y: null };
}

function handleReplyTo() {
  const replyStorageKey = LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO;
  const { conversationId, id: replyTo } = props;

  LocalStorage.updateJsonStore(replyStorageKey, conversationId, replyTo);
  emitter.emit(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, props);
}

const avatarInfo = computed(() => {
  // #1941: eco com quem estava atribuído = avatar dessa pessoa; nunca o remetente.
  if (eco.autor.value) {
    return {
      name: eco.nomeDoAutor.value,
      src: eco.autor.value.thumbnail || '',
    };
  }
  if (props.contentAttributes?.externalEcho) {
    const { name, avatar_url, medium, voice_enabled } = inbox.value;
    const iconName = avatar_url
      ? null
      : getInboxIconByType(
          tipoDoIconeDaCaixa(inbox.value),
          medium,
          'fill',
          voice_enabled
        );
    return {
      name: iconName ? '' : name || t('CONVERSATION.NATIVE_APP'),
      src: avatar_url || '',
      iconName,
    };
  }

  // If no sender, check for Slack (or other integration) sender info
  if (!props.sender) {
    const { senderName, senderAvatarUrl } = props.additionalAttributes || {};
    if (senderName) {
      return { name: senderName, src: senderAvatarUrl ?? '' };
    }
    return { name: t('CONVERSATION.BOT'), src: '' };
  }

  const { sender } = props;
  const { name, type, avatarUrl, thumbnail } = sender || {};

  // If sender type is agent bot, use avatarUrl
  if ([SENDER_TYPES.AGENT_BOT, SENDER_TYPES.CAPTAIN_ASSISTANT].includes(type)) {
    return {
      name: name ?? '',
      src: avatarUrl ?? '',
    };
  }

  // For all other senders, use thumbnail
  return {
    name: name ?? '',
    src: thumbnail ?? '',
  };
});

const avatarTooltip = computed(() => {
  if (eco.autor.value) {
    return t('CONVERSA_CANAL.ECO_DO_CELULAR.ENVIADA_POR', {
      nome: eco.nomeDoAutor.value,
    });
  }
  if (props.contentAttributes?.externalEcho) {
    return replaceInstallationName(t('CONVERSATION.NATIVE_APP_ADVISORY'));
  }
  if (avatarInfo.value.name === '') return '';
  return `${t('CONVERSATION.SENT_BY')} ${avatarInfo.value.name}`;
});

const setupHighlightTimer = () => {
  if (Number(route.query.messageId) !== Number(props.id)) {
    return;
  }

  showBackgroundHighlight.value = true;
  const HIGHLIGHT_TIMER = 1000;
  useTimeoutFn(() => {
    showBackgroundHighlight.value = false;
  }, HIGHLIGHT_TIMER);
};

onMounted(setupHighlightTimer);

provideMessageContext({
  ...toRefs(props),
  content: computed(() =>
    notaDoConector.value
      ? t('CONVERSA_CANAL.NOTA_DO_CONECTOR.AVISO')
      : conteudo.value
  ),
  isPrivate: computed(() => props.private),
  variant,
  orientation,
  isBotOrAgentMessage,
  shouldGroupWithNext,
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="shouldRenderMessage"
    :id="`message${props.id}`"
    class="flex w-full mb-2 message-bubble-container"
    :data-message-id="props.id"
    :class="[
      flexOrientationClass,
      {
        'group-with-next': shouldGroupWithNext,
        'bg-n-alpha-1': showBackgroundHighlight,
        'relative ltr:pl-12 rtl:pr-12': encaminhar.emSelecao.value,
        'bg-[#000]/[0.06] dark:bg-white/[0.06]': encaminhar.marcada.value,
        'transition-colors duration-500': pele,
        // #2211: faixa âmbar com contorno amber-11 (≥ 3:1 contra o fundo nos dois temas).
        'bg-n-amber-3 ring-2 ring-inset ring-n-amber-11': destacadaPelaCitacao,
      },
    ]"
  >
    <MarcaDeEncaminhar
      v-if="encaminhar.emSelecao.value && encaminhar.podeEncaminhar.value"
      :marcada="encaminhar.marcada.value"
      @alternar="encaminhar.alternar"
    />
    <div
      v-if="variant === MESSAGE_VARIANTS.ACTIVITY"
      :class="{ 'flex w-full justify-start': ligacao }"
    >
      <LigacaoDoWhatsapp v-if="ligacao" />
      <AvisoDeTemporarias v-else-if="temporarias" />
      <!-- O texto vem do contexto da mensagem (o da nota do conector é o aviso curto, #1941). -->
      <ActivityBubble v-else />
    </div>
    <LinhaDoInstagram
      v-else-if="linhaDoInstagram"
      :pode-responder="contextMenuEnabledOptions.replyTo"
      :pode-reagir="reacaoDoAtendente.visivel.value && !isReadOnly"
      :reacao-atual="reacaoDoAtendente.atual.value"
      :reacao-bloqueada="reacaoDoAtendente.bloqueado.value"
      :reagindo="reacaoDoAtendente.enviando.value"
      @responder="handleReplyTo"
      @reagir="reacaoDoAtendente.reagir"
      @menu="openContextMenu($event)"
    />
    <div
      v-else
      :class="[
        gridClass,
        {
          'gap-y-2': contentAttributes.externalError,
          'w-full': variant === MESSAGE_VARIANTS.EMAIL,
        },
      ]"
      class="gap-x-2"
      :style="{
        gridTemplateAreas: gridTemplate,
      }"
    >
      <div
        v-if="!shouldGroupWithNext && shouldShowAvatar"
        v-tooltip.left-end="avatarTooltip"
        class="[grid-area:avatar] flex items-end"
      >
        <Avatar v-bind="avatarInfo" :size="24" />
      </div>
      <div
        class="[grid-area:bubble] flex min-w-0 group/linha"
        :class="{
          'ltr:ml-8 rtl:mr-8 justify-end': orientation === ORIENTATION.RIGHT,
          'ltr:mr-8 rtl:ml-8': orientation === ORIENTATION.LEFT,
          'flex-col items-start gap-2': anuncioForaDoBalao,
          'flex-col gap-1': isCampaignMessage || (hasMessageExtras && !pele),
          'items-end':
            (isCampaignMessage || (hasMessageExtras && !pele)) &&
            orientation === ORIENTATION.RIGHT,
        }"
        @contextmenu="openContextMenu($event)"
      >
        <CampaignMessageLabel
          v-if="isCampaignMessage"
          :additional-attributes="additionalAttributes"
        />
        <WhatsappReferral
          v-if="anuncioForaDoBalao"
          :referral="contentAttributes.referral"
        />
        <Component :is="componentToRender" />
        <BotaoDeReagir
          v-if="reacaoDoAtendente.visivel.value && !isReadOnly"
          :mensagem-id="id"
          :lado="orientation"
          :atual="reacaoDoAtendente.atual.value"
          :bloqueado="reacaoDoAtendente.bloqueado.value"
          :enviando="reacaoDoAtendente.enviando.value"
          @reagir="reacaoDoAtendente.reagir"
        />
        <BotaoDeEncaminhar
          v-if="encaminhar.botaoAoLado.value && !isReadOnly"
          :lado="orientation"
          @encaminhar="encaminhar.encaminharDireto"
        />
        <!-- #1709: com a pele valem o RotuloEditada e o SeloDeReacoes dela. -->
        <EditedMark
          v-if="isEdited && !pele"
          :history="contentAttributes.editHistory"
          :current-user-id="currentUserId"
        />
        <MessageReactions
          v-if="messageReactions.length && !pele"
          :reactions="messageReactions"
          :current-user-id="currentUserId"
        />
      </div>
      <MessageError
        v-if="contentAttributes.externalError"
        class="[grid-area:meta]"
        :class="flexOrientationClass"
        :error="contentAttributes.externalError"
        :read-only="isReadOnly"
        @retry="emit('retry')"
      />
    </div>
    <div v-if="shouldShowContextMenu" class="context-menu-wrap">
      <ContextMenu
        v-if="isBubble"
        :context-menu-position="contextMenuPosition"
        :is-open="showContextMenu"
        :enabled-options="contextMenuEnabledOptions"
        :message="payloadForContextMenu"
        hide-button
        @open="openContextMenu"
        @close="closeContextMenu"
        @reply-to="handleReplyTo"
        @encaminhar="encaminhar.iniciarSelecao"
        @react="messageActionDialogs?.openReaction()"
        @edit="messageActionDialogs?.openEdit()"
      />
      <MessageActionDialogs
        v-if="isReactable || isEditable"
        ref="messageActionDialogs"
        :conversation-id="conversationId"
        :message-id="id"
        :content="conteudo || ''"
        :reactions="messageReactions"
      />
    </div>
  </div>
</template>

<style lang="scss">
.group-with-next + .message-bubble-container {
  .left-bubble {
    @apply ltr:rounded-tl-sm rtl:rounded-tr-sm;
  }

  .right-bubble {
    @apply ltr:rounded-tr-sm rtl:rounded-tl-sm;
  }
}
</style>
