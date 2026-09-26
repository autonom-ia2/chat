// Destinatários que a campanha da API do WhatsApp pulou por motivo nosso, já
// contados em cancelled_count: quem recusou mensagens ativas (chat#737) e quem
// teve o lead descartado na Prospecção com a campanha em andamento (chat#713).
const SKIP_COUNTS = [
  ['opted_out_count', 'CAMPAIGN.WHATSAPP_API.TABLE.OPTED_OUT'],
  ['discarded_count', 'CAMPAIGN.WHATSAPP_API.TABLE.DISCARDED'],
];

export const whatsappApiSkipLines = (campaign, t) =>
  SKIP_COUNTS.filter(([field]) => campaign?.[field] > 0).map(([field, key]) =>
    t(key, { count: campaign[field] })
  );
