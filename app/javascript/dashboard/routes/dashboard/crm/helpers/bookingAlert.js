import { skipReasonKey } from './meetingNotices';

// Alerta do agendamento ao responsável (#1291). O backend (`Notices::AgentAlert`)
// chama a pessoa pelo caminho dos lembretes do CRM: uma tarefa que vence na hora.
// No cartão do painel ela não é um retorno atrasado, então é reconhecida pelo
// `metadata.source` e mostrada com texto próprio. Lembrete comum devolve `null`.
export const BOOKING_ALERT_SOURCE = 'booking_agent_alert';

const NOTICE_FAILED = 'notice_failed';

export const bookingAlert = reminder => {
  const metadata = reminder?.metadata;
  if (metadata?.source !== BOOKING_ALERT_SOURCE) return null;

  const reasonKey = skipReasonKey(metadata.reason);

  return {
    isNoticeFailed: metadata.event === NOTICE_FAILED,
    name: metadata.contact_name || '',
    startsAt: metadata.starts_at || '',
    // Motivo com texto próprio; erro do envio (classe do erro, interrupted,
    // delivery_failed) e alerta antigo sem motivo viram null.
    reasonKey: reasonKey === 'OTHER' ? null : reasonKey,
  };
};
