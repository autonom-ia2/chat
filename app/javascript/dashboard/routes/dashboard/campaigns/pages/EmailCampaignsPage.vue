<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useToggle } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { isRecipientImportActive } from 'dashboard/helper/emailCampaignImport';
import RecipientImportStatus from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/RecipientImportStatus.vue';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import EmailCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue';
import EmailCampaignDetailsDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDetailsDialog.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const [showDialog, toggleDialog] = useToggle();

const campaigns = useMapGetter('emailCampaigns/getCampaigns');
const uiFlags = useMapGetter('emailCampaigns/getUIFlags');
const globalConfig = useMapGetter('globalConfig/get');

const editing = ref(null);
const detailsCampaign = ref(null);

const enabled = computed(
  () =>
    globalConfig.value?.emailCampaignEnabled === true &&
    globalConfig.value?.crmKanbanEnabled === true
);
const isFetching = computed(() => uiFlags.value.isFetching);

const statusLabel = status => {
  switch (status) {
    case 'draft':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.STATUS.DRAFT');
    case 'scheduled':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.STATUS.SCHEDULED');
    case 'sending':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.STATUS.SENDING');
    case 'sent':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.STATUS.SENT');
    case 'paused':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.STATUS.PAUSED');
    case 'canceled':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.STATUS.CANCELED');
    case 'failed':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.STATUS.FAILED');
    default:
      return status;
  }
};

const statusClass = status => {
  const map = {
    draft: 'text-n-slate-11 bg-n-alpha-2',
    scheduled: 'text-n-blue-11 bg-n-blue-3',
    sending: 'text-n-amber-11 bg-n-amber-3',
    sent: 'text-n-teal-11 bg-n-teal-3',
    paused: 'text-n-amber-11 bg-n-amber-3',
    canceled: 'text-n-slate-11 bg-n-alpha-2',
    failed: 'text-n-ruby-11 bg-n-ruby-3',
  };
  return map[status] || 'text-n-slate-11 bg-n-alpha-2';
};

// Selo da geração de e-mail por IA (assíncrona). idle não mostra nada.
const aiBadge = aiStatus => {
  const map = {
    processing: {
      label: t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BADGE.PROCESSING'),
      class: 'text-n-blue-11 bg-n-blue-3',
      icon: 'i-lucide-sparkles',
    },
    ready: {
      label: t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BADGE.READY'),
      class: 'text-n-teal-11 bg-n-teal-3',
      icon: 'i-lucide-sparkles',
    },
    failed: {
      label: t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BADGE.FAILED'),
      class: 'text-n-ruby-11 bg-n-ruby-3',
      icon: 'i-lucide-triangle-alert',
    },
  };
  return map[aiStatus] || null;
};

const builderRoute = campaign => ({
  name: 'campaigns_email_builder',
  params: {
    accountId: route.params.accountId,
    campaignId: campaign.id,
  },
});

const hasCampaignBody = campaign => Boolean(campaign.body_html);
const canSendNow = campaign =>
  campaign.status === 'draft' &&
  !isRecipientImportActive(campaign) &&
  campaign.recipients_count > 0 &&
  hasCampaignBody(campaign);
const canPause = campaign => campaign.status === 'sending';
const canResume = campaign => campaign.status === 'paused';
const canCancel = campaign =>
  !isRecipientImportActive(campaign) &&
  ['draft', 'scheduled', 'sending', 'paused'].includes(campaign.status);

const fetchCampaigns = (silent = false) =>
  enabled.value
    ? store.dispatch('emailCampaigns/get', { silent })
    : Promise.resolve();

// Realtime-ish refresh: a campaign in a transient state (sending / scheduled)
// changes server-side as Sidekiq delivers + SNS events land, but the list is
// fetched once on mount. Poll while any campaign is transient so the status badge
// flips to "Enviada" and the counts settle without a manual reload; idle (no-op)
// when everything is terminal.
const POLL_MS = 6000;
let pollTimer = null;
const hasActiveCampaign = computed(() =>
  campaigns.value.some(
    c =>
      ['sending', 'scheduled'].includes(c.status) ||
      c.ai_status === 'processing' ||
      isRecipientImportActive(c)
  )
);
const startPolling = () => {
  if (pollTimer) return;
  pollTimer = setInterval(() => {
    if (hasActiveCampaign.value && !isFetching.value)
      fetchCampaigns(true).catch(() => {});
  }, POLL_MS);
};

const openCompose = () => {
  editing.value = null;
  toggleDialog(true);
};

const openEdit = campaign => {
  editing.value = campaign;
  toggleDialog(true);
};

const openRecipients = campaign => {
  detailsCampaign.value = campaign;
};

const onSaved = () => {
  toggleDialog(false);
  editing.value = null;
  fetchCampaigns();
};

const sendNow = async campaign => {
  try {
    await store.dispatch('emailCampaigns/sendNow', campaign.id);
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SEND_SUCCESS'));
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.ERROR'));
  }
};

const pause = async campaign => {
  try {
    await store.dispatch('emailCampaigns/pause', campaign.id);
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.PAUSE_SUCCESS'));
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.ERROR'));
  }
};

const resume = async campaign => {
  try {
    await store.dispatch('emailCampaigns/resume', campaign.id);
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.RESUME_SUCCESS'));
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.ERROR'));
  }
};

const cancel = async campaign => {
  try {
    await store.dispatch('emailCampaigns/cancel', campaign.id);
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.CANCEL_SUCCESS'));
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.ERROR'));
  }
};

const duplicate = async campaign => {
  try {
    const newCampaign = await store.dispatch(
      'emailCampaigns/duplicate',
      campaign.id
    );
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DUPLICATE_SUCCESS'));
    router.push(builderRoute(newCampaign));
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.ERROR'));
  }
};

const removeCampaign = async campaign => {
  try {
    await store.dispatch('emailCampaigns/delete', campaign.id);
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.ERROR'));
  }
};

onMounted(() => {
  if (!enabled.value) return;
  store.dispatch('emailCampaigns/get');
  store.dispatch('emailSenderIdentities/get');
  // Caixas conectadas alimentam as opções de "envio direto" no diálogo de campanha.
  store.dispatch('inboxes/get');
  startPolling();
});

onBeforeUnmount(() => {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
});
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.EMAIL_CAMPAIGN.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.EMAIL_CAMPAIGN.NEW')"
    @click="openCompose()"
    @close="toggleDialog(false)"
  >
    <template #action>
      <EmailCampaignDialog
        v-if="showDialog"
        :campaign="editing"
        @saved="onSaved()"
        @close="toggleDialog(false)"
      />
    </template>

    <div class="flex flex-col gap-4">
      <p class="max-w-3xl mb-0 text-sm leading-5 text-n-slate-11">
        {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DESCRIPTION') }}
      </p>

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
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.EMPTY_STATE.TITLE') }}
        </p>
        <p class="max-w-xl mb-0 text-sm leading-5 text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.EMPTY_STATE.SUBTITLE') }}
        </p>
      </div>

      <div v-else class="flex flex-col gap-4">
        <div
          v-for="campaign in campaigns"
          :key="campaign.id"
          class="flex flex-col gap-4 p-4 border rounded-lg border-n-weak"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="mb-1 font-medium truncate text-n-slate-12">
                {{ campaign.name }}
              </p>
              <p class="mb-1 text-sm truncate text-n-slate-11">
                {{ campaign.subject }}
              </p>
              <span
                class="inline-flex px-2 py-1 text-xs font-medium rounded-md"
                :class="statusClass(campaign.status)"
              >
                {{ statusLabel(campaign.status) }}
              </span>
              <span
                v-if="aiBadge(campaign.ai_status)"
                class="inline-flex items-center gap-1 px-2 py-1 ml-2 text-xs font-medium rounded-md"
                :class="aiBadge(campaign.ai_status).class"
              >
                <span
                  :class="aiBadge(campaign.ai_status).icon"
                  class="size-3"
                />
                {{ aiBadge(campaign.ai_status).label }}
              </span>
            </div>
            <div class="flex flex-wrap items-center justify-end gap-2">
              <Button
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.MANAGE_RECIPIENTS')"
                icon="i-lucide-users"
                color="slate"
                variant="outline"
                size="sm"
                @click="openRecipients(campaign)"
              />
              <Button
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DUPLICATE')"
                icon="i-lucide-copy"
                color="slate"
                variant="ghost"
                size="sm"
                :is-loading="uiFlags.isCreating"
                @click="duplicate(campaign)"
              />
              <Button
                v-if="campaign.status === 'draft'"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.EDIT')"
                icon="i-lucide-pencil"
                color="slate"
                variant="ghost"
                size="sm"
                @click="openEdit(campaign)"
              />
              <router-link
                v-if="campaign.status === 'draft'"
                :to="builderRoute(campaign)"
              >
                <Button
                  :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.OPEN_BUILDER')"
                  icon="i-lucide-layout-template"
                  color="blue"
                  variant="ghost"
                  size="sm"
                />
              </router-link>
              <Button
                v-if="canSendNow(campaign)"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SEND_NOW')"
                icon="i-lucide-send"
                color="blue"
                variant="outline"
                size="sm"
                :is-loading="uiFlags.isUpdating"
                @click="sendNow(campaign)"
              />
              <Button
                v-if="canPause(campaign)"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.PAUSE')"
                icon="i-lucide-pause"
                color="amber"
                variant="ghost"
                size="sm"
                @click="pause(campaign)"
              />
              <Button
                v-if="canResume(campaign)"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.RESUME')"
                icon="i-lucide-play"
                color="blue"
                variant="ghost"
                size="sm"
                :is-loading="uiFlags.isUpdating"
                @click="resume(campaign)"
              />
              <Button
                v-if="canCancel(campaign)"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.CANCEL')"
                icon="i-lucide-x"
                color="ruby"
                variant="ghost"
                size="sm"
                @click="cancel(campaign)"
              />
              <Button
                v-if="campaign.status === 'draft'"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DELETE')"
                icon="i-lucide-trash-2"
                color="ruby"
                variant="ghost"
                size="sm"
                :disabled="isRecipientImportActive(campaign)"
                @click="removeCampaign(campaign)"
              />
            </div>
          </div>

          <RecipientImportStatus :campaign="campaign" />

          <p v-if="campaign.last_error" class="mb-0 text-xs text-n-ruby-11">
            {{ campaign.last_error }}
          </p>

          <div class="flex flex-wrap gap-6 text-sm">
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.RECIPIENTS') }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ campaign.recipients_count }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.SENT') }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ campaign.sent_count }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.FAILED') }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ campaign.failed_count }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.SUPPRESSED') }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ campaign.suppressed_count }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <EmailCampaignDetailsDialog
      v-if="detailsCampaign"
      :campaign="detailsCampaign"
      @close="detailsCampaign = null"
    />
  </CampaignLayout>
</template>
