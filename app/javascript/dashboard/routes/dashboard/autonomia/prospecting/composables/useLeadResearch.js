// Pesquisa de empresa e decisor pela tela (#679). O servidor aceita o pedido
// (202) e pesquisa em fila; o resultado chega pelo evento ao vivo, que troca o
// lead. O progresso da busca sai dos leads na tela. Usar como contato (#680)
// adota um sócio como decisor e contato; a resposta é o lead inteiro.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { researchProgress } from '../utils/leadResearch';

export const useLeadResearch = (state, { replaceLead }) => {
  const { t } = useI18n();
  const {
    leads,
    openSearchResearchProgress,
    researchRequestLeadId,
    adoptingOwner,
  } = state;

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

  // O servidor diz o que aconteceu com o contato: só "virou a pessoa" afirma a
  // troca. Contato dividido com outro negócio, ou que já era do usuário, fica
  // como estava, e a mensagem diz isso.
  const adoptedMessage = (data, name) => {
    const panel = 'PROSPECTING.RESEARCH.PANEL';
    if (data.contact_outcome === 'shared_with_other_lead') {
      return data.shared_lead_name
        ? t(`${panel}.OWNER_ADOPTED_SHARED_CONTACT`, {
            name,
            other: data.shared_lead_name,
          })
        : t(`${panel}.OWNER_ADOPTED_SHARED_CONTACT_UNNAMED`, { name });
    }
    if (data.contact_outcome === 'kept_existing_contact') {
      return t(`${panel}.OWNER_ADOPTED_KEPT_CONTACT`, { name });
    }
    return t(`${panel}.OWNER_ADOPTED`, { name });
  };

  const adoptOwner = async (lead, owner) => {
    if (!lead?.id || adoptingOwner.value) return;

    adoptingOwner.value = { leadId: lead.id, name: owner.name };

    try {
      const { data } = await AutonomiaProspectingAPI.adoptOwner(
        lead.id,
        owner.name
      );
      replaceLead(data.payload);
      useAlert(adoptedMessage(data, owner.name));
    } catch (e) {
      alertError(e, t('PROSPECTING.RESEARCH.PANEL.ADOPT_ERROR'));
    } finally {
      adoptingOwner.value = null;
    }
  };

  return {
    requestLeadResearch,
    adoptOwner,
    researchProgress: computed(() =>
      researchProgress(leads.value, openSearchResearchProgress.value)
    ),
  };
};
