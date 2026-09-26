<script setup>
import { useI18n } from 'vue-i18n';
import LeadPhoneActions from './LeadPhoneActions.vue';
import LeadSocialLinks from './LeadSocialLinks.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import * as formatters from '../../utils/searchFormatters';
import { isLeadDiscarded } from '../../utils/leadCrmPresence';
import {
  isLeadEnriched,
  isLeadEnriching as isEnriching,
} from '../../utils/leadEnrichment';

defineProps({
  lead: { type: Object, required: true },
});

const { t } = useI18n();
const {
  canManage,
  canSendToCrm,
  settings,
  selectedLeadDetailId,
  enrichingLeadId,
  enrichLead,
  openCrmSend,
  contactUrl,
  crmCardUrl,
} = useProspectingSearchContext();

const isLeadEnriching = lead => isEnriching(lead, enrichingLeadId.value);
// Link oficial do lugar no Google quando o provider trouxe; senão, busca por
// coordenadas ou nome.
const googleMapsLeadUrl = lead =>
  lead.google_maps_uri || formatters.googleMapsLeadUrl(lead, t);
const toggleDetails = lead => {
  selectedLeadDetailId.value =
    selectedLeadDetailId.value === lead.id ? null : lead.id;
};
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-2 border-t border-n-weak px-4 pb-4 pt-3"
  >
    <a
      :href="googleMapsLeadUrl(lead)"
      target="_blank"
      rel="noopener noreferrer"
      class="inline-flex h-8 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-3 text-xs font-medium text-n-slate-12 hover:bg-n-solid-2"
    >
      <span class="i-lucide-map-pin size-3.5" />
      {{ t('PROSPECTING.SEARCH.OPEN_MAP') }}
    </a>
    <button
      type="button"
      class="inline-flex h-8 items-center gap-1.5 rounded-md border border-n-brand/30 bg-n-brand-2 px-3 text-xs font-semibold text-n-brand hover:bg-n-brand-3"
      :aria-expanded="selectedLeadDetailId === lead.id ? 'true' : 'false'"
      aria-haspopup="dialog"
      @click="toggleDetails(lead)"
    >
      <span class="i-lucide-panel-right-open size-3.5" />
      {{ t('PROSPECTING.SEARCH.OPEN_DETAILS') }}
    </button>
    <button
      v-if="canManage"
      type="button"
      class="inline-flex h-8 items-center gap-1 rounded-md px-3 text-xs font-semibold transition-colors disabled:cursor-not-allowed"
      :class="
        isLeadEnriched(lead)
          ? 'bg-emerald-100 text-emerald-800 ring-1 ring-emerald-200'
          : 'border border-n-weak text-n-slate-12 hover:bg-n-solid-2 disabled:opacity-60'
      "
      :disabled="
        isLeadEnriched(lead) ||
        isLeadEnriching(lead) ||
        !settings?.research_enabled ||
        !lead.website
      "
      :title="
        isLeadEnriched(lead)
          ? t('PROSPECTING.SEARCH.ENRICHED')
          : !settings?.research_enabled
            ? t('PROSPECTING.SEARCH.ENRICHMENT_DISABLED')
            : !lead.website
              ? t('PROSPECTING.SEARCH.ENRICHMENT_NO_SITE')
              : t('PROSPECTING.SEARCH.ENRICH_LEAD')
      "
      @click="enrichLead(lead)"
    >
      <span
        class="size-3.5"
        :class="
          isLeadEnriching(lead)
            ? 'animate-spin rounded-full border-2 border-n-slate-5 border-t-n-slate-11'
            : isLeadEnriched(lead)
              ? 'i-lucide-check-circle-2'
              : 'i-lucide-sparkles'
        "
      />
      {{
        isLeadEnriching(lead)
          ? t('PROSPECTING.SEARCH.ENRICHING')
          : isLeadEnriched(lead)
            ? t('PROSPECTING.SEARCH.ENRICHED')
            : t('PROSPECTING.SEARCH.ENRICH_LEAD')
      }}
    </button>
    <LeadPhoneActions :lead="lead" />
    <LeadSocialLinks :lead="lead" />
    <a
      v-if="lead.contact_id"
      :href="contactUrl(lead.contact_id)"
      class="inline-flex h-8 items-center rounded-md border border-n-weak px-3 text-xs font-medium text-n-brand underline"
    >
      {{ t('PROSPECTING.SEARCH.OPEN_CONTACT') }}
    </a>
    <a
      v-if="lead.crm_card_id"
      :href="crmCardUrl(lead.crm_card_id)"
      class="inline-flex h-8 items-center rounded-md border border-n-weak px-3 text-xs font-medium text-n-brand underline"
    >
      {{ t('PROSPECTING.SEARCH.OPEN_CRM_CARD') }}
    </a>
    <button
      v-else-if="canSendToCrm && !isLeadDiscarded(lead)"
      type="button"
      class="inline-flex h-8 items-center gap-1.5 rounded-md bg-n-brand px-3 text-xs font-semibold text-white shadow-sm"
      @click="openCrmSend([lead])"
    >
      <span class="i-lucide-kanban-square size-3.5" aria-hidden="true" />
      {{ t('PROSPECTING.SEARCH.SEND_TO_CRM') }}
    </button>
    <slot />
  </div>
</template>
