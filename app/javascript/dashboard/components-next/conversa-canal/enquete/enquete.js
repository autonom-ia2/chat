// Enquete do WhatsApp (#1702). A enquete chega com
// content_attributes.rich_message = { type: 'poll', options: [{ id, title }], multiple }
// (pergunta no texto da mensagem; `name`/`multiple_answers` também valem)
// e os votos ficam agregados nela em content_attributes.poll_votes =
// [{ sender_type, sender_id, options: [títulos], at }], um por eleitor (o último voto vale).
// Aqui só se conta o que veio.

export const ehEnquete = atributos =>
  atributos?.richMessage?.type === 'poll' &&
  Array.isArray(atributos.richMessage.options);

export const votosDaEnquete = atributos =>
  (Array.isArray(atributos?.pollVotes) ? atributos.pollVotes : []).filter(
    voto => voto && Array.isArray(voto.options)
  );

// Uma linha por opção: quantos votos, a fração da barra (do total de eleitores, como
// no app) e quem votou.
export const apurarEnquete = atributos => {
  const opcoes = atributos?.richMessage?.options || [];
  const votos = votosDaEnquete(atributos);
  const eleitores = votos.filter(voto => voto.options.length > 0).length;
  return opcoes.map(opcao => {
    const quem = votos.filter(voto => voto.options.includes(opcao.title));
    return {
      id: opcao.id ?? opcao.title,
      titulo: opcao.title,
      votos: quem.length,
      fracao: eleitores ? quem.length / eleitores : 0,
      quem,
    };
  });
};

export const totalDeEleitores = atributos =>
  votosDaEnquete(atributos).filter(voto => voto.options.length > 0).length;
