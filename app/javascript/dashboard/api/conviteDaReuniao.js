// Resposta ao convite de reunião (#1984). PROTÓTIPO: adaptador falso, sem rede — devolve a
// resposta como se o servidor tivesse confirmado. Na implementação, troca pelo POST
// `/api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id/convite`.
const ESPERA_FALSA = 700;

export default {
  responder(_mensagemId, resposta) {
    return new Promise(resolve => {
      setTimeout(() => resolve({ data: { resposta } }), ESPERA_FALSA);
    });
  },
};
