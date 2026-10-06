<script setup>
import { DOT, DASH } from 'dashboard/components-next/CampaignJourney/textMarks';
// People of a message campaign (#1007, PRD §6.5, E3, E4): situation tabs, generated message,
// reason with code, when, "Abrir conversa" for who replied, and "Baixar resultado" of the tab.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import CampaignResultsAPI from 'dashboard/api/campaignResults';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DeliveryStatusBadge from 'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/DeliveryStatusBadge.vue';
import {
  deliveryReason,
  rawDeliveryReason,
} from 'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/deliveryReason';
import { downloadCsv } from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import { statusTabs } from './resultMetrics';

const props = defineProps({
  channel: { type: String, required: true },
  campaignId: { type: [String, Number], required: true },
  filters: { type: Array, default: () => [] },
  totals: { type: Object, default: () => ({}) },
  refreshKey: { type: Number, default: 0 },
});

const NS = 'RESULT_JOURNEY.PEOPLE';
const { t, locale } = useI18n();
const canManage = useCanManage('campaign_manage');

const status = ref('');
const page = ref(1);
const rows = ref([]);
const meta = ref({});
const isLoading = ref(false);
const hasError = ref(false);
const exporting = ref(false);
let requestId = 0;

const tabs = computed(() =>
  statusTabs(props.filters).map(key => ({
    key,
    label: key ? t(`${NS}.FILTER.${key.toUpperCase()}`) : t(`${NS}.ALL`),
    count: key ? props.totals[key] : props.totals.audience,
  }))
);

const totalPages = computed(() => meta.value.total_pages || 1);

const fetchRows = async () => {
  requestId += 1;
  const current = requestId;
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await CampaignResultsAPI.getRecipients(
      props.channel,
      props.campaignId,
      { status: status.value, page: page.value }
    );
    if (current !== requestId) return;
    rows.value = data.payload.rows || [];
    meta.value = data.payload.meta || {};
  } catch {
    if (current === requestId) hasError.value = true;
  } finally {
    if (current === requestId) isLoading.value = false;
  }
};

const choose = key => {
  if (status.value === key) return;
  status.value = key;
  page.value = 1;
  fetchRows();
};

const goTo = value => {
  page.value = value;
  fetchRows();
};

const download = async () => {
  if (exporting.value) return;
  exporting.value = true;
  try {
    const { data } = await CampaignResultsAPI.exportResult(
      props.channel,
      props.campaignId,
      { status: status.value }
    );
    downloadCsv(
      data,
      `campaign-${props.channel}-${props.campaignId}-${status.value || 'all'}.csv`
    );
  } catch {
    useAlert(t('RESULT_JOURNEY.DOWNLOAD_ERROR'));
  } finally {
    exporting.value = false;
  }
};

const when = row => {
  const value = row.failed_at || row.read_at || row.delivered_at || row.sent_at;
  if (!value) return '';
  return new Date(value).toLocaleString(locale.value.replace('_', '-'), {
    dateStyle: 'short',
    timeStyle: 'short',
  });
};

const reason = row => deliveryReason(row, t);
const code = row =>
  row.error_code && String(row.error_code) !== String(rawDeliveryReason(row))
    ? row.error_code
    : '';

const conversationRoute = row => ({
  name: 'inbox_conversation',
  params: { conversation_id: row.conversation_display_id },
});

watch(
  () => [props.channel, props.campaignId],
  () => {
    status.value = '';
    page.value = 1;
    fetchRows();
  },
  { immediate: true }
);
watch(() => props.refreshKey, fetchRows);

defineExpose({ fetchRows, choose });
</script>

<template>
  <section
    class="min-w-0 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
    data-people-table
  >
    <header
      class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-4 xl:px-6"
    >
      <h2 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.TITLE`) }}
      </h2>
      <Button
        v-if="canManage"
        :label="t('RESULT_JOURNEY.DOWNLOAD')"
        icon="i-lucide-download"
        slate
        outline
        class="!min-h-11 !rounded-xl"
        :is-loading="exporting"
        data-export
        @click="download"
      />
    </header>
    <nav
      class="flex max-w-full gap-1 overflow-x-auto border-b border-n-weak px-4 py-3 xl:px-6"
      :aria-label="t(`${NS}.FILTER_LABEL`)"
    >
      <button
        v-for="tab in tabs"
        :key="tab.key || 'all'"
        type="button"
        class="flex min-h-11 shrink-0 items-center gap-1.5 rounded-xl px-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          status === tab.key
            ? 'bg-n-blue-3 text-n-blue-11'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        :aria-pressed="status === tab.key"
        :data-tab="tab.key || 'all'"
        @click="choose(tab.key)"
      >
        {{ tab.label }}
        <span v-if="typeof tab.count === 'number'" class="tabular-nums">
          {{ tab.count }}
        </span>
      </button>
    </nav>

    <div v-if="isLoading && !rows.length" class="flex justify-center p-12">
      <Spinner />
    </div>
    <p
      v-else-if="hasError"
      role="alert"
      class="m-0 px-6 py-6 text-sm text-n-ruby-11"
    >
      {{ t('RESULT_JOURNEY.LOAD_ERROR') }}
    </p>
    <p
      v-else-if="!rows.length"
      class="m-0 px-6 py-10 text-center text-sm text-n-slate-11"
    >
      {{ t(`${NS}.EMPTY`) }}
    </p>
    <template v-else>
      <ul class="m-0 flex list-none flex-col p-0 xl:hidden" data-people-cards>
        <li
          v-for="row in rows"
          :key="`card-${row.id}`"
          class="flex flex-col gap-2 border-b border-n-weak px-4 py-4 last:border-0"
        >
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div class="min-w-0">
              <p class="mb-0 break-words text-sm font-semibold text-n-slate-12">
                {{ row.contact.name || '—' }}
              </p>
              <p class="mb-0 text-xs tabular-nums text-n-slate-11">
                {{ row.contact.phone_number || '—' }}
              </p>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <DeliveryStatusBadge :status="row.status" />
              <span
                v-if="row.replied"
                class="inline-flex h-6 items-center rounded-md bg-n-blue-3 px-2 text-xs font-medium text-n-blue-11"
              >
                {{ t(`${NS}.REPLIED_BADGE`) }}
              </span>
            </div>
          </div>
          <p
            class="mb-0 line-clamp-3 whitespace-pre-line break-words text-sm"
            :class="
              row.message_content ? 'text-n-slate-11' : 'italic text-n-slate-10'
            "
          >
            {{ row.message_content || t(`${NS}.NO_MESSAGE`) }}
          </p>
          <p v-if="reason(row)" class="mb-0 text-xs text-n-ruby-11">
            {{ reason(row) }}
            <template v-if="code(row)">
              {{ DOT }} {{ t(`${NS}.CODE`, { code: code(row) }) }}
            </template>
          </p>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-xs text-n-slate-11">{{ when(row) }}</span>
            <router-link
              v-if="row.conversation_display_id"
              :to="conversationRoute(row)"
              class="flex min-h-11 items-center gap-1 rounded-xl px-2 text-sm font-medium text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              data-open-conversation
            >
              {{ t(`${NS}.OPEN_CONVERSATION`) }}
              <span class="i-lucide-arrow-up-right size-4" aria-hidden="true" />
            </router-link>
          </div>
        </li>
      </ul>
      <div class="hidden max-w-full overflow-x-auto xl:block">
        <table class="w-full border-collapse text-sm" data-people-rows>
          <thead>
            <tr
              class="border-b border-n-weak text-start text-xs text-n-slate-11"
            >
              <th class="px-6 py-3 text-start font-medium">
                {{ t(`${NS}.CONTACT`) }}
              </th>
              <th class="py-3 pe-4 text-start font-medium">
                {{ t(`${NS}.STATUS`) }}
              </th>
              <th class="py-3 pe-4 text-start font-medium">
                {{ t(`${NS}.MESSAGE`) }}
              </th>
              <th class="py-3 pe-4 text-start font-medium">
                {{ t(`${NS}.REASON`) }}
              </th>
              <th class="py-3 pe-4 text-start font-medium">
                {{ t(`${NS}.WHEN`) }}
              </th>
              <th class="py-3 pe-6 text-end font-medium">
                <span class="sr-only">{{ t(`${NS}.OPEN_CONVERSATION`) }}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows"
              :key="row.id"
              class="border-b border-n-weak align-top last:border-0"
              :data-row="row.id"
            >
              <td class="max-w-56 px-6 py-3">
                <p class="mb-0 truncate font-medium text-n-slate-12">
                  {{ row.contact.name || '—' }}
                </p>
                <p class="mb-0 text-xs tabular-nums text-n-slate-11">
                  {{ row.contact.phone_number || '—' }}
                </p>
              </td>
              <td class="py-3 pe-4">
                <div class="flex flex-wrap gap-1.5">
                  <DeliveryStatusBadge :status="row.status" />
                  <span
                    v-if="row.replied"
                    class="inline-flex h-6 items-center rounded-md bg-n-blue-3 px-2 text-xs font-medium text-n-blue-11"
                  >
                    {{ t(`${NS}.REPLIED_BADGE`) }}
                  </span>
                </div>
              </td>
              <td class="max-w-md py-3 pe-4">
                <span
                  class="line-clamp-2 whitespace-pre-line break-words"
                  :class="
                    row.message_content
                      ? 'text-n-slate-11'
                      : 'italic text-n-slate-10'
                  "
                >
                  {{ row.message_content || t(`${NS}.NO_MESSAGE`) }}
                </span>
              </td>
              <td class="max-w-56 py-3 pe-4">
                <span v-if="reason(row)" class="line-clamp-2 text-n-slate-11">
                  {{ reason(row) }}
                </span>
                <span v-else class="text-n-slate-10">{{ DASH }}</span>
                <span
                  v-if="code(row)"
                  class="block text-xs tabular-nums text-n-slate-10"
                >
                  {{ t(`${NS}.CODE`, { code: code(row) }) }}
                </span>
              </td>
              <td class="whitespace-nowrap py-3 pe-4 text-n-slate-11">
                {{ when(row) }}
              </td>
              <td class="py-2 pe-6 text-end">
                <router-link
                  v-if="row.conversation_display_id"
                  :to="conversationRoute(row)"
                  class="inline-flex min-h-11 items-center gap-1 whitespace-nowrap rounded-xl px-2 font-medium text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                  data-open-conversation
                >
                  {{ t(`${NS}.OPEN_CONVERSATION`) }}
                  <span
                    class="i-lucide-arrow-up-right size-4"
                    aria-hidden="true"
                  />
                </router-link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <footer
      v-if="totalPages > 1"
      class="flex flex-wrap items-center justify-end gap-3 border-t border-n-weak px-4 py-3 text-sm text-n-slate-11 xl:px-6"
    >
      <span>{{ t(`${NS}.PAGE_OF`, { page, total: totalPages }) }}</span>
      <Button
        :label="t(`${NS}.PREV`)"
        slate
        outline
        class="!min-h-11"
        :disabled="isLoading || page <= 1"
        @click="goTo(page - 1)"
      />
      <Button
        :label="t(`${NS}.NEXT`)"
        slate
        outline
        class="!min-h-11"
        :disabled="isLoading || page >= totalPages"
        @click="goTo(page + 1)"
      />
    </footer>
  </section>
</template>
