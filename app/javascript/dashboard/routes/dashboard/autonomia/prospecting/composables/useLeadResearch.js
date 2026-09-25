// Pesquisa de empresa e decisor pela tela (#679). O servidor aceita o pedido
// (202) e pesquisa em fila; o resultado chega pelo evento ao vivo, que troca o
// lead. O progresso da busca sai dos leads na tela.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { researchProgress } from '../utils/leadResearch';

export const useLeadResearch = (state, { replaceLead }) => {
  const { t } = useI18n();
  const { leads, openSearchResearchProgress, researchRequestLeadId } = state;

  const requestLeadResearch = async (lead, { force = false } = {}) => {
    if (!lead?.id || researchRequestLeadId.value) return;

    researchRequestLeadId.value = lead.id;

    try {
      const { data } = await AutonomiaProspectingAPI.researchLead(lead.id, {
        force,
      });
      replaceLead(data.payload?.lead);
      useAlert(t('PROSPECTING.RESEARCH.QUEUED_ALERT'));
    } catch (e) {
      alertError(e, t('PROSPECTING.RESEARCH.REQUEST_ERROR'));
    } finally {
      researchRequestLeadId.value = null;
    }
  };

  return {
    requestLeadResearch,
    researchProgress: computed(() =>
      researchProgress(leads.value, openSearchResearchProgress.value)
    ),
  };
};
