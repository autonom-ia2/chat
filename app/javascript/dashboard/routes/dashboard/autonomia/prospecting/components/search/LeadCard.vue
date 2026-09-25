<script setup>
// Card do lead nos resultados, como o do Orth (ResultsTable.tsx): anel,
// selos de posição, bairro, sinais, telefone com selo de verificado e ações.
// O card inteiro abre e fecha o painel; clique em botão, link ou caixa de
// seleção dentro dele segue com a própria ação.
// A tela de Listas (#682) usa o mesmo card, sem a caixa de seleção e com as
// ações dela no slot "actions".
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ProspectingPriorityRing from '../ProspectingPriorityRing.vue';
import LeadCardActions from './LeadCardActions.vue';
import LeadResearchSummary from './LeadResearchSummary.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import {
  leadPrioritySignals,
  priorityTheme,
  priorityValue,
} from '../../utils/prospectingPriority';
import { isWhatsAppVerified, leadPhoneDisplay } from '../../utils/leadPhone';
import { phoneRegionFromSettings } from '../../utils/phoneContract';
import * as formatters from '../../utils/searchFormatters';

const props = defineProps({
  lead: { type: Object, required: true },
  selectable: { type: Boolean, default: true },
});

const DOT_SEPARATOR = '·';
const NESTED_INTERACTIVE =
  'a, button, input, select, textarea, label, [role="checkbox"]';

const { t } = useI18n();
const {
  selectedLeadIds,
  toggleLeadSelection,
  selectedLeadDetailId,
  selectedSearch,
  settings,
} = useProspectingSearchContext();

const priority = computed(() => priorityValue(props.lead));
const theme = computed(() =>
  priority.value === null ? null : priorityTheme(priority.value)
);
const signals = computed(() =>
  leadPrioritySignals(props.lead, {
    t,
    scoreMode: selectedSearch.value?.score_mode,
  })
);
const location = computed(
  () =>
    props.lead.neighborhood ||
    formatters.formatLeadAddress(props.lead, t) ||
    '-'
);
const phone = computed(() =>
  leadPhoneDisplay(props.lead, phoneRegionFromSettings(settings.value))
);
const isChecked = computed(() =>
  selectedLeadIds.value.map(Number).includes(Number(props.lead.id))
);
const isOpen = computed(() => selectedLeadDetailId.value === props.lead.id);
// Com a pesquisa (#679), o decisor vem dela; o do enriquecimento por IA fica
// só para lead antigo, sem o bloco research.
const legacyDecisionName = computed(() =>
  props.lead.research ? null : props.lead.decision_name
);

const toggleDetails = event => {
  if (event.target.closest(NESTED_INTERACTIVE)) return;
  selectedLeadDetailId.value = isOpen.value ? null : props.lead.id;
};
</script>

<template>
  <article
    class="grid min-w-0 cursor-pointer gap-3 overflow-hidden rounded-lg border bg-n-solid-1 text-sm transition-colors"
    :class="
      isOpen
        ? 'border-n-brand ring-1 ring-n-brand'
        : 'border-n-weak hover:border-n-slate-5'
    "
    @click="toggleDetails"
  >
    <div class="flex min-w-0 items-start gap-3 p-4 pb-2">
      <ProspectingPriorityRing :priority="priority" :size="56" />
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
            v-if="theme"
            class="text-xs font-medium"
            :class="theme.titleClass"
          >
            {{ theme.title }}
          </span>
          <span v-if="theme" class="text-n-slate-6">
            {{ DOT_SEPARATOR }}
          </span>
          <span class="min-w-0 flex-1 truncate text-sm text-n-slate-10">
            {{ location }}
          </span>
        </div>
      </div>
      <input
        v-if="selectable"
        type="checkbox"
        class="mt-1 size-4 shrink-0"
        :checked="isChecked"
        :aria-label="
          isChecked
            ? t('PROSPECTING.SEARCH.DESELECT_LEAD')
            : t('PROSPECTING.SEARCH.SELECT_LEAD')
        "
        @change="toggleLeadSelection(lead.id)"
      />
    </div>

    <div v-if="signals.length" class="flex flex-wrap gap-1.5 px-4 pb-2">
      <component
        :is="signal.href ? 'a' : 'span'"
        v-for="signal in signals"
        :key="signal.key"
        :href="signal.href || undefined"
        :target="signal.href ? '_blank' : undefined"
        :rel="signal.href ? 'noopener noreferrer' : undefined"
        class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium"
        :class="[signal.card, { 'hover:underline': signal.href }]"
      >
        <span :class="[signal.icon, signal.iconClass]" class="size-3" />
        {{ signal.label }}
      </component>
    </div>

    <div
      v-if="phone"
      data-test="lead-phone"
      class="flex flex-wrap items-center gap-1.5 px-4 pb-2 text-xs"
    >
      <span class="font-medium text-n-slate-11">{{ phone }}</span>
      <span
        v-if="isWhatsAppVerified(lead)"
        class="inline-flex items-center gap-0.5 text-[11px] font-medium text-n-teal-11"
      >
        <span class="i-lucide-check size-3" />
        {{ t('PROSPECTING.SEARCH.WHATSAPP_VERIFIED') }}
      </span>
    </div>

    <LeadResearchSummary
      v-if="lead.research"
      :research="lead.research"
      :research-enabled="Boolean(settings?.research_enabled)"
    />

    <div
      v-if="
        lead.enrichment_status === 'completed' ||
        legacyDecisionName ||
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
      <div
        v-if="legacyDecisionName"
        data-test="lead-legacy-decision"
        class="leading-relaxed"
      >
        <span class="font-semibold text-emerald-950">
          {{ `${t('PROSPECTING.SEARCH.DECISION_MAKER')}:` }}
        </span>
        {{ legacyDecisionName }}
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

    <LeadCardActions :lead="lead">
      <slot name="actions" />
    </LeadCardActions>
  </article>
</template>
