<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import ReportDrilldownCard from 'dashboard/routes/dashboard/settings/reports/components/ReportDrilldownCard.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';

const props = defineProps({
  agentId: { type: [Number, String], required: true },
  range: { type: String, default: '7d' },
  metric: { type: String, default: null },
  canManage: { type: Boolean, default: false },
  allowTeach: { type: Boolean, default: true },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const panelRef = ref(null);
const records = ref([]);
const meta = ref({});
const status = ref('idle');
const error = ref(null);
const { run, abort } = useAbortableRequest();

const title = computed(() =>
  props.metric
    ? t(`AGENTS.PERFORMANCE.OUTCOMES.${props.metric.toUpperCase()}`)
    : ''
);

const description = computed(() => {
  const count = meta.value.count ?? 0;
  const days = props.range === '30d' ? 30 : 7;
  const subtitle = t('AGENTS.PERFORMANCE.DRILLDOWN.SUBTITLE_PERIOD', {
    count,
    days,
  });
  if (!meta.value.has_more) return subtitle;

  return `${subtitle} · ${t('AGENTS.PERFORMANCE.DRILLDOWN.LIMIT_NOTE', {
    limit: meta.value.limit || 50,
  })}`;
});

const fetchRecords = async () => {
  if (!props.metric) return;

  status.value = 'loading';
  error.value = null;
  records.value = [];
  meta.value = {};

  try {
    const response = await run(signal =>
      AutonomiaAgentsAPI.analyticsConversations(props.agentId, {
        range: props.range,
        metric: props.metric,
        signal,
      })
    );
    if (!response) return;
    const payload = response.data;
    records.value = payload.payload;
    meta.value = payload.meta;
    status.value = 'success';
  } catch (requestError) {
    if (isAbortError(requestError)) return;
    status.value = 'error';
    error.value = requestError;
  }
};

const onPanelClose = () => {
  abort();
  status.value = 'idle';
  emit('close');
};

watch(
  [() => props.metric, () => props.range, () => props.agentId],
  async ([metric]) => {
    if (!metric) {
      abort();
      panelRef.value?.close();
      return;
    }
    await nextTick();
    panelRef.value?.open();
    fetchRecords();
  },
  { flush: 'post' }
);

onBeforeUnmount(abort);

const teachFromReport = () => {
  if (!props.canManage) return;
  router.push({
    name: 'autonomia_agent_panel',
    params: { agentId: props.agentId, tab: 'knowledge' },
  });
  onPanelClose();
};

const recordKey = record =>
  `${record.report_id || record.record_type || 'conversation'}-${
    record.record_id || record.conversation_id || record.conversation?.id
  }-${record.occurred_at || record.reported_at || ''}`;

const cardRecord = record => {
  if (props.metric !== 'wrong_replies') return record;

  const timestamp =
    typeof record.reported_at === 'number'
      ? record.reported_at
      : Math.floor(Date.parse(record.reported_at || '') / 1000);

  return {
    ...record,
    record_type: 'message',
    message: {
      id: record.message_id,
      content: record.message,
      created_at: Number.isFinite(timestamp) ? timestamp : null,
      message_type: 'outgoing',
    },
  };
};

const conversationPath = record => {
  const displayId = record.conversation?.display_id;
  if (!displayId) return '';

  return frontendURL(
    conversationUrl({ accountId: route.params.accountId, id: displayId })
  );
};
</script>

<template>
  <SidePanel
    ref="panelRef"
    :title="title"
    :description="description"
    width="xl"
    panel-test-id="agent-conversations-drawer"
    @close="onPanelClose"
  >
    <div class="min-h-0">
      <span data-testid="agent-drawer-period" class="sr-only">
        {{ description }}
      </span>
      <span
        v-if="meta.has_more"
        data-testid="agent-drawer-has-more"
        class="sr-only"
      >
        {{
          t('AGENTS.PERFORMANCE.DRILLDOWN.LIMIT_NOTE', { limit: meta.limit })
        }}
      </span>
      <div
        v-if="status === 'loading'"
        class="flex items-center justify-center h-40"
        aria-busy="true"
      >
        <Spinner />
      </div>
      <div v-else-if="status === 'error'" class="grid gap-3" role="alert">
        <p class="text-sm text-n-ruby-11">
          {{ t('AGENTS.PERFORMANCE.DRILLDOWN.ERROR') }}
        </p>
        <button
          type="button"
          class="inline-flex items-center justify-center self-start min-h-11 px-4 text-sm font-semibold rounded-lg border border-n-weak text-n-slate-12 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-action="retry"
          @click="fetchRecords"
        >
          {{ t('AGENTS.PERFORMANCE.RETRY') }}
        </button>
      </div>
      <div v-else-if="status === 'success'" class="flex flex-col gap-3">
        <p
          v-if="meta.has_hidden"
          class="flex items-start gap-2 px-3 py-2 text-xs leading-5 rounded-lg bg-n-amber-2 text-n-amber-12"
          data-state="hidden-records"
          data-testid="agent-drawer-has-hidden"
        >
          <span class="i-lucide-eye-off size-4 shrink-0" aria-hidden="true" />
          {{ t('AGENTS.PANEL.REDESIGN_DRAWER.HIDDEN') }}
        </p>
        <div
          v-if="!records.length"
          class="flex items-center justify-center h-40 text-sm text-n-slate-11"
          data-state="empty"
        >
          {{ t('AGENTS.PERFORMANCE.DRILLDOWN.EMPTY') }}
        </div>
        <template v-else>
          <article
            v-for="record in records"
            :key="recordKey(record)"
            class="flex flex-col gap-2"
            data-testid="agent-conversation-row"
            :data-conversation-display-id="
              record.conversation?.display_id || undefined
            "
          >
            <ReportDrilldownCard :record="cardRecord(record)" agent-panel />
            <a
              v-if="conversationPath(record)"
              :href="conversationPath(record)"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center self-start min-h-11 gap-2 px-3 mx-3 text-xs font-semibold rounded-lg text-n-blue-11 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              data-testid="agent-conversation-open"
            >
              <span class="i-lucide-external-link size-4" aria-hidden="true" />
              {{
                t('AGENTS.PANEL.REDESIGN_DRAWER.OPEN', {
                  id: record.conversation?.display_id,
                })
              }}
            </a>
            <template v-if="metric === 'wrong_replies'">
              <p
                v-if="record.reason_label"
                class="px-3 text-xs leading-5 text-n-slate-11"
                data-testid="agent-wrong-reason"
                :data-report-reason="record.report_reason"
              >
                {{
                  t('AGENTS.PANEL.REDESIGN_DRAWER.REASON', {
                    reason: record.reason_label,
                  })
                }}
              </p>
              <p
                v-if="record.suggested_answer"
                class="px-3 text-xs leading-5 text-n-slate-11"
              >
                {{
                  t('AGENTS.PANEL.REDESIGN_DRAWER.SUGGESTION', {
                    text: record.suggested_answer,
                  })
                }}
              </p>
              <button
                v-if="canManage && allowTeach && record.report_id"
                type="button"
                class="self-start min-h-11 px-3 mx-3 text-xs font-semibold rounded-lg text-n-blue-11 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                data-testid="agent-wrong-teach"
                @click="teachFromReport"
              >
                {{ t('AGENTS.PANEL.REDESIGN_DRAWER.TEACH') }}
              </button>
            </template>
          </article>
        </template>
      </div>
    </div>
    <template #close>
      <button
        type="button"
        class="inline-flex items-center justify-center min-w-11 min-h-11 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-label="t('GENERAL.CLOSE')"
        data-testid="agent-drawer-close"
        @click="onPanelClose"
      >
        <span class="i-lucide-x size-4" aria-hidden="true" />
      </button>
    </template>
  </SidePanel>
</template>
