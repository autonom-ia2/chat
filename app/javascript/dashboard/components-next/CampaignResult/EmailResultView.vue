<script setup>
// Result of an e-mail campaign (#1007, PRD §6.5, D18, O1). Everything the old Gestão de campanhas
// showed for a selected e-mail campaign lives here, reading the same e-mail reports API and reusing
// its data and actions (checklist in docs/campaigns/publicos/resultado-1007.md; health and people
// redrawn in the result layout by #990): indicators with rates
// and delivery evidence, import status, health (re-evaluate, resume, problems), chart over time,
// clicks per link and the per-person table with its filters and filtered export. New: Responderam
// (CRM mark of #1002), the E1 sum, "Quem respondeu" with "Abrir conversa", masked "Baixar
// resultado", the actions (L8) and refresh every 15s while sending (E2).
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import CampaignResultsAPI from 'dashboard/api/campaignResults';
import EmailCampaignReportsAPI from 'dashboard/api/emailCampaignReports';
import EmailCampaignsAPI from 'dashboard/api/emailCampaigns';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignTimelineChart from 'dashboard/components-next/Campaigns/EmailProtection/CampaignTimelineChart.vue';
import RecipientImportStatus from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/RecipientImportStatus.vue';
import {
  NS as EMAIL_NS,
  deliveryKey,
  displayStatusLabel,
  downloadCsv,
  formatNumber,
  hasActiveEmailWork,
  reputationDenominator,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import { CAMPAIGN_CHANNELS } from 'dashboard/components-next/CampaignJourney/campaignChannels';
import ResultHeader from './ResultHeader.vue';
import ResultKpiStrip from './ResultKpiStrip.vue';
import ResultCrmBand from './ResultCrmBand.vue';
import ResultLinkClicks from './ResultLinkClicks.vue';
import ResultRepliedList from './ResultRepliedList.vue';
import EmailResultActions from './EmailResultActions.vue';
import ResultEmailHealth from './ResultEmailHealth.vue';
import ResultEmailRecipients from './ResultEmailRecipients.vue';
import { useResultPolling } from './useResultPolling';
import { journeyStatus, resultBalance } from './resultMetrics';

const props = defineProps({
  campaignId: { type: [String, Number], required: true },
});

const NS = 'RESULT_JOURNEY';
const CM = 'CAMPAIGN_MANAGEMENT';
const CHANNEL = CAMPAIGN_CHANNELS.EMAIL;
const { t, locale } = useI18n();
const router = useRouter();
const canManage = useCanManage('campaign_manage');
const globalConfig = useMapGetter('globalConfig/get');
const emailReportsEnabled = computed(
  () =>
    globalConfig.value?.emailCampaignEnabled === true &&
    globalConfig.value?.crmKanbanEnabled === true
);

const result = ref(null);
const summary = ref(null);
const health = ref({});
const campaign = ref({});
const isLoading = ref(false);
const loadError = ref('');
const refreshKey = ref(0);
const recipientsPanel = ref(null);
const timeline = ref([]);
const timelineSource = ref({});
const timelineInterval = ref('day');
const timelineLoading = ref(false);
const timelineError = ref(false);
const clicks = ref([]);
const clicksLoading = ref(false);
const clicksError = ref(false);
const exporting = ref(false);

const number = value => formatNumber(value, locale.value);
const totals = computed(() => result.value?.totals || {});
const deliveryLabel = source => t(`${EMAIL_NS}.STATUS.${deliveryKey(source)}`);

const rateLabel = (rate, key) => {
  if (typeof rate !== 'number') return '';
  const formatted = t(`${EMAIL_NS}.RATE`, { value: number(rate) });
  if (!['BOUNCED', 'COMPLAINED'].includes(key))
    return `${formatted} · ${deliveryLabel(summary.value || {})}`;
  const count = reputationDenominator(
    summary.value,
    key === 'BOUNCED' ? 'hard_bounce_rate' : 'complaint_rate'
  );
  return typeof count === 'number'
    ? `${formatted} · ${t(`${CM}.KPIS.SENT`)}: ${number(count)}`
    : formatted;
};

const deliveryDetails = computed(() => {
  const evidence = summary.value?.delivery_evidence;
  if (!evidence) return [];
  return [
    ['delivered', evidence.provider_confirmed],
    ['accepted_service', evidence.direct_acceptance_only],
  ]
    .filter(([, count]) => Number.isInteger(count) && count >= 0)
    .map(([key, count]) => ({
      key,
      label: t(`${EMAIL_NS}.STATUS.${key}`),
      value: count,
    }));
});

const kpis = computed(() => {
  const s = summary.value || {};
  const items = [
    {
      key: 'ELIGIBLE',
      label: t(`${NS}.KPI.ELIGIBLE`),
      value: totals.value.eligible,
      note: t(`${NS}.KPI.AUDIENCE_NOTE`),
    },
    { key: 'SENT', label: t(`${CM}.KPIS.SENT`), value: s.sent },
    {
      key: 'DELIVERED',
      label: deliveryLabel(s),
      value: s.delivered,
      details: deliveryDetails.value,
    },
    {
      key: 'OPENED',
      label: `${t(`${CM}.KPIS.OPENED`)} (${t(`${CM}.APPROXIMATE`)})`,
      value: s.opened,
      rate: s.open_rate,
    },
    {
      key: 'CLICKED',
      label: t(`${CM}.KPIS.CLICKED`),
      value: s.clicked,
      rate: s.click_rate,
    },
    {
      key: 'REPLIED',
      label: t(`${NS}.KPI.REPLIED`),
      value: totals.value.replied,
      note: t(`${NS}.KPI.REPLIED_NOTE`),
    },
    {
      key: 'UNSUBSCRIBED',
      label: t(`${CM}.KPIS.UNSUBSCRIBED`),
      value: s.unsubscribed,
      rate: s.unsubscribe_rate,
    },
    {
      key: 'BOUNCED',
      label: displayStatusLabel(t, 'permanent'),
      value: s.permanent_bounced,
      rate: s.hard_bounce_rate,
    },
    {
      key: 'TEMPORARY',
      label: t(`${EMAIL_NS}.STATUS.temporary`),
      value: s.temporary_bounced,
    },
    {
      key: 'COMPLAINED',
      label: t(`${EMAIL_NS}.STATUS.complained`),
      value: s.complained,
      rate: s.complaint_rate,
    },
    {
      key: 'UNKNOWN',
      label: displayStatusLabel(t, 'bounce_unknown'),
      value: s.unknown_bounced,
    },
  ];
  return items.map(item => ({
    ...item,
    note: item.note || rateLabel(item.rate, item.key),
  }));
});

const metricsHelp = computed(() => {
  const hints = [t(`${EMAIL_NS}.METRICS_HINT`)];
  if (deliveryKey(summary.value || {}) !== 'delivered')
    hints.push(t(`${EMAIL_NS}.DELIVERY_HINT`));
  return hints.join(' ');
});

const balance = computed(() => resultBalance(CHANNEL, totals.value));

const date = value =>
  value
    ? new Date(value).toLocaleString(locale.value.replace('_', '-'), {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    : '';

// `sent_at` only exists once the whole list went out; a paused or running send is dated by its
// first e-mail (`started_at`, #990).
const sendDate = info => {
  if (info.sent_at) return { key: 'SENT_ON', value: info.sent_at };
  if (info.started_at) return { key: 'STARTED_ON', value: info.started_at };
  if (info.scheduled_at)
    return { key: 'SCHEDULED_FOR', value: info.scheduled_at };
  return null;
};

// Which visual identity the AI e-mail used (#1076), as the campaign recorded it.
const identityText = computed(() => {
  const identity = campaign.value?.brand_identity;
  if (!identity?.name) return '';
  return t('BRAND_KITS.RESULT.IDENTITY', {
    name: identity.name,
    mode: t(
      `BRAND_KITS.PICKER.MODES.${(identity.mode || 'light').toUpperCase()}`
    ),
  });
});

const subtitle = computed(() => {
  const info = result.value?.campaign || {};
  const when = sendDate(info);
  return [
    t('CAMPAIGN_JOURNEY.CHANNELS.EMAIL'),
    info.from_email,
    when && t(`${NS}.SUBTITLE.${when.key}`, { date: date(when.value) }),
    info.audience && t(`${NS}.SUBTITLE.AUDIENCE`, { name: info.audience.name }),
    identityText.value,
  ]
    .filter(Boolean)
    .join(' · ');
});

const fetchResult = async () => {
  const { data } = await CampaignResultsAPI.getResult(
    CHANNEL,
    props.campaignId
  );
  result.value = data.payload;
};

const fetchReports = async () => {
  const [reports, show] = await Promise.all([
    EmailCampaignReportsAPI.getReports(props.campaignId),
    EmailCampaignsAPI.show(props.campaignId),
  ]);
  const payload = reports.data.payload;
  summary.value = payload.summary;
  const row =
    (payload.campaigns || []).find(
      item => String(item.id) === String(props.campaignId)
    ) || {};
  campaign.value = show.data.payload || show.data;
  health.value = {
    ...row,
    ...campaign.value,
    id: campaign.value.id,
    protection: payload.protection || campaign.value.protection,
    preflight: payload.preflight || campaign.value.preflight,
  };
};

const fetchTimeline = async () => {
  timelineLoading.value = true;
  timelineError.value = false;
  try {
    const { data } = await EmailCampaignReportsAPI.getTimeline(
      props.campaignId,
      timelineInterval.value
    );
    timeline.value = data.payload.series || [];
    timelineSource.value = { delivery_mode: data.payload.delivery_mode };
  } catch {
    timelineError.value = true;
  } finally {
    timelineLoading.value = false;
  }
};

const fetchClicks = async () => {
  clicksLoading.value = true;
  clicksError.value = false;
  try {
    const { data } = await EmailCampaignReportsAPI.getClicks(props.campaignId);
    clicks.value = data.payload.clicks || [];
  } catch {
    clicksError.value = true;
  } finally {
    clicksLoading.value = false;
  }
};

const fetchAll = async () => {
  await Promise.all([fetchResult(), fetchReports()]);
};

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  result.value = null;
  try {
    await fetchAll();
    fetchTimeline();
    fetchClicks();
  } catch (error) {
    loadError.value =
      error?.response?.status === 404
        ? t(`${NS}.NOT_FOUND`)
        : t(`${NS}.LOAD_ERROR`);
  } finally {
    isLoading.value = false;
  }
};

const refresh = async () => {
  await fetchAll();
  fetchTimeline();
  fetchClicks();
  refreshKey.value += 1;
};

const setTimelineInterval = interval => {
  timelineInterval.value = interval;
  fetchTimeline();
};

const download = async () => {
  if (exporting.value) return;
  exporting.value = true;
  try {
    const { data } = await CampaignResultsAPI.exportResult(
      CHANNEL,
      props.campaignId
    );
    downloadCsv(data, `campaign-email-${props.campaignId}-result.csv`);
  } catch {
    useAlert(t(`${NS}.DOWNLOAD_ERROR`));
  } finally {
    exporting.value = false;
  }
};

const onDeleted = () => router.push({ name: 'campaigns_journey_index' });

useResultPolling(
  refresh,
  () =>
    Boolean(result.value?.campaign?.processing) ||
    hasActiveEmailWork(health.value)
);

watch(
  () => props.campaignId,
  () => {
    if (emailReportsEnabled.value) load();
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <div
      v-if="!emailReportsEnabled"
      class="flex flex-col items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-8 text-center"
      data-paywall
    >
      <span class="i-lucide-lock size-8 text-n-slate-10" aria-hidden="true" />
      <h2 class="m-0 text-lg font-medium text-n-slate-12">
        {{ t(`${CM}.PAYWALL.TITLE`) }}
      </h2>
      <p class="m-0 max-w-md text-sm text-n-slate-11">
        {{ t(`${CM}.PAYWALL.DESCRIPTION`) }}
      </p>
    </div>
    <div v-else-if="isLoading" class="flex justify-center p-12">
      <Spinner />
    </div>
    <p
      v-else-if="loadError"
      role="alert"
      class="m-0 rounded-2xl border border-n-weak bg-n-solid-1 p-6 text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </p>
    <template v-else-if="result">
      <ResultHeader
        :name="result.campaign.name"
        :channel="CHANNEL"
        :status-key="journeyStatus(CHANNEL, result.campaign.status)"
        :subtitle="subtitle"
      >
        <template #actions>
          <EmailResultActions
            :campaign="health"
            @updated="refresh"
            @deleted="onDeleted"
          />
          <Button
            v-if="canManage"
            :label="t(`${NS}.DOWNLOAD`)"
            icon="i-lucide-download"
            slate
            outline
            class="!min-h-11 !rounded-xl"
            :is-loading="exporting"
            data-export
            @click="download"
          />
          <Button
            :label="t(`${NS}.REFRESH`)"
            icon="i-lucide-refresh-cw"
            slate
            outline
            class="!min-h-11 !rounded-xl"
            data-refresh
            @click="refresh"
          />
        </template>
      </ResultHeader>

      <p
        v-if="result.campaign.processing"
        role="status"
        class="m-0 flex items-start gap-3 rounded-2xl border border-n-amber-6 bg-n-amber-2 px-5 py-4 text-sm text-n-amber-12"
        data-processing
      >
        <span
          class="i-lucide-loader-circle mt-0.5 size-4 shrink-0 animate-spin"
          aria-hidden="true"
        />
        {{ t(`${NS}.PROCESSING_EMAIL`) }}
      </p>

      <ResultKpiStrip :items="kpis" :label="t(`${NS}.KPI.LABEL`)" />
      <div class="flex flex-col gap-1">
        <p
          class="m-0 text-xs text-n-slate-11"
          :class="{ 'text-n-ruby-11': !balance.holds }"
          data-balance
        >
          {{
            t(`${NS}.BALANCE.EMAIL`, {
              delivered: balance.parts[0].value,
              bounced: balance.parts[1].value,
              notSent: balance.parts[2].value,
              total: balance.total,
            })
          }}
        </p>
        <p class="m-0 text-xs text-n-slate-11" data-metrics-help>
          {{ metricsHelp }}
        </p>
      </div>

      <RecipientImportStatus :campaign="health" :can-recover="canManage" />
      <ResultEmailHealth
        :campaign="health"
        @updated="refresh"
        @problems="recipientsPanel?.showProblems()"
      />

      <div class="grid min-w-0 grid-cols-1 gap-6 xl:grid-cols-3">
        <div class="min-w-0 xl:col-span-2">
          <CampaignTimelineChart
            :series="timeline"
            :source="timelineSource"
            :interval="timelineInterval"
            :loading="timelineLoading"
            :error="timelineError"
            @update:interval="setTimelineInterval"
          />
        </div>
        <ResultLinkClicks
          :clicks="clicks"
          :loading="clicksLoading"
          :error="clicksError"
        />
      </div>

      <ResultCrmBand :name="result.campaign.name" :crm="result.crm" />
      <ResultRepliedList
        :channel="CHANNEL"
        :campaign-id="campaignId"
        :refresh-key="refreshKey"
      />
      <ResultEmailRecipients
        ref="recipientsPanel"
        :campaign-id="campaignId"
        :refresh-key="refreshKey"
      />
    </template>
  </div>
</template>
