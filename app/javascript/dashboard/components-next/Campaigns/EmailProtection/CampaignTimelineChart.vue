<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  NS,
  deliveryKey,
  formatNumber,
  localeTag,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import LineChart from 'shared/components/charts/LineChart.vue';

const props = defineProps({
  series: {
    type: Array,
    default: () => [],
  },
  source: {
    type: Object,
    default: () => ({}),
  },
  interval: {
    type: String,
    default: 'day',
    validator: value => ['day', 'hour'].includes(value),
  },
  loading: Boolean,
  error: Boolean,
});

const emit = defineEmits(['update:interval']);

const { t, locale } = useI18n();

const number = value => formatNumber(value, locale.value);
const deliveryLabel = computed(() =>
  t(`${NS}.STATUS.${deliveryKey(props.source)}`)
);

const intervalOptions = computed(() => [
  { id: 'day', label: t('CAMPAIGN_MANAGEMENT.TIMELINE.INTERVAL.DAY') },
  { id: 'hour', label: t('CAMPAIGN_MANAGEMENT.TIMELINE.INTERVAL.HOUR') },
]);

const bucketDate = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};

const formatBucket = value => {
  const date = bucketDate(value);
  if (!date) return value;

  if (props.interval === 'hour') {
    return new Intl.DateTimeFormat(localeTag(locale.value), {
      day: '2-digit',
      month: 'short',
      hour: '2-digit',
    }).format(date);
  }

  return new Intl.DateTimeFormat(localeTag(locale.value), {
    day: '2-digit',
    month: 'short',
  }).format(date);
};

const hourlySingleDay = computed(() => {
  if (props.interval !== 'hour') return false;
  const days = props.series
    .map(bucket => bucketDate(bucket.bucket))
    .filter(Boolean)
    .map(date => `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`);
  return new Set(days).size <= 1;
});

const formatAxisBucket = value => {
  const date = bucketDate(value);
  if (!date) return value;
  if (props.interval !== 'hour') return formatBucket(value);

  return new Intl.DateTimeFormat(
    localeTag(locale.value),
    hourlySingleDay.value
      ? { hour: '2-digit' }
      : { day: '2-digit', month: '2-digit', hour: '2-digit' }
  ).format(date);
};

const total = key =>
  props.series.reduce((sum, bucket) => {
    const value = Number(bucket?.[key]);
    return Number.isFinite(value) ? sum + value : sum;
  }, 0);

const metrics = computed(() => [
  {
    id: 'delivered',
    label: deliveryLabel.value,
    value: total('delivered'),
    dot: 'bg-[#16a34a]',
  },
  {
    id: 'opened',
    label: t('CAMPAIGN_MANAGEMENT.TABLE.OPENS'),
    value: total('open'),
    dot: 'bg-[#2563eb]',
  },
  {
    id: 'clicked',
    label: t('CAMPAIGN_MANAGEMENT.TABLE.CLICKS'),
    value: total('click'),
    dot: 'bg-[#7c3aed]',
  },
]);

const xTickLabels = computed(() =>
  props.series.map(bucket => formatAxisBucket(bucket.bucket))
);

const collection = computed(() => ({
  labels: props.series.map(bucket => formatBucket(bucket.bucket)),
  datasets: [
    {
      id: 'delivered',
      label: deliveryLabel.value,
      data: props.series.map(bucket => bucket.delivered ?? null),
      borderColor: '#16a34a',
      backgroundColor: '#16a34a',
    },
    {
      id: 'opened',
      label: `${t('CAMPAIGN_MANAGEMENT.TABLE.OPENS')} (${t(
        'CAMPAIGN_MANAGEMENT.APPROXIMATE'
      )})`,
      data: props.series.map(bucket => bucket.open ?? null),
      borderColor: '#2563eb',
      backgroundColor: '#2563eb',
    },
    {
      id: 'clicked',
      label: t('CAMPAIGN_MANAGEMENT.TABLE.CLICKS'),
      data: props.series.map(bucket => bucket.click ?? null),
      borderColor: '#7c3aed',
      backgroundColor: '#7c3aed',
    },
  ],
}));

const xLabelStride = computed(() => {
  if (props.series.length <= 1) return 1;
  const desiredLabels = props.interval === 'hour' ? 3 : 7;
  return Math.max(Math.ceil(props.series.length / desiredLabels), 1);
});

const showDeliveryHint = computed(
  () => deliveryKey(props.source) !== 'delivered'
);
</script>

<template>
  <section
    class="flex flex-col gap-5 p-5 border rounded-xl border-n-weak bg-n-solid-1"
    data-campaign-timeline
  >
    <div
      class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
    >
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('CAMPAIGN_MANAGEMENT.TIMELINE.TITLE') }}
      </h3>

      <div
        class="inline-flex self-start gap-1 p-1 rounded-lg bg-n-alpha-2"
        role="group"
        :aria-label="t('CAMPAIGN_MANAGEMENT.TIMELINE.TITLE')"
      >
        <Button
          v-for="option in intervalOptions"
          :key="option.id"
          :label="option.label"
          :variant="interval === option.id ? 'faded' : 'ghost'"
          :color="interval === option.id ? 'blue' : 'slate'"
          size="sm"
          :aria-pressed="interval === option.id"
          @click="emit('update:interval', option.id)"
        />
      </div>
    </div>

    <p v-if="loading" class="m-0 text-sm text-n-slate-11" role="status">
      {{ t(`${NS}.LOADING`) }}
    </p>
    <p v-else-if="error" class="m-0 text-sm text-n-ruby-11" role="alert">
      {{ t(`${NS}.ERROR`) }}
    </p>
    <p v-else-if="!series.length" class="m-0 text-sm text-n-slate-11">
      {{ t('CAMPAIGN_MANAGEMENT.TIMELINE.EMPTY') }}
    </p>

    <template v-else>
      <div
        class="grid grid-cols-1 gap-3 sm:grid-cols-3 sm:gap-0"
        data-timeline-metrics
      >
        <div
          v-for="(metric, index) in metrics"
          :key="metric.id"
          class="flex min-w-0 items-center gap-3 py-1 sm:px-5"
          :class="{
            'sm:ps-0': index === 0,
            'sm:border-s sm:border-n-weak': index > 0,
          }"
          :data-timeline-metric="metric.id"
        >
          <span
            class="size-2.5 shrink-0 rounded-full"
            :class="metric.dot"
            aria-hidden="true"
          />
          <div class="min-w-0">
            <p class="m-0 text-xs leading-4 text-n-slate-11 sm:text-sm">
              {{ metric.label }}
            </p>
            <strong
              class="block mt-0.5 text-xl font-semibold text-n-slate-12 sm:text-2xl"
            >
              {{ number(metric.value) }}
            </strong>
          </div>
        </div>
      </div>

      <div class="min-w-0" data-timeline-chart>
        <LineChart
          :collection="collection"
          :aria-label="t('CAMPAIGN_MANAGEMENT.TIMELINE.TITLE')"
          :height="280"
          :point-radius="interval === 'hour' ? 3 : 4"
          point-border-color="rgb(var(--solid-1))"
          :show-values="false"
          show-tooltip
          :y-tick-count="5"
          :x-inset="12"
          :x-label-stride="xLabelStride"
          :x-tick-labels="xTickLabels"
          class="![--cw-viz-line-width:0.125rem] [&_.cw-viz-line__axis]:stroke-n-weak [&_.cw-viz-line__tick-mark]:stroke-n-weak [&_.cw-viz-line\_\_tooltip]:!max-w-[22rem] max-sm:[&_.cw-viz-line\_\_tooltip]:!max-w-[calc(100%-1rem)]"
        />
      </div>

      <p
        v-if="showDeliveryHint"
        class="m-0 text-xs text-n-slate-11"
        data-timeline-delivery-hint
      >
        {{ t(`${NS}.DELIVERY_HINT`) }}
      </p>
    </template>
  </section>
</template>
