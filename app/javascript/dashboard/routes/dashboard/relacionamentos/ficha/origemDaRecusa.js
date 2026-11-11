// #2894 — de onde veio o pedido para não receber mensagens, e quando a pessoa
// pode ser liberada pela ficha. Espelha o servidor: só a recusa marcada à mão e a
// que veio da resposta a uma campanha têm tela que a desfaz
// (Api::V1::Accounts::Contacts::OptOutsController::UNDOABLE_SOURCES).
export const ORIGENS_LIBERAVEIS = ['manual', 'campaign_reply'];

const ORIGENS_CONHECIDAS = [
  'manual',
  'campaign_reply',
  'follow_up_reply',
  'email_unsubscribe',
  'prospecting',
];

export const podeLiberar = origem => ORIGENS_LIBERAVEIS.includes(origem);

// A chave de tradução em palavra simples; origem desconhecida cai em "outro".
export const chaveDaOrigem = origem =>
  ORIGENS_CONHECIDAS.includes(origem) ? origem : 'outra';
