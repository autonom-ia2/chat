// Qual opção o cliente tocou (chat#1473, P3). A resposta é OUTRA mensagem: a de entrada que aponta a mensagem das
// opções em `content_attributes.in_reply_to` (o Chatwoot grava a partir do `context.id` da Meta) e traz
// `content_attributes.selected_option` ({ id, title }, gravado pelo recebimento do WhatsApp). Vale a mais recente.
// Lê as mensagens da conversa aberta como a loja as guarda, com as chaves da API (snake_case).
import { MESSAGE_TYPES } from '../../constants';

const answerOf = (message, messageId) => {
  const attributes = message?.content_attributes;
  if (message?.message_type !== MESSAGE_TYPES.INCOMING) return null;
  if (attributes?.in_reply_to !== messageId) return null;

  const selected = attributes.selected_option;
  return typeof selected?.id === 'string' ? selected : null;
};

export const selectedOptionFor = (messageId, messages) => {
  if (!Array.isArray(messages)) return null;

  return messages.reduce(
    (latest, message) => answerOf(message, messageId) ?? latest,
    null
  );
};
