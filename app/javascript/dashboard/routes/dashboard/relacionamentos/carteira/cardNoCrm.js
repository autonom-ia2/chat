// #2898 — para onde leva "Abrir no CRM" da renovação de um seguro: o quadro do
// CRM já com o card aberto (`card_id`, como a ficha da pessoa faz em
// ficha/useAcoesDaFicha.js). Na demonstração o card não existe: abre só o
// quadro.
export const destinoDoCard = (cardId, naDemonstracao = false) => ({
  name: 'crm_kanban_index',
  query: naDemonstracao || !cardId ? undefined : { card_id: String(cardId) },
});
