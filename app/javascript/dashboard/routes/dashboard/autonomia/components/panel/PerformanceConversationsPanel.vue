<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ReportDrilldownCard from 'dashboard/routes/dashboard/settings/reports/components/ReportDrilldownCard.vue';

// #284 — the conversation list behind a Performance outcome. `metric` null = closed.
// Records use the reports drilldown envelope, so the same card renders them.
const props = defineProps({
  agentId: { type: [Number, String], required: true },
  range: { type: String, default: '7d' },
  metric: { type: String, default: null },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const panelRef = ref(null);
const records = ref([]);
const meta = ref({});
const isFetching = ref(false);
const hasError = ref(false);
let requestToken = 0;

const title = computed(() =>
  props.metric
    ? t(`AGENTS.PERFORMANCE.OUTCOMES.${props.metric.toUpperCase()}`)
    : ''
);

// The API returns only the most recent `limit` records plus a `has_more` flag
// (no separate total count); the tile already shows the total.
const subtitle = computed(() => {
  const { count, has_more: hasMore, limit } = meta.value;
  if (count === undefined) return '';
  if (hasMore) {
    return t('AGENTS.PERFORMANCE.DRILLDOWN.LIMIT_NOTE', { limit });
  }
  return t('AGENTS.PERFORMANCE.DRILLDOWN.SUBTITLE', { count });
});

const fetchRecords = async () => {
  if (!props.metric) return;
  requestToken += 1;
  const token = requestToken;
  isFetching.value = true;
  hasError.value = false;
  try {
    const { data } = await AutonomiaAgentsAPI.analyticsConversations(
      props.agentId,
      { range: props.range, metric: props.metric }
    );
    if (token !== requestToken) return;
    records.value = data.payload || [];
    meta.value = data.meta || {};
  } catch (error) {
    if (token !== requestToken) return;
    hasError.value = true;
  } finally {
    if (token === requestToken) isFetching.value = false;
  }
};

watch(
  () => [props.metric, props.range],
  ([metric]) => {
    if (!metric) {
      panelRef.value?.close();
      records.value = [];
      meta.value = {};
      return;
    }
    panelRef.value?.open();
    fetchRecords();
  },
  { flush: 'post' }
);

const recordKey = record =>
  `${record.record_type}-${record.conversation?.id}-${record.occurred_at}`;
</script>

<template>
  <SidePanel
    ref="panelRef"
    :title="title"
    :description="subtitle"
    width="xl"
    @close="emit('close')"
  >
    <div v-if="isFetching" class="flex items-center justify-center h-40">
      <Spinner />
    </div>
    <div
      v-else-if="hasError"
      class="flex items-center justify-center h-40 text-sm text-n-ruby-11"
    >
      {{ t('AGENTS.PERFORMANCE.DRILLDOWN.ERROR') }}
    </div>
    <div
      v-else-if="records.length === 0"
      class="flex items-center justify-center h-40 text-sm text-n-slate-10"
    >
      {{ t('AGENTS.PERFORMANCE.DRILLDOWN.EMPTY') }}
    </div>
    <div v-else class="flex flex-col gap-2">
      <ReportDrilldownCard
        v-for="record in records"
        :key="recordKey(record)"
        :record="record"
      />
    </div>
  </SidePanel>
</template>
