<script setup>
import {
  DOT,
  COLON,
} from 'dashboard/components-next/CampaignJourney/textMarks';
// Gestão de campanhas as the multichannel overview (#1007, PRD D18, §6.10, O3): period, channel
// (connected ones), totals and the comparison per campaign. A row opens the campaign's Resultado,
// where the detail lives. Old links with ?email_campaign=<id> open that e-mail's Resultado.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import CampaignResultsAPI from 'dashboard/api/campaignResults';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  CAMPAIGN_CHANNELS,
  CHANNEL_ICONS,
} from 'dashboard/components-next/CampaignJourney/campaignChannels';
import { useAvailableCampaignChannels } from 'dashboard/components-next/CampaignJourney/useAvailableCampaignChannels';
import { useOnEnter } from 'dashboard/components-next/CampaignJourney/useOnEnter';
import ResultKpiStrip from 'dashboard/components-next/CampaignResult/ResultKpiStrip.vue';
import {
  RESULT_CHANNELS,
  percent,
  resultRoute,
} from 'dashboard/components-next/CampaignResult/resultMetrics';

const NS = 'RESULT_JOURNEY.OVERVIEW';
const PERIODS = [7, 30, 90];

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { channels, features } = useAvailableCampaignChannels();

const days = ref(30);
const channel = ref('');
const page = ref(1);
const overview = ref(null);
const isLoading = ref(false);
const hasError = ref(false);
let requestId = 0;

const localeTag = computed(() => locale.value.replace('_', '-'));
const number = value =>
  typeof value === 'number'
    ? new Intl.NumberFormat(localeTag.value).format(value)
    : '—';
const rateText = value =>
  typeof value === 'number'
    ? `${new Intl.NumberFormat(localeTag.value, { maximumFractionDigits: 1 }).format(value)}%`
    : '—';
const date = value =>
  value
    ? new Date(value).toLocaleDateString(localeTag.value, {
        day: '2-digit',
        month: '2-digit',
      })
    : '—';

const channelTabs = computed(() => [
  '',
  ...channels.value.filter(item => RESULT_CHANNELS.includes(item)),
]);
const channelLabel = key =>
  key
    ? t(`CAMPAIGN_JOURNEY.CHANNELS.${key.toUpperCase()}`)
    : t(`${NS}.ALL_CHANNELS`);
const periodOptions = computed(() =>
  PERIODS.map(value => ({
    value,
    label: t(`${NS}.PERIOD_DAYS`, { days: value }),
  }))
);

const totals = computed(() => overview.value?.totals || {});
const rows = computed(() => overview.value?.campaigns || []);
const meta = computed(() => overview.value?.meta || {});
const isEmailOnly = computed(() => channel.value === CAMPAIGN_CHANNELS.EMAIL);

const kpis = computed(() => {
  const value = totals.value;
  const items = [
    {
      key: 'campaigns',
      label: t(`${NS}.TOTALS.CAMPAIGNS`),
      value: value.campaigns,
      note: t(`${NS}.TOTALS.CAMPAIGNS_NOTE`, { days: days.value }),
    },
    {
      key: 'reached',
      label: t(`${NS}.TOTALS.REACHED`),
      value: value.reached,
      note: t(`${NS}.TOTALS.REACHED_NOTE`),
    },
    {
      key: 'replied',
      label: t(`${NS}.TOTALS.REPLIED`),
      value: value.replied,
      note: t(`${NS}.TOTALS.REPLIED_NOTE`, {
        rate: rateText(percent(value.replied, value.reached)),
      }),
    },
  ];
  if (value.deals) {
    items.push({
      key: 'deals',
      label: t(`${NS}.TOTALS.DEALS`),
      value: value.deals.cards,
      note: t(`${NS}.TOTALS.DEALS_NOTE`, { won: number(value.deals.won) }),
    });
  }
  if (value.email_health) {
    items.push({
      key: 'email_health',
      label: t(`${NS}.TOTALS.EMAIL_HEALTH`),
      display: rateText(value.email_health.hard_bounce_rate),
      note: t(`${NS}.TOTALS.EMAIL_HEALTH_NOTE`, {
        complaints: rateText(value.email_health.complaint_rate),
      }),
    });
  }
  return items;
});

const engagement = row => {
  if (!row.engagement) return '—';
  return t(`${NS}.ENGAGEMENT.${row.engagement.kind.toUpperCase()}`, {
    rate: rateText(
      row.engagement.rate ?? percent(row.engagement.count, row.sent)
    ),
  });
};

const fetchOverview = async () => {
  requestId += 1;
  const current = requestId;
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await CampaignResultsAPI.getOverview({
      days: days.value,
      channel: channel.value,
      page: page.value,
    });
    if (current !== requestId) return;
    overview.value = data.payload;
  } catch {
    if (current === requestId) hasError.value = true;
  } finally {
    if (current === requestId) isLoading.value = false;
  }
};

const chooseChannel = value => {
  if (channel.value === value) return;
  channel.value = value;
  page.value = 1;
  fetchOverview();
};

const goTo = value => {
  page.value = value;
  fetchOverview();
};

watch(days, () => {
  page.value = 1;
  fetchOverview();
});

const enter = () => {
  const legacyEmail = route.query.email_campaign;
  if (typeof legacyEmail === 'string' && legacyEmail) {
    router.replace(resultRoute(CAMPAIGN_CHANNELS.EMAIL, legacyEmail));
    return;
  }
  store.dispatch('inboxes/get');
  if (features.value.emailCampaigns)
    store.dispatch('emailSenderIdentities/get');
  fetchOverview();
};

useOnEnter(enter);
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-4 sm:p-5 lg:p-8">
      <nav
        class="mb-5 flex items-center gap-2 text-xs text-n-slate-11"
        :aria-label="t('RESULT_JOURNEY.BREADCRUMB')"
      >
        {{ t('CAMPAIGN_JOURNEY.SIDEBAR.GROUP') }}
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <span class="font-medium text-n-blue-11" aria-current="page">
          {{ t(`${NS}.TITLE`) }}
        </span>
      </nav>
      <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
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
        <ChoiceSelect
          v-model="days"
          :options="periodOptions"
          :aria-label="t(`${NS}.PERIOD`)"
          compact
        />
      </header>

      <nav
        class="mb-5 flex max-w-full gap-1 overflow-x-auto"
        :aria-label="t(`${NS}.CHANNEL_FILTER`)"
      >
        <button
          v-for="tab in channelTabs"
          :key="tab || 'all'"
          type="button"
          class="min-h-11 shrink-0 rounded-xl px-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            channel === tab
              ? 'bg-n-blue-3 text-n-blue-11'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          :aria-pressed="channel === tab"
          :data-channel="tab || 'all'"
          @click="chooseChannel(tab)"
        >
          {{ channelLabel(tab) }}
        </button>
      </nav>

      <div v-if="isLoading && !overview" class="flex justify-center p-12">
        <Spinner />
      </div>
      <p
        v-else-if="hasError"
        role="alert"
        class="m-0 rounded-2xl border border-n-weak bg-n-solid-1 p-6 text-sm text-n-ruby-11"
      >
        {{ t('RESULT_JOURNEY.LOAD_ERROR') }}
      </p>
      <template v-else-if="overview">
        <ResultKpiStrip :items="kpis" :label="t(`${NS}.TOTALS.LABEL`)" />

        <section
          class="mt-6 min-w-0 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
          data-overview-table
        >
          <p
            v-if="!rows.length"
            class="m-0 px-6 py-10 text-center text-sm text-n-slate-11"
          >
            {{ t(`${NS}.EMPTY`) }}
          </p>
          <template v-else>
            <ul class="m-0 flex list-none flex-col p-0 xl:hidden">
              <li
                v-for="row in rows"
                :key="`card-${row.channel}-${row.id}`"
                class="border-b border-n-weak last:border-0"
              >
                <router-link
                  :to="resultRoute(row.channel, row.id)"
                  class="flex flex-col gap-2 px-4 py-4 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-n-brand"
                  :aria-label="t(`${NS}.OPEN_ARIA`, { name: row.name })"
                >
                  <span class="flex min-w-0 items-center gap-3">
                    <span
                      class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
                      aria-hidden="true"
                    >
                      <span
                        :class="CHANNEL_ICONS[row.channel]"
                        class="size-4"
                      />
                    </span>
                    <span class="min-w-0">
                      <span
                        class="block break-words text-sm font-semibold text-n-slate-12"
                      >
                        {{ row.name }}
                      </span>
                      <span class="block text-xs text-n-slate-11">
                        {{ channelLabel(row.channel) }} {{ DOT }}
                        {{ date(row.sent_at) }}
                      </span>
                    </span>
                  </span>
                  <span
                    class="grid grid-cols-2 gap-2 text-xs text-n-slate-11 sm:grid-cols-4"
                  >
                    <span>
                      {{ t(`${NS}.TABLE.SENT`) }}{{ COLON }}
                      <strong class="text-n-slate-12">{{
                        number(row.sent)
                      }}</strong>
                    </span>
                    <span>
                      {{ t(`${NS}.TABLE.DELIVERED`) }}{{ COLON }}
                      <strong class="text-n-slate-12">
                        {{ number(row.delivered) }}
                      </strong>
                    </span>
                    <span>{{ engagement(row) }}</span>
                    <span>
                      {{ t(`${NS}.TABLE.REPLIED`) }}{{ COLON }}
                      <strong class="text-n-slate-12">
                        {{ number(row.replied) }} {{ DOT }}
                        {{ rateText(row.reply_rate) }}
                      </strong>
                    </span>
                  </span>
                </router-link>
              </li>
            </ul>
            <div class="hidden max-w-full overflow-x-auto xl:block">
              <table class="w-full border-collapse text-sm" data-overview-rows>
                <thead>
                  <tr class="border-b border-n-weak text-xs text-n-slate-11">
                    <th class="px-6 py-3 text-start font-medium">
                      {{ t(`${NS}.TABLE.CAMPAIGN`) }}
                    </th>
                    <th class="py-3 pe-4 text-start font-medium">
                      {{ t(`${NS}.TABLE.DATE`) }}
                    </th>
                    <th class="py-3 pe-4 text-end font-medium">
                      {{ t(`${NS}.TABLE.SENT`) }}
                    </th>
                    <th class="py-3 pe-4 text-end font-medium">
                      {{ t(`${NS}.TABLE.DELIVERED`) }}
                    </th>
                    <th class="py-3 pe-4 text-start font-medium">
                      {{ t(`${NS}.TABLE.ENGAGEMENT`) }}
                    </th>
                    <template v-if="isEmailOnly">
                      <th class="py-3 pe-4 text-end font-medium">
                        {{ t(`${NS}.TABLE.CLICK_RATE`) }}
                      </th>
                      <th class="py-3 pe-4 text-end font-medium">
                        {{ t(`${NS}.TABLE.BOUNCE_RATE`) }}
                      </th>
                      <th class="py-3 pe-4 text-end font-medium">
                        {{ t(`${NS}.TABLE.UNSUBSCRIBE_RATE`) }}
                      </th>
                    </template>
                    <th class="py-3 pe-4 text-end font-medium">
                      {{ t(`${NS}.TABLE.REPLIED`) }}
                    </th>
                    <th class="py-3 pe-6 text-end font-medium">
                      {{ t(`${NS}.TABLE.RATE`) }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="row in rows"
                    :key="`${row.channel}-${row.id}`"
                    class="border-b border-n-weak last:border-0 hover:bg-n-alpha-1"
                    :data-row="`${row.channel}-${row.id}`"
                  >
                    <td class="max-w-sm px-6 py-2">
                      <router-link
                        :to="resultRoute(row.channel, row.id)"
                        class="flex min-h-11 min-w-0 items-center gap-3 rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                        :aria-label="t(`${NS}.OPEN_ARIA`, { name: row.name })"
                      >
                        <span
                          class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
                          aria-hidden="true"
                        >
                          <span
                            :class="CHANNEL_ICONS[row.channel]"
                            class="size-4"
                          />
                        </span>
                        <span class="min-w-0">
                          <span
                            class="block truncate font-semibold text-n-slate-12"
                          >
                            {{ row.name }}
                          </span>
                          <span class="block text-xs text-n-slate-11">
                            {{ channelLabel(row.channel) }}
                          </span>
                        </span>
                      </router-link>
                    </td>
                    <td class="py-2 pe-4 text-n-slate-11">
                      {{ date(row.sent_at) }}
                    </td>
                    <td class="py-2 pe-4 text-end tabular-nums text-n-slate-12">
                      {{ number(row.sent) }}
                    </td>
                    <td class="py-2 pe-4 text-end tabular-nums text-n-slate-12">
                      {{ number(row.delivered) }}
                    </td>
                    <td class="py-2 pe-4 text-n-slate-11">
                      {{ engagement(row) }}
                    </td>
                    <template v-if="isEmailOnly">
                      <td class="py-2 pe-4 text-end tabular-nums">
                        {{ rateText(row.email?.click_rate) }}
                      </td>
                      <td class="py-2 pe-4 text-end tabular-nums">
                        {{ rateText(row.email?.hard_bounce_rate) }}
                      </td>
                      <td class="py-2 pe-4 text-end tabular-nums">
                        {{ rateText(row.email?.unsubscribe_rate) }}
                      </td>
                    </template>
                    <td class="py-2 pe-4 text-end tabular-nums text-n-slate-12">
                      {{ number(row.replied) }}
                    </td>
                    <td
                      class="py-2 pe-6 text-end font-semibold tabular-nums text-n-slate-12"
                    >
                      {{ rateText(row.reply_rate) }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </template>
          <footer
            v-if="(meta.total_pages || 1) > 1"
            class="flex flex-wrap items-center justify-end gap-3 border-t border-n-weak px-4 py-3 text-sm text-n-slate-11 xl:px-6"
          >
            <span>
              {{
                t('RESULT_JOURNEY.PEOPLE.PAGE_OF', {
                  page,
                  total: meta.total_pages,
                })
              }}
            </span>
            <Button
              :label="t('RESULT_JOURNEY.PEOPLE.PREV')"
              slate
              outline
              class="!min-h-11"
              :disabled="isLoading || page <= 1"
              @click="goTo(page - 1)"
            />
            <Button
              :label="t('RESULT_JOURNEY.PEOPLE.NEXT')"
              slate
              outline
              class="!min-h-11"
              :disabled="isLoading || page >= meta.total_pages"
              @click="goTo(page + 1)"
            />
          </footer>
        </section>
        <p class="mb-0 mt-4 text-xs text-n-slate-11">
          {{ t(`${NS}.FOOTER`) }}
        </p>
      </template>
    </div>
  </section>
</template>
