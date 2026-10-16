// O voto do cliente numa enquete (chat#1709, fase 3). O voto é OUTRA mensagem, que aponta a enquete em
// `content_attributes.in_reply_to` e traz `selected_options` ([{ id, title }], gravado pelo recebimento do WAHA). Vale
// a mais recente: o voto trocado é uma mensagem nova, e o voto retirado é uma atividade escondida com a lista vazia.
// Lê as mensagens da conversa aberta como a loja as guarda (snake_case, em ordem de chegada). Só enxerga o que está
// carregado. Sem `selected_options`, cai no `selected_option` (uma opção só), como a escolha de lista.
import { MESSAGE_TYPES } from '../../constants';

const VOTE_TYPES = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.ACTIVITY];

const isOption = option => typeof option?.id === 'string';

const voteOf = (message, pollId) => {
  const attributes = message?.content_attributes;
  if (!VOTE_TYPES.includes(message?.message_type)) return null;
  if (attributes?.in_reply_to !== pollId) return null;

  if (Array.isArray(attributes.selected_options)) {
    return attributes.selected_options.filter(isOption);
  }
  if (message.message_type !== MESSAGE_TYPES.INCOMING) return null;
  return isOption(attributes.selected_option)
    ? [attributes.selected_option]
    : null;
};

// [{ id, title }] do voto mais recente (vazio = retirado), ou null quando não há voto carregado.
export const pollVoteFor = (pollId, messages) => {
  if (!Array.isArray(messages)) return null;

  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const vote = voteOf(messages[index], pollId);
    if (vote) return vote;
  }
  return null;
};
