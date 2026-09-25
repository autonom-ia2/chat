// Estado do enriquecimento de um lead na tela (#678). O pedido aceito fica na
// fila do servidor (queued, depois running) até o evento ao vivo trazer o
// resultado; nesse tempo o botão segue em andamento, e não volta a
// "Enriquecer" só porque a resposta 202 já chegou.
const ENRICHMENT_IN_PROGRESS = ['queued', 'running'];

export const isLeadEnriched = lead => lead?.enrichment_status === 'completed';

export const isLeadEnriching = (lead, requestingLeadId) =>
  requestingLeadId === lead?.id ||
  ENRICHMENT_IN_PROGRESS.includes(lead?.enrichment_status);
