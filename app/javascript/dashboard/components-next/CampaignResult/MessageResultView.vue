<script setup>
// Result of a message campaign — WhatsApp Oficial, WhatsApp API and SMS (#1007, PRD §6.5, O2):
// Público, Enviadas, Entregues, Lidas (Oficial), Responderam, Falharam and Puladas; the E1 sum;
// "processando" band with refresh every 15s (E2); the delivery chart of the old WhatsApp page;
// the CRM band with "Ver no CRM"; people with the generated message, reason, "Abrir conversa"
// (E3) and "Baixar resultado" (E4). WhatsApp API keeps its Pausar / Retomar / Cancelar.
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import CampaignResultsAPI from 'dashboard/api/campaignResults';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CampaignDeliveryBreakdown from 'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryBreakdown.vue';
import { CAMPAIGN_CHANNELS } from 'dashboard/components-next/CampaignJourney/campaignChannels';
import ResultHeader from './ResultHeader.vue';
import ResultKpiStrip from './ResultKpiStrip.vue';
import ResultCrmBand from './ResultCrmBand.vue';
import ResultPeopleTable from './ResultPeopleTable.vue';
import { useResultPolling } from './useResultPolling';
import { journeyStatus, messageKpis, resultBalance } from './resultMetrics';

const props = defineProps({
  channel: { type: String, required: true },
  campaignId: { type: [String, Number], required: true },
});

const NS = 'RESULT_JOURNEY';
const { t, locale } = useI18n();
const store = useStore();
const canManage = useCanManage('campaign_manage');

const result = ref(null);
const isLoading = ref(false);
const loadError = ref('');
const refreshKey = ref(0);
const busy = ref('');
const cancelDialog = ref(null);
const askingCancel = ref(false);

const campaign = computed(() => result.value?.campaign || {});
const totals = computed(() => result.value?.totals || {});
const isApi = computed(() => props.channel === CAMPAIGN_CHANNELS.WHATSAPP_API);

const date = value =>
  value
    ? new Date(value).toLocaleString(locale.value.replace('_', '-'), {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    : '';

const subtitle = computed(() => {
  const parts = [
    t(`CAMPAIGN_JOURNEY.CHANNELS.${props.channel.toUpperCase()}`),
    campaign.value.inbox?.name,
    campaign.value.template_name &&
      t(`${NS}.SUBTITLE.TEMPLATE`, { name: campaign.value.template_name }),
    campaign.value.scheduled_at &&
      t(`${NS}.SUBTITLE.SENT_ON`, {
        date: date(campaign.value.started_at || campaign.value.scheduled_at),
      }),
    campaign.value.audience &&
      t(`${NS}.SUBTITLE.AUDIENCE`, { name: campaign.value.audience.name }),
  ];
  return parts.filter(Boolean).join(' · ');
});

const kpis = computed(() =>
  messageKpis(props.channel, totals.value).map(kpi => {
    let note = '';
    if (kpi.key === 'audience') note = t(`${NS}.KPI.AUDIENCE_NOTE`);
    else if (kpi.key === 'replied') note = t(`${NS}.KPI.REPLIED_NOTE`);
    else if (kpi.rate !== null)
      note = t(`${NS}.KPI.RATE`, {
        rate: kpi.rate.toLocaleString(locale.value.replace('_', '-')),
      });
    return {
      key: kpi.key,
      label: t(`${NS}.KPI.${kpi.key.toUpperCase()}`),
      value: kpi.value,
      note,
    };
  })
);

const balance = computed(() => resultBalance(props.channel, totals.value));
const showBreakdown = computed(
  () => !isApi.value && (totals.value.audience || 0) > 0
);
const breakdownMetrics = computed(() => ({
  audience: totals.value.audience,
  delivered: totals.value.delivered ?? 0,
  read: totals.value.read ?? 0,
  failed: totals.value.failed,
  skipped: totals.value.skipped,
}));
const smsWithoutRecords = computed(
  () => props.channel === CAMPAIGN_CHANNELS.SMS && !(totals.value.audience > 0)
);

const fetchResult = async () => {
  try {
    const { data } = await CampaignResultsAPI.getResult(
      props.channel,
      props.campaignId
    );
    result.value = data.payload;
    loadError.value = '';
  } catch (error) {
    loadError.value =
      error?.response?.status === 404
        ? t(`${NS}.NOT_FOUND`)
        : t(`${NS}.LOAD_ERROR`);
  }
};

const load = async () => {
  isLoading.value = true;
  result.value = null;
  await fetchResult();
  isLoading.value = false;
};

const refresh = async () => {
  await fetchResult();
  refreshKey.value += 1;
};

useResultPolling(refresh, () => Boolean(campaign.value.processing));

const runApiAction = async action => {
  if (busy.value) return;
  busy.value = action;
  try {
    await store.dispatch(`whatsappApiCampaigns/${action}`, campaign.value.id);
    useAlert(t(`${NS}.ACTIONS.API_${action.toUpperCase()}`));
    await refresh();
  } catch {
    useAlert(t(`${NS}.ACTIONS.ERROR`));
  } finally {
    busy.value = '';
  }
};

const askCancel = async () => {
  askingCancel.value = true;
  await nextTick();
  cancelDialog.value?.open();
};
const confirmCancel = async () => {
  await runApiAction('cancel');
  cancelDialog.value?.close();
};

watch(() => [props.channel, props.campaignId], load, { immediate: true });
</script>

<template>
  <div class="flex flex-col gap-6">
    <div v-if="isLoading" class="flex justify-center p-12">
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
        :name="campaign.name"
        :channel="channel"
        :status-key="journeyStatus(channel, campaign.status)"
        :subtitle="subtitle"
      >
        <template #actions>
          <template v-if="isApi && canManage">
            <Button
              v-if="campaign.status === 'running'"
              :label="t(`${NS}.ACTIONS.PAUSE`)"
              icon="i-lucide-pause"
              amber
              outline
              class="!min-h-11 !rounded-xl"
              :is-loading="busy === 'pause'"
              data-action="pause"
              @click="runApiAction('pause')"
            />
            <Button
              v-if="campaign.status === 'paused'"
              :label="t(`${NS}.ACTIONS.RESUME`)"
              icon="i-lucide-play"
              slate
              outline
              class="!min-h-11 !rounded-xl"
              :is-loading="busy === 'resume'"
              data-action="resume"
              @click="runApiAction('resume')"
            />
            <Button
              v-if="
                ['scheduled', 'running', 'paused'].includes(campaign.status)
              "
              :label="t(`${NS}.ACTIONS.CANCEL`)"
              icon="i-lucide-x"
              ruby
              outline
              class="!min-h-11 !rounded-xl"
              data-action="cancel"
              @click="askCancel"
            />
          </template>
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
        v-if="campaign.processing"
        role="status"
        class="m-0 flex items-start gap-3 rounded-2xl border border-n-amber-6 bg-n-amber-2 px-5 py-4 text-sm text-n-amber-12"
        data-processing
      >
        <span
          class="i-lucide-loader-circle mt-0.5 size-4 shrink-0 animate-spin"
          aria-hidden="true"
        />
        {{
          t(`${NS}.PROCESSING`, {
            queued: totals.queued || 0,
          })
        }}
      </p>
      <p
        v-if="smsWithoutRecords"
        class="m-0 rounded-2xl border border-n-weak bg-n-solid-1 px-5 py-4 text-sm text-n-slate-11"
        data-sms-partial
      >
        {{ t(`${NS}.SMS_PARTIAL`) }}
      </p>

      <ResultKpiStrip :items="kpis" :label="t(`${NS}.KPI.LABEL`)" />
      <p
        class="m-0 text-xs text-n-slate-11"
        :class="{ 'text-n-ruby-11': !balance.holds }"
        data-balance
      >
        {{
          t(`${NS}.BALANCE.MESSAGE`, {
            sent: balance.parts[0].value,
            failed: balance.parts[1].value,
            skipped: balance.parts[2].value,
            queued: balance.parts[3].value,
            total: balance.total,
          })
        }}
      </p>

      <CampaignDeliveryBreakdown
        v-if="showBreakdown"
        :metrics="breakdownMetrics"
      />

      <ResultCrmBand :name="campaign.name" :crm="result.crm" />

      <ResultPeopleTable
        :channel="channel"
        :campaign-id="campaignId"
        :filters="result.filters"
        :totals="totals"
        :refresh-key="refreshKey"
      />
    </template>
    <Dialog
      v-if="askingCancel"
      ref="cancelDialog"
      type="alert"
      :title="t(`${NS}.ACTIONS.CONFIRM_CANCEL`)"
      :description="campaign.name"
      :is-loading="busy === 'cancel'"
      @confirm="confirmCancel"
      @close="askingCancel = false"
    />
  </div>
</template>
