<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useToggle } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useAlert } from 'dashboard/composables';
import { isRecipientImportActive } from 'dashboard/helper/emailCampaignImport';
import RecipientImportStatus from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/RecipientImportStatus.vue';

import EmailStatusBadge from 'dashboard/components-next/Campaigns/EmailProtection/EmailStatusBadge.vue';
import EmailStatusFilter from 'dashboard/components-next/Campaigns/EmailProtection/EmailStatusFilter.vue';
import EmailCampaignHealth from 'dashboard/components-next/Campaigns/EmailProtection/EmailCampaignHealth.vue';
import {
  NS,
  safeError,
  hasActiveEmailWork,
  formatNumber,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import { useEmailReportRefresh } from 'dashboard/components-next/Campaigns/EmailProtection/useEmailReportRefresh';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import EmailCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue';
import EmailCampaignDetailsDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDetailsDialog.vue';

const { t, locale } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const [showDialog, toggleDialog] = useToggle();
const canManage = useCanManage('campaign_manage');

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
const request = useAbortableRequest();
const isFetching = request.isPending;

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
const canCancel = campaign =>
  !isRecipientImportActive(campaign) &&
  ['draft', 'scheduled', 'sending', 'paused'].includes(campaign.status);

const campaignStatus = ref(
  typeof route.query.email_status === 'string' ? route.query.email_status : ''
);
const errorMessage = ref('');
const number = value => formatNumber(value, locale.value);
const fetchCampaigns = async (silent = false) => {
  if (!enabled.value) return;
  errorMessage.value = '';
  try {
    await request.run(signal =>
      store.dispatch('emailCampaigns/get', {
        silent,
        status: campaignStatus.value,
        signal,
      })
    );
  } catch (error) {
    errorMessage.value = safeError(t, error);
  }
};
watch(campaignStatus, () => {
  router.replace({
    query: { ...route.query, email_status: campaignStatus.value || undefined },
  });
  fetchCampaigns();
});
useEmitter(BUS_EVENTS.EMAIL_CAMPAIGN_AI_READY, () => fetchCampaigns(true));
useEmitter(BUS_EVENTS.EMAIL_CAMPAIGN_AI_FAILED, () => fetchCampaigns(true));
useEmailReportRefresh(
  () => (!request.isPending.value ? fetchCampaigns(true) : undefined),
  () => campaigns.value.some(hasActiveEmailWork)
);

const openCompose = () => {
  editing.value = null;
  toggleDialog(true);
};

const openEdit = campaign => {
  editing.value = campaign;
  toggleDialog(true);
};

const detailsProblems = ref(false);
const openRecipients = (campaign, problems = false) => {
  detailsProblems.value = problems;
  detailsCampaign.value = campaign;
};

const onSaved = () => {
  toggleDialog(false);
  editing.value = null;
  fetchCampaigns();
};

const sendNow = async campaign => {
  try {
    const result = await store.dispatch('emailCampaigns/sendNow', campaign.id);
    useAlert(
      result.status === 'paused'
        ? t(`${NS}.STILL_BLOCKED`)
        : t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SEND_SUCCESS')
    );
    fetchCampaigns(true);
  } catch (error) {
    useAlert(safeError(t, error));
  }
};

const pause = async campaign => {
  try {
    await store.dispatch('emailCampaigns/pause', campaign.id);
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.PAUSE_SUCCESS'));
  } catch (error) {
    useAlert(safeError(t, error));
  }
};

const cancel = async campaign => {
  try {
    await store.dispatch('emailCampaigns/cancel', campaign.id);
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.CANCEL_SUCCESS'));
  } catch (error) {
    useAlert(safeError(t, error));
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
    useAlert(safeError(t, error));
  }
};

const removeCampaign = async campaign => {
  try {
    await store.dispatch('emailCampaigns/delete', campaign.id);
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(safeError(t, error));
  }
};

onMounted(() => {
  if (!enabled.value) return;
  fetchCampaigns();
  store.dispatch('emailSenderIdentities/get');
  // Caixas conectadas alimentam as opções de "envio direto" no diálogo de campanha.
  store.dispatch('inboxes/get');
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

      <div class="flex flex-wrap items-end gap-3">
        <EmailStatusFilter v-model="campaignStatus" campaign />
        <Button
          :label="t(`${NS}.REFRESH`)"
          icon="i-lucide-refresh-cw"
          slate
          outline
          :disabled="isFetching"
          @click="fetchCampaigns()"
        />
      </div>
      <p v-if="errorMessage" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>
      <div
        v-else-if="isFetching"
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
              <EmailStatusBadge :record="campaign" campaign />
              <span
                v-if="aiBadge(campaign.ai_status)"
                class="inline-flex items-center gap-1 px-2 py-1 ms-2 text-xs font-medium rounded-md"
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
                v-if="canManage"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DUPLICATE')"
                icon="i-lucide-copy"
                color="slate"
                variant="ghost"
                size="sm"
                :is-loading="uiFlags.isCreating"
                @click="duplicate(campaign)"
              />
              <Button
                v-if="canManage && campaign.status === 'draft'"
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
                v-if="canManage && canSendNow(campaign)"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SEND_NOW')"
                icon="i-lucide-send"
                color="blue"
                variant="outline"
                size="sm"
                :is-loading="uiFlags.isUpdating"
                @click="sendNow(campaign)"
              />
              <Button
                v-if="canManage && canPause(campaign)"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.PAUSE')"
                icon="i-lucide-pause"
                color="amber"
                variant="ghost"
                size="sm"
                @click="pause(campaign)"
              />
              <Button
                v-if="canManage && canCancel(campaign)"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.CANCEL')"
                icon="i-lucide-x"
                color="ruby"
                variant="ghost"
                size="sm"
                @click="cancel(campaign)"
              />
              <Button
                v-if="canManage && campaign.status === 'draft'"
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
          <EmailCampaignHealth
            v-if="
              campaign.status === 'paused' ||
              campaign.protection ||
              campaign.preflight
            "
            :campaign="campaign"
            @updated="fetchCampaigns(true)"
            @problems="openRecipients(campaign, true)"
          />

          <p v-if="campaign.last_error" class="mb-0 text-xs text-n-ruby-11">
            {{
              safeError(t, {
                response: { data: { error_code: campaign.error_code } },
              })
            }}
          </p>

          <div class="flex flex-wrap gap-6 text-sm">
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.RECIPIENTS') }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ number(campaign.recipients_count) }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.SENT') }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ number(campaign.sent_count) }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.FAILED') }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ number(campaign.failed_count) }}
              </span>
            </div>
            <div
              v-if="campaign.preflight?.counts?.invalid"
              class="flex flex-col"
            >
              <span class="text-xs text-n-slate-11">
                {{ t(`${NS}.STATUS.invalid`) }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ number(campaign.preflight.counts.invalid) }}
              </span>
            </div>
            <div
              v-if="campaign.preflight?.counts?.review"
              class="flex flex-col"
            >
              <span class="text-xs text-n-slate-11">
                {{ t(`${NS}.STATUS.review`) }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ number(campaign.preflight.counts.review) }}
              </span>
            </div>
            <div
              v-if="campaign.preflight?.counts?.protected"
              class="flex flex-col"
            >
              <span class="text-xs text-n-slate-11">
                {{ t(`${NS}.STATUS.protected`) }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ number(campaign.preflight.counts.protected) }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <EmailCampaignDetailsDialog
      v-if="detailsCampaign"
      :campaign="detailsCampaign"
      :initial-problem="detailsProblems"
      @close="detailsCampaign = null"
    />
  </CampaignLayout>
</template>
