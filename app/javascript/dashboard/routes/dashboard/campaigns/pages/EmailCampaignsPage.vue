<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
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
  statusKey,
  formatNumber,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import { useEmailReportRefresh } from 'dashboard/components-next/Campaigns/EmailProtection/useEmailReportRefresh';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { vOnClickOutside } from '@vueuse/components';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
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

const pause = async campaign => {
  try {
    await store.dispatch('emailCampaigns/pause', campaign.id);
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.PAUSE_SUCCESS'));
  } catch (error) {
    useAlert(safeError(t, error));
  }
};

const cancel = async campaign => {
  await store.dispatch('emailCampaigns/cancel', campaign.id);
  useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.CANCEL_SUCCESS'));
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
  await store.dispatch('emailCampaigns/delete', campaign.id);
  useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DELETE_SUCCESS'));
};

onMounted(() => {
  if (!enabled.value) return;
  fetchCampaigns();
  store.dispatch('emailSenderIdentities/get');
  // Caixas conectadas alimentam as opções de "envio direto" no diálogo de campanha.
  store.dispatch('inboxes/get');
});

const UX = 'CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE';
const search = ref('');
const menuId = ref(null);
const diagnosticCampaign = ref(null);
const diagnosticDialog = ref(null);
const destructive = ref(null);
const confirmDialog = ref(null);
const isConfirming = ref(false);
const tabs = ['', 'draft', 'scheduled', 'sent'];
const visibleCampaigns = computed(() => {
  const query = search.value.trim().toLocaleLowerCase(locale.value);
  return campaigns.value.filter(item =>
    [item.name, item.subject].some(value =>
      value?.toLocaleLowerCase(locale.value).includes(query)
    )
  );
});
const drafts = computed(() =>
  campaigns.value.filter(item => item.status === 'draft')
);
const nextScheduled = computed(
  () =>
    campaigns.value
      .filter(item => item.status === 'scheduled')
      .sort((a, b) => new Date(a.scheduled_at) - new Date(b.scheduled_at))[0]
);
const sentCampaigns = computed(
  () => campaigns.value.filter(item => item.status === 'sent').length
);
const needsContent = item => !item.subject?.trim() || !item.body_html;
const reviewRoute = item => ({
  ...builderRoute(item),
  query: { step: 'review' },
});
const galleryRoute = computed(() => ({
  name: 'campaigns_email_templates',
  params: { accountId: route.params.accountId },
}));
const campaignNote = item => {
  if (isRecipientImportActive(item)) return t(`${UX}.IMPORT_ACTIVE`);
  if (item.recipient_import?.status === 'failed')
    return t(`${UX}.IMPORT_FAILED`);
  if (item.status === 'draft')
    return t(`${UX}.${needsContent(item) ? 'COMPLETE_EMAIL' : 'REVIEW_SEND'}`);
  return t(`${NS}.STATUS.${statusKey(item, true)}`);
};
const formatDate = value =>
  value
    ? new Intl.DateTimeFormat(locale.value, {
        dateStyle: 'medium',
        timeStyle: 'short',
      }).format(new Date(value))
    : '—';
const showDiagnostics = async item => {
  menuId.value = null;
  diagnosticCampaign.value = item;
  await nextTick();
  diagnosticDialog.value.open();
};
const askDestructive = async (item, action) => {
  menuId.value = null;
  destructive.value = { item, action };
  await nextTick();
  confirmDialog.value.open();
};
const confirmDestructive = async () => {
  isConfirming.value = true;
  const { item, action } = destructive.value;
  try {
    if (action === 'delete') await removeCampaign(item);
    else await cancel(item);
    confirmDialog.value.close();
  } catch (error) {
    useAlert(safeError(t, error));
  } finally {
    isConfirming.value = false;
  }
};
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-5 lg:p-8">
      <p class="mb-5 flex items-center gap-2 text-xs text-n-slate-11">
        {{ t(`${UX}.CAMPAIGNS`) }}
        <span class="i-lucide-chevron-right size-3.5" />
        <span class="font-medium text-n-blue-11">{{ t(`${UX}.EMAIL`) }}</span>
      </p>
      <header class="mb-7 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1
            class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
          >
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.HEADER_TITLE') }}
          </h1>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t(`${UX}.LIST_SUBTITLE`) }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <router-link :to="galleryRoute"
            ><Button
              :label="t(`${UX}.LIBRARY_BUTTON`)"
              icon="i-lucide-layout-template"
              slate
              outline
              class="!min-h-11 !rounded-xl"
          /></router-link>
          <div v-on-click-outside="() => toggleDialog(false)" class="relative">
            <Button
              v-if="canManage"
              :label="t(`${UX}.NEW_CAMPAIGN`)"
              icon="i-lucide-plus"
              class="!min-h-11 !rounded-xl"
              @click="openCompose"
            />
            <EmailCampaignDialog
              v-if="showDialog"
              :campaign="editing"
              @saved="onSaved"
              @close="toggleDialog(false)"
            />
          </div>
        </div>
      </header>
      <section
        class="mb-7 flex flex-col overflow-hidden rounded-3xl border border-n-weak bg-n-solid-1 shadow-sm md:flex-row"
        :aria-label="t(`${UX}.OVERVIEW`)"
      >
        <div
          class="relative min-w-0 overflow-hidden bg-[#0D2344] px-6 py-6 text-white md:w-[32%]"
        >
          <span
            class="absolute -end-8 -top-12 size-40 rounded-full border-[1.5rem] border-n-blue-9 opacity-10"
            aria-hidden="true"
          />
          <p
            class="relative mb-0 flex items-center gap-2 text-xs text-n-blue-6"
          >
            <span class="i-lucide-sparkles size-4" />{{ t(`${UX}.NEXT_SEND`) }}
          </p>
          <p class="relative mb-0 mt-3 text-xl font-semibold tracking-tight">
            {{ drafts[0]?.name || t(`${UX}.START_NEXT`) }}
          </p>
          <router-link
            v-if="drafts[0]"
            :to="reviewRoute(drafts[0])"
            class="relative mt-4 flex min-h-11 items-center gap-2 text-sm font-medium text-n-blue-6 hover:text-white"
            >{{ t(`${UX}.REVIEW_SEND`) }}
            <span class="i-lucide-arrow-right size-4"
          /></router-link>
          <Button
            v-else-if="canManage"
            :label="t(`${UX}.NEW_CAMPAIGN`)"
            variant="ghost"
            class="relative mt-4 !text-n-blue-6"
            @click="openCompose"
          />
        </div>
        <div
          class="flex flex-1 flex-wrap items-center justify-between gap-5 px-6 py-6 md:px-8"
        >
          <div>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t(`${UX}.IN_PREPARATION`) }}
            </p>
            <p
              class="mb-0 mt-2 text-3xl font-semibold tabular-nums text-n-slate-12"
            >
              {{ number(drafts.length) }}
              <span class="text-sm font-normal text-n-slate-11">{{
                t(`${UX}.DRAFTS`)
              }}</span>
            </p>
            <p class="mb-0 mt-2 text-xs text-n-slate-11">
              {{ t(`${UX}.CURRENT_VIEW`) }}
            </p>
          </div>
          <div class="hidden h-16 w-px bg-n-weak sm:block" />
          <div>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t(`${UX}.NEXT_SCHEDULE`) }}
            </p>
            <p class="mb-0 mt-2 text-lg font-semibold text-n-slate-12">
              {{ formatDate(nextScheduled?.scheduled_at) }}
            </p>
            <p class="mb-0 mt-2 text-xs text-n-slate-11">
              {{ nextScheduled?.name || t(`${UX}.NO_SCHEDULE`) }}
            </p>
          </div>
          <div class="hidden h-16 w-px bg-n-weak xl:block" />
          <div class="hidden xl:block">
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t(`${UX}.SENT_CAMPAIGNS`) }}
            </p>
            <p
              class="mb-0 mt-2 text-3xl font-semibold tabular-nums text-n-slate-12"
            >
              {{ number(sentCampaigns) }}
            </p>
            <button
              class="mt-2 min-h-11 text-xs font-medium text-n-blue-11"
              @click="campaignStatus = 'sent'"
            >
              {{ t(`${UX}.VIEW_RESULTS`) }}
              <span class="i-lucide-arrow-right ms-1 inline-block size-3" />
            </button>
          </div>
        </div>
      </section>
      <section class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm">
        <header
          class="flex flex-wrap items-center justify-between gap-4 border-b border-n-weak px-5 py-4 xl:px-6"
        >
          <nav
            class="flex max-w-full gap-1 overflow-x-auto"
            :aria-label="t(`${NS}.CAMPAIGN_STATUS`)"
          >
            <button
              v-for="tab in tabs"
              :key="tab"
              class="min-h-11 shrink-0 rounded-xl px-3 text-sm font-medium"
              :class="
                campaignStatus === tab
                  ? 'bg-n-blue-3 text-n-blue-11'
                  : 'text-n-slate-11 hover:bg-n-alpha-1'
              "
              :aria-pressed="campaignStatus === tab"
              @click="campaignStatus = tab"
            >
              {{ t(`${UX}.TABS.${tab || 'all'}`) }}
            </button>
          </nav>
          <label
            class="flex min-h-11 w-full items-center gap-2 rounded-xl border border-n-weak px-3 focus-within:ring-2 focus-within:ring-n-brand sm:w-60"
            ><span
              class="i-lucide-search size-4 shrink-0 text-n-slate-11" /><input
              v-model="search"
              type="search"
              :aria-label="t(`${UX}.SEARCH_CAMPAIGN`)"
              :placeholder="t(`${UX}.SEARCH_CAMPAIGN`)"
              class="m-0 min-w-0 w-full !border-0 !bg-transparent !p-0 text-sm !shadow-none !outline-none focus:!ring-0"
          /></label>
        </header>
        <p
          v-if="errorMessage"
          role="alert"
          class="m-0 p-6 text-sm text-n-ruby-11"
        >
          {{ errorMessage }}
        </p>
        <div v-else-if="isFetching" class="flex justify-center p-12">
          <Spinner />
        </div>
        <div
          v-else-if="!visibleCampaigns.length"
          class="flex flex-col items-center gap-2 p-12 text-center"
        >
          <span class="i-lucide-mail size-8 text-n-slate-9" />
          <p class="mb-0 font-medium text-n-slate-12">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.EMPTY_STATE.TITLE') }}
          </p>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t(`${UX}.EMPTY_SEARCH`) }}
          </p>
        </div>
        <article
          v-for="item in isFetching ? [] : visibleCampaigns"
          :key="item.id"
          class="flex flex-col gap-5 border-b border-n-weak px-5 py-5 last:border-0 xl:flex-row xl:items-center xl:px-6"
        >
          <div class="flex min-w-0 flex-1 gap-4">
            <div
              class="relative flex h-20 w-16 shrink-0 justify-center overflow-hidden rounded-xl border border-n-weak bg-n-alpha-1"
            >
              <iframe
                v-if="item.body_html"
                :srcdoc="item.body_html"
                :title="t(`${UX}.THUMBNAIL`, { name: item.name })"
                sandbox=""
                referrerpolicy="no-referrer"
                tabindex="-1"
                aria-hidden="true"
                class="pointer-events-none h-[60rem] w-[37.5rem] shrink-0 origin-top scale-[.105] border-0"
              />
              <span
                v-else
                class="i-lucide-mail absolute top-6 size-7 text-n-slate-9"
              />
            </div>
            <div class="min-w-0 pt-0.5">
              <div class="mb-1.5 flex flex-wrap items-center gap-3">
                <button
                  class="text-start text-sm font-semibold text-n-slate-12 hover:text-n-blue-11"
                  @click="
                    item.status === 'draft'
                      ? router.push(builderRoute(item))
                      : showDiagnostics(item)
                  "
                >
                  {{ item.name }}</button
                ><EmailStatusBadge
                  :record="item"
                  campaign
                  class="!rounded-full"
                />
              </div>
              <p class="mb-0 truncate text-sm text-n-slate-11">
                {{ item.subject || t(`${UX}.NO_SUBJECT`) }}
              </p>
              <p class="mb-0 mt-2 text-xs text-n-slate-11">
                {{ formatDate(item.updated_at) }}
              </p>
              <span
                v-if="aiBadge(item.ai_status)"
                class="mt-2 inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs"
                :class="aiBadge(item.ai_status).class"
                ><span :class="aiBadge(item.ai_status).icon" class="size-3" />{{
                  aiBadge(item.ai_status).label
                }}</span
              >
            </div>
          </div>
          <div class="flex items-center gap-7 xl:w-[17rem] xl:shrink-0">
            <div class="w-16 shrink-0">
              <p
                class="mb-0 text-sm font-semibold tabular-nums text-n-slate-12"
              >
                {{
                  number(
                    item.status === 'sent'
                      ? item.sent_count
                      : item.recipients_count
                  )
                }}
              </p>
              <p class="mb-0 mt-1 text-xs text-n-slate-11">
                {{
                  t(
                    `CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.${item.status === 'sent' ? 'SENT' : 'RECIPIENTS'}`
                  )
                }}
              </p>
            </div>
            <button class="min-h-11 text-start" @click="showDiagnostics(item)">
              <p
                class="mb-0 text-xs font-medium"
                :class="
                  needsContent(item) && item.status === 'draft'
                    ? 'text-n-amber-11'
                    : 'text-n-blue-11'
                "
              >
                {{ campaignNote(item) }}
              </p>
              <p class="mb-0 mt-1 text-xs text-n-slate-11">
                {{ t(`${UX}.SEE_DETAILS`) }}
              </p>
            </button>
          </div>
          <div
            v-on-click-outside="() => (menuId = null)"
            class="relative flex flex-wrap items-center gap-2 xl:shrink-0"
          >
            <template v-if="item.status === 'draft'">
              <router-link :to="builderRoute(item)"
                ><Button
                  :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.EDIT')"
                  icon="i-lucide-pencil"
                  slate
                  outline
                  class="!min-h-11 !rounded-xl"
              /></router-link>
              <template v-if="canManage"
                ><Button
                  :label="t(`${UX}.SEND`)"
                  @click="router.push(reviewRoute(item))"
                  icon="i-lucide-send"
                  :variant="needsContent(item) ? 'outline' : 'solid'"
                  :color="needsContent(item) ? 'amber' : 'blue'"
                  class="!min-h-11 !rounded-xl"
              /></template>
            </template>
            <Button
              v-else
              :label="
                t(
                  `${UX}.${item.status === 'scheduled' ? 'VIEW_SCHEDULE' : 'VIEW_RESULTS'}`
                )
              "
              icon="i-lucide-chart-no-axes-combined"
              slate
              outline
              class="!min-h-11 !rounded-xl"
              @click="showDiagnostics(item)"
            />
            <Button
              :aria-label="t(`${UX}.MORE_ACTIONS`, { name: item.name })"
              :aria-expanded="menuId === item.id"
              icon="i-lucide-ellipsis"
              slate
              ghost
              class="!size-11 !rounded-xl"
              @click="menuId = menuId === item.id ? null : item.id"
            />
            <div
              v-if="menuId === item.id"
              class="absolute end-0 top-12 z-20 w-60 rounded-xl border border-n-weak bg-n-solid-1 p-1.5 text-sm shadow-lg"
            >
              <Button
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.MANAGE_RECIPIENTS')"
                icon="i-lucide-users"
                slate
                ghost
                justify="start"
                class="!min-h-11 w-full"
                @click="
                  openRecipients(item);
                  menuId = null;
                "
              />
              <Button
                v-if="canManage"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DUPLICATE')"
                icon="i-lucide-copy"
                slate
                ghost
                justify="start"
                class="!min-h-11 w-full"
                :is-loading="uiFlags.isCreating"
                @click="
                  duplicate(item);
                  menuId = null;
                "
              />
              <Button
                v-if="canManage && item.status === 'draft'"
                :label="t(`${UX}.SENDER_SETTINGS`)"
                icon="i-lucide-settings-2"
                slate
                ghost
                justify="start"
                class="!min-h-11 w-full"
                @click="
                  openEdit(item);
                  menuId = null;
                "
              />
              <Button
                v-if="canManage && canPause(item)"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.PAUSE')"
                icon="i-lucide-pause"
                amber
                ghost
                justify="start"
                class="!min-h-11 w-full"
                @click="
                  pause(item);
                  menuId = null;
                "
              />
              <Button
                v-if="canManage && canCancel(item)"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.CANCEL')"
                icon="i-lucide-x"
                ruby
                ghost
                justify="start"
                class="!min-h-11 w-full"
                @click="askDestructive(item, 'cancel')"
              />
              <Button
                v-if="canManage && item.status === 'draft'"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DELETE')"
                icon="i-lucide-trash-2"
                ruby
                ghost
                justify="start"
                class="!min-h-11 w-full"
                :disabled="isRecipientImportActive(item)"
                @click="askDestructive(item, 'delete')"
              />
            </div>
          </div>
        </article>
        <footer
          class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak px-6 py-4 text-xs text-n-slate-11"
        >
          <span>{{
            t(`${UX}.LIST_COUNT`, { count: visibleCampaigns.length })
          }}</span
          ><Button
            :label="t(`${NS}.REFRESH`)"
            icon="i-lucide-refresh-cw"
            slate
            ghost
            class="!min-h-11"
            :disabled="isFetching"
            @click="fetchCampaigns()"
          />
        </footer>
      </section>
      <details class="mt-3 text-xs text-n-slate-11">
        <summary class="min-h-11 cursor-pointer py-3">
          {{ t(`${UX}.ALL_STATUS_FILTERS`) }}
        </summary>
        <div class="max-w-sm">
          <EmailStatusFilter v-model="campaignStatus" campaign />
        </div>
      </details>
      <p class="mt-3 flex items-start gap-2 text-xs leading-5 text-n-slate-11">
        <span class="i-lucide-shield-check size-4 shrink-0" />{{
          t(`${UX}.PROTECTION_NOTE`)
        }}
      </p>
    </div>
    <Dialog
      v-if="diagnosticCampaign"
      ref="diagnosticDialog"
      :title="diagnosticCampaign.name"
      width="3xl"
      overflow-y-auto
      :show-confirm-button="false"
      :cancel-button-label="t(`${UX}.CLOSE`)"
      @close="diagnosticCampaign = null"
    >
      <RecipientImportStatus
        :campaign="diagnosticCampaign"
        :can-recover="canManage"
      />
      <EmailCampaignHealth
        :campaign="diagnosticCampaign"
        @updated="fetchCampaigns(true)"
        @problems="openRecipients(diagnosticCampaign, true)"
      />
      <Button
        :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.MANAGE_RECIPIENTS')"
        icon="i-lucide-users"
        slate
        outline
        @click="openRecipients(diagnosticCampaign)"
      />
    </Dialog>
    <Dialog
      v-if="destructive"
      ref="confirmDialog"
      type="alert"
      :title="t(`${UX}.CONFIRM_${destructive.action.toUpperCase()}`)"
      :description="destructive.item.name"
      :is-loading="isConfirming"
      @confirm="confirmDestructive"
      @close="destructive = null"
    />
    <EmailCampaignDetailsDialog
      v-if="detailsCampaign"
      :campaign="detailsCampaign"
      :initial-problem="detailsProblems"
      @close="detailsCampaign = null"
      @review="
        router.push(reviewRoute(detailsCampaign));
        detailsCampaign = null;
      "
      @updated="fetchCampaigns(true)"
    />
  </section>
</template>
