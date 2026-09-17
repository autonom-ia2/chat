<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import EmailRecipients from 'dashboard/components-next/Campaigns/EmailProtection/EmailRecipients.vue';
import EmailStatusBadge from 'dashboard/components-next/Campaigns/EmailProtection/EmailStatusBadge.vue';
import EmailStatusFilter from 'dashboard/components-next/Campaigns/EmailProtection/EmailStatusFilter.vue';
import EmailCampaignHealth from 'dashboard/components-next/Campaigns/EmailProtection/EmailCampaignHealth.vue';
import {
  NS,
  formatNumber,
  deliveryKey,
  localeTag,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import { useEmailReportRefresh } from 'dashboard/components-next/Campaigns/EmailProtection/useEmailReportRefresh';
import QRCode from 'qrcode';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import EmailCampaignReportsAPI from 'dashboard/api/emailCampaignReports';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';
import LineChart from 'shared/components/charts/LineChart.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const globalConfig = useMapGetter('globalConfig/get');
const whatsappInboxes = useMapGetter('inboxes/getWhatsAppInboxes');
// Email campaign reports and trackable links are independent modules sharing
// this page: links must work for CRM accounts without the email add-on.
const emailReportsEnabled = computed(
  () =>
    globalConfig.value?.emailCampaignEnabled === true &&
    globalConfig.value?.crmKanbanEnabled === true
);
const trackedLinksEnabled = computed(
  () => globalConfig.value?.crmKanbanEnabled === true
);
const enabled = computed(
  () => emailReportsEnabled.value || trackedLinksEnabled.value
);

const summary = ref(null);
const campaigns = ref([]);
const campaignOptions = ref([]);
const selectedCampaignId = ref(
  typeof route.query.email_campaign === 'string'
    ? route.query.email_campaign
    : ''
);
const campaignStatus = ref(
  typeof route.query.email_status === 'string' ? route.query.email_status : ''
);
const reportRequest = useAbortableRequest();
const timelineRequest = useAbortableRequest();
const clicksRequest = useAbortableRequest();
const isLoading = reportRequest.isPending;
const health = ref({});
const recipientsPanel = ref(null);
const timelineError = ref(false);
const clicksError = ref(false);
const timelineLoading = timelineRequest.isPending;
const clicksLoading = clicksRequest.isPending;
const number = value => formatNumber(value, locale.value);
const hasError = ref(false);

const timeline = ref([]);
const timelineSource = ref({});
const deliveryLabel = source => t(`${NS}.STATUS.${deliveryKey(source)}`);
const timelineInterval = ref('day');
const clicks = ref([]);
const trackedLinks = ref([]);
const trackedLinkForm = ref({
  name: '',
  inboxId: '',
  prefilledText: '',
});
const isTrackedLinksLoading = ref(false);
const isTrackedLinkCreating = ref(false);
const deletingTrackedLinkId = ref(null);
const copiedTrackedLinkId = ref(null);

const kpiCards = computed(() => {
  const s = summary.value || {};
  return [
    {
      key: 'SENT',
      label: t('CAMPAIGN_MANAGEMENT.KPIS.SENT'),
      icon: 'i-lucide-send',
      value: s.sent ?? null,
      rate: null,
    },
    {
      key: 'DELIVERED',
      label: deliveryLabel(s),
      icon: 'i-lucide-mail-check',
      value: s.delivered ?? null,
      rate: null,
    },
    {
      key: 'OPENED',
      label: `${t('CAMPAIGN_MANAGEMENT.KPIS.OPENED')} (${t('CAMPAIGN_MANAGEMENT.APPROXIMATE')})`,
      icon: 'i-lucide-mail-open',
      value: s.opened ?? null,
      rate: s.open_rate,
    },
    {
      key: 'CLICKED',
      label: t('CAMPAIGN_MANAGEMENT.KPIS.CLICKED'),
      icon: 'i-lucide-mouse-pointer-click',
      value: s.clicked ?? null,
      rate: s.click_rate,
    },
    {
      key: 'UNSUBSCRIBED',
      label: t('CAMPAIGN_MANAGEMENT.KPIS.UNSUBSCRIBED'),
      icon: 'i-lucide-user-x',
      value: s.unsubscribed ?? null,
      rate: s.unsubscribe_rate,
    },
    {
      key: 'BOUNCED',
      label: t(`${NS}.STATUS.permanent`),
      icon: 'i-lucide-mail-x',
      value: s.permanent_bounced ?? null,
      rate: s.hard_bounce_rate,
    },
    {
      key: 'COMPLAINED',
      label: t(`${NS}.STATUS.complained`),
      icon: 'i-lucide-octagon-alert',
      value: s.complained ?? null,
      rate: s.complaint_rate,
    },
    {
      key: 'TEMPORARY',
      label: t(`${NS}.STATUS.temporary`),
      icon: 'i-lucide-clock',
      value: s.temporary_bounced,
      rate: null,
    },
    {
      key: 'UNKNOWN',
      label: t(`${NS}.STATUS.bounce_unknown`),
      icon: 'i-lucide-circle-help',
      value: s.unknown_bounced,
      rate: null,
    },
  ];
});

const rateLabel = (rate, key) => {
  if (typeof rate !== 'number') return '—';
  const denominator = ['BOUNCED', 'COMPLAINED'].includes(key)
    ? t(`${NS}.OVER_SENT`)
    : `· ${deliveryLabel(summary.value || {})}`;
  return `${t(`${NS}.RATE`, { value: number(rate) })} ${denominator}`;
};

const hasCampaigns = computed(() => campaigns.value.length > 0);
const hasTrackedLinks = computed(() => trackedLinks.value.length > 0);
const canCreateTrackedLink = computed(
  () =>
    trackedLinkForm.value.name.trim().length > 0 &&
    Boolean(trackedLinkForm.value.inboxId)
);

const percentage = value =>
  typeof value === 'number' ? t(`${NS}.RATE`, { value: number(value) }) : '—';
const comparisonRows = computed(() =>
  campaigns.value.map(c => ({
    ...c,
    openRate: percentage(c.open_rate),
    clickRate: percentage(c.click_rate),
    bounceRate: percentage(c.hard_bounce_rate),
    unsubscribeRate: percentage(c.unsubscribe_rate),
  }))
);

const formatBucket = value => {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  if (timelineInterval.value === 'hour') {
    return new Intl.DateTimeFormat(localeTag(locale.value), {
      day: '2-digit',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
    }).format(date);
  }
  return new Intl.DateTimeFormat(localeTag(locale.value), {
    day: '2-digit',
    month: 'short',
  }).format(date);
};

const timelineCollection = computed(() => ({
  labels: timeline.value.map(bucket => formatBucket(bucket.bucket)),
  datasets: [
    {
      label: deliveryLabel(timelineSource.value),
      data: timeline.value.map(bucket => bucket.delivered ?? null),
      borderColor: '#16a34a',
      backgroundColor: '#16a34a',
      tension: 0.2,
    },
    {
      label: `${t('CAMPAIGN_MANAGEMENT.KPIS.OPENED')} (${t('CAMPAIGN_MANAGEMENT.APPROXIMATE')})`,
      data: timeline.value.map(bucket => bucket.open ?? null),
      borderColor: '#2563eb',
      backgroundColor: '#2563eb',
      tension: 0.2,
    },
    {
      label: t('CAMPAIGN_MANAGEMENT.KPIS.CLICKED'),
      data: timeline.value.map(bucket => bucket.click ?? null),
      borderColor: '#7c3aed',
      backgroundColor: '#7c3aed',
      tension: 0.2,
    },
  ],
}));

const fetchReports = async () => {
  if (!emailReportsEnabled.value) return;
  hasError.value = false;
  try {
    const response = await reportRequest.run(signal =>
      EmailCampaignReportsAPI.getReports(selectedCampaignId.value, {
        campaignStatus: campaignStatus.value,
        signal,
      })
    );
    if (!response) return;
    const { payload } = response.data;
    summary.value = payload.summary;
    campaigns.value = payload.campaigns || [];
    // Options have their own contract; never replace them with selected results.
    if (payload.campaign_options)
      campaignOptions.value = payload.campaign_options;
    else if (!selectedCampaignId.value && !campaignStatus.value)
      campaignOptions.value = payload.campaigns || [];
    const campaign =
      campaigns.value.find(
        item => String(item.id) === String(selectedCampaignId.value)
      ) || {};
    health.value = {
      ...campaign,
      id: selectedCampaignId.value || undefined,
      protection: payload.protection || campaign.protection,
      preflight: payload.preflight || campaign.preflight,
    };
  } catch (error) {
    hasError.value = true;
  }
};
const fetchTimeline = async () => {
  timelineError.value = false;
  timelineSource.value = {};
  timeline.value = [];
  try {
    const response = await timelineRequest.run(signal =>
      EmailCampaignReportsAPI.getTimeline(
        selectedCampaignId.value,
        timelineInterval.value,
        { signal }
      )
    );
    if (response) {
      timeline.value = response.data.payload.series || [];
      timelineSource.value = {
        delivery_mode: response.data.payload.delivery_mode,
      };
    }
  } catch (error) {
    timelineError.value = true;
  }
};
const fetchClicks = async () => {
  clicksError.value = false;
  try {
    const response = await clicksRequest.run(signal =>
      EmailCampaignReportsAPI.getClicks(selectedCampaignId.value, { signal })
    );
    if (response) clicks.value = response.data.payload.clicks || [];
  } catch (error) {
    clicksError.value = true;
  }
};
const fetchCampaignDrilldown = async () => {
  if (!selectedCampaignId.value) {
    timelineRequest.abort();
    clicksRequest.abort();
    timeline.value = [];
    clicks.value = [];
    return;
  }
  await Promise.all([fetchTimeline(), fetchClicks()]);
};
const onFilterChange = async () => {
  router.replace({
    query: {
      ...route.query,
      email_campaign: selectedCampaignId.value || undefined,
      email_status: campaignStatus.value || undefined,
    },
  });
  await Promise.all([fetchReports(), fetchCampaignDrilldown()]);
};
useEmailReportRefresh(() =>
  !isLoading.value && emailReportsEnabled.value
    ? Promise.all([fetchReports(), fetchCampaignDrilldown()])
    : undefined
);

const intervalOptions = computed(() => [
  { id: 'day', label: t('CAMPAIGN_MANAGEMENT.TIMELINE.INTERVAL.DAY') },
  { id: 'hour', label: t('CAMPAIGN_MANAGEMENT.TIMELINE.INTERVAL.HOUR') },
]);

const openRateApproxHeader = computed(
  () =>
    `${t('CAMPAIGN_MANAGEMENT.RATES.OPEN_RATE')} (${t('CAMPAIGN_MANAGEMENT.APPROXIMATE')})`
);

const setTimelineInterval = async interval => {
  timelineInterval.value = interval;
  await fetchTimeline();
};

const resetTrackedLinkForm = () => {
  trackedLinkForm.value = {
    name: '',
    inboxId: '',
    prefilledText: '',
  };
};

const fetchTrackedLinks = async () => {
  isTrackedLinksLoading.value = true;
  try {
    const { data } = await CtwaTrackedLinksAPI.get();
    trackedLinks.value = data.payload || [];
  } catch (error) {
    trackedLinks.value = [];
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.CREATE_ERROR'));
  } finally {
    isTrackedLinksLoading.value = false;
  }
};

const createTrackedLink = async () => {
  if (!canCreateTrackedLink.value || isTrackedLinkCreating.value) return;

  isTrackedLinkCreating.value = true;
  try {
    await CtwaTrackedLinksAPI.create({
      name: trackedLinkForm.value.name.trim(),
      inbox_id: Number(trackedLinkForm.value.inboxId),
      prefilled_text: trackedLinkForm.value.prefilledText.trim(),
    });
    resetTrackedLinkForm();
    await fetchTrackedLinks();
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.CREATE_SUCCESS'));
  } catch (error) {
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.CREATE_ERROR'));
  } finally {
    isTrackedLinkCreating.value = false;
  }
};

const copyTrackedLink = async link => {
  if (!link.short_url) return;

  try {
    await navigator.clipboard.writeText(link.short_url);
    copiedTrackedLinkId.value = link.id;
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.COPIED'));
    window.setTimeout(() => {
      if (copiedTrackedLinkId.value === link.id) {
        copiedTrackedLinkId.value = null;
      }
    }, 2000);
  } catch (error) {
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.CREATE_ERROR'));
  }
};

// O QR aponta para o link curto (/l/CODIGO), nao direto para o wa.me: e o redirecionamento
// que conta o clique e captura gclid/utm. QR apontando para o wa.me nunca contabiliza.
const downloadTrackedLinkQr = async link => {
  if (!link.short_url) return;

  try {
    const qrDataUrl = await QRCode.toDataURL(link.short_url, { width: 512 });
    const anchor = document.createElement('a');
    anchor.href = qrDataUrl;
    anchor.download = `${link.code || 'ctwa-link'}-qr.png`;
    anchor.click();
  } catch (error) {
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.CREATE_ERROR'));
  }
};

const deleteTrackedLink = async link => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CRM_KANBAN.TRACKED_LINKS.DELETE_CONFIRM'))) return;

  deletingTrackedLinkId.value = link.id;
  try {
    await CtwaTrackedLinksAPI.delete(link.id);
    trackedLinks.value = trackedLinks.value.filter(item => item.id !== link.id);
  } catch (error) {
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.CREATE_ERROR'));
  } finally {
    deletingTrackedLinkId.value = null;
  }
};

onMounted(() => {
  if (emailReportsEnabled.value) {
    fetchReports();
    fetchCampaignDrilldown();
  }
  if (trackedLinksEnabled.value) {
    fetchTrackedLinks();
    store.dispatch('inboxes/get');
  }
});
</script>

<template>
  <div
    class="flex flex-col min-w-0 w-full h-full overflow-y-auto bg-n-background"
  >
    <header class="px-6 py-5 border-b border-n-weak">
      <div class="min-w-0">
        <h1 class="mb-1 text-xl font-semibold text-n-slate-12">
          {{ t('CAMPAIGN_MANAGEMENT.HEADER.TITLE') }}
        </h1>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('CAMPAIGN_MANAGEMENT.HEADER.DESCRIPTION') }}
        </p>
      </div>
    </header>

    <div
      v-if="!enabled"
      class="flex flex-col items-center justify-center flex-1 gap-3 p-8 text-center"
    >
      <span class="i-lucide-lock size-8 text-n-slate-10" />
      <h2 class="m-0 text-lg font-medium text-n-slate-12">
        {{ t('CAMPAIGN_MANAGEMENT.PAYWALL.TITLE') }}
      </h2>
      <p class="max-w-md m-0 text-sm text-n-slate-11">
        {{ t('CAMPAIGN_MANAGEMENT.PAYWALL.DESCRIPTION') }}
      </p>
    </div>

    <div v-else class="flex flex-col min-w-0 gap-6 p-6">
      <template v-if="emailReportsEnabled">
        <section
          class="flex flex-col gap-1 p-5 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CAMPAIGN_MANAGEMENT.FILTER.LABEL') }}
          </span>
          <div class="flex flex-wrap items-center gap-3">
            <select
              v-model="selectedCampaignId"
              :aria-label="t('CAMPAIGN_MANAGEMENT.FILTER.LABEL')"
              class="px-3 h-9 text-sm border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12 min-w-60"
              @change="onFilterChange"
            >
              <option value="">
                {{ t('CAMPAIGN_MANAGEMENT.FILTER.ALL') }}
              </option>
              <option
                v-for="campaign in campaignOptions"
                :key="campaign.id"
                :value="campaign.id"
              >
                {{ campaign.name }}
              </option>
            </select>
            <EmailStatusFilter
              v-model="campaignStatus"
              campaign
              @update:model-value="onFilterChange"
            />
            <Button
              :label="t(`${NS}.REFRESH`)"
              icon="i-lucide-refresh-cw"
              slate
              outline
              :disabled="isLoading"
              @click="onFilterChange"
            />
          </div>
        </section>
      </template>

      <section
        v-if="trackedLinksEnabled"
        class="flex flex-col gap-5 p-5 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="flex flex-col gap-1">
          <h2 class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('CRM_KANBAN.TRACKED_LINKS.TITLE') }}
          </h2>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('CRM_KANBAN.TRACKED_LINKS.SUBTITLE') }}
          </p>
        </div>

        <form
          class="grid grid-cols-1 gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(12rem,16rem)_minmax(0,1.5fr)_auto]"
          @submit.prevent="createTrackedLink"
        >
          <Input
            v-model="trackedLinkForm.name"
            :label="t('CRM_KANBAN.TRACKED_LINKS.NAME')"
            :placeholder="t('CRM_KANBAN.TRACKED_LINKS.NAME_PLACEHOLDER')"
          />

          <label class="flex flex-col min-w-0 gap-1">
            <span class="mb-0.5 text-heading-3 text-n-slate-12">
              {{ t('CRM_KANBAN.TRACKED_LINKS.INBOX') }}
            </span>
            <select
              v-model="trackedLinkForm.inboxId"
              class="w-full px-3 h-10 text-sm border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12"
            >
              <option value="">
                {{ t('CRM_KANBAN.TRACKED_LINKS.INBOX') }}
              </option>
              <option
                v-for="inbox in whatsappInboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </select>
          </label>

          <Input
            v-model="trackedLinkForm.prefilledText"
            :label="t('CRM_KANBAN.TRACKED_LINKS.PREFILLED')"
            :placeholder="t('CRM_KANBAN.TRACKED_LINKS.PREFILLED_PLACEHOLDER')"
          />

          <div class="flex items-end">
            <Button
              :label="t('CRM_KANBAN.TRACKED_LINKS.ADD')"
              icon="i-lucide-plus"
              type="submit"
              class="w-full lg:w-auto"
              :disabled="!canCreateTrackedLink || isTrackedLinkCreating"
              :is-loading="isTrackedLinkCreating"
            />
          </div>
        </form>

        <div
          v-if="isTrackedLinksLoading"
          class="flex items-center justify-center py-10 text-sm text-n-slate-11"
        >
          <span class="i-lucide-loader-2 size-5 animate-spin" />
        </div>

        <div
          v-else-if="!hasTrackedLinks"
          class="py-8 text-sm text-center border rounded-lg border-n-weak bg-n-alpha-black1 text-n-slate-11"
        >
          {{ t('CRM_KANBAN.TRACKED_LINKS.EMPTY') }}
        </div>

        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm border-collapse">
            <thead>
              <tr class="text-start border-b border-n-weak text-n-slate-11">
                <th class="py-2 pe-3 text-xs font-medium">
                  {{ t('CRM_KANBAN.TRACKED_LINKS.NAME') }}
                </th>
                <th class="py-2 pe-3 text-xs font-medium">
                  {{ t('CRM_KANBAN.TRACKED_LINKS.CODE') }}
                </th>
                <th class="py-2 pe-3 text-xs font-medium text-end">
                  {{ t('CRM_KANBAN.TRACKED_LINKS.CLICKS') }}
                </th>
                <th class="py-2 pe-3 text-xs font-medium text-end">
                  {{ t('CRM_KANBAN.TRACKED_LINKS.CONVERSATIONS') }}
                </th>
                <th class="py-2 text-xs font-medium text-end">
                  {{ t('CRM_KANBAN.TRACKED_LINKS.COPY_LINK') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="link in trackedLinks"
                :key="link.id"
                class="border-b border-n-weak last:border-b-0"
              >
                <td class="max-w-xs py-3 pe-3">
                  <span class="block truncate text-n-slate-12">
                    {{ link.name }}
                  </span>
                  <span
                    v-if="link.prefilled_text"
                    class="block truncate text-xs text-n-slate-10"
                  >
                    {{ link.prefilled_text }}
                  </span>
                </td>
                <td class="py-3 pe-3 font-mono text-xs text-n-slate-11">
                  {{ link.code }}
                </td>
                <td class="py-3 pe-3 text-end text-n-slate-12">
                  {{ link.clicks_count ?? 0 }}
                </td>
                <td class="py-3 pe-3 text-end text-n-slate-12">
                  {{ link.conversations_count ?? 0 }}
                </td>
                <td class="py-3">
                  <div class="flex flex-wrap justify-end gap-2">
                    <Button
                      :label="
                        copiedTrackedLinkId === link.id
                          ? t('CRM_KANBAN.TRACKED_LINKS.COPIED')
                          : t('CRM_KANBAN.TRACKED_LINKS.COPY_LINK')
                      "
                      icon="i-lucide-copy"
                      slate
                      outline
                      sm
                      type="button"
                      :disabled="!link.short_url"
                      @click="copyTrackedLink(link)"
                    />
                    <Button
                      :label="t('CRM_KANBAN.TRACKED_LINKS.DOWNLOAD_QR')"
                      icon="i-lucide-qr-code"
                      slate
                      outline
                      sm
                      type="button"
                      :disabled="!link.short_url"
                      @click="downloadTrackedLinkQr(link)"
                    />
                    <Button
                      :label="t('CRM_KANBAN.TRACKED_LINKS.DELETE')"
                      icon="i-lucide-trash-2"
                      ruby
                      ghost
                      sm
                      type="button"
                      :disabled="deletingTrackedLinkId === link.id"
                      :is-loading="deletingTrackedLinkId === link.id"
                      @click="deleteTrackedLink(link)"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <template v-if="emailReportsEnabled">
        <p v-if="isLoading" role="status" class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.LOADING`) }}
        </p>
        <p v-else-if="hasError" class="m-0 text-sm text-n-ruby-11">
          {{ t('CAMPAIGN_MANAGEMENT.ERROR') }}
        </p>

        <div
          v-else-if="!isLoading && !hasCampaigns"
          class="flex flex-col items-center justify-center gap-2 p-10 text-center border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="i-lucide-inbox size-8 text-n-slate-10" />
          <h2 class="m-0 text-base font-medium text-n-slate-12">
            {{ t('CAMPAIGN_MANAGEMENT.EMPTY_STATE.TITLE') }}
          </h2>
          <p class="max-w-md m-0 text-sm text-n-slate-11">
            {{ t('CAMPAIGN_MANAGEMENT.EMPTY_STATE.SUBTITLE') }}
          </p>
        </div>

        <div
          v-if="summary && hasCampaigns"
          v-show="!isLoading && !hasError"
          class="flex flex-col min-w-0 gap-6"
        >
          <EmailCampaignHealth
            :campaign="health"
            @updated="fetchReports"
            @problems="recipientsPanel?.showProblems()"
          />
          <section class="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-4">
            <div
              v-for="card in kpiCards"
              :key="card.key"
              class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-1"
            >
              <div class="flex items-center gap-2 text-n-slate-11">
                <span :class="card.icon" class="size-4" />
                <span class="text-xs font-medium">{{ card.label }}</span>
              </div>
              <span class="text-2xl font-semibold text-n-slate-12">
                {{ number(card.value) }}
              </span>
              <span
                v-if="card.rate !== null && card.rate !== undefined"
                class="text-xs text-n-slate-11"
              >
                {{ rateLabel(card.rate, card.key) }}
              </span>
            </div>
          </section>

          <p class="flex items-start gap-2 m-0 text-xs text-n-slate-11">
            <span class="i-lucide-info size-4 shrink-0" />
            {{ t(`${NS}.METRICS_HINT`) }}
          </p>

          <p
            v-if="deliveryKey(summary) !== 'delivered'"
            class="m-0 text-xs text-n-slate-11"
          >
            {{ t(`${NS}.DELIVERY_HINT`) }}
          </p>
          <p
            v-if="summary.delivery_evidence"
            class="m-0 text-xs text-n-slate-11"
          >
            {{
              `${t(`${NS}.STATUS.delivered`)}: ${number(summary.delivery_evidence.provider_confirmed)}`
            }}
            {{
              ` · ${t(`${NS}.STATUS.accepted_service`)}: ${number(summary.delivery_evidence.direct_acceptance_only)}`
            }}
          </p>

          <template v-if="selectedCampaignId">
            <section
              class="flex flex-col gap-3 p-5 border rounded-xl border-n-weak bg-n-solid-1"
            >
              <div class="flex items-center justify-between gap-3">
                <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                  {{ t('CAMPAIGN_MANAGEMENT.TIMELINE.TITLE') }}
                </h3>
                <div class="flex gap-1">
                  <button
                    v-for="option in intervalOptions"
                    :key="option.id"
                    class="px-2 py-1 text-xs font-medium border rounded-lg border-n-weak"
                    :class="
                      timelineInterval === option.id
                        ? 'bg-n-alpha-2 text-n-slate-12'
                        : 'bg-n-alpha-black1 text-n-slate-11'
                    "
                    @click="setTimelineInterval(option.id)"
                  >
                    {{ option.label }}
                  </button>
                </div>
              </div>
              <p v-if="timelineLoading" class="m-0 text-sm text-n-slate-11">
                {{ t(`${NS}.LOADING`) }}
              </p>
              <p
                v-else-if="timelineError"
                role="alert"
                class="m-0 text-sm text-n-ruby-11"
              >
                {{ t(`${NS}.ERROR`) }}
              </p>
              <p
                v-else-if="!timeline.length"
                class="m-0 text-sm text-n-slate-11"
              >
                {{ t('CAMPAIGN_MANAGEMENT.TIMELINE.EMPTY') }}
              </p>
              <template v-else>
                <div class="h-64">
                  <LineChart :collection="timelineCollection" />
                </div>
                <p
                  v-if="deliveryKey(timelineSource) !== 'delivered'"
                  class="m-0 text-xs text-n-slate-11"
                >
                  {{ t(`${NS}.DELIVERY_HINT`) }}
                </p>
              </template>
            </section>

            <section
              class="flex flex-col gap-3 p-5 border rounded-xl border-n-weak bg-n-solid-1"
            >
              <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.TITLE') }}
              </h3>
              <p v-if="clicksLoading" class="m-0 text-sm text-n-slate-11">
                {{ t(`${NS}.LOADING`) }}
              </p>
              <p
                v-else-if="clicksError"
                role="alert"
                class="m-0 text-sm text-n-ruby-11"
              >
                {{ t(`${NS}.ERROR`) }}
              </p>
              <p v-else-if="!clicks.length" class="m-0 text-sm text-n-slate-11">
                {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.EMPTY') }}
              </p>
              <div v-else class="max-w-full overflow-x-auto">
                <table class="w-full text-sm border-collapse">
                  <thead>
                    <tr
                      class="text-start border-b border-n-weak text-n-slate-11"
                    >
                      <th class="py-2 pe-3 text-xs font-medium">
                        {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.URL') }}
                      </th>
                      <th class="py-2 pe-3 text-xs font-medium text-end">
                        {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.UNIQUE') }}
                      </th>
                      <th class="py-2 text-xs font-medium text-end">
                        {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.TOTAL') }}
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      v-for="click in clicks"
                      :key="click.url"
                      class="border-b border-n-weak last:border-b-0"
                    >
                      <td class="max-w-md py-2 pe-3 truncate text-n-slate-12">
                        {{ click.url }}
                      </td>
                      <td class="py-2 pe-3 text-end text-n-slate-12">
                        {{ number(click.unique_clicks) }}
                      </td>
                      <td class="py-2 text-end text-n-slate-12">
                        {{ number(click.total_clicks) }}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>

            <EmailRecipients
              ref="recipientsPanel"
              :campaign-id="selectedCampaignId"
            />
          </template>

          <section
            class="flex flex-col gap-3 p-5 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <h3 class="m-0 text-sm font-semibold text-n-slate-12">
              {{ t('CAMPAIGN_MANAGEMENT.COMPARISON.TITLE') }}
            </h3>
            <div class="max-w-full overflow-x-auto">
              <table class="w-full text-sm border-collapse">
                <thead>
                  <tr class="text-start border-b border-n-weak text-n-slate-11">
                    <th class="py-2 pe-3 text-xs font-medium">
                      {{ t('CAMPAIGN_MANAGEMENT.TABLE.NAME') }}
                    </th>
                    <th class="py-2 pe-3 text-xs font-medium">
                      {{ t('CAMPAIGN_MANAGEMENT.TABLE.STATUS') }}
                    </th>
                    <th class="py-2 pe-3 text-xs font-medium text-end">
                      {{ t('CAMPAIGN_MANAGEMENT.KPIS.SENT') }}
                    </th>
                    <th class="py-2 pe-3 text-xs font-medium text-end">
                      {{ deliveryLabel(summary) }}
                    </th>
                    <th class="py-2 pe-3 text-xs font-medium text-end">
                      {{ openRateApproxHeader }}
                    </th>
                    <th class="py-2 pe-3 text-xs font-medium text-end">
                      {{ t('CAMPAIGN_MANAGEMENT.RATES.CLICK_RATE') }}
                    </th>
                    <th class="py-2 pe-3 text-xs font-medium text-end">
                      {{ t(`${NS}.HARD_RATE`) }}
                    </th>
                    <th class="py-2 text-xs font-medium text-end">
                      {{ t('CAMPAIGN_MANAGEMENT.RATES.UNSUBSCRIBE_RATE') }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="row in comparisonRows"
                    :key="row.id"
                    class="border-b border-n-weak last:border-b-0"
                  >
                    <td class="max-w-xs py-2 pe-3 truncate text-n-slate-12">
                      {{ row.name }}
                    </td>
                    <td class="py-2 pe-3 text-n-slate-11">
                      <EmailStatusBadge :record="row" campaign />
                    </td>
                    <td class="py-2 pe-3 text-end text-n-slate-12">
                      {{ number(row.sent) }}
                    </td>
                    <td class="py-2 pe-3 text-end text-n-slate-12">
                      {{ number(row.delivered) }}
                      <span class="block text-xs text-n-slate-11">{{
                        deliveryLabel(row)
                      }}</span>
                    </td>
                    <td class="py-2 pe-3 text-end text-n-slate-12">
                      {{ row.openRate }}
                    </td>
                    <td class="py-2 pe-3 text-end text-n-slate-12">
                      {{ row.clickRate }}
                    </td>
                    <td class="py-2 pe-3 text-end text-n-slate-12">
                      {{ row.bounceRate }}
                    </td>
                    <td class="py-2 text-end text-n-slate-12">
                      {{ row.unsubscribeRate }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </template>
    </div>
  </div>
</template>
