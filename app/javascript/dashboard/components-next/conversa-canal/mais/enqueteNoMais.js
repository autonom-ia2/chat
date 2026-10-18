// A enquete no "+" (#1702, com o tipo `poll` do #1709). O tipo só existe com a flag
// `whatsapp_rich_native` na conta: sem ela o servidor recusa e o item nem aparece.
// - nativa: a conversa lista 'poll' em `whatsapp_api_rich_native` (caixa WAHA com o
//   conector customizado, plano B do Híbrido), e o cliente vota no WhatsApp;
// - texto: no resto (WhatsApp oficial, que não tem enquete; grupo; motor sem enquete)
//   o cliente recebe a pergunta e as opções numeradas, e a prévia mostra isso.
export const FLAG_DA_ENQUETE = 'whatsapp_rich_native';

export const ENQUETE = { NATIVA: 'nativa', TEXTO: 'texto' };

// A lista vem da conversa do store (snake_case) ou já convertida (camelCase).
export const tiposNativosDaConversa = conversa => {
  const tipos =
    conversa?.whatsapp_api_rich_native ?? conversa?.whatsappApiRichNative;
  return Array.isArray(tipos) ? tipos : [];
};

export const comoSaiAEnquete = ({ flagLigada, conversa }) => {
  if (!flagLigada) return null;
  return tiposNativosDaConversa(conversa).includes('poll')
    ? ENQUETE.NATIVA
    : ENQUETE.TEXTO;
};
