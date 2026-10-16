// Os votos de uma enquete (chat#1709; formato da tela do Frontend geral, #1702). Ficam AGREGADOS na própria enquete,
// em `content_attributes.poll_votes` (aqui `contentAttributes.pollVotes`): [{ senderType, senderId, options: [títulos],
// at }], um por eleitor; o voto novo substitui o anterior, e o voto retirado fica com `options` vazio. A mensagem do
// voto em si é uma atividade escondida, que a conversa não mostra.

const titlesOf = vote =>
  (Array.isArray(vote?.options) ? vote.options : []).filter(
    title => typeof title === 'string' && title
  );

// Os títulos votados (de todos os eleitores, sem repetir; vazio = votos retirados), ou null quando ninguém votou.
export const pollVotedTitles = pollVotes => {
  const votes = Array.isArray(pollVotes) ? pollVotes : [];
  if (!votes.length) return null;

  return [...new Set(votes.flatMap(titlesOf))];
};
