<script setup>
import { useI18n } from 'vue-i18n';
import ProspectingPriorityRing from '../ProspectingPriorityRing.vue';
import LeadCardActions from './LeadCardActions.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import {
  leadPrioritySignals,
  priorityTheme,
  priorityValue,
} from '../../utils/prospectingPriority';
import * as formatters from '../../utils/searchFormatters';

defineProps({
  lead: { type: Object, required: true },
});

const DOT_SEPARATOR = '·';

const { t } = useI18n();
const { selectedLeadIds, toggleLeadSelection } = useProspectingSearchContext();

const leadPriority = lead => priorityValue(lead);
const leadPriorityTheme = lead => {
  const priority = leadPriority(lead);
  return priority === null ? null : priorityTheme(priority);
};
const leadSignals = lead => leadPrioritySignals(lead);
const formatLeadAddress = lead => formatters.formatLeadAddress(lead, t);
</script>

<template>
  <article
    class="grid min-w-0 gap-3 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 text-sm transition-colors hover:border-n-slate-5"
  >
    <div class="flex min-w-0 items-start gap-3 p-4 pb-2">
      <ProspectingPriorityRing :priority="leadPriority(lead)" :size="56" />
      <div class="min-w-0 flex-1">
        <div class="flex flex-wrap items-center gap-1.5">
          <span
            v-if="lead.search_rank"
            class="inline-flex items-center rounded bg-n-amber-2 px-1.5 py-0.5 text-[10px] font-bold leading-tight text-n-amber-11 ring-1 ring-n-amber-5"
          >
            {{
              t('PROSPECTING.SEARCH.PRIORITY_GOOGLE_RANK', {
                rank: lead.search_rank,
              })
            }}
          </span>
          <span
            v-if="lead.priority_position"
            class="text-[11px] text-n-slate-10"
          >
            {{
              t('PROSPECTING.SEARCH.PRIORITY_POSITION', {
                position: lead.priority_position,
              })
            }}
          </span>
          <span
            v-if="lead.priority_position === 1"
            class="inline-flex items-center gap-0.5 rounded-full bg-n-teal-2 px-1.5 py-0.5 text-[10px] font-semibold leading-tight text-n-teal-11 ring-1 ring-n-teal-5"
          >
            <span class="i-lucide-zap size-3" />
            {{ t('PROSPECTING.SEARCH.PRIORITY_FIRST_CALL_SHORT') }}
          </span>
        </div>
        <h3
          class="mt-1 break-words text-base font-semibold leading-tight text-n-slate-12"
        >
          {{ lead.name }}
        </h3>
        <div
          class="mt-1 grid min-w-0 max-w-full grid-cols-[auto_auto_minmax(0,1fr)] items-baseline gap-1.5 overflow-hidden"
        >
          <span
            v-if="leadPriorityTheme(lead)"
            class="text-xs font-medium"
            :class="leadPriorityTheme(lead).titleClass"
          >
            {{ leadPriorityTheme(lead).title }}
          </span>
          <span v-if="leadPriorityTheme(lead)" class="text-n-slate-6">
            {{ DOT_SEPARATOR }}
          </span>
          <span class="min-w-0 flex-1 truncate text-sm text-n-slate-10">
            {{ formatLeadAddress(lead) || '-' }}
          </span>
        </div>
      </div>
      <input
        type="checkbox"
        class="mt-1 size-4 shrink-0"
        :checked="selectedLeadIds.map(Number).includes(Number(lead.id))"
        @change="toggleLeadSelection(lead.id)"
      />
    </div>

    <div
      v-if="leadSignals(lead).length"
      class="flex flex-wrap gap-1.5 px-4 pb-2"
    >
      <a
        v-for="signal in leadSignals(lead)"
        v-show="signal.key === 'website' && lead.website"
        :key="`${signal.key}-link`"
        :href="lead.website"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium hover:underline"
        :class="signal.card"
      >
        <span :class="[signal.icon, signal.iconClass]" class="size-3" />
        {{ signal.label }}
      </a>
      <span
        v-for="signal in leadSignals(lead).filter(
          item => item.key !== 'website' || !lead.website
        )"
        :key="signal.key"
        class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium"
        :class="signal.card"
      >
        <span :class="[signal.icon, signal.iconClass]" class="size-3" />
        {{ signal.label }}
      </span>
    </div>

    <div
      v-if="
        lead.enrichment_status === 'completed' ||
        lead.decision_name ||
        lead.enrichment_summary
      "
      class="mx-4 mb-3 grid gap-2 rounded-md border border-emerald-100 bg-emerald-50/70 p-3 text-xs text-emerald-950"
    >
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-[11px] font-semibold text-emerald-800 ring-1 ring-emerald-200"
        >
          <span class="i-lucide-sparkles size-3" />
          {{ t('PROSPECTING.SEARCH.ENRICHMENT_TITLE') }}
        </span>
        <span class="text-[11px] font-medium text-emerald-700">
          {{ t('PROSPECTING.SEARCH.ENRICHMENT_COMPLETED') }}
        </span>
      </div>
      <div v-if="lead.decision_name" class="leading-relaxed">
        <span class="font-semibold text-emerald-950">
          {{ `${t('PROSPECTING.SEARCH.DECISION_MAKER')}:` }}
        </span>
        {{ lead.decision_name }}
        <span v-if="lead.decision_role">
          {{ `· ${lead.decision_role}` }}
        </span>
      </div>
      <div
        v-if="lead.enrichment_summary"
        class="whitespace-pre-line break-words leading-relaxed"
      >
        {{ lead.enrichment_summary }}
      </div>
    </div>

    <LeadCardActions :lead="lead" />
  </article>
</template>
