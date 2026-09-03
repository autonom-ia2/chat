<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PerformanceOutcomes from './PerformanceOutcomes.vue';
import PerformanceConversationsPanel from './PerformanceConversationsPanel.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();

const analytics = useMapGetter('autonomiaAnalytics/getAnalytics');
const uiFlags = useMapGetter('autonomiaAnalytics/getUIFlags');

const range = ref('7d');

const load = () =>
  store.dispatch('autonomiaAnalytics/fetch', {
    agentId: props.agent.id,
    range: range.value,
  });

const setRange = r => {
  if (range.value === r) return;
  range.value = r;
  load();
};

// Reload on mount and whenever the agent or range changes. The host page swaps
// <component :is> WITHOUT a :key, so this component is reused across agents — an
// immediate watcher (not onMounted) is what reloads when props.agent.id changes.
watch([() => props.agent.id, range], load, { immediate: true });

// Formats a 0..1 ratio as a whole percentage, or "—" when null/undefined.
const pct = v => (v == null ? '—' : `${Math.round(v * 100)}%`);

// Only treat as data when the loaded payload matches BOTH the current agent and
// range, so neither the previous range's content nor another agent's data flashes
// while a new request is in flight (the component is reused across agents).
const data = computed(() =>
  analytics.value &&
  analytics.value.range === range.value &&
  analytics.value.agentId === props.agent.id
    ? analytics.value
    : null
);

const isLoading = computed(() => uiFlags.value.fetching);
const isError = computed(() => uiFlags.value.error);
const isEmpty = computed(() => {
  const a = data.value;
  return !!a && a.replies_sent + a.handoff_count === 0;
});

const stats = computed(() => {
  const a = data.value;
  if (!a) return [];
  return [
    {
      key: 'conversations',
      icon: 'i-lucide-messages-square',
      label: t('AGENTS.PERFORMANCE.STATS.CONVERSATIONS'),
      value: a.conversations_handled,
    },
    {
      key: 'replies',
      icon: 'i-lucide-send',
      label: t('AGENTS.PERFORMANCE.STATS.REPLIES'),
      value: a.replies_sent,
    },
    {
      key: 'handoff_rate',
      icon: 'i-lucide-user-round',
      label: t('AGENTS.PERFORMANCE.STATS.HANDOFF_RATE'),
      value: pct(a.handoff_rate),
    },
    {
      key: 'avg_confidence',
      icon: 'i-lucide-gauge',
      label: t('AGENTS.PERFORMANCE.STATS.AVG_CONFIDENCE'),
      value: pct(a.avg_confidence),
    },
    {
      key: 'knowledge_rate',
      icon: 'i-lucide-book-open',
      label: t('AGENTS.PERFORMANCE.STATS.KNOWLEDGE_RATE'),
      value: pct(a.knowledge_answer_rate),
    },
  ];
});

// Fixed Tailwind height classes so timeline bars stay Tailwind-only with no
// inline styles. Only Tailwind default-scale heights are used (13/15 are not in
// the default scale and would not emit), giving a 12-step ladder up to h-16.
const HEIGHT_CLASSES = [
  'h-0',
  'h-1',
  'h-2',
  'h-3',
  'h-4',
  'h-5',
  'h-6',
  'h-8',
  'h-10',
  'h-12',
  'h-14',
  'h-16',
];

const timelineMax = computed(() => {
  const a = data.value;
  if (!a) return 0;
  return a.timeline.reduce((max, p) => Math.max(max, p.replies, p.handoffs), 0);
});

// Short day/month label for the timeline x-axis ends and the per-bar aria text.
// Intl only (no date lib); falls back to the raw ISO if it can't be parsed.
const shortDate = iso => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat(undefined, {
    day: '2-digit',
    month: 'short',
  }).format(d);
};

// Maps a count to a height class proportional to the busiest day in the range.
const barClass = count => {
  const max = timelineMax.value;
  const last = HEIGHT_CLASSES.length - 1;
  if (!max || !count) return HEIGHT_CLASSES[0];
  const step = Math.max(1, Math.round((count / max) * last));
  return HEIGHT_CLASSES[step];
};

const topReasons = computed(() => data.value?.top_handoff_reasons ?? []);
// reason is an allowlisted code (low_confidence, ai_unavailable, ...) — map it to a
// human label via static i18n keys; unknown/blank falls back to "Other / unspecified".
const REASON_LABEL_KEYS = {
  low_confidence: 'AGENTS.PERFORMANCE.REASONS.CODES.low_confidence',
  ai_unavailable: 'AGENTS.PERFORMANCE.REASONS.CODES.ai_unavailable',
  human_requested: 'AGENTS.PERFORMANCE.REASONS.CODES.human_requested',
  missing_knowledge: 'AGENTS.PERFORMANCE.REASONS.CODES.missing_knowledge',
  policy: 'AGENTS.PERFORMANCE.REASONS.CODES.policy',
  other: 'AGENTS.PERFORMANCE.REASONS.OTHER',
};
const reasonLabel = reason =>
  t(REASON_LABEL_KEYS[reason] ?? 'AGENTS.PERFORMANCE.REASONS.OTHER');

const insight = computed(() => data.value?.insight ?? null);
const insightTitle = computed(() => {
  if (!insight.value) return '';
  return insight.value.type === 'high_handoff'
    ? t('AGENTS.PERFORMANCE.INSIGHT.HIGH_HANDOFF_TITLE')
    : t('AGENTS.PERFORMANCE.INSIGHT.LOW_KNOWLEDGE_TITLE');
});
// Specific reason codes drive the actionable body; 'other'/blank carry no topic
// to act on, so they're dropped — when nothing specific remains the generic line shows.
const insightReasons = computed(
  () =>
    insight.value?.top_reasons?.filter(r => r.reason && r.reason !== 'other') ??
    []
);
const hasInsightReasons = computed(() => insightReasons.value.length > 0);

const rangeOptions = computed(() => [
  { value: '7d', label: t('AGENTS.PERFORMANCE.RANGE.7D') },
  { value: '30d', label: t('AGENTS.PERFORMANCE.RANGE.30D') },
]);

// #284 — clicking an outcome number opens the conversation list for that metric.
const drilldownMetric = ref(null);
const openDrilldown = metric => {
  drilldownMetric.value = metric;
};
const closeDrilldown = () => {
  drilldownMetric.value = null;
};
</script>

<template>
  <div class="flex flex-col w-full h-full max-w-3xl gap-6 px-6 py-6 mx-auto">
    <div class="flex items-center justify-end">
      <div class="inline-flex p-1 rounded-lg bg-n-alpha-1">
        <button
          v-for="option in rangeOptions"
          :key="option.value"
          type="button"
          :aria-pressed="range === option.value"
          class="px-3 py-1 text-xs font-medium rounded-md transition-colors"
          :class="
            range === option.value
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="setRange(option.value)"
        >
          {{ option.label }}
        </button>
      </div>
    </div>

    <div
      v-if="isLoading && !data"
      class="flex items-center justify-center flex-1 py-12"
    >
      <Spinner :size="24" />
    </div>

    <div
      v-else-if="isError"
      class="flex flex-col items-center justify-center flex-1 gap-3 px-6 py-12 text-center border border-dashed rounded-xl border-n-weak"
    >
      <Icon icon="i-lucide-circle-alert" class="text-3xl text-n-ruby-9" />
      <p class="text-sm text-n-slate-11">
        {{ t('AGENTS.PERFORMANCE.ERROR') }}
      </p>
      <NextButton
        outline
        slate
        sm
        :label="t('AGENTS.PERFORMANCE.RETRY')"
        @click="load"
      />
    </div>

    <div
      v-else-if="isEmpty"
      class="flex flex-col items-center justify-center flex-1 gap-3 px-6 py-12 text-center border border-dashed rounded-xl border-n-weak"
    >
      <Icon icon="i-lucide-bar-chart-3" class="text-3xl text-n-slate-10" />
      <p class="max-w-md text-sm text-n-slate-11">
        {{ t('AGENTS.PERFORMANCE.EMPTY') }}
      </p>
    </div>

    <template v-else-if="data">
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div
          v-for="stat in stats"
          :key="stat.key"
          class="flex flex-col gap-2 px-4 py-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <Icon :icon="stat.icon" class="text-n-slate-11" />
          <span class="text-xl font-medium text-n-slate-12">{{
            stat.value
          }}</span>
          <span class="text-xs text-n-slate-10">{{ stat.label }}</span>
        </div>
      </div>

      <PerformanceOutcomes
        :outcomes="data.outcomes || {}"
        @select="openDrilldown"
      />

      <div
        class="flex flex-col gap-4 px-4 py-4 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('AGENTS.PERFORMANCE.TIMELINE.TITLE') }}
          </h3>
          <div class="flex items-center gap-3 text-xs text-n-slate-10">
            <span class="flex items-center gap-1.5">
              <span class="inline-block w-2 h-2 rounded-full bg-n-blue-9" />
              {{ t('AGENTS.PERFORMANCE.TIMELINE.REPLIES') }}
            </span>
            <span class="flex items-center gap-1.5">
              <span class="inline-block w-2 h-2 rounded-full bg-n-amber-9" />
              {{ t('AGENTS.PERFORMANCE.TIMELINE.HANDOFFS') }}
            </span>
          </div>
        </div>
        <div class="flex items-end justify-between h-16 gap-px">
          <div
            v-for="point in data.timeline"
            :key="point.date"
            class="flex items-end justify-center flex-1 h-full gap-px"
            :title="point.date"
            role="img"
            :aria-label="
              t('AGENTS.PERFORMANCE.TIMELINE.BAR_ARIA', {
                date: shortDate(point.date),
                replies: point.replies,
                handoffs: point.handoffs,
              })
            "
          >
            <span
              class="w-full max-w-[6px] rounded-sm bg-n-blue-9"
              :class="barClass(point.replies)"
              aria-hidden="true"
            />
            <span
              class="w-full max-w-[6px] rounded-sm bg-n-amber-9"
              :class="barClass(point.handoffs)"
              aria-hidden="true"
            />
          </div>
        </div>
        <div
          v-if="data.timeline.length"
          class="flex items-center justify-between text-xs text-n-slate-10"
          aria-hidden="true"
        >
          <span>{{ shortDate(data.timeline[0].date) }}</span>
          <span>{{ shortDate(data.timeline.at(-1).date) }}</span>
        </div>
      </div>

      <div
        class="flex flex-col gap-3 px-4 py-4 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('AGENTS.PERFORMANCE.REASONS.TITLE') }}
        </h3>
        <p v-if="topReasons.length === 0" class="text-sm text-n-slate-10">
          {{ t('AGENTS.PERFORMANCE.REASONS.EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="(row, index) in topReasons"
            :key="index"
            class="flex items-center justify-between gap-3 text-sm"
          >
            <span class="truncate text-n-slate-11">{{
              reasonLabel(row.reason)
            }}</span>
            <span class="font-medium text-n-slate-12">{{ row.count }}</span>
          </li>
        </ul>
      </div>

      <div
        v-if="insight"
        class="flex gap-3 px-4 py-4 border rounded-xl border-n-amber-6 bg-n-amber-2"
      >
        <Icon
          icon="i-lucide-lightbulb"
          class="flex-shrink-0 mt-0.5 text-n-amber-11"
        />
        <div class="flex flex-col gap-2">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ insightTitle }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{
              hasInsightReasons
                ? t('AGENTS.PERFORMANCE.INSIGHT.BODY')
                : t('AGENTS.PERFORMANCE.INSIGHT.BODY_GENERIC')
            }}
          </p>
          <ul
            v-if="hasInsightReasons"
            class="flex flex-col gap-1 pl-4 text-sm list-disc text-n-slate-11"
          >
            <li v-for="(row, index) in insightReasons" :key="index">
              {{ reasonLabel(row.reason) }}
            </li>
          </ul>
        </div>
      </div>
    </template>

    <PerformanceConversationsPanel
      :agent-id="agent.id"
      :range="range"
      :metric="drilldownMetric"
      @close="closeDrilldown"
    />
  </div>
</template>
