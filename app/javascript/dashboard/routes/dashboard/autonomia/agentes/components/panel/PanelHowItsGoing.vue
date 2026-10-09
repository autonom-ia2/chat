<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';
import PanelConversationsDrawer from './PanelConversationsDrawer.vue';

const props = defineProps({
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  canOpenConversation: { type: Boolean, default: false },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const range = ref('7d');
const status = ref('idle');
const error = ref(null);
const data = ref(null);
const selectedMetric = ref(null);
const timelineScrollRef = ref(null);
const { run, abort } = useAbortableRequest();

const isInternal = computed(() => props.agent.actuation === 'internal');
const isQuote = computed(() => props.agent.agent_type === 'insurance_quote');

const scrollTimelineToRecent = () => {
  const element = timelineScrollRef.value;
  if (!element || typeof window === 'undefined') return;

  const isMobile = window.matchMedia?.('(max-width: 1023px)')?.matches ?? true;
  if (!isMobile || element.scrollWidth <= element.clientWidth) return;

  element.scrollLeft = element.scrollWidth;
};

const load = async () => {
  if (isInternal.value) {
    abort();
    status.value = 'success';
    data.value = null;
    error.value = null;
    return;
  }

  status.value = 'loading';
  error.value = null;
  data.value = null;

  try {
    const response = await run(signal =>
      AutonomiaAgentsAPI.analytics(props.agent.id, {
        range: range.value,
        signal,
      })
    );
    if (!response) return;
    data.value = response.data;
    status.value = 'success';
    await nextTick();
    scrollTimelineToRecent();
  } catch (requestError) {
    if (isAbortError(requestError)) return;
    status.value = 'error';
    error.value = requestError;
  }
};

watch(
  [() => props.agent.id, range, isInternal],
  () => {
    selectedMetric.value = null;
    load();
  },
  { immediate: true }
);

const hasActivity = computed(() => {
  const analytics = data.value;
  return Boolean(
    analytics &&
      (Number(analytics.replies_sent || 0) > 0 ||
        Number(analytics.handoff_count || 0) > 0)
  );
});

const isEmptyWeek = computed(
  () => !hasActivity.value && data.value?.range === '7d'
);

const pct = value =>
  value == null
    ? t('AGENTS.PANEL.REDESIGN_PERFORMANCE.NO_DATA')
    : `${Math.round(Number(value) * 100)}%`;

const stats = computed(() => {
  if (!data.value) return [];
  const base = [
    {
      key: 'conversations',
      icon: 'i-lucide-messages-square',
      label: t('AGENTS.PANEL.REDESIGN_PERFORMANCE.CONVERSATIONS_HANDLED'),
      value: data.value.conversations_handled,
    },
    {
      key: 'replies',
      icon: 'i-lucide-send',
      label: t('AGENTS.PANEL.REDESIGN_PERFORMANCE.REPLIES_SENT'),
      value: data.value.replies_sent,
    },
    {
      key: 'handoff',
      icon: 'i-lucide-user-round',
      label: t('AGENTS.PANEL.REDESIGN_PERFORMANCE.HANDOFF_RATE', {
        count: data.value.handoff_count ?? 0,
      }),
      value: pct(data.value.handoff_rate),
    },
    {
      key: 'confidence',
      icon: 'i-lucide-sparkles',
      label: t('AGENTS.PANEL.REDESIGN_PERFORMANCE.AVG_CONFIDENCE'),
      value: pct(data.value.avg_confidence),
    },
  ];

  if (!isQuote.value) {
    base.push({
      key: 'knowledge',
      icon: 'i-lucide-book-open',
      label: t('AGENTS.PANEL.REDESIGN_PERFORMANCE.KNOWLEDGE_RATE'),
      value: pct(data.value.knowledge_answer_rate),
    });
  }

  return base;
});

const outcomeMetrics = [
  { key: 'handled', icon: 'i-lucide-messages-square' },
  { key: 'resolved_without_human', icon: 'i-lucide-check-circle-2' },
  { key: 'handed_off', icon: 'i-lucide-user-round' },
  { key: 'reopened', icon: 'i-lucide-rotate-ccw' },
  { key: 'wrong_replies', icon: 'i-lucide-thumbs-down' },
];

const outcomes = computed(() =>
  outcomeMetrics.map(metric => ({
    ...metric,
    label: t(`AGENTS.PERFORMANCE.OUTCOMES.${metric.key.toUpperCase()}`),
    value: data.value?.outcomes?.[metric.key] ?? 0,
  }))
);

const reasonLabel = reason =>
  t(`AGENTS.PERFORMANCE.REASONS.CODES.${reason}`, {
    defaultValue: t('AGENTS.PERFORMANCE.REASONS.OTHER'),
  });

const dateLabel = value => {
  if (!value) return '';
  const [year, month, day] = value.split('-');
  return year && month && day ? `${day}/${month}` : value;
};

const maxTimeline = computed(() =>
  Math.max(
    1,
    ...(data.value?.timeline || []).map(point =>
      Math.max(Number(point.replies || 0), Number(point.handoffs || 0))
    )
  )
);

const BAR_HEIGHT_CLASSES = [
  'h-0',
  'h-1/5',
  'h-2/5',
  'h-3/5',
  'h-4/5',
  'h-full',
];

const barHeightClass = value => {
  const amount = Number(value || 0);
  if (!amount) return BAR_HEIGHT_CLASSES[0];

  const index = Math.min(
    BAR_HEIGHT_CLASSES.length - 1,
    Math.ceil((amount / maxTimeline.value) * (BAR_HEIGHT_CLASSES.length - 1))
  );
  return BAR_HEIGHT_CLASSES[index];
};

const timelineTotals = computed(() =>
  (data.value?.timeline || []).reduce(
    (totals, point) => ({
      replies: totals.replies + Number(point.replies || 0),
      handoffs: totals.handoffs + Number(point.handoffs || 0),
    }),
    { replies: 0, handoffs: 0 }
  )
);

const openMetric = metric => {
  selectedMetric.value = metric;
};

const closeDrawer = () => {
  selectedMetric.value = null;
};

const openConversation = () => {
  if (!props.canOpenConversation) return;
  router.push({ name: 'home', params: { accountId: route.params.accountId } });
};

const openTest = () => {
  router.push({
    name: 'autonomia_agent_panel',
    params: { agentId: props.agent.id, tab: 'test' },
  });
};
</script>

<template>
  <section
    class="flex flex-col w-full max-w-6xl gap-5 px-4 py-6 mx-auto sm:px-6 lg:px-8"
    data-testid="agent-performance"
  >
    <div
      class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
    >
      <div>
        <h2 class="text-xl font-semibold text-n-slate-12">
          {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.TITLE') }}
        </h2>
        <p class="mt-1 text-sm leading-5 text-n-slate-11">
          {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.DESCRIPTION') }}
        </p>
      </div>
      <div
        v-if="!isInternal"
        class="inline-flex self-start p-1 rounded-lg bg-n-alpha-1"
        role="group"
        :aria-label="t('AGENTS.PERFORMANCE.RANGE.LABEL')"
      >
        <button
          v-for="period in ['7d', '30d']"
          :key="period"
          type="button"
          class="min-h-11 px-3 text-sm font-medium rounded-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            range === period
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          :aria-pressed="range === period"
          :data-testid="`agent-analytics-range-${period}`"
          @click="range = period"
        >
          {{ t(`AGENTS.PERFORMANCE.RANGE.${period.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <div
      v-if="isInternal"
      class="flex flex-col items-start gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1"
      data-state="internal"
      data-testid="agent-internal-summary"
    >
      <div class="flex items-start gap-3">
        <span
          class="flex items-center justify-center shrink-0 rounded-xl size-10 bg-n-iris-3 text-n-iris-11"
          aria-hidden="true"
        >
          <span class="i-lucide-message-circle-heart size-5" />
        </span>
        <div>
          <h3 class="text-base font-semibold text-n-slate-12">
            {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.INTERNAL_TITLE') }}
          </h3>
          <p class="mt-1 text-sm leading-5 text-n-slate-11">
            {{
              t('AGENTS.PANEL.REDESIGN_PERFORMANCE.INTERNAL_DESCRIPTION', {
                name: agent.name,
              })
            }}
          </p>
        </div>
      </div>
      <button
        v-if="canOpenConversation"
        type="button"
        class="inline-flex items-center justify-center min-h-11 gap-2 px-4 text-sm font-semibold rounded-lg bg-n-blue-11 text-white dark:text-n-navy hover:bg-n-blue-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        data-action="open-conversation"
        @click="openConversation"
      >
        <span class="i-lucide-message-square size-4" aria-hidden="true" />
        {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.OPEN_CONVERSATION') }}
      </button>
      <p v-else class="text-sm text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.INTERNAL_NO_ACCESS') }}
      </p>
    </div>

    <div
      v-if="status === 'loading'"
      class="grid gap-4"
      aria-busy="true"
      :aria-label="t('AGENTS.PANEL.LOADING')"
      data-state="loading"
      data-testid="agent-performance-loading"
    >
      <span class="sr-only">{{ t('AGENTS.PANEL.LOADING') }}</span>
      <div class="h-28 rounded-xl animate-pulse bg-n-solid-3" />
      <div class="h-64 rounded-xl animate-pulse bg-n-solid-3" />
    </div>

    <div
      v-else-if="status === 'error'"
      class="grid gap-3"
      role="alert"
      data-testid="agent-performance-error"
    >
      <p class="text-sm text-n-ruby-11">
        {{ t('AGENTS.PERFORMANCE.ERROR') }}
      </p>
      <button
        type="button"
        class="inline-flex items-center justify-center self-start min-h-11 gap-2 px-4 text-sm font-semibold rounded-lg border border-n-weak text-n-slate-12 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        data-action="retry"
        data-testid="agent-performance-retry"
        @click="load"
      >
        <span class="i-lucide-refresh-cw size-4" aria-hidden="true" />
        {{ t('AGENTS.PERFORMANCE.RETRY') }}
      </button>
    </div>

    <template v-else-if="!isInternal && data">
      <div
        v-if="!hasActivity && isEmptyWeek"
        class="flex flex-col items-center gap-3 p-8 text-center border border-dashed rounded-xl border-n-weak"
        data-state="empty-week"
        data-testid="agent-performance-empty"
      >
        <span
          class="flex items-center justify-center rounded-full size-12 bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="i-lucide-sparkles size-6" />
        </span>
        <p class="max-w-lg text-sm leading-6 text-n-slate-11">
          <span class="sr-only">
            {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.NO_DATA') }}
          </span>
          {{ t('AGENTS.PERFORMANCE.REDESIGN_EMPTY_WEEK') }}
        </p>
        <button
          type="button"
          class="inline-flex items-center justify-center min-h-11 px-4 text-sm font-semibold rounded-lg bg-n-blue-11 text-white dark:text-n-navy hover:bg-n-blue-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-action="show-30-days"
          @click="range = '30d'"
        >
          {{ t('AGENTS.PERFORMANCE.EMPTY_WEEK_ACTION') }}
        </button>
      </div>

      <div
        v-else-if="!hasActivity"
        class="flex flex-col items-center gap-3 p-8 text-center border border-dashed rounded-xl border-n-weak"
        data-state="empty-total"
        data-testid="agent-performance-empty"
      >
        <span
          class="flex items-center justify-center rounded-full size-12 bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="i-lucide-sparkles size-6" />
        </span>
        <p class="max-w-lg text-sm leading-6 text-n-slate-11">
          <span class="sr-only">
            {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.NO_DATA') }}
          </span>
          {{ t('AGENTS.PERFORMANCE.EMPTY') }}
        </p>
        <button
          type="button"
          class="inline-flex items-center justify-center min-h-11 px-4 text-sm font-semibold rounded-lg bg-n-blue-11 text-white dark:text-n-navy hover:bg-n-blue-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-action="open-test"
          @click="openTest"
        >
          {{ t('AGENTS.PERFORMANCE.EMPTY_TOTAL_ACTION') }}
        </button>
      </div>

      <template v-else>
        <div
          class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5"
          data-testid="agent-external-summary"
        >
          <article
            v-for="stat in stats"
            :key="stat.key"
            class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <span class="flex items-center gap-2 text-xs text-n-slate-11">
              <span :class="stat.icon" class="size-4" aria-hidden="true" />
              {{ stat.label }}
            </span>
            <strong class="text-2xl font-semibold tabular-nums text-n-slate-12">
              {{ stat.value ?? t('AGENTS.PANEL.REDESIGN_PERFORMANCE.NO_DATA') }}
            </strong>
          </article>
        </div>

        <section
          v-if="
            data.insight && !(isQuote && data.insight.type === 'low_knowledge')
          "
          class="flex items-start gap-3 p-4 border rounded-xl border-n-blue-6 bg-n-blue-2"
        >
          <span
            class="i-lucide-lightbulb size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          <div class="text-sm leading-5 text-n-blue-12">
            <h3 class="font-semibold">
              {{
                data.insight.type === 'low_knowledge'
                  ? t('AGENTS.PERFORMANCE.INSIGHT.LOW_KNOWLEDGE_TITLE')
                  : t('AGENTS.PERFORMANCE.INSIGHT.HIGH_HANDOFF_TITLE')
              }}
            </h3>
            <p class="mt-1">
              {{
                data.insight.type === 'low_knowledge'
                  ? t('AGENTS.PERFORMANCE.INSIGHT.BODY_GENERIC')
                  : t('AGENTS.PERFORMANCE.INSIGHT.BODY')
              }}
            </p>
            <button
              v-if="canManage && data.insight.type === 'low_knowledge'"
              type="button"
              class="mt-3 font-semibold underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="
                router.push({
                  name: 'autonomia_agent_panel',
                  params: { agentId: agent.id, tab: 'knowledge' },
                })
              "
            >
              {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.TEACH') }}
            </button>
          </div>
        </section>

        <section
          v-if="data.outcomes"
          class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div>
            <h3 class="text-sm font-semibold text-n-slate-12">
              {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.OUTCOMES_TITLE') }}
            </h3>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.OUTCOMES_HINT') }}
            </p>
          </div>
          <div class="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-5">
            <button
              v-for="outcome in outcomes"
              :key="outcome.key"
              type="button"
              class="flex flex-col items-start gap-1 p-3 text-left border rounded-lg border-n-weak hover:border-n-brand hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :data-metric="outcome.key"
              :data-testid="`agent-outcome-${outcome.key}`"
              @click="openMetric(outcome.key)"
            >
              <Icon :icon="outcome.icon" class="text-n-slate-11" />
              <strong
                class="text-xl font-medium tabular-nums text-n-slate-12"
                data-testid="agent-outcome-count"
              >
                {{ outcome.value }}
              </strong>
              <span class="text-xs text-n-slate-11">{{ outcome.label }}</span>
            </button>
          </div>
        </section>

        <section class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <div class="flex items-center justify-between gap-3 mb-4">
            <h3 class="text-sm font-semibold text-n-slate-12">
              {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.TIMELINE_TITLE') }}
            </h3>
            <span class="text-xs text-n-slate-11">
              {{
                data.range === '30d'
                  ? t('AGENTS.PERFORMANCE.RANGE.30D')
                  : t('AGENTS.PERFORMANCE.RANGE.7D')
              }}
            </span>
          </div>
          <div
            class="overflow-x-auto focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            data-timeline-scroll
            ref="timelineScrollRef"
            role="region"
            tabindex="0"
            :aria-label="t('AGENTS.PANEL.REDESIGN_PERFORMANCE.TIMELINE_TITLE')"
          >
            <div
              class="flex items-end min-w-max gap-3 h-36 lg:w-full lg:min-w-0 lg:gap-1"
              role="img"
              data-testid="agent-timeline"
              :aria-label="
                t('AGENTS.PERFORMANCE.TIMELINE.TOTALS_ARIA', {
                  replies: timelineTotals.replies,
                  handoffs: timelineTotals.handoffs,
                  period:
                    data.range === '30d'
                      ? t('AGENTS.PERFORMANCE.RANGE.30D')
                      : t('AGENTS.PERFORMANCE.RANGE.7D'),
                })
              "
            >
              <div
                v-for="(point, index) in data.timeline || []"
                :key="point.date"
                class="flex flex-col items-center justify-end gap-2 w-8 shrink-0 lg:flex-1 lg:min-w-0 lg:w-auto"
                role="img"
                :aria-label="
                  t('AGENTS.PERFORMANCE.TIMELINE.BAR_ARIA', {
                    date: dateLabel(point.date),
                    replies: point.replies || 0,
                    handoffs: point.handoffs || 0,
                  })
                "
              >
                <div class="flex items-end justify-center w-full h-28 gap-1">
                  <span
                    class="w-2 rounded-t bg-n-blue-9"
                    :class="barHeightClass(point.replies)"
                    aria-hidden="true"
                  />
                  <span
                    class="w-2 rounded-t bg-n-amber-9"
                    :class="barHeightClass(point.handoffs)"
                    aria-hidden="true"
                  />
                </div>
                <span
                  v-if="
                    index === 0 || index === (data.timeline || []).length - 1
                  "
                  class="text-[0.6875rem] text-n-slate-11"
                >
                  {{ dateLabel(point.date) }}
                </span>
              </div>
            </div>
          </div>
          <div class="flex flex-wrap gap-4 mt-4 text-xs text-n-slate-11">
            <span class="inline-flex items-center gap-1.5">
              <span
                class="size-2 rounded-full bg-n-blue-9"
                aria-hidden="true"
              />
              {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.TIMELINE_REPLIES') }}
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span
                class="size-2 rounded-full bg-n-amber-9"
                aria-hidden="true"
              />
              {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.TIMELINE_HANDOFFS') }}
            </span>
          </div>
        </section>

        <section class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ t('AGENTS.PANEL.REDESIGN_PERFORMANCE.REASONS_TITLE') }}
          </h3>
          <p
            v-if="!data.top_handoff_reasons?.length"
            class="mt-3 text-sm text-n-slate-11"
            data-state="empty-reasons"
          >
            {{ t('AGENTS.PERFORMANCE.REASONS.EMPTY') }}
          </p>
          <ul v-else class="grid gap-2 mt-3 sm:grid-cols-2">
            <li
              v-for="reason in data.top_handoff_reasons"
              :key="reason.reason"
              class="flex items-center justify-between gap-4 text-sm"
            >
              <span class="text-n-slate-11">{{
                reasonLabel(reason.reason)
              }}</span>
              <strong class="tabular-nums text-n-slate-12">{{
                reason.count
              }}</strong>
            </li>
          </ul>
        </section>
      </template>
    </template>
  </section>

  <PanelConversationsDrawer
    :agent-id="agent.id"
    :range="range"
    :metric="selectedMetric"
    :can-manage="canManage"
    :allow-teach="!isQuote"
    @close="closeDrawer"
  />
</template>
