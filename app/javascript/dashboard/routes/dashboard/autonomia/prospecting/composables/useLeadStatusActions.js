// Descartar, desfazer o descarte, "Não quer ser contatado" (chat#713) e criar
// contatos em lote (#732, item 10). A busca e as Listas usam o mesmo: cada uma
// entrega o replaceLead dela, que troca o lead onde ele aparece na tela.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { sendInBatches } from '../utils/crmSend';
import { isLeadDiscarded } from '../utils/leadCrmPresence';

export const useLeadStatusActions = ({ replaceLead }) => {
  const { t } = useI18n();
  const creatingContacts = ref(false);

  // A recusa sobe para a janela de descarte, que mostra a frase do servidor.
  const discardLeads = async (leadIds, reason) => {
    const { data } = await AutonomiaProspectingAPI.discardLeads({
      leadIds,
      reason,
    });
    (data.payload?.leads || []).forEach(replaceLead);
    return data.payload;
  };

  const restoreLead = async lead => {
    try {
      const { data } = await AutonomiaProspectingAPI.updateLead(lead.id, {
        status: 'new_lead',
      });
      replaceLead(data.payload);
      useAlert(t('PROSPECTING.LEAD_STATUS.RESTORED'));
    } catch (e) {
      alertError(e, t('PROSPECTING.LEAD_STATUS.RESTORE_ERROR'));
    }
  };

  // "Não quer ser contatado" e o desfazer (chat#713). A confirmação é da tela;
  // aqui só o pedido, a troca do lead e o aviso.
  const setConsentRefusal = async (lead, refused) => {
    const key = refused ? 'REFUSE' : 'WITHDRAW';
    try {
      const { data } = refused
        ? await AutonomiaProspectingAPI.refuseLeadConsent(lead.id)
        : await AutonomiaProspectingAPI.withdrawLeadConsentRefusal(lead.id);
      replaceLead(data.payload);
      useAlert(t(`PROSPECTING.CONSENT_REFUSAL.${key}.DONE`));
    } catch (e) {
      alertError(e, t(`PROSPECTING.CONSENT_REFUSAL.${key}.ERROR`));
    }
  };
  const refuseConsent = lead => setConsentRefusal(lead, true);
  const withdrawConsentRefusal = lead => setConsentRefusal(lead, false);

  // Lotes de até 30, como o envio ao CRM. Descartado não vira contato (o
  // servidor também recusa). O lead que ganhou contato mostra "Abrir contato".
  const createContacts = async leads => {
    const eligible = leads.filter(lead => !isLeadDiscarded(lead));
    if (creatingContacts.value || !eligible.length) return;

    creatingContacts.value = true;
    try {
      const summary = await sendInBatches(
        eligible.map(lead => lead.id),
        batch => AutonomiaProspectingAPI.createLeadContacts(batch)
      );
      const byId = new Map(eligible.map(lead => [Number(lead.id), lead]));
      [...summary.created, ...summary.existing].forEach(item => {
        const lead = byId.get(Number(item.lead_id));
        if (lead) replaceLead({ ...lead, contact_id: item.contact_id });
      });
      useAlert(
        t('PROSPECTING.BULK.CONTACTS_RESULT', {
          created: summary.created.length,
          existing: summary.existing.length,
          failed: summary.failed.length,
        })
      );
    } finally {
      creatingContacts.value = false;
    }
  };

  return {
    creatingContacts,
    discardLeads,
    restoreLead,
    refuseConsent,
    withdrawConsentRefusal,
    createContacts,
  };
};
