// Filtro "Funil" da lista de conversas (multifunil #1150): quando um card muda, a conversa dele na lista relê os funis
// da API (refreshConversationFunnel). Para não virar uma rajada de GETs (mover vários cards no Kanban, várias abas):
// - só pede quando o funil ou o status do card mudou (card novo, ou que esta aba ainda não viu, conta como mudança);
// - espera um instante e junta os avisos da mesma conversa num pedido só.
export const FUNNEL_REFRESH_DEBOUNCE_MS = 300;

const lastSeenCards = new Map();
const timers = new Map();

export const cardFunnelChanged = card => {
  const current = `${card.pipeline_id}:${card.status}`;
  const previous = lastSeenCards.get(card.id);
  lastSeenCards.set(card.id, current);
  return previous !== current;
};

export const scheduleFunnelRefresh = (dispatch, conversationId) => {
  clearTimeout(timers.get(conversationId));
  timers.set(
    conversationId,
    setTimeout(() => {
      timers.delete(conversationId);
      dispatch('refreshConversationFunnel', conversationId);
    }, FUNNEL_REFRESH_DEBOUNCE_MS)
  );
};

// Só para os specs: começa de uma aba recém-aberta.
export const resetFunnelRefresh = () => {
  timers.forEach(timer => clearTimeout(timer));
  timers.clear();
  lastSeenCards.clear();
};
