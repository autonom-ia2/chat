// Contexto dos leads na tela de Listas (#682): o mesmo que LeadCard,
// LeadDetailDrawer e LeadPhoneActions leem na busca, montado com os leads da
// lista aberta. Pesquisa, WhatsApp e destino no CRM usam os composables da
// busca; o que só existe na busca (seleção em lote, busca aberta) fica de fora.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { provideProspectingLeadContext } from './useProspectingSearch';
import { useLeadLiveUpdates } from './useLeadLiveUpdates';
import { useLeadResearch } from './useLeadResearch';
import { useLeadWhatsApp } from './useLeadWhatsApp';
import { useSearchCrm } from './useSearchCrm';

// Troca o lead onde ele aparece na tela: na lista aberta e no catálogo do
// modal de adicionar.
const useListLeadReplacement = ({ allLeads, selectedList }) => {
  const replaceLead = updatedLead => {
    if (!updatedLead?.id) return;
    const swap = lead => (lead.id === updatedLead.id ? updatedLead : lead);

    allLeads.value = allLeads.value.map(swap);
    if (selectedList.value?.leads) {
      selectedList.value = {
        ...selectedList.value,
        leads: selectedList.value.leads.map(swap),
      };
    }
  };

  // Enriquecimento, pesquisa e WhatsApp terminam no servidor e chegam pelo
  // evento (#678).
  useLeadLiveUpdates(replaceLead);
  return replaceLead;
};

const useListEnrichment = replaceLead => {
  const { t } = useI18n();
  const enrichingLeadId = ref(null);

  const enrichLead = async lead => {
    if (!lead?.id || enrichingLeadId.value) return;

    enrichingLeadId.value = lead.id;
    try {
      const { data } = await AutonomiaProspectingAPI.enrichLead(lead.id);
      replaceLead(data.payload?.lead);
      useAlert(t('PROSPECTING.SEARCH.ENRICHMENT_QUEUED'));
    } catch (e) {
      alertError(e, t('PROSPECTING.ERRORS.ENRICH_LEAD'));
    } finally {
      enrichingLeadId.value = null;
    }
  };

  return { enrichingLeadId, enrichLead };
};

export const useListLeadsContext = ({
  canManage,
  settings,
  allLeads,
  selectedList,
  crmSendLeads,
}) => {
  const route = useRoute();
  const listLeads = computed(() => selectedList.value?.leads || []);
  const selectedLeadDetailId = ref(null);
  const crm = {
    settings,
    crmPipelines: ref([]),
    crmStages: ref([]),
    crmForm: ref({ pipeline_id: '', stage_id: '' }),
  };
  const replaceLead = useListLeadReplacement({ allLeads, selectedList });
  const { fetchCrmPipelines } = useSearchCrm(crm);
  const research = {
    researchRequestLeadId: ref(null),
    adoptingOwner: ref(null),
  };
  const { requestLeadResearch, adoptOwner } = useLeadResearch(
    { ...research, leads: listLeads, openSearchResearchProgress: ref(null) },
    { replaceLead }
  );
  const whatsapp = useLeadWhatsApp(
    { verifyingWhatsAppLeadIds: ref([]), settings },
    { canManage, replaceLead }
  );

  const context = {
    canManage,
    settings,
    // Lista não é uma busca: sem modo de nota da busca, os sinais saem como
    // na lista antes do #682.
    selectedSearch: computed(() => null),
    selectedLeadDetailId,
    selectedLeadDetail: computed(() =>
      listLeads.value.find(lead => lead.id === selectedLeadDetailId.value)
    ),
    crmStages: crm.crmStages,
    crmForm: crm.crmForm,
    ...useListEnrichment(replaceLead),
    ...research,
    requestLeadResearch,
    adoptOwner,
    isWhatsAppChecking: whatsapp.isWhatsAppChecking,
    openCrmSend: leadsToSend => {
      crmSendLeads.value = leadsToSend;
    },
    contactUrl: contactId =>
      `/app/accounts/${route.params.accountId}/contacts/${contactId}`,
    crmCardUrl: cardId =>
      `/app/accounts/${route.params.accountId}/crm?card_id=${cardId}`,
  };
  provideProspectingLeadContext(context);

  return {
    ...context,
    replaceLead,
    fetchCrmPipelines,
    verifyLeadsWhatsApp: whatsapp.verifyLeadsWhatsApp,
  };
};
