// #2138 — incluir ou tirar só a própria pessoa de quem acompanha a conversa.
// A API de participantes grava a LISTA INTEIRA (PATCH user_ids), então a lista é
// lida do servidor na hora, nunca do que a tela guardou: sem isso, quem uma colega
// incluiu há pouco sairia junto. Sem a leitura, não se grava nada.
import ConversationInboxApi from 'dashboard/api/inbox/conversation';

// A lista nova a partir da lista lida: os outros continuam como estão.
export const listaAoAcompanhar = ({ atuais, euId, acompanhar }) => {
  const outros = atuais.filter(id => id !== euId);
  return acompanhar ? [...outros, euId] : outros;
};

export const lerQuemAcompanha = async conversationId => {
  const { data } = await ConversationInboxApi.fetchParticipants(conversationId);
  if (!Array.isArray(data)) throw new Error('lista de quem acompanha ilegível');
  return data.map(pessoa => pessoa.id);
};

// Devolve a lista gravada (ids). `gravar` é a action de hoje
// (conversationWatchers/update), que também guarda a resposta no store.
export const mudarAcompanhar = async ({
  conversationId,
  euId,
  acompanhar,
  gravar,
}) => {
  const atuais = await lerQuemAcompanha(conversationId);
  const userIds = listaAoAcompanhar({ atuais, euId, acompanhar });
  const igual =
    userIds.length === atuais.length &&
    userIds.every(id => atuais.includes(id));
  if (!igual) await gravar({ conversationId, userIds });
  return userIds;
};
