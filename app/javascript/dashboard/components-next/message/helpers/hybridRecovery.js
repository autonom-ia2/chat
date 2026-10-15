// chat#1489: a mensagem que a Cloud entregou como "não suportada" é buscada no
// celular pelo WhatsApp API. O estado fica em contentAttributes.hybridRecovery.
const STATE_KEYS = {
  pending: 'CONVERSATION.HYBRID_RECOVERY.PENDING',
  recovered: 'CONVERSATION.HYBRID_RECOVERY.RECOVERED',
  failed: 'CONVERSATION.HYBRID_RECOVERY.FAILED',
};
const MEDIA_KEY = 'CONVERSATION.HYBRID_RECOVERY.MEDIA';

// Chave i18n do aviso da recuperação, ou null quando a mensagem não passou por ela.
export const hybridRecoveryNoteKey = contentAttributes => {
  const state = contentAttributes?.hybridRecovery;
  if (
    state === 'failed' &&
    contentAttributes.hybridRecoveryReason === 'media'
  ) {
    return MEDIA_KEY;
  }
  return STATE_KEYS[state] || null;
};
