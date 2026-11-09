// Motivos gravados pelo backend quando o contato recusou mensagens ativas (chat#737) ou
// está bloqueado (chat#2733).
export const OPTED_OUT_REASON = 'opted_out';
export const BLOCKED_REASON = 'blocked';

export const rawDeliveryReason = delivery =>
  delivery.error_message || delivery.error_title || delivery.error_code || '';

// Códigos nossos viram texto traduzido; mensagens do provedor aparecem como vieram.
export const deliveryReason = (delivery, t) => {
  const reason = rawDeliveryReason(delivery);
  if (reason === OPTED_OUT_REASON) {
    return t('CAMPAIGN.WHATSAPP.ANALYTICS.TABLE.REASON_OPTED_OUT');
  }
  if (reason === BLOCKED_REASON) {
    return t('CAMPAIGN.WHATSAPP.ANALYTICS.TABLE.REASON_BLOCKED');
  }
  return reason;
};
