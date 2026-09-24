// Frente de telefone: verificação de WhatsApp dos leads da busca aberta, em
// fila, até WHATSAPP_VERIFICATION_BATCH por vez.
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { normalizedLeadPhone } from '../utils/leadPhone';

const WHATSAPP_VERIFICATION_BATCH = 25;

export const useLeadWhatsApp = (state, { canManage, replaceLead }) => {
  const { verifyingWhatsAppLeadIds } = state;
  const whatsappVerificationRequested = new Set();

  const isWhatsAppChecking = lead =>
    verifyingWhatsAppLeadIds.value.map(Number).includes(Number(lead?.id));

  const shouldVerifyWhatsApp = lead =>
    lead?.id &&
    normalizedLeadPhone(lead) &&
    !lead?.whatsapp_verification_status &&
    !whatsappVerificationRequested.has(Number(lead.id));

  async function verifyLeadWhatsApp(lead) {
    if (!shouldVerifyWhatsApp(lead)) return;

    const leadId = Number(lead.id);
    whatsappVerificationRequested.add(leadId);
    verifyingWhatsAppLeadIds.value = [
      ...verifyingWhatsAppLeadIds.value,
      leadId,
    ];

    try {
      const { data } = await AutonomiaProspectingAPI.verifyLeadWhatsApp(
        lead.id
      );
      replaceLead(data.payload?.lead);
    } catch {
      // Falha de WAHA/configuração não deve bloquear o trabalho com o lead.
    } finally {
      verifyingWhatsAppLeadIds.value = verifyingWhatsAppLeadIds.value.filter(
        id => Number(id) !== leadId
      );
    }
  }

  const verifyLeadsWhatsApp = leadsToVerify => {
    if (!canManage.value) return;
    leadsToVerify
      .filter(shouldVerifyWhatsApp)
      .slice(0, WHATSAPP_VERIFICATION_BATCH)
      .reduce(
        (promise, lead) => promise.then(() => verifyLeadWhatsApp(lead)),
        Promise.resolve()
      );
  };

  return { isWhatsAppChecking, verifyLeadsWhatsApp };
};
