<script setup>
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import {
  isWhatsAppUnavailable,
  isWhatsAppVerified,
  leadPhoneUrl,
  leadWhatsAppUrl,
} from '../../utils/leadPhone';
import * as formatters from '../../utils/searchFormatters';

defineProps({
  lead: { type: Object, required: true },
});

const { t } = useI18n();
const {
  canManage,
  settings,
  selectedLeadDetailId,
  enrichingLeadId,
  convertingCrmLeadId,
  canCreateCrmCard,
  isWhatsAppChecking,
  enrichLead,
  createCrmCard,
  contactUrl,
  crmCardUrl,
} = useProspectingSearchContext();

const isLeadEnriched = lead => lead?.enrichment_status === 'completed';
const googleMapsLeadUrl = lead => formatters.googleMapsLeadUrl(lead, t);
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
      @click="selectedLeadDetailId = lead.id"
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
        enrichingLeadId === lead.id ||
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
          enrichingLeadId === lead.id
            ? 'animate-spin rounded-full border-2 border-n-slate-5 border-t-n-slate-11'
            : isLeadEnriched(lead)
              ? 'i-lucide-check-circle-2'
              : 'i-lucide-sparkles'
        "
      />
      {{
        enrichingLeadId === lead.id
          ? t('PROSPECTING.SEARCH.ENRICHING')
          : isLeadEnriched(lead)
            ? t('PROSPECTING.SEARCH.ENRICHED')
            : t('PROSPECTING.SEARCH.ENRICH_LEAD')
      }}
    </button>
    <span
      v-if="lead.phone && isWhatsAppChecking(lead)"
      class="inline-flex h-8 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-2 px-3 text-xs font-medium text-n-slate-10"
    >
      <span
        class="size-3 animate-spin rounded-full border-2 border-n-slate-5 border-t-n-slate-11"
      />
      {{ t('PROSPECTING.SEARCH.CHECKING_WHATSAPP') }}
    </span>
    <a
      v-else-if="
        lead.phone && !isWhatsAppUnavailable(lead) && leadWhatsAppUrl(lead)
      "
      :href="leadWhatsAppUrl(lead)"
      target="_blank"
      rel="noopener noreferrer"
      class="inline-flex h-8 items-center gap-1 rounded-md px-3 text-xs font-semibold transition-colors"
      :class="
        isWhatsAppVerified(lead)
          ? 'bg-n-teal-9 text-white shadow-sm hover:bg-n-teal-10'
          : 'border border-n-teal-5 bg-n-solid-1 text-n-teal-11 hover:bg-n-teal-2'
      "
    >
      <span class="i-lucide-message-circle size-3.5" />
      {{ t('PROSPECTING.SEARCH.WHATSAPP') }}
    </a>
    <span
      v-else
      class="inline-flex h-8 cursor-not-allowed items-center gap-1 rounded-md border border-n-weak bg-n-solid-2 px-3 text-xs font-medium text-n-slate-8"
    >
      <span class="i-lucide-message-circle size-3.5" />
      {{ t('PROSPECTING.SEARCH.NO_WHATSAPP') }}
    </span>
    <a
      v-if="leadPhoneUrl(lead)"
      :href="leadPhoneUrl(lead)"
      class="inline-flex h-8 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-3 text-xs font-semibold text-n-slate-12 transition-colors hover:bg-n-solid-2"
    >
      <span class="i-lucide-phone size-3.5" />
      {{ t('PROSPECTING.SEARCH.CALL') }}
    </a>
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
      v-else-if="canManage"
      type="button"
      class="inline-flex h-8 items-center gap-1.5 rounded-md bg-n-brand px-3 text-xs font-semibold text-white shadow-sm disabled:cursor-not-allowed disabled:opacity-60"
      :disabled="convertingCrmLeadId === lead.id || !canCreateCrmCard"
      @click="createCrmCard(lead)"
    >
      <span class="i-lucide-kanban-square size-3.5" />
      {{
        convertingCrmLeadId === lead.id
          ? t('PROSPECTING.SEARCH.CREATING_CRM_CARD')
          : t('PROSPECTING.SEARCH.CREATE_CRM_CARD')
      }}
    </button>
  </div>
</template>
