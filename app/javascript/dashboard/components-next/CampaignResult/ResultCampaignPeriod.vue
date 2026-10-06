<script setup>
// "Como foi esta campanha" (#990): the numbers of THIS campaign for a period, read from
// GET …/campaign_journey/results/email/:id/period. "Desde o início" is the default and matches
// the totals at the top of the Resultado; the account's 7-day protection window lives in
// "Ver detalhes" of the card, never here.
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CampaignResultsAPI from 'dashboard/api/campaignResults';
import { CAMPAIGN_CHANNELS } from 'dashboard/components-next/CampaignJourney/campaignChannels';
import {
  NS as EMAIL_NS,
  displayStatusLabel,
  formatNumber,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';

const props = defineProps({
  campaignId: { type: [String, Number], required: true },
  // Changes when the campaign changes (resumed, re-evaluated), so the numbers are read again.
  version: { type: String, default: '' },
});

const NS = 'RESULT_JOURNEY.EMAIL_HEALTH.PERIOD';
const PERIODS = ['7', '14', '30', 'all'];
const { t, locale } = useI18n();

const period = ref('all');
const metrics = ref(null);
const isLoading = ref(false);
const hasError = ref(false);
let controller = null;

const number = value => formatNumber(value, locale.value);
const rateOfSent = value =>
  typeof value === 'number'
    ? t(`${NS}.RATE_OF_SENT`, {
        rate: t(`${EMAIL_NS}.RATE`, { value: number(value) }),
      })
    : '';

const isEmpty = computed(() => metrics.value?.sent === 0);
const items = computed(() => {
  const m = metrics.value || {};
  return [
    { key: 'sent', label: t(`${EMAIL_NS}.STATUS.sent`), count: m.sent },
    {
      key: 'permanent',
      label: displayStatusLabel(t, 'permanent'),
      count: m.permanent_bounces,
      rate: rateOfSent(m.hard_bounce_rate),
    },
    {
      key: 'temporary',
      label: t(`${EMAIL_NS}.STATUS.temporary`),
      count: m.temporary_bounces,
    },
    {
      key: 'complained',
      label: t(`${EMAIL_NS}.STATUS.complained`),
      count: m.complaints,
      rate: rateOfSent(m.complaint_rate),
    },
  ];
});

const load = async () => {
  controller?.abort();
  controller = new AbortController();
  const { signal } = controller;
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await CampaignResultsAPI.getPeriodMetrics(
      CAMPAIGN_CHANNELS.EMAIL,
      props.campaignId,
      period.value,
      { signal }
    );
    metrics.value = data.payload;
  } catch (error) {
    if (signal.aborted) return;
    metrics.value = null;
    hasError.value = true;
  } finally {
    if (!signal.aborted) isLoading.value = false;
  }
};

const choose = value => {
  if (period.value === value) return;
  period.value = value;
};

watch([() => props.campaignId, () => props.version, period], load, {
  immediate: true,
});
onBeforeUnmount(() => controller?.abort());
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-3"
    aria-labelledby="result-campaign-period-title"
    data-campaign-period
  >
    <div class="flex flex-wrap items-center justify-between gap-2">
      <h3
        id="result-campaign-period-title"
        class="m-0 text-sm font-semibold text-n-slate-12"
      >
        {{ t(`${NS}.TITLE`) }}
      </h3>
      <div
        role="group"
        class="grid w-full grid-cols-2 gap-1 sm:flex sm:w-auto"
        :aria-label="t(`${NS}.FILTER`)"
      >
        <button
          v-for="option in PERIODS"
          :key="option"
          type="button"
          class="min-h-11 rounded-xl px-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            period === option
              ? 'bg-n-blue-3 text-n-blue-11'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          :aria-pressed="period === option"
          :data-period="option"
          @click="choose(option)"
        >
          {{ t(`${NS}.OPTIONS.${option.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <p
      v-if="hasError"
      role="alert"
      class="m-0 text-sm text-n-ruby-11"
      data-period-error
    >
      {{ t(`${NS}.ERROR`) }}
    </p>
    <p
      v-else-if="isEmpty"
      class="m-0 rounded-xl border border-n-weak px-4 py-3 text-sm text-n-slate-11"
      data-period-empty
    >
      {{ t(`${NS}.EMPTY`) }}
    </p>
    <dl
      v-else-if="metrics"
      class="m-0 grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-n-weak bg-n-weak sm:grid-cols-4"
      :class="{ 'opacity-60': isLoading }"
      :aria-busy="isLoading"
      data-period-metrics
    >
      <div
        v-for="item in items"
        :key="item.key"
        class="min-w-0 bg-n-solid-1 px-4 py-3"
        :data-metric="item.key"
      >
        <dt class="text-xs text-n-slate-11">{{ item.label }}</dt>
        <dd class="m-0 mt-1 text-xl font-semibold tabular-nums text-n-slate-12">
          {{ number(item.count) }}
        </dd>
        <dd v-if="item.rate" class="m-0 text-xs text-n-slate-11">
          {{ item.rate }}
        </dd>
      </div>
    </dl>
    <p v-else class="m-0 text-sm text-n-slate-11" data-period-loading>
      {{ t(`${NS}.LOADING`) }}
    </p>
  </section>
</template>
