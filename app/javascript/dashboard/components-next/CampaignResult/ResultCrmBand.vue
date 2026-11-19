<script setup>
// "Quem respondeu já aparece no CRM com a marca Campanha: <nome>" + "Ver no CRM" (#1007, PRD §6.5),
// which opens the Kanban filtered by this campaign's mark (K6 filter of #1002).
// #3063: what the campaign turned into there — cards, won and, for who sees sales values, the R$ of the won
// (on a renewal whose new policy arrived, its premium).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { crmKanbanRoute, wonValueText } from './resultMetrics';

const props = defineProps({
  name: { type: String, required: true },
  crm: { type: Object, default: () => ({}) },
});

const { t, locale } = useI18n();
const route = computed(() => crmKanbanRoute(props.crm.source_id));
const deals = computed(() => props.crm.deals || null);
const dealsText = computed(() => {
  if (!deals.value) return '';
  const number = new Intl.NumberFormat(locale.value.replace('_', '-'));
  return t('RESULT_JOURNEY.CRM.DEALS', {
    cards: number.format(deals.value.cards),
    won: number.format(deals.value.won),
  });
});
const wonValue = computed(() =>
  deals.value
    ? wonValueText(deals.value.won_value, locale.value.replace('_', '-'))
    : null
);
</script>

<template>
  <section
    class="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-n-blue-6 bg-n-blue-2 px-5 py-4"
    data-crm-band
  >
    <p
      class="mb-0 flex min-w-0 flex-wrap items-center gap-2 text-sm text-n-slate-12"
    >
      <span
        class="inline-flex rounded-full bg-n-blue-3 px-2 py-0.5 text-xs font-semibold text-n-blue-11"
      >
        {{ t('RESULT_JOURNEY.CRM.PILL') }}
      </span>
      <span class="min-w-0 break-words">
        {{ t('RESULT_JOURNEY.CRM.BAND') }}
        <strong>{{ t('RESULT_JOURNEY.CRM.MARK', { name }) }}</strong>
      </span>
    </p>
    <p
      v-if="deals"
      class="mb-0 flex min-w-0 flex-wrap items-baseline gap-x-3 gap-y-1 text-sm text-n-slate-11"
      data-crm-deals
    >
      <strong
        v-if="wonValue"
        class="text-lg font-semibold tabular-nums text-n-slate-12"
        data-crm-won-value
      >
        {{ t('RESULT_JOURNEY.CRM.WON_VALUE', { value: wonValue }) }}
      </strong>
      <span class="tabular-nums">{{ dealsText }}</span>
    </p>
    <router-link
      v-if="crm.enabled && crm.source_id"
      :to="route"
      class="flex min-h-11 items-center gap-1 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      data-crm-link
    >
      {{ t('RESULT_JOURNEY.CRM.OPEN') }}
      <span class="i-lucide-arrow-right size-4" aria-hidden="true" />
    </router-link>
  </section>
</template>
