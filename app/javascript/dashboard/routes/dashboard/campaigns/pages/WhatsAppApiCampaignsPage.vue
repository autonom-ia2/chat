<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { useStore } from 'dashboard/composables/store';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import WhatsAppApiCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppApiCampaign/WhatsAppApiCampaignDialog.vue';

const { t } = useI18n();
const store = useStore();
const refreshTimer = ref(null);
const [showCreateDialog, toggleCreateDialog] = useToggle();
const canManage = useCanManage('campaign_manage');

const campaigns = useMapGetter('whatsappApiCampaigns/getCampaigns');
const uiFlags = useMapGetter('whatsappApiCampaigns/getUIFlags');
const globalConfig = useMapGetter('globalConfig/get');

const isFetching = computed(() => uiFlags.value.isFetching);
const enabled = computed(
  () => globalConfig.value?.whatsappApiCampaignsEnabled === true
);
const activeCampaigns = computed(() =>
  campaigns.value.filter(campaign =>
    ['scheduled', 'running', 'paused'].includes(campaign.status)
  )
);

const statusLabel = status => {
  switch (status) {
    case 'scheduled':
      return t('CAMPAIGN.WHATSAPP_API.STATUS.SCHEDULED');
    case 'running':
      return t('CAMPAIGN.WHATSAPP_API.STATUS.RUNNING');
    case 'paused':
      return t('CAMPAIGN.WHATSAPP_API.STATUS.PAUSED');
    case 'completed':
      return t('CAMPAIGN.WHATSAPP_API.STATUS.COMPLETED');
    case 'completed_with_failures':
      return t('CAMPAIGN.WHATSAPP_API.STATUS.COMPLETED_WITH_FAILURES');
    case 'cancelled':
      return t('CAMPAIGN.WHATSAPP_API.STATUS.CANCELLED');
    case 'failed':
      return t('CAMPAIGN.WHATSAPP_API.STATUS.FAILED');
    default:
      return t('CAMPAIGN.WHATSAPP_API.STATUS.UNKNOWN');
  }
};

const statusClass = status => {
  const map = {
    scheduled: 'text-n-blue-11 bg-n-blue-3',
    running: 'text-n-teal-11 bg-n-teal-3',
    paused: 'text-n-amber-11 bg-n-amber-3',
    completed: 'text-n-teal-11 bg-n-teal-3',
    completed_with_failures: 'text-n-amber-11 bg-n-amber-3',
    cancelled: 'text-n-slate-11 bg-n-alpha-2',
    failed: 'text-n-ruby-11 bg-n-ruby-3',
  };
  return map[status] || 'text-n-slate-11 bg-n-alpha-2';
};

const audienceProgress = campaign =>
  `${campaign.sent_count}/${campaign.recipients_count}`;

const scheduledAtLabel = scheduledAt =>
  scheduledAt ? new Date(scheduledAt).toLocaleString() : '';

const fetchCampaigns = (silent = false) =>
  enabled.value
    ? store.dispatch('whatsappApiCampaigns/get', { silent })
    : Promise.resolve();

const refreshData = async (silent = false) => {
  await Promise.all([
    fetchCampaigns(silent),
    store.dispatch('labels/get'),
    store.dispatch('inboxes/get'),
  ]);
};

const startPolling = () => {
  if (refreshTimer.value) clearInterval(refreshTimer.value);
  refreshTimer.value = setInterval(() => {
    if (activeCampaigns.value.length > 0) fetchCampaigns(true);
  }, 10000);
};

const runAction = async (action, campaign) => {
  try {
    await store.dispatch(`whatsappApiCampaigns/${action}`, campaign.id);
    switch (action) {
      case 'pause':
        useAlert(t('CAMPAIGN.WHATSAPP_API.ACTIONS.PAUSE_SUCCESS'));
        break;
      case 'resume':
        useAlert(t('CAMPAIGN.WHATSAPP_API.ACTIONS.RESUME_SUCCESS'));
        break;
      case 'cancel':
        useAlert(t('CAMPAIGN.WHATSAPP_API.ACTIONS.CANCEL_SUCCESS'));
        break;
      default:
        useAlert(t('CAMPAIGN.WHATSAPP_API.ACTIONS.ERROR'));
    }
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP_API.ACTIONS.ERROR'));
  }
};

onMounted(() => {
  refreshData();
  startPolling();
});

onBeforeUnmount(() => {
  if (refreshTimer.value) clearInterval(refreshTimer.value);
});
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.WHATSAPP_API.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.WHATSAPP_API.NEW_CAMPAIGN')"
    @click="toggleCreateDialog()"
    @close="toggleCreateDialog(false)"
  >
    <template #action>
      <WhatsAppApiCampaignDialog
        v-if="showCreateDialog"
        @created="refreshData(true)"
        @close="toggleCreateDialog(false)"
      />
    </template>

    <div class="flex flex-col gap-4">
      <section class="grid gap-3 md:grid-cols-3">
        <div class="p-4 border rounded-lg border-n-weak">
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.WHATSAPP_API.INFO.INBOX_TITLE') }}
          </p>
          <p class="mb-0 text-sm leading-5 text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP_API.INFO.INBOX_BODY') }}
          </p>
        </div>
        <div class="p-4 border rounded-lg border-n-weak">
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.WHATSAPP_API.INFO.CADENCE_TITLE') }}
          </p>
          <p class="mb-0 text-sm leading-5 text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP_API.INFO.CADENCE_BODY') }}
          </p>
        </div>
        <div class="p-4 border rounded-lg border-n-weak">
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.WHATSAPP_API.INFO.MESSAGE_TITLE') }}
          </p>
          <p class="mb-0 text-sm leading-5 text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP_API.INFO.MESSAGE_BODY') }}
          </p>
        </div>
      </section>

      <div
        v-if="isFetching"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>

      <div
        v-else-if="campaigns.length === 0"
        class="flex flex-col items-center justify-center gap-2 py-16 text-center border rounded-lg border-n-weak"
      >
        <p class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('CAMPAIGN.WHATSAPP_API.EMPTY_STATE.TITLE') }}
        </p>
        <p class="max-w-xl mb-0 text-sm leading-5 text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP_API.EMPTY_STATE.SUBTITLE') }}
        </p>
      </div>

      <div v-else class="overflow-hidden border rounded-lg border-n-weak">
        <table class="w-full text-sm table-fixed">
          <thead class="bg-n-alpha-2 text-n-slate-11">
            <tr>
              <th class="w-[24%] px-4 py-3 font-medium text-left">
                {{ t('CAMPAIGN.WHATSAPP_API.TABLE.CAMPAIGN') }}
              </th>
              <th class="w-[14%] px-4 py-3 font-medium text-left">
                {{ t('CAMPAIGN.WHATSAPP_API.TABLE.STATUS') }}
              </th>
              <th class="w-[14%] px-4 py-3 font-medium text-left">
                {{ t('CAMPAIGN.WHATSAPP_API.TABLE.AUDIENCE') }}
              </th>
              <th class="w-[18%] px-4 py-3 font-medium text-left">
                {{ t('CAMPAIGN.WHATSAPP_API.TABLE.INBOX') }}
              </th>
              <th class="w-[14%] px-4 py-3 font-medium text-left">
                {{ t('CAMPAIGN.WHATSAPP_API.TABLE.SCHEDULED_AT') }}
              </th>
              <th class="w-[16%] px-4 py-3 font-medium text-right">
                {{ t('CAMPAIGN.WHATSAPP_API.TABLE.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="campaign in campaigns"
              :key="campaign.id"
              class="border-t border-n-weak"
            >
              <td class="px-4 py-4 align-top">
                <p class="mb-1 font-medium truncate text-n-slate-12">
                  {{ campaign.title }}
                </p>
                <p class="mb-0 text-xs truncate text-n-slate-11">
                  {{
                    campaign.message_body ||
                    t('CAMPAIGN.WHATSAPP_API.TABLE.MEDIA_ONLY')
                  }}
                </p>
              </td>
              <td class="px-4 py-4 align-top">
                <span
                  class="inline-flex px-2 py-1 text-xs font-medium rounded-md"
                  :class="statusClass(campaign.status)"
                >
                  {{ statusLabel(campaign.status) }}
                </span>
              </td>
              <td class="px-4 py-4 align-top text-n-slate-12">
                <p class="mb-1">
                  {{ audienceProgress(campaign) }}
                </p>
                <p
                  v-if="campaign.failed_count"
                  class="mb-0 text-xs text-n-ruby-11"
                >
                  {{
                    t('CAMPAIGN.WHATSAPP_API.TABLE.FAILURES', {
                      count: campaign.failed_count,
                    })
                  }}
                </p>
              </td>
              <td class="px-4 py-4 align-top text-n-slate-12">
                <p class="mb-0 truncate">{{ campaign.inbox?.name }}</p>
              </td>
              <td class="px-4 py-4 align-top text-n-slate-11">
                {{ scheduledAtLabel(campaign.scheduled_at) }}
              </td>
              <td class="px-4 py-4 align-top">
                <div v-if="canManage" class="flex justify-end gap-1">
                  <Button
                    v-if="campaign.status === 'running'"
                    icon="i-lucide-pause"
                    color="slate"
                    variant="ghost"
                    size="sm"
                    @click="runAction('pause', campaign)"
                  />
                  <Button
                    v-if="campaign.status === 'paused'"
                    icon="i-lucide-play"
                    color="teal"
                    variant="ghost"
                    size="sm"
                    @click="runAction('resume', campaign)"
                  />
                  <Button
                    v-if="
                      ['scheduled', 'running', 'paused'].includes(
                        campaign.status
                      )
                    "
                    icon="i-lucide-ban"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    @click="runAction('cancel', campaign)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </CampaignLayout>
</template>
