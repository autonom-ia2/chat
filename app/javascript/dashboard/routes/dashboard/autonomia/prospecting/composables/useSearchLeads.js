// Trabalho com os leads da busca aberta: verificação de WhatsApp, card no CRM,
// enriquecimento, seleção, ações em lote e exportação CSV.
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { normalizedLeadPhone } from '../utils/leadPhone';
import { formatLeadAddress } from '../utils/searchFormatters';

const WHATSAPP_VERIFICATION_BATCH = 25;
const CSV_HEADER = ['name', 'phone', 'website', 'address', 'status', 'source'];

const useWhatsAppVerification = (state, { canManage, replaceLead }) => {
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

const useLeadSelection = state => {
  const { selectedLeadIds, sortedLeads } = state;

  const toggleLeadSelection = leadId => {
    const ids = new Set(selectedLeadIds.value.map(Number));
    if (ids.has(Number(leadId))) {
      ids.delete(Number(leadId));
    } else {
      ids.add(Number(leadId));
    }
    selectedLeadIds.value = [...ids];
  };

  const toggleAllVisibleLeads = () => {
    if (selectedLeadIds.value.length === sortedLeads.value.length) {
      selectedLeadIds.value = [];
      return;
    }

    selectedLeadIds.value = sortedLeads.value.map(lead => lead.id);
  };

  return { toggleLeadSelection, toggleAllVisibleLeads };
};

const useLeadCsv = (state, t) => {
  const { selectedLeadObjects, sortedLeads, selectedSearchId } = state;

  const csvValueFor = (lead, key) => {
    if (key === 'source') return lead.source_label || lead.provider;
    if (key === 'address') return formatLeadAddress(lead, t);
    return lead[key] || '';
  };

  const exportCsv = () => {
    const rows = selectedLeadObjects.value.length
      ? selectedLeadObjects.value
      : sortedLeads.value;
    const header = CSV_HEADER;
    const csvRows = rows.map(lead =>
      header
        .map(key => {
          const value = csvValueFor(lead, key);
          return `"${String(value).replaceAll('"', '""')}"`;
        })
        .join(',')
    );
    const blob = new Blob([[header.join(','), ...csvRows].join('\n')], {
      type: 'text/csv;charset=utf-8;',
    });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `prospeccao-${selectedSearchId.value || 'leads'}.csv`;
    link.click();
    URL.revokeObjectURL(link.href);
  };

  return { exportCsv };
};

export const useSearchLeads = (state, { canManage }) => {
  const { t } = useI18n();
  const route = useRoute();
  const {
    leads,
    convertingCrmLeadId,
    enrichingLeadId,
    bulkAction,
    crmForm,
    canCreateCrmCard,
    hasSelectedLeads,
    selectedLeadObjects,
  } = state;

  const replaceLead = updatedLead => {
    if (!updatedLead?.id) return;
    leads.value = leads.value.map(item =>
      item.id === updatedLead.id ? updatedLead : item
    );
  };

  const createCrmCard = async (lead, options = {}) => {
    if (
      !lead?.id ||
      lead.crm_card_id ||
      convertingCrmLeadId.value ||
      !canCreateCrmCard.value
    ) {
      return;
    }

    convertingCrmLeadId.value = lead.id;

    try {
      const { data } = await AutonomiaProspectingAPI.createLeadCrmCard(
        lead.id,
        {
          pipeline_id: crmForm.value.pipeline_id,
          stage_id: crmForm.value.stage_id,
        }
      );
      replaceLead(data.payload?.lead);
      if (options.showAlert !== false) {
        useAlert(t('PROSPECTING.SEARCH.CRM_CARD_CREATED'));
      }
    } catch (e) {
      alertError(e, t('PROSPECTING.ERRORS.CREATE_CRM_CARD'));
    } finally {
      convertingCrmLeadId.value = null;
    }
  };

  const enrichLead = async lead => {
    if (!lead?.id || enrichingLeadId.value) return;

    enrichingLeadId.value = lead.id;
    replaceLead({ ...lead, enrichment_status: 'running' });

    try {
      const { data } = await AutonomiaProspectingAPI.enrichLead(lead.id);
      replaceLead(data.payload?.lead);
      useAlert(t('PROSPECTING.SEARCH.ENRICHMENT_COMPLETED'));
    } catch (e) {
      replaceLead({ ...lead, enrichment_status: 'failed' });
      alertError(e, t('PROSPECTING.ERRORS.ENRICH_LEAD'));
    } finally {
      enrichingLeadId.value = null;
    }
  };

  const runBulkAction = async action => {
    if (!hasSelectedLeads.value || bulkAction.value) return;

    bulkAction.value = action;

    try {
      if (action === 'crm_cards') {
        await selectedLeadObjects.value
          .filter(item => !item.crm_card_id)
          .reduce(
            (promise, lead) =>
              promise.then(() => createCrmCard(lead, { showAlert: false })),
            Promise.resolve()
          );
        useAlert(t('PROSPECTING.SEARCH.CRM_CARD_CREATED'));
      }
    } finally {
      bulkAction.value = '';
    }
  };

  const contactUrl = contactId =>
    `/app/accounts/${route.params.accountId}/contacts/${contactId}`;

  const crmCardUrl = cardId =>
    `/app/accounts/${route.params.accountId}/crm?card_id=${cardId}`;

  return {
    replaceLead,
    createCrmCard,
    enrichLead,
    runBulkAction,
    contactUrl,
    crmCardUrl,
    ...useWhatsAppVerification(state, { canManage, replaceLead }),
    ...useLeadSelection(state),
    ...useLeadCsv(state, t),
  };
};
