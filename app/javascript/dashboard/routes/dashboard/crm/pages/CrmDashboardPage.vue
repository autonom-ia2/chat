<script setup>
import CrmVistasNumeros from '../components/numeros/CrmVistasNumeros.vue';
import { useMenuNovo } from 'dashboard/components-next/sidebar/fork/useMenuNovo';
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import MetaConversionsAPI from 'dashboard/api/metaConversions';
import CtwaCampaignsAPI from 'dashboard/api/ctwaCampaigns';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import ReportMetricCard from 'dashboard/routes/dashboard/settings/reports/components/ReportMetricCard.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import {
  openWork,
  outcomeKpis,
  duracao,
  showsSales,
  throughputDatasets,
} from '../helpers/dashboardOutcomes';
import { originRows as buildOriginRows } from '../helpers/dashboardOrigins';
import { useCrmPermissions } from '../composables/useCrmPermissions';

const { t } = useI18n();
const { resolvedLocale } = useLocale();

const PERIODS = [
  { key: 'LAST_7', days: 7, groupBy: 'day' },
  { key: 'LAST_30', days: 30, groupBy: 'day' },
  { key: 'LAST_90', days: 90, groupBy: 'week' },
  { key: 'LAST_365', days: 365, groupBy: 'month' },
];

// Com o menu novo (#1617) a página se chama Números e ganha o seletor do CRM.
const { ligado: menuNovo } = useMenuNovo();
const pipelines = ref([]);
const selectedPipelineId = ref('');
const selectedPeriodKey = ref('LAST_30');

const summary = ref(null);
const funnel = ref(null);
const throughput = ref(null);
const followUps = ref(null);
const workload = ref(null);
const meetings = ref(null);
const originMetrics = ref([]);

// Meta conversions (Ads) sync-health block, gated on real CTWA ad activity.
const metaSummary = ref(null);
const hasCtwaAds = ref(false);

// Install-level flag (exposed in window.globalConfig, like CRM_KANBAN_ENABLED).
const isMeetingsEnabled = computed(
  () => window.globalConfig?.CRM_CALENDAR_MEETINGS_ENABLED === 'true'
);

const isLoading = ref(true);
const loadError = ref(false);

const selectedPeriod = computed(
  () => PERIODS.find(p => p.key === selectedPeriodKey.value) || PERIODS[1]
);

const hasPipelines = computed(() => pipelines.value.length > 0);
// value em String, como no select nativo antigo (value=String(pipeline.id)).
const pipelineChoices = computed(() =>
  pipelines.value.map(pipeline => ({
    value: String(pipeline.id),
    label: pipeline.name,
  }))
);
const periodChoices = computed(() =>
  PERIODS.map(period => ({
    value: period.key,
    label: t(`CRM_KANBAN.DASHBOARD.PERIOD.${period.key}`),
  }))
);

const requestParams = computed(() => {
  const until = new Date();
  const since = new Date();
  since.setDate(since.getDate() - selectedPeriod.value.days);
  return {
    pipeline_id: selectedPipelineId.value || undefined,
    since: since.toISOString(),
    until: until.toISOString(),
    group_by: selectedPeriod.value.groupBy,
  };
});

const formatMoney = (cents, currency) =>
  new Intl.NumberFormat(resolvedLocale.value, {
    style: 'currency',
    currency: currency || 'BRL',
  }).format(Number(cents || 0) / 100);

const formatNumber = num =>
  new Intl.NumberFormat(resolvedLocale.value).format(Number(num || 0));

const formatPercent = ratio =>
  ratio == null ? '—' : `${Math.round(Number(ratio) * 100)}%`;

const formatLastSent = value =>
  value
    ? new Intl.DateTimeFormat(resolvedLocale.value, {
        dateStyle: 'medium',
        timeStyle: 'short',
      }).format(new Date(value))
    : t('CRM_KANBAN.DASHBOARD.META_SYNC.NEVER');

// Gate true but no conversions yet → show the EMPTY hint instead of zeros.
const hasMetaData = computed(() => {
  const payload = metaSummary.value;
  if (!payload) return false;
  const events = payload.by_event_type || {};
  return (payload.accepted_count || 0) > 0 || Object.keys(events).length > 0;
});

// Joins a [{ currency, value_cents }] list into a single multi-currency string,
// honoring the locked rule that currencies are never summed together.
const formatCurrencyList = list => {
  // #1876: o zero sai na moeda da meta do funil, não sempre em real.
  if (!list || !list.length)
    return formatMoney(0, summary.value?.goal?.currency);
  return list
    .map(entry => formatMoney(entry.value_cents, entry.currency))
    .join(' · ');
};

// Revenue sent to Meta, per currency (the endpoint groups by currency so a
// mixed-currency book is never summed under a single R$ label).
const metaRevenueLabel = computed(() => {
  const byCurrency = metaSummary.value?.accepted_value_by_currency || {};
  const list = Object.entries(byCurrency).map(([currency, cents]) => ({
    currency,
    value_cents: cents,
  }));
  return formatCurrencyList(list);
});

// Monthly sales target box: attainment % + pacing (on track when attainment
// keeps up with the share of the month already elapsed).
const goal = computed(() => summary.value?.goal || null);
const goalAttainmentPct = computed(() =>
  goal.value ? Math.min(100, Math.round(goal.value.attainment * 100)) : 0
);
const goalOnTrack = computed(
  () => goal.value && goal.value.attainment >= goal.value.month_elapsed
);
const goalProgressLabel = computed(() => {
  if (!goal.value) return '';
  const achieved = formatMoney(goal.value.achieved_cents, goal.value.currency);
  const target = formatMoney(goal.value.target_cents, goal.value.currency);
  return `${achieved} / ${target}`;
});

const funnelMaxCount = computed(() => {
  const stages = funnel.value?.stages || [];
  return Math.max(1, ...stages.map(stage => stage.count || 0));
});

const workloadMaxCount = computed(() => {
  const list = workload.value?.responsibles || [];
  return Math.max(1, ...list.map(entry => entry.count || 0));
});

const hasFunnel = computed(() =>
  (funnel.value?.stages || []).some(stage => stage.count > 0)
);

// Funil de atendimento (#1151) mostra resolvidos e cancelados, nunca venda.
const isSaleFunnel = computed(() => showsSales(summary.value));
// #2075 — sem a chave de valores o servidor manda o dinheiro vazio: os quadros em R$ e a meta somem
// (as contagens ficam), em vez de mostrar "R$ 0".
const { canSeeSalesValues } = useCrmPermissions();
const comValores = computed(
  () => isSaleFunnel.value && canSeeSalesValues.value
);
const outcomeCards = computed(() => outcomeKpis(summary.value));
// #1498 — funil de Atender: tempo de solução (média), sem a espera do cliente.
const tempoDeSolucao = computed(() => {
  const segundos = summary.value?.resolution_time?.average_seconds;
  const { chave, valores } = duracao(segundos ?? Number.NaN);
  return t(`CRM_KANBAN.DASHBOARD.DURACAO.${chave}`, valores);
});
const openWorkItems = computed(() => openWork(summary.value));

const throughputSets = computed(() => throughputDatasets(throughput.value));

// #1876: formato do @chatwoot/viz (categories/series); o antigo labels/datasets deixava o gráfico vazio desde o #15458.
const throughputChart = computed(() => {
  const series = throughput.value?.series || [];
  return {
    categories: series.map(point => point.date),
    series: throughputSets.value.map(set => ({
      id: set.key,
      label: t(`CRM_KANBAN.DASHBOARD.THROUGHPUT.${set.labelKey}`),
      color: set.color,
      data: series.map(point => point[set.key] || 0),
    })),
  };
});

const hasThroughput = computed(() =>
  (throughput.value?.series || []).some(point =>
    throughputSets.value.some(set => (point[set.key] || 0) > 0)
  )
);

const workloadLabel = entry => {
  if (entry.type === 'bot')
    return entry.name || t('CRM_KANBAN.DASHBOARD.WORKLOAD.BOT');
  if (entry.type === 'none') return t('CRM_KANBAN.DASHBOARD.WORKLOAD.NONE');
  return entry.name || `#${entry.key}`;
};

const originRows = computed(() => buildOriginRows(originMetrics.value));

const hasOriginRows = computed(() => originRows.value.length > 0);

const maxOriginWonCount = computed(() =>
  Math.max(1, ...originRows.value.map(row => row.wonCount))
);

const fetchReports = async () => {
  if (!hasPipelines.value) return;
  isLoading.value = true;
  loadError.value = false;
  try {
    const params = requestParams.value;
    const [
      summaryRes,
      funnelRes,
      throughputRes,
      followUpsRes,
      workloadRes,
      meetingsRes,
      campaignsRes,
    ] = await Promise.all([
      CrmKanbanAPI.getReportSummary(params),
      CrmKanbanAPI.getReportFunnel(params),
      CrmKanbanAPI.getReportThroughput(params),
      CrmKanbanAPI.getReportFollowUps(params),
      CrmKanbanAPI.getReportWorkload(params),
      isMeetingsEnabled.value
        ? CrmKanbanAPI.getReportMeetings(params)
        : Promise.resolve(null),
      CtwaCampaignsAPI.get({
        pipeline_id: params.pipeline_id,
        since: params.since,
        until: params.until,
        include_origin_metrics: true,
      }),
    ]);
    summary.value = summaryRes.data.payload;
    funnel.value = funnelRes.data.payload;
    throughput.value = throughputRes.data.payload;
    followUps.value = followUpsRes.data.payload;
    workload.value = workloadRes.data.payload;
    meetings.value = meetingsRes?.data?.payload || null;
    originMetrics.value = campaignsRes.data.origin_metrics || [];
  } catch (error) {
    loadError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const fetchPipelines = async () => {
  try {
    const { data } = await CrmKanbanAPI.getReportPipelines();
    pipelines.value = data.payload || [];
    const defaultPipeline =
      pipelines.value.find(pipeline => pipeline.is_default) ||
      pipelines.value[0];
    if (defaultPipeline) {
      selectedPipelineId.value = String(defaultPipeline.id);
    } else {
      isLoading.value = false;
    }
  } catch (error) {
    loadError.value = true;
    isLoading.value = false;
  }
};

const fetchMetaSummary = async () => {
  const { pipeline_id, since, until } = requestParams.value;
  try {
    const { data } = await MetaConversionsAPI.getSummary({
      pipeline_id,
      since,
      until,
    });
    metaSummary.value = data.payload;
  } catch {
    metaSummary.value = null;
  }
};

// One-shot gate: only render the Meta block when the account runs CTWA ads.
const loadCtwaGate = async () => {
  try {
    const { data } = await CtwaCampaignsAPI.get();
    // Paid CTWA only: organic referrals / tracked links must not light the Meta
    // block. Legacy touches predate `source` and were always paid.
    hasCtwaAds.value = (data.payload || []).some(
      option => !option.source || option.source === 'meta_ctwa'
    );
  } catch {
    hasCtwaAds.value = false;
  }
};

watch([selectedPipelineId, selectedPeriodKey], () => {
  if (selectedPipelineId.value) fetchReports();
  if (hasCtwaAds.value && selectedPipelineId.value) fetchMetaSummary();
});

onMounted(async () => {
  await fetchPipelines();
  await loadCtwaGate();
  if (hasCtwaAds.value && selectedPipelineId.value) fetchMetaSummary();
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <header
      class="flex flex-col gap-4 px-6 py-5 border-b sm:flex-row sm:items-center sm:justify-between border-n-weak"
    >
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-4 mb-1">
          <h1 class="m-0 text-xl font-semibold text-n-slate-12">
            {{
              menuNovo
                ? t('FORK_SIDEBAR.CRM.TITULO_NUMEROS')
                : t('CRM_KANBAN.DASHBOARD.TITLE')
            }}
          </h1>
          <CrmVistasNumeros />
        </div>
        <p class="m-0 text-sm text-n-slate-11">
          {{
            t(
              isSaleFunnel
                ? 'CRM_KANBAN.DASHBOARD.SUBTITLE'
                : 'CRM_KANBAN.DASHBOARD.SUBTITLE_ATENDER'
            )
          }}
        </p>
      </div>
      <div v-if="hasPipelines" class="flex flex-wrap items-center gap-3">
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          {{ t('CRM_KANBAN.DASHBOARD.PIPELINE_LABEL') }}
          <ChoiceSelect
            v-model="selectedPipelineId"
            :options="pipelineChoices"
            :aria-label="t('CRM_KANBAN.DASHBOARD.PIPELINE_LABEL')"
            compact
          />
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          {{ t('CRM_KANBAN.DASHBOARD.PERIOD_LABEL') }}
          <ChoiceSelect
            v-model="selectedPeriodKey"
            :options="periodChoices"
            :aria-label="t('CRM_KANBAN.DASHBOARD.PERIOD_LABEL')"
            compact
          />
        </label>
        <Button
          icon="i-lucide-refresh-cw"
          slate
          faded
          sm
          :is-loading="isLoading"
          @click="fetchReports"
        />
      </div>
    </header>
    <!-- #1897: com CRM › Números por papel, o seletor "Só eu · Equipe" e o aviso aos administradores. -->
    <slot name="topo" />

    <div
      v-if="isLoading && !summary"
      class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-11"
    >
      <Spinner />
      <span class="text-sm">{{ t('CRM_KANBAN.DASHBOARD.LOADING') }}</span>
    </div>

    <div
      v-else-if="!hasPipelines"
      class="flex items-center justify-center flex-1 p-8 text-sm text-center text-n-slate-11"
    >
      {{ t('CRM_KANBAN.DASHBOARD.EMPTY') }}
    </div>

    <div
      v-else-if="loadError"
      class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-11"
    >
      <span class="text-sm">{{ t('CRM_KANBAN.DASHBOARD.ERROR') }}</span>
      <Button
        :label="t('CRM_KANBAN.DASHBOARD.RETRY')"
        sm
        @click="fetchReports"
      />
    </div>

    <div v-else class="flex flex-col gap-6 p-6">
      <!-- KPI row -->
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
        <div
          v-for="kpi in outcomeCards"
          :key="kpi.key"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <ReportMetricCard
            :label="t(`CRM_KANBAN.DASHBOARD.KPI.${kpi.key}`)"
            :value="formatNumber(kpi.value)"
            :info-text="t(`CRM_KANBAN.DASHBOARD.KPI.${kpi.key}_INFO`)"
          />
        </div>
        <div
          class="col-span-2 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <h3
            class="flex items-center gap-1 m-0 text-sm font-medium text-n-slate-11"
          >
            <span>{{ t('CRM_KANBAN.DASHBOARD.KPI.OPEN_WORK') }}</span>
            <fluent-icon
              v-tooltip="t('CRM_KANBAN.DASHBOARD.KPI.OPEN_WORK_INFO')"
              size="14"
              icon="info"
              class="mt-0.5 text-n-slate-10"
            />
          </h3>
          <dl class="grid grid-cols-3 gap-2 mt-1 mb-0">
            <div
              v-for="item in openWorkItems"
              :key="item.key"
              class="flex flex-col-reverse min-w-0"
            >
              <dt class="text-xs text-n-slate-11">
                {{ t(`CRM_KANBAN.DASHBOARD.KPI.OPEN_${item.key}`) }}
              </dt>
              <dd class="m-0 text-xl truncate text-n-slate-12">
                {{ formatNumber(item.value) }}
              </dd>
            </div>
          </dl>
        </div>
        <div
          v-if="!isSaleFunnel"
          data-kpi-tempo-solucao
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <ReportMetricCard
            :label="t('CRM_KANBAN.DASHBOARD.KPI.RESOLUTION_TIME')"
            :value="tempoDeSolucao"
            :info-text="t('CRM_KANBAN.DASHBOARD.KPI.RESOLUTION_TIME_INFO')"
          />
        </div>
        <div
          v-if="isSaleFunnel"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <ReportMetricCard
            :label="t('CRM_KANBAN.DASHBOARD.KPI.WIN_RATE')"
            :value="formatPercent(summary?.win_rate)"
            :info-text="t('CRM_KANBAN.DASHBOARD.KPI.WIN_RATE_INFO')"
          />
        </div>
        <div
          v-if="comValores"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <ReportMetricCard
            :label="t('CRM_KANBAN.DASHBOARD.KPI.WIN_RATE_VALUE')"
            :value="formatPercent(summary?.win_rate_by_value)"
            :info-text="t('CRM_KANBAN.DASHBOARD.KPI.WIN_RATE_VALUE_INFO')"
          />
        </div>
        <div
          v-if="comValores"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <ReportMetricCard
            :label="t('CRM_KANBAN.DASHBOARD.KPI.WON_VALUE')"
            :value="formatCurrencyList(summary?.won_value_by_currency)"
            :info-text="t('CRM_KANBAN.DASHBOARD.KPI.WON_VALUE_INFO')"
          />
        </div>
        <div
          v-if="comValores"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <ReportMetricCard
            :label="t('CRM_KANBAN.DASHBOARD.KPI.LOST_VALUE')"
            :value="formatCurrencyList(summary?.lost_value_by_currency)"
            :info-text="t('CRM_KANBAN.DASHBOARD.KPI.LOST_VALUE_INFO')"
          />
        </div>
        <div
          v-if="comValores"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <ReportMetricCard
            :label="t('CRM_KANBAN.DASHBOARD.KPI.OPEN_VALUE')"
            :value="formatCurrencyList(summary?.open_value_by_currency)"
            :info-text="t('CRM_KANBAN.DASHBOARD.KPI.OPEN_VALUE_INFO')"
          />
        </div>
        <div
          v-if="comValores"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <h3
            class="flex items-center gap-1 m-0 text-sm font-medium text-n-slate-11"
          >
            <span>{{ t('CRM_KANBAN.DASHBOARD.KPI.GOAL') }}</span>
            <fluent-icon
              v-tooltip="t('CRM_KANBAN.DASHBOARD.KPI.GOAL_INFO')"
              size="14"
              icon="info"
              class="mt-0.5 text-n-slate-10"
            />
          </h3>
          <template v-if="goal">
            <p class="mt-1 mb-2 text-2xl font-medium text-n-slate-12">
              {{ formatPercent(goal.attainment) }}
            </p>
            <div class="h-1.5 overflow-hidden rounded-full bg-n-alpha-black2">
              <div
                class="h-full rounded-full"
                :class="goalOnTrack ? 'bg-n-teal-9' : 'bg-n-amber-9'"
                :style="{ width: `${goalAttainmentPct}%` }"
              />
            </div>
            <div class="flex items-center justify-between mt-2">
              <span class="text-xs text-n-slate-11">
                {{ goalProgressLabel }}
              </span>
              <span
                class="px-1.5 py-0.5 text-xs font-medium rounded"
                :class="
                  goalOnTrack
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-amber-3 text-n-amber-11'
                "
              >
                {{
                  goalOnTrack
                    ? t('CRM_KANBAN.DASHBOARD.KPI.GOAL_ON_TRACK')
                    : t('CRM_KANBAN.DASHBOARD.KPI.GOAL_BEHIND')
                }}
              </span>
            </div>
          </template>
          <p v-else class="mt-1 text-sm text-n-slate-11">
            {{ t('CRM_KANBAN.DASHBOARD.KPI.GOAL_EMPTY') }}
          </p>
        </div>
      </div>

      <!-- Meta conversions (Ads) — gated by real CTWA ad activity -->
      <section
        v-if="hasCtwaAds && isSaleFunnel"
        class="p-5 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <h3 class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.DASHBOARD.META_SYNC.TITLE') }}
        </h3>
        <p class="mb-4 text-xs text-n-slate-11">
          {{ t('CRM_KANBAN.DASHBOARD.META_SYNC.SUBTITLE') }}
        </p>
        <p v-if="!hasMetaData" class="text-sm text-n-slate-11">
          {{ t('CRM_KANBAN.DASHBOARD.META_SYNC.EMPTY') }}
        </p>
        <div v-else class="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <ReportMetricCard
              :label="t('CRM_KANBAN.DASHBOARD.META_SYNC.ACCEPTED')"
              :value="formatNumber(metaSummary?.accepted_count)"
            />
          </div>
          <div
            v-if="canSeeSalesValues"
            class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <ReportMetricCard
              :label="t('CRM_KANBAN.DASHBOARD.META_SYNC.REVENUE')"
              :value="metaRevenueLabel"
            />
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <ReportMetricCard
              :label="t('CRM_KANBAN.DASHBOARD.META_SYNC.ERRORS')"
              :value="formatNumber(metaSummary?.by_status?.error)"
            />
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <ReportMetricCard
              :label="t('CRM_KANBAN.DASHBOARD.META_SYNC.LAST_SENT')"
              :value="formatLastSent(metaSummary?.last_sent_at)"
            />
          </div>
        </div>
      </section>

      <!-- Origin performance (#1498: só funil de Vender, é receita) -->
      <section
        v-if="isSaleFunnel"
        class="p-5 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <h3 class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('CRM_DASHBOARD.ORIGIN.TITLE') }}
        </h3>
        <p class="mb-4 text-xs text-n-slate-11">
          {{ t('CRM_DASHBOARD.ORIGIN.SUBTITLE') }}
        </p>
        <p v-if="!hasOriginRows" class="text-sm text-n-slate-11">
          {{ t('CRM_DASHBOARD.ORIGIN.EMPTY') }}
        </p>
        <div v-else class="flex flex-col gap-4">
          <div
            v-for="row in originRows"
            :key="row.source"
            class="flex flex-col gap-3 sm:flex-row sm:items-center"
          >
            <div class="flex items-center min-w-0 gap-2 sm:w-48 shrink-0">
              <span
                class="text-base shrink-0 text-n-slate-10"
                :class="row.icon"
              />
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ t(row.labelKey) }}
              </span>
            </div>
            <div
              class="relative flex-1 h-5 overflow-hidden rounded-md bg-n-alpha-black2"
            >
              <div
                class="h-full rounded-md"
                :class="row.barClass"
                :style="{
                  width: `${Math.max(
                    4,
                    (row.wonCount / maxOriginWonCount) * 100
                  )}%`,
                }"
              />
            </div>
            <div class="grid grid-cols-2 gap-3 sm:w-72 shrink-0">
              <div>
                <p class="m-0 text-sm font-medium text-n-slate-12">
                  {{ formatNumber(row.wonCount) }}
                </p>
                <p class="m-0 text-xs text-n-slate-11">
                  {{ t('CRM_DASHBOARD.ORIGIN.WON') }}
                </p>
              </div>
              <div v-if="canSeeSalesValues">
                <p class="m-0 text-sm font-medium truncate text-n-slate-12">
                  {{ formatCurrencyList(row.valueList) }}
                </p>
                <p class="m-0 text-xs text-n-slate-11">
                  {{ t('CRM_DASHBOARD.ORIGIN.REVENUE') }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- Meetings (no-show) — gated by the meetings install flag -->
      <section
        v-if="isMeetingsEnabled"
        class="p-5 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <h3 class="mb-4 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.DASHBOARD.MEETINGS.TITLE') }}
        </h3>
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-3">
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <ReportMetricCard
              :label="t('CRM_KANBAN.DASHBOARD.MEETINGS.HELD')"
              :value="formatNumber(meetings?.held)"
            />
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <ReportMetricCard
              :label="t('CRM_KANBAN.DASHBOARD.MEETINGS.NO_SHOW')"
              :value="formatNumber(meetings?.no_show)"
            />
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <ReportMetricCard
              :label="t('CRM_KANBAN.DASHBOARD.MEETINGS.NO_SHOW_RATE')"
              :value="formatPercent(meetings?.no_show_rate)"
            />
          </div>
        </div>
      </section>

      <!-- Funnel -->
      <section class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
        <h3 class="mb-4 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.DASHBOARD.FUNNEL.TITLE') }}
        </h3>
        <p v-if="!hasFunnel" class="text-sm text-n-slate-11">
          {{ t('CRM_KANBAN.DASHBOARD.FUNNEL.EMPTY') }}
        </p>
        <div v-else class="flex flex-col gap-3">
          <div
            v-for="stage in funnel.stages"
            :key="stage.id"
            class="flex items-center gap-3"
          >
            <span class="w-40 shrink-0 text-sm truncate text-n-slate-11">
              {{ stage.name }}
            </span>
            <div
              class="relative flex-1 h-6 overflow-hidden rounded-md bg-n-alpha-black2"
            >
              <div
                class="h-full rounded-md"
                :style="{
                  width: `${Math.max(2, (stage.count / funnelMaxCount) * 100)}%`,
                  backgroundColor: stage.color || '#64748b',
                }"
              />
            </div>
            <span
              class="w-12 text-sm font-medium text-right shrink-0 text-n-slate-12"
            >
              {{ formatNumber(stage.count) }}
            </span>
            <span
              v-if="comValores"
              class="w-48 text-xs text-right truncate shrink-0 text-n-slate-11"
            >
              {{ formatCurrencyList(stage.value_by_currency) }}
            </span>
          </div>
        </div>
      </section>

      <!-- Follow-ups -->
      <section class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
        <h3 class="mb-4 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.DASHBOARD.FOLLOW_UPS.TITLE') }}
        </h3>
        <div class="grid grid-cols-3 gap-4">
          <div>
            <p class="m-0 text-2xl font-semibold text-n-slate-12">
              {{ formatNumber(followUps?.by_status?.pending) }}
            </p>
            <p class="m-0 text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.DASHBOARD.FOLLOW_UPS.PENDING') }}
            </p>
          </div>
          <div>
            <p class="m-0 text-2xl font-semibold text-n-ruby-11">
              {{ formatNumber(followUps?.overdue) }}
            </p>
            <p class="m-0 text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.DASHBOARD.FOLLOW_UPS.OVERDUE') }}
            </p>
            <p
              v-if="followUps?.overdue_by && followUps.overdue > 0"
              data-overdue-by
              class="m-0 text-xs text-n-slate-10"
            >
              {{
                t('CRM_KANBAN.DASHBOARD.FOLLOW_UPS.OVERDUE_BY', {
                  ai: formatNumber(followUps.overdue_by.ai),
                  human: formatNumber(followUps.overdue_by.human),
                })
              }}
            </p>
          </div>
          <div>
            <p class="m-0 text-2xl font-semibold text-n-slate-12">
              {{ formatNumber(followUps?.due_soon) }}
            </p>
            <p class="m-0 text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.DASHBOARD.FOLLOW_UPS.DUE_SOON') }}
            </p>
          </div>
        </div>
      </section>

      <!-- Throughput -->
      <section class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
        <h3 class="mb-4 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.DASHBOARD.THROUGHPUT.TITLE') }}
        </h3>
        <p v-if="!hasThroughput" class="text-sm text-n-slate-11">
          {{ t('CRM_KANBAN.DASHBOARD.THROUGHPUT.EMPTY') }}
        </p>
        <div v-else class="h-64">
          <BarChart
            :data="throughputChart"
            :height="232"
            :aria-label="t('CRM_KANBAN.DASHBOARD.THROUGHPUT.TITLE')"
          />
        </div>
      </section>

      <!-- Workload -->
      <section class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
        <h3 class="mb-4 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.DASHBOARD.WORKLOAD.TITLE') }}
        </h3>
        <p
          v-if="!(workload?.responsibles || []).length"
          class="text-sm text-n-slate-11"
        >
          {{ t('CRM_KANBAN.DASHBOARD.WORKLOAD.EMPTY') }}
        </p>
        <div v-else class="flex flex-col gap-3">
          <div
            v-for="entry in workload.responsibles"
            :key="entry.key"
            class="flex items-center gap-3"
          >
            <span
              class="flex items-center w-40 gap-2 text-sm truncate shrink-0 text-n-slate-11"
            >
              <span
                v-if="entry.type === 'bot'"
                class="i-lucide-bot text-n-slate-10"
              />
              <span
                v-else-if="entry.type === 'none'"
                class="i-lucide-user-round-x text-n-slate-10"
              />
              <span v-else class="i-lucide-user-round text-n-slate-10" />
              {{ workloadLabel(entry) }}
            </span>
            <div
              class="relative flex-1 h-5 overflow-hidden rounded-md bg-n-alpha-black2"
            >
              <div
                class="h-full rounded-md bg-n-blue-9"
                :style="{
                  width: `${Math.max(2, (entry.count / workloadMaxCount) * 100)}%`,
                }"
              />
            </div>
            <span
              class="w-12 text-sm font-medium text-right shrink-0 text-n-slate-12"
            >
              {{ formatNumber(entry.count) }}
            </span>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
