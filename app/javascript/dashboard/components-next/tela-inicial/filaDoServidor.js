import ConversationApi from 'dashboard/api/inbox/conversation';

// #1801 — os números da tela inicial vêm do servidor, com o filtro "Não atendidas" do próprio
// Chatwoot (Conversation.unattended: sem primeira resposta ou com o cliente esperando).
// Uma chamada só à lista: o meta dela é contado antes do filtro de responsável (o mesmo de
// GET /conversations/meta), e a página traz as minhas, da que espera há mais tempo.
export const CONSULTA_DA_FILA = {
  status: 'open',
  conversationType: 'unattended',
  assigneeType: 'me',
  sortBy: 'waiting_since_asc',
  page: 1,
};

export const buscarFila = async () => {
  const { data } = await ConversationApi.get(CONSULTA_DA_FILA);
  const meta = data?.data?.meta || {};
  const lista = data?.data?.payload || [];
  return {
    esperamVoce: Number(meta.mine_count) || 0,
    esperamAlguem: Number(meta.unassigned_count) || 0,
    proxima: lista[0] || null,
  };
};

// Desde quando o cliente espera: a última mensagem sem resposta; sem ela (conversa ainda sem
// primeira resposta), desde que a conversa começou.
export const esperaDesde = conversa =>
  Number(conversa?.waiting_since) || Number(conversa?.created_at) || 0;
