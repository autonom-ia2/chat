// Quando o painel oferece "Reagir" e "Editar" numa mensagem (chat#1709, fase 3). A conversa diz o que o motor da caixa
// WAHA comum sabe fazer (`whatsapp_api_message_actions`, só com a flag); a mensagem diz se a ação cabe nela. São as
// mesmas regras do servidor (Waha::RichNative::MessageActions), que confere de novo (inclusive quem pode editar).
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../constants';

// Margem sob os 15 minutos do WhatsApp, igual ao servidor (EDIT_WINDOW).
export const EDIT_WINDOW_MINUTES = 14;
export const EDIT_WINDOW_SECONDS = EDIT_WINDOW_MINUTES * 60;
// Teto do texto do WhatsApp, igual ao servidor (Waha::RichNative::Edits::MAX_LENGTH).
export const EDIT_MAX_LENGTH = 4096;

// O número da empresa reage uma vez por mensagem: atendentes, IA e o celular da empresa são o mesmo autor. 'agent' e
// 'phone' são os nomes antigos do mesmo autor.
const BUSINESS_AUTHORS = ['business', 'agent', 'phone'];

const actionsOf = conversation =>
  Array.isArray(conversation?.whatsapp_api_message_actions)
    ? conversation.whatsapp_api_message_actions
    : [];

const isDeleted = message => Boolean(message.contentAttributes?.deleted);

// Mensagem que falhou (gravar nela mandaria o erro de volta ao conector, que reenviaria).
const isFailed = message =>
  message.status === MESSAGE_STATUS.FAILED ||
  Boolean(message.contentAttributes?.externalError);

export const canReact = (conversation, message) =>
  actionsOf(conversation).includes('react') &&
  [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING].includes(
    message.messageType
  ) &&
  !message.private &&
  !isFailed(message) &&
  !isDeleted(message);

export const canEdit = (
  conversation,
  message,
  nowSeconds = Date.now() / 1000
) =>
  actionsOf(conversation).includes('edit') &&
  message.messageType === MESSAGE_TYPES.OUTGOING &&
  !message.private &&
  message.contentType === 'text' &&
  !(message.attachments && message.attachments.length) &&
  !message.contentAttributes?.richMessage &&
  !isFailed(message) &&
  !isDeleted(message) &&
  nowSeconds - message.createdAt <= EDIT_WINDOW_SECONDS;

export const isBusinessReaction = reaction =>
  BUSINESS_AUTHORS.includes(reaction?.by);

const validReactions = reactions =>
  (Array.isArray(reactions) ? reactions : []).filter(
    reaction => typeof reaction?.emoji === 'string' && reaction.emoji
  );

// As reações agrupadas por emoji, na ordem em que apareceram:
// [{ emoji, count, fromContact, fromBusiness, mine }]. `mine`: a reação da empresa foi feita por este atendente.
export const groupReactions = (reactions, currentUserId) => {
  const groups = new Map();
  validReactions(reactions).forEach(reaction => {
    const { emoji } = reaction;
    const group = groups.get(emoji) ?? {
      emoji,
      count: 0,
      fromContact: false,
      fromBusiness: false,
      mine: false,
    };
    const business = isBusinessReaction(reaction);
    groups.set(emoji, {
      ...group,
      count: group.count + 1,
      fromContact: group.fromContact || reaction.by === 'contact',
      fromBusiness: group.fromBusiness || business,
      mine:
        group.mine ||
        (business &&
          currentUserId != null &&
          reaction.userId === currentUserId),
    });
  });
  return [...groups.values()];
};

// A reação da empresa na mensagem ('' quando a empresa não reagiu), feita por qualquer atendente ou pelo celular.
export const businessReaction = reactions =>
  validReactions(reactions).find(isBusinessReaction)?.emoji ?? '';
