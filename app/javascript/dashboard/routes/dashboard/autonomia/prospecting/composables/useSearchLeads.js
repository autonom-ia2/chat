// Trabalho com os leads da busca aberta: card no CRM, enriquecimento, seleção
// e ações em lote. WhatsApp (useLeadWhatsApp) e CSV (useLeadCsv) têm arquivo
// próprio.
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { mergeDisjoint } from '../utils/mergeDisjoint';
import { useLeadCsv } from './useLeadCsv';
import { useLeadWhatsApp } from './useLeadWhatsApp';

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

  return mergeDisjoint(
    {
      replaceLead,
      createCrmCard,
      enrichLead,
      runBulkAction,
      contactUrl,
      crmCardUrl,
    },
    useLeadWhatsApp(state, { canManage, replaceLead }),
    useLeadSelection(state),
    useLeadCsv(state, t)
  );
};
