// Quando o painel oferece "Reagir" e "Editar" numa mensagem (chat#1709, fase 3). A conversa diz o que o motor da caixa
// WAHA comum sabe fazer (`whatsapp_api_message_actions`, só com a flag); a mensagem diz se a ação cabe nela. São as
// mesmas regras do servidor (Waha::RichNative::MessageActions), que confere de novo.
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../constants';

// Margem sob os 15 minutos do WhatsApp, igual ao servidor.
export const EDIT_WINDOW_SECONDS = 14 * 60;

const actionsOf = conversation =>
  Array.isArray(conversation?.whatsapp_api_message_actions)
    ? conversation.whatsapp_api_message_actions
    : [];

const isDeleted = message => Boolean(message.contentAttributes?.deleted);

export const canReact = (conversation, message) =>
  actionsOf(conversation).includes('react') &&
  [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING].includes(
    message.messageType
  ) &&
  !message.private &&
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
  message.status !== MESSAGE_STATUS.FAILED &&
  !isDeleted(message) &&
  nowSeconds - message.createdAt <= EDIT_WINDOW_SECONDS;

// As reações agrupadas por emoji, na ordem em que apareceram: [{ emoji, count, mine }].
export const groupReactions = (reactions, currentUserId) => {
  const groups = new Map();
  (Array.isArray(reactions) ? reactions : []).forEach(reaction => {
    const emoji = typeof reaction?.emoji === 'string' ? reaction.emoji : '';
    if (!emoji) return;
    const group = groups.get(emoji) ?? { emoji, count: 0, mine: false };
    group.count += 1;
    group.mine =
      group.mine ||
      (reaction.by === 'agent' && reaction.userId === currentUserId);
    groups.set(emoji, group);
  });
  return [...groups.values()];
};

// A reação deste atendente na mensagem ('' quando não reagiu).
export const myReaction = (reactions, currentUserId) =>
  (Array.isArray(reactions) ? reactions : []).find(
    reaction => reaction?.by === 'agent' && reaction.userId === currentUserId
  )?.emoji ?? '';
