<script setup>
import {
  DOT,
  COLON,
} from 'dashboard/components-next/CampaignJourney/textMarks';
// "Campanha" (#993, PRD §6.1): every existing campaign of every channel in one list.
// With Públicos on, "Nova campanha" opens the 3-step journey (NewCampaignPage); without
// them it offers the connected channels (M1–M2) and opens their existing forms.
// `?channel=` (old addresses, PRD A3) preselects the channel filter.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useOnEnter } from 'dashboard/components-next/CampaignJourney/useOnEnter';
import { toLocaleTag } from 'dashboard/components-next/CampaignJourney/localeTag';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CampaignChannelChooser from 'dashboard/components-next/CampaignJourney/CampaignChannelChooser.vue';
import EmailCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue';
import WhatsAppCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue';
import WhatsAppApiCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppApiCampaign/WhatsAppApiCampaignDialog.vue';
import SMSCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignDialog.vue';
import LiveChatCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignDialog.vue';
import EmailResultActions from 'dashboard/components-next/CampaignResult/EmailResultActions.vue';
import {
  CAMPAIGN_CHANNELS,
  CHANNEL_ICONS,
  CHANNEL_LABEL_KEYS,
} from 'dashboard/components-next/CampaignJourney/campaignChannels';
import {
  JOURNEY_STATUSES,
  STATUS_ORDER,
  buildJourneyRows,
  filterChannels,
  filterJourneyRows,
} from 'dashboard/components-next/CampaignJourney/campaignRows';
import { useAvailableCampaignChannels } from 'dashboard/components-next/CampaignJourney/useAvailableCampaignChannels';

const NS = 'CAMPAIGN_JOURNEY.LIST';
const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

const { t, locale } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const canManage = useCanManage('campaign_manage');
const { channels, features } = useAvailableCampaignChannels();

const campaigns = useMapGetter('campaigns/getAllCampaigns');
const whatsappApiCampaigns = useMapGetter('whatsappApiCampaigns/getCampaigns');
const emailCampaigns = useMapGetter('emailCampaigns/getCampaigns');
const globalConfig = useMapGetter('globalConfig/get');

const audiencesEnabled = computed(
  () => globalConfig.value?.campaignImportEnabled === true
);

const isLoading = ref(false);
const hasLoadError = ref(false);
const channelFilter = ref(
  CHANNEL_LABEL_KEYS[route.query.channel] ? route.query.channel : ''
);
const statusFilter = ref('');
const search = ref('');
const isChooserOpen = ref(false);
const creatingChannel = ref('');

const CREATION_DIALOGS = {
  [CAMPAIGN_CHANNELS.EMAIL]: EmailCampaignDialog,
  [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: WhatsAppCampaignDialog,
  [CAMPAIGN_CHANNELS.WHATSAPP_API]: WhatsAppApiCampaignDialog,
  [CAMPAIGN_CHANNELS.SMS]: SMSCampaignDialog,
  [CAMPAIGN_CHANNELS.LIVE_CHAT]: LiveChatCampaignDialog,
};

const rows = computed(() =>
  buildJourneyRows({
    campaigns: campaigns.value || [],
    whatsappApiCampaigns: features.value.whatsappApiCampaigns
      ? whatsappApiCampaigns.value || []
      : [],
    emailCampaigns: features.value.emailCampaigns
      ? emailCampaigns.value || []
      : [],
  })
);

const visibleRows = computed(() =>
  filterJourneyRows(rows.value, {
    channel: channelFilter.value,
    status: statusFilter.value,
    search: search.value,
  })
);

const channelChips = computed(() => filterChannels(rows.value, channels.value));

const channelLabel = channel =>
  t(`CAMPAIGN_JOURNEY.CHANNELS.${CHANNEL_LABEL_KEYS[channel]}`);
const statusLabel = status =>
  t(`CAMPAIGN_JOURNEY.STATUS.${status.toUpperCase()}`);

const STATUS_CLASSES = {
  [JOURNEY_STATUSES.DRAFT]: 'bg-n-alpha-2 text-n-slate-11',
  [JOURNEY_STATUSES.SCHEDULED]: 'bg-n-amber-3 text-n-amber-11',
  [JOURNEY_STATUSES.SENDING]: 'bg-n-blue-3 text-n-blue-11',
  [JOURNEY_STATUSES.PAUSED]: 'bg-n-amber-3 text-n-amber-11',
  [JOURNEY_STATUSES.COMPLETED]: 'bg-n-teal-3 text-n-teal-11',
  [JOURNEY_STATUSES.CANCELLED]: 'bg-n-alpha-2 text-n-slate-11',
  [JOURNEY_STATUSES.FAILED]: 'bg-n-ruby-3 text-n-ruby-11',
  [JOURNEY_STATUSES.ALWAYS_ON]: 'bg-n-blue-3 text-n-blue-11',
};

const statusOptions = computed(() => [
  { value: '', label: t(`${NS}.ALL_STATUSES`) },
  ...STATUS_ORDER.map(status => ({
    value: status,
    label: statusLabel(status),
  })),
]);

const formatDate = time =>
  new Date(time).toLocaleString(toLocaleTag(locale.value), {
    dateStyle: 'short',
    timeStyle: 'short',
  });

// "Agendada para", "Começou em", "Enviada em" or "Criada em" (#990): the date alone does not say
// whether the send already happened.
const formatWhen = row => {
  if (row.status === JOURNEY_STATUSES.ALWAYS_ON) return t(`${NS}.ALWAYS`);
  if (!row.when) return t(`${NS}.NO_DATE`);
  return t(`${NS}.WHEN_AT.${row.whenKind.toUpperCase()}`, {
    date: formatDate(row.when),
  });
};

const nextScheduled = computed(
  () =>
    rows.value
      .filter(row => row.status === JOURNEY_STATUSES.SCHEDULED && row.when)
      .sort((a, b) => a.when - b.when)[0] || null
);
const inPreparation = computed(
  () =>
    rows.value.filter(row =>
      [JOURNEY_STATUSES.DRAFT, JOURNEY_STATUSES.SCHEDULED].includes(row.status)
    ).length
);
const sentLast30Days = computed(() => {
  const since = Date.now() - THIRTY_DAYS_MS;
  return rows.value.filter(
    row =>
      row.status === JOURNEY_STATUSES.COMPLETED && row.when && row.when >= since
  ).length;
});
const alwaysOn = computed(
  () =>
    rows.value.filter(row => row.status === JOURNEY_STATUSES.ALWAYS_ON).length
);

const fetchAll = async () => {
  isLoading.value = true;
  hasLoadError.value = false;
  const requests = [
    store.dispatch('inboxes/get'),
    store.dispatch('campaigns/get'),
  ];
  if (features.value.whatsappApiCampaigns) {
    requests.push(store.dispatch('whatsappApiCampaigns/get'));
  }
  if (features.value.emailCampaigns) {
    requests.push(
      store.dispatch('emailCampaigns/get'),
      store.dispatch('emailSenderIdentities/get')
    );
  }
  const results = await Promise.allSettled(requests);
  hasLoadError.value = results.some(result => result.status === 'rejected');
  isLoading.value = false;
};

const closeCreation = () => {
  isChooserOpen.value = false;
  creatingChannel.value = '';
};
watch(
  () => route.query.channel,
  channel => {
    channelFilter.value = CHANNEL_LABEL_KEYS[channel] ? channel : '';
  }
);

const toggleChooser = () => {
  if (audiencesEnabled.value) {
    router.push({ name: 'campaigns_journey_new' });
    return;
  }
  if (creatingChannel.value || isChooserOpen.value) {
    closeCreation();
    return;
  }
  isChooserOpen.value = true;
};
const chooseChannel = channel => {
  isChooserOpen.value = false;
  creatingChannel.value = channel;
};
const onCreated = () => {
  closeCreation();
  fetchAll();
};

useOnEnter(fetchAll);
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-4 sm:p-5 lg:p-8">
      <nav
        class="mb-5 flex items-center gap-2 text-xs text-n-slate-11"
        :aria-label="t(`${NS}.BREADCRUMB`)"
      >
        {{ t('CAMPAIGN_JOURNEY.SIDEBAR.GROUP') }}
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <span class="font-medium text-n-blue-11" aria-current="page">
          {{ t('CAMPAIGN_JOURNEY.SIDEBAR.CAMPAIGNS') }}
        </span>
      </nav>
      <header class="mb-7 flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <h1
            class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
          >
            {{ t(`${NS}.TITLE`) }}
          </h1>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t(`${NS}.SUBTITLE`) }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <Button
            v-if="audiencesEnabled"
            :label="t('CAMPAIGN_JOURNEY.SIDEBAR.AUDIENCES')"
            icon="i-lucide-users"
            slate
            outline
            class="!min-h-11 !rounded-xl"
            @click="router.push({ name: 'campaigns_journey_audiences' })"
          />
          <div
            v-if="canManage"
            v-on-click-outside="closeCreation"
            class="relative"
          >
            <Button
              :label="t(`${NS}.NEW_CAMPAIGN`)"
              icon="i-lucide-plus"
              class="!min-h-11 !rounded-xl"
              data-test="new-campaign"
              :aria-expanded="isChooserOpen || Boolean(creatingChannel)"
              aria-haspopup="dialog"
              @click="toggleChooser"
            />
            <CampaignChannelChooser
              v-if="isChooserOpen"
              :channels="channels"
              @choose="chooseChannel"
              @close="closeCreation"
            />
            <component
              :is="CREATION_DIALOGS[creatingChannel]"
              v-if="creatingChannel"
              @saved="onCreated"
              @created="onCreated"
              @close="closeCreation"
            />
          </div>
        </div>
      </header>

      <section
        class="mb-7 flex flex-col overflow-hidden rounded-3xl border border-n-weak bg-n-solid-1 shadow-sm md:flex-row"
        :aria-label="t(`${NS}.OVERVIEW`)"
      >
        <div
          class="relative min-w-0 overflow-hidden bg-[#0D2344] px-6 py-6 text-white md:w-[32%]"
        >
          <p class="mb-0 text-xs text-white opacity-80">
            {{ t(`${NS}.NEXT_SEND`) }}
          </p>
          <p class="mb-0 mt-3 text-xl font-semibold tracking-tight">
            {{ nextScheduled?.name || t(`${NS}.NO_NEXT_SEND`) }}
          </p>
          <p
            v-if="nextScheduled"
            class="mb-0 mt-2 text-sm text-white opacity-80"
          >
            {{ channelLabel(nextScheduled.channel) }} {{ DOT }}
            {{ formatDate(nextScheduled.when) }}
          </p>
        </div>
        <dl
          class="m-0 grid min-w-0 flex-1 grid-cols-1 gap-5 px-6 py-6 sm:grid-cols-3 md:px-8"
        >
          <div class="min-w-0">
            <dt class="text-xs text-n-slate-11">
              {{ t(`${NS}.IN_PREPARATION`) }}
            </dt>
            <dd
              class="m-0 mt-2 text-3xl font-semibold tabular-nums text-n-slate-12"
            >
              {{ inPreparation }}
            </dd>
          </div>
          <div class="min-w-0 sm:border-s sm:border-n-weak sm:ps-5">
            <dt class="text-xs text-n-slate-11">
              {{ t(`${NS}.SENT_30_DAYS`) }}
            </dt>
            <dd
              class="m-0 mt-2 text-3xl font-semibold tabular-nums text-n-slate-12"
            >
              {{ sentLast30Days }}
            </dd>
          </div>
          <div class="min-w-0 sm:border-s sm:border-n-weak sm:ps-5">
            <dt class="text-xs text-n-slate-11">{{ t(`${NS}.ALWAYS_ON`) }}</dt>
            <dd
              class="m-0 mt-2 text-3xl font-semibold tabular-nums text-n-slate-12"
            >
              {{ alwaysOn }}
            </dd>
          </div>
        </dl>
      </section>

      <section class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm">
        <header
          class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-4 xl:px-6"
        >
          <nav
            class="flex max-w-full gap-1 overflow-x-auto"
            :aria-label="t(`${NS}.CHANNEL_FILTER`)"
          >
            <button
              v-for="channel in ['', ...channelChips]"
              :key="channel || 'all'"
              type="button"
              class="min-h-11 shrink-0 rounded-xl px-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :class="
                channelFilter === channel
                  ? 'bg-n-blue-3 text-n-blue-11'
                  : 'text-n-slate-11 hover:bg-n-alpha-1'
              "
              :data-filter="channel || 'all'"
              :aria-pressed="channelFilter === channel"
              @click="channelFilter = channel"
            >
              {{ channel ? channelLabel(channel) : t(`${NS}.ALL_CHANNELS`) }}
            </button>
          </nav>
          <div class="flex w-full flex-wrap items-center gap-2 sm:w-auto">
            <ChoiceSelect
              v-model="statusFilter"
              :options="statusOptions"
              :aria-label="t(`${NS}.STATUS_FILTER`)"
              compact
            />
            <label
              class="flex min-h-11 w-full items-center gap-2 rounded-xl border border-n-weak px-3 focus-within:ring-2 focus-within:ring-n-brand sm:w-60"
            >
              <span
                class="i-lucide-search size-4 shrink-0 text-n-slate-11"
                aria-hidden="true"
              />
              <input
                v-model="search"
                type="search"
                :aria-label="t(`${NS}.SEARCH`)"
                :placeholder="t(`${NS}.SEARCH`)"
                class="m-0 w-full min-w-0 !border-0 !bg-transparent !p-0 text-sm !shadow-none !outline-none focus:!ring-0"
              />
            </label>
          </div>
        </header>
        <p
          v-if="hasLoadError"
          role="alert"
          class="m-0 border-b border-n-weak px-6 py-3 text-sm text-n-ruby-11"
        >
          {{ t(`${NS}.LOAD_ERROR`) }}
        </p>
        <div v-if="isLoading && !rows.length" class="flex justify-center p-12">
          <Spinner />
        </div>
        <div
          v-else-if="!visibleRows.length"
          class="flex flex-col items-center gap-2 p-12 text-center"
        >
          <span
            class="i-lucide-megaphone size-8 text-n-slate-9"
            aria-hidden="true"
          />
          <p class="mb-0 font-medium text-n-slate-12">
            {{ rows.length ? t(`${NS}.EMPTY_FILTER`) : t(`${NS}.EMPTY_TITLE`) }}
          </p>
          <p v-if="!rows.length" class="mb-0 text-sm text-n-slate-11">
            {{ t(`${NS}.EMPTY_SUBTITLE`) }}
          </p>
        </div>
        <ul v-else class="m-0 list-none p-0">
          <li
            v-for="row in visibleRows"
            :key="row.key"
            :data-row="row.key"
            class="grid gap-3 border-b border-n-weak px-4 py-4 last:border-0 md:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_8rem_auto] md:items-center xl:px-6"
          >
            <div class="flex min-w-0 items-center gap-3">
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
                aria-hidden="true"
              >
                <span :class="CHANNEL_ICONS[row.channel]" class="size-5" />
              </span>
              <div class="min-w-0">
                <p class="mb-0 truncate text-sm font-semibold text-n-slate-12">
                  {{ row.name }}
                </p>
                <p class="mb-0 truncate text-xs text-n-slate-11">
                  {{ channelLabel(row.channel) }}
                  <template v-if="row.detail">
                    {{ DOT }} {{ row.detail }}
                  </template>
                </p>
              </div>
            </div>
            <p class="mb-0 text-sm text-n-slate-12">
              <span class="text-xs text-n-slate-11 md:hidden">
                {{ t(`${NS}.WHEN`) }}{{ COLON }}
              </span>
              {{ formatWhen(row) }}
            </p>
            <p class="mb-0 text-sm text-n-slate-11">
              <template v-if="row.total !== null">
                {{
                  t(`${NS}.SENT_OF`, { sent: row.sent ?? 0, total: row.total })
                }}
              </template>
            </p>
            <p class="mb-0">
              <span
                class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
                :class="STATUS_CLASSES[row.status]"
              >
                {{ statusLabel(row.status) }}
              </span>
            </p>
            <div class="flex items-center justify-end gap-1 md:w-40">
              <router-link
                :to="row.route"
                class="flex min-h-11 items-center gap-1 rounded-xl px-2 text-sm font-medium text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                :aria-label="t(`${NS}.OPEN_ARIA`, { name: row.name })"
              >
                {{ t(`${NS}.OPEN`) }}
                <span class="i-lucide-arrow-right size-4" aria-hidden="true" />
              </router-link>
              <!-- L8 (#1007): e-mail actions also from the list. -->
              <EmailResultActions
                v-if="row.channel === CAMPAIGN_CHANNELS.EMAIL && row.source"
                :campaign="row.source"
                compact
                @updated="fetchAll"
                @deleted="fetchAll"
              />
            </div>
          </li>
        </ul>
      </section>
    </div>
  </section>
</template>
