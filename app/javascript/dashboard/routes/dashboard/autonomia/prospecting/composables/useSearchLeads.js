// Trabalho com os leads da busca aberta: envio ao CRM, enriquecimento, seleção
// e ações em lote. WhatsApp (useLeadWhatsApp) e exportação (useLeadExport) têm arquivo
// próprio.
import { watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { mergeDisjoint } from '../utils/mergeDisjoint';
import { mergeLeadResearch } from '../utils/leadResearch';

// Campos que o servidor grava por busca (lead_ranks e lead_scoring, #678).
const SEARCH_SCOPED_FIELDS = [
  'search_rank',
  'score',
  'score_breakdown',
  'priority_score',
  'priority_position',
];

const pickSearchScopedFields = lead =>
  Object.fromEntries(
    SEARCH_SCOPED_FIELDS.filter(field => field in lead).map(field => [
      field,
      lead[field],
    ])
  );
import { useLeadResearch } from './useLeadResearch';
import { useLeadExport } from './useLeadExport';
import { useLeadLiveUpdates } from './useLeadLiveUpdates';
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

  // O contador é o que vai (ACAO-X02): lead que o filtro esconde sai da
  // seleção, em vez de ficar contado e não ser enviado nem exportado.
  watch(
    () => sortedLeads.value.map(lead => Number(lead.id)),
    visibleIds => {
      const visible = new Set(visibleIds);
      const kept = selectedLeadIds.value.filter(id => visible.has(Number(id)));
      if (kept.length !== selectedLeadIds.value.length) {
        selectedLeadIds.value = kept;
      }
    }
  );

  return { toggleLeadSelection, toggleAllVisibleLeads };
};

// Janela Enviar ao CRM (#680): abre com os leads escolhidos e aplica o
// resultado de cada um. Lead que foi (criado ou já existente) ganha o link do
// card e sai da seleção; o que falhou continua selecionado para tentar de novo.
const useCrmSend = state => {
  const { leads, crmSendLeads, selectedLeadIds } = state;

  const openCrmSend = leadsToSend => {
    crmSendLeads.value = leadsToSend;
  };

  const closeCrmSend = () => {
    crmSendLeads.value = null;
  };

  const applyCrmSendResult = ({ created, existing }) => {
    const sent = new Map(
      [...created, ...existing].map(item => [Number(item.lead_id), item])
    );
    leads.value = leads.value.map(lead => {
      const item = sent.get(Number(lead.id));
      if (!item) return lead;
      return {
        ...lead,
        crm_card_id: item.card_id,
        contact_id: item.contact_id || lead.contact_id,
      };
    });
    selectedLeadIds.value = selectedLeadIds.value.filter(
      id => !sent.has(Number(id))
    );
  };

  return { openCrmSend, closeCrmSend, applyCrmSendResult };
};

export const useSearchLeads = (state, { canManage }) => {
  const { t } = useI18n();
  const route = useRoute();
  const { leads, enrichingLeadId } = state;

  // Toda resposta da API (evento, enriquecimento, pesquisa, WhatsApp) traz
  // o lead da conta, com posição, nota e prioridade da última busca que o
  // tocou. Esses campos são desta busca (#678) e ficam.
  // A pesquisa de empresa e decisor (#679) não regride: resposta atrasada não
  // desfaz o resultado que o evento já trouxe.
  const replaceLead = updatedLead => {
    if (!updatedLead?.id) return;
    leads.value = leads.value.map(item =>
      item.id === updatedLead.id
        ? mergeLeadResearch(item, {
            ...updatedLead,
            ...pickSearchScopedFields(item),
          })
        : item
    );
  };

  useLeadLiveUpdates(replaceLead);

  // O servidor aceita o pedido (202) e enriquece em fila; o resultado chega
  // pelo evento ao vivo (#678). Pedido recusado deixa o lead como estava.
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

  const contactUrl = contactId =>
    `/app/accounts/${route.params.accountId}/contacts/${contactId}`;

  const crmCardUrl = cardId =>
    `/app/accounts/${route.params.accountId}/crm?card_id=${cardId}`;

  return mergeDisjoint(
    {
      replaceLead,
      enrichLead,
      contactUrl,
      crmCardUrl,
    },
    useLeadWhatsApp(state, { canManage, replaceLead }),
    useLeadResearch(state, { replaceLead }),
    useLeadSelection(state),
    useCrmSend(state),
    useLeadExport(state, t)
  );
};
