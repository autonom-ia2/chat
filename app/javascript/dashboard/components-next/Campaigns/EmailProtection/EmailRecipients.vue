<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import ReportsAPI from 'dashboard/api/emailCampaignReports';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import EmailStatusBadge from './EmailStatusBadge.vue';
import EmailStatusFilter from './EmailStatusFilter.vue';
import { useEmailReportRefresh } from './useEmailReportRefresh';
import {
  NS,
  reasonKey,
  safeError,
  formatNumber,
  formatDate,
  downloadCsv,
} from './presentation';

const props = defineProps({
  campaignId: { type: [String, Number], required: true },
  problemOnly: Boolean,
  refreshKey: { type: [Number, String], default: 0 },
});

const { t, locale } = useI18n();
const canManage = useCanManage('campaign_manage');
const { run, abort, isPending } = useAbortableRequest();
const section = ref(null);
const search = ref('');
const status = ref(props.problemOnly ? 'attention' : '');
const problemStatus = ref('attention');
const page = ref(1);
const recipients = ref([]);
const meta = ref({});
const errorMessage = ref('');
const exportError = ref('');
const exporting = ref(false);
const copied = ref(null);
let searchTimer;

const isProblemFilter = computed(() => status.value === 'attention');
const filters = computed(() => {
  let selectedStatus = status.value;
  if (isProblemFilter.value) {
    selectedStatus =
      problemStatus.value === 'attention' ? '' : problemStatus.value;
  }
  return {
    search: search.value,
    status: selectedStatus,
    problem: isProblemFilter.value,
  };
});

const metricHelp = computed(() => {
  const hints = [t(`${NS}.METRICS_HINT`)];
  if (meta.value.delivery_mode && meta.value.delivery_mode !== 'ses') {
    hints.push(t(`${NS}.DELIVERY_HINT`));
  }
  return hints.join(' ');
});

const totalPages = computed(
  () =>
    meta.value.total_pages ??
    (Math.ceil((meta.value.count || 0) / (meta.value.per_page || 50)) || 1)
);

const number = value => formatNumber(value, locale.value);
const date = value => formatDate(value, locale.value);
const recipientStatusRecord = recipient => ({
  ...recipient,
  delivery_mode:
    Object.hasOwn(recipient, 'delivery_mode') &&
    recipient.delivery_mode !== undefined
      ? recipient.delivery_mode
      : meta.value.delivery_mode,
});

const fetchRecipients = async () => {
  clearTimeout(searchTimer);
  errorMessage.value = '';
  try {
    const response = await run(signal =>
      ReportsAPI.getRecipients(props.campaignId, {
        ...filters.value,
        page: page.value,
        signal,
      })
    );
    if (!response) return;
    recipients.value = response.data.payload.recipients || [];
    meta.value = response.data.payload.meta || {};
  } catch (error) {
    errorMessage.value = safeError(t, error);
  }
};

const resetPage = () => {
  page.value = 1;
};

watch(status, value => {
  if (value !== 'attention') problemStatus.value = 'attention';
  resetPage();
  fetchRecipients();
});

watch(problemStatus, () => {
  if (!isProblemFilter.value) return;
  resetPage();
  fetchRecipients();
});

watch(search, () => {
  abort();
  resetPage();
  clearTimeout(searchTimer);
  searchTimer = setTimeout(fetchRecipients, 300);
});

watch(
  () => props.problemOnly,
  value => {
    if (value) {
      status.value = 'attention';
      problemStatus.value = 'attention';
    } else if (status.value === 'attention') {
      status.value = '';
    }
  }
);

watch(
  () => props.campaignId,
  () => {
    abort();
    resetPage();
    meta.value = {};
    recipients.value = [];
    fetchRecipients();
  },
  { immediate: true }
);

watch(() => props.refreshKey, fetchRecipients);

const clearFilters = () => {
  search.value = '';
  status.value = '';
  problemStatus.value = 'attention';
  resetPage();
  fetchRecipients();
};

const goToPage = value => {
  page.value = value;
  fetchRecipients();
};

const exportCsv = async () => {
  if (exporting.value) return;
  exporting.value = true;
  exportError.value = '';
  try {
    const { data } = await ReportsAPI.export(props.campaignId, filters.value);
    downloadCsv(data, `email-campaign-${props.campaignId}-filtered.csv`);
  } catch (error) {
    exportError.value = safeError(t, error);
  } finally {
    exporting.value = false;
  }
};

const copyEmail = async recipient => {
  try {
    await navigator.clipboard.writeText(recipient.email);
    copied.value = recipient.id;
  } catch (error) {
    exportError.value = t(`${NS}.ERROR`);
  }
};

useEmailReportRefresh(
  () => (!isPending.value ? fetchRecipients() : undefined),
  () =>
    recipients.value.some(
      row => row.status === 'pending' || row.preflight_status === 'unchecked'
    )
);

onBeforeUnmount(() => clearTimeout(searchTimer));

const showProblems = () => {
  search.value = '';
  status.value = 'attention';
  problemStatus.value = 'attention';
  resetPage();
  fetchRecipients();
  section.value?.scrollIntoView?.({ block: 'start', behavior: 'smooth' });
};

defineExpose({ fetchRecipients, showProblems });
</script>

<template>
  <section
    ref="section"
    class="flex flex-col min-w-0 gap-4 p-4 border rounded-lg border-n-weak bg-n-solid-1"
  >
    <div
      class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex items-center gap-2">
        <h3 class="m-0 text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN_MANAGEMENT.RECIPIENTS.TITLE') }}
        </h3>
        <span
          class="inline-flex text-n-slate-10"
          tabindex="0"
          :aria-label="metricHelp"
          :title="metricHelp"
        >
          <Icon icon="i-lucide-info" class="size-4" />
        </span>
      </div>
      <div class="flex flex-wrap gap-2">
        <Button
          :label="t(`${NS}.REFRESH`)"
          icon="i-lucide-refresh-cw"
          sm
          slate
          outline
          :disabled="isPending"
          @click="fetchRecipients"
        />
        <Button
          v-if="canManage"
          :label="t(`${NS}.EXPORT`)"
          icon="i-lucide-download"
          sm
          outline
          :disabled="exporting || isPending"
          :is-loading="exporting"
          @click="exportCsv"
        />
      </div>
    </div>

    <div
      data-email-recipient-filters
      class="grid grid-cols-1 gap-3 md:grid-cols-2 md:items-end xl:items-end"
      :class="
        isProblemFilter
          ? 'xl:grid-cols-[minmax(18rem,1fr)_14rem_14rem_auto]'
          : 'xl:grid-cols-[minmax(18rem,1fr)_14rem_auto]'
      "
    >
      <Input
        v-model="search"
        :label="t(`${NS}.SEARCH`)"
        class="w-full min-w-0"
        @enter="fetchRecipients"
      />
      <EmailStatusFilter
        v-model="status"
        :delivery-mode="meta.delivery_mode"
        class="w-full"
      />
      <EmailStatusFilter
        v-if="isProblemFilter"
        v-model="problemStatus"
        problem
        :delivery-mode="meta.delivery_mode"
        class="w-full"
      />
      <Button
        :label="t(`${NS}.CLEAR`)"
        sm
        slate
        ghost
        class="justify-self-start xl:justify-self-end"
        @click="clearFilters"
      />
    </div>

    <p v-if="exportError" class="m-0 text-sm text-n-ruby-11" role="alert">
      {{ exportError }}
    </p>
    <p v-if="isPending" class="m-0 text-sm text-n-slate-11" role="status">
      {{ t(`${NS}.LOADING`) }}
    </p>
    <p v-else-if="errorMessage" class="m-0 text-sm text-n-ruby-11" role="alert">
      {{ errorMessage }}
    </p>
    <p v-else-if="!recipients.length" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.EMPTY`) }}
    </p>

    <template v-else>
      <div class="flex flex-col gap-2 sm:hidden" data-recipient-mobile-list>
        <article
          v-for="recipient in recipients"
          :key="`mobile-${recipient.id}`"
          class="flex flex-col gap-3 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
          data-recipient-card
        >
          <div class="flex flex-col min-w-0 gap-1">
            <bdi
              dir="ltr"
              class="block max-w-full text-sm font-medium truncate text-n-slate-12"
            >
              {{ recipient.email }}
            </bdi>
            <p
              v-if="recipient.name"
              class="m-0 text-xs truncate text-n-slate-11"
            >
              {{ recipient.name }}
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <EmailStatusBadge :record="recipientStatusRecord(recipient)" />
          </div>

          <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-n-slate-11">
            <span>
              {{ t('CAMPAIGN_MANAGEMENT.TABLE.OPENS') }}
              {{ number(recipient.opens) }}
            </span>
            <span>
              {{ t('CAMPAIGN_MANAGEMENT.TABLE.CLICKS') }}
              {{ number(recipient.clicks) }}
            </span>
          </div>

          <details>
            <summary
              class="inline-flex items-center gap-1 cursor-pointer text-sm text-n-blue-11"
            >
              <Icon icon="i-lucide-chevron-right" class="size-3.5" />
              {{ t(`${NS}.DETAILS`) }}
            </summary>
            <div class="flex flex-col gap-2 mt-2 text-xs">
              <bdi dir="ltr" class="break-all">{{ recipient.email }}</bdi>
              <p v-if="recipient.name" class="m-0 break-words">
                <span class="font-medium">{{
                  t('CAMPAIGN_MANAGEMENT.TABLE.NAME')
                }}</span>
                {{ recipient.name }}
              </p>
              <Button
                :label="
                  t(`${NS}.${copied === recipient.id ? 'COPIED' : 'COPY'}`)
                "
                icon="i-lucide-copy"
                sm
                slate
                outline
                class="self-start"
                @click="copyEmail(recipient)"
              />
              <p
                v-if="
                  recipient.reason_code ||
                  recipient.suppression_reason ||
                  recipient.preflight_reason
                "
                class="m-0"
              >
                {{
                  t(
                    `${NS}.REASON.${reasonKey(
                      recipient.suppression_reason ||
                        recipient.reason_code ||
                        recipient.preflight_reason
                    )}`
                  )
                }}
              </p>
              <p v-if="recipient.preflight_status" class="m-0">
                <EmailStatusBadge
                  :record="{ status: recipient.preflight_status }"
                />
              </p>
              <p
                v-if="
                  recipient.attempts !== undefined &&
                  recipient.attempts !== null
                "
                class="m-0"
              >
                {{
                  t(`${NS}.RETRY_COUNT`, {
                    count: number(recipient.attempts),
                  })
                }}
              </p>
              <p v-if="recipient.sent_at" class="m-0">
                {{ t(`${NS}.SENT_AT`, { date: date(recipient.sent_at) }) }}
              </p>
              <p v-if="recipient.last_event_at" class="m-0">
                <span>{{ t('CAMPAIGN_MANAGEMENT.TABLE.LAST_EVENT_AT') }}</span>
                <span>{{ date(recipient.last_event_at) }}</span>
              </p>
            </div>
          </details>
        </article>
      </div>

      <div class="hidden max-w-full overflow-x-auto sm:block">
        <table class="w-full min-w-[60rem] text-sm text-start border-collapse">
          <thead>
            <tr class="border-b border-n-weak text-n-slate-11">
              <th class="py-2 pe-3 text-start">
                {{ t('CAMPAIGN_MANAGEMENT.TABLE.EMAIL') }}
              </th>
              <th class="py-2 pe-3 text-start">
                {{ t('CAMPAIGN_MANAGEMENT.TABLE.NAME') }}
              </th>
              <th class="py-2 pe-3 text-start">
                {{ t('CAMPAIGN_MANAGEMENT.TABLE.STATUS') }}
              </th>
              <th class="py-2 pe-3 text-end">
                {{ t('CAMPAIGN_MANAGEMENT.TABLE.OPENS') }}
              </th>
              <th class="py-2 pe-3 text-end">
                {{ t('CAMPAIGN_MANAGEMENT.TABLE.CLICKS') }}
              </th>
              <th class="py-2 text-start">{{ t(`${NS}.DETAILS`) }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="recipient in recipients"
              :key="recipient.id"
              class="border-b border-n-weak text-n-slate-12"
            >
              <td class="min-w-60 py-3 pe-3">
                <bdi dir="ltr" class="block w-60 truncate">{{
                  recipient.email
                }}</bdi>
              </td>
              <td class="min-w-48 py-3 pe-3">
                <span class="block w-48 truncate" :title="recipient.name">
                  {{ recipient.name || '' }}
                </span>
              </td>
              <td class="min-w-48 py-3 pe-3">
                <EmailStatusBadge :record="recipientStatusRecord(recipient)" />
              </td>
              <td class="py-3 pe-3 text-end">{{ number(recipient.opens) }}</td>
              <td class="py-3 pe-3 text-end">{{ number(recipient.clicks) }}</td>
              <td class="min-w-48 py-3">
                <details>
                  <summary
                    class="inline-flex items-center gap-1 cursor-pointer text-n-blue-11"
                  >
                    <Icon icon="i-lucide-chevron-right" class="size-3.5" />
                    {{ t(`${NS}.DETAILS`) }}
                  </summary>
                  <div class="flex flex-col w-60 gap-2 mt-2 text-xs">
                    <bdi dir="ltr" class="break-all">{{ recipient.email }}</bdi>
                    <p v-if="recipient.name" class="m-0 break-words">
                      <span class="font-medium">{{
                        t('CAMPAIGN_MANAGEMENT.TABLE.NAME')
                      }}</span>
                      {{ recipient.name }}
                    </p>
                    <Button
                      :label="
                        t(
                          `${NS}.${copied === recipient.id ? 'COPIED' : 'COPY'}`
                        )
                      "
                      icon="i-lucide-copy"
                      sm
                      slate
                      outline
                      @click="copyEmail(recipient)"
                    />
                    <p
                      v-if="
                        recipient.reason_code ||
                        recipient.suppression_reason ||
                        recipient.preflight_reason
                      "
                      class="m-0"
                    >
                      {{
                        t(
                          `${NS}.REASON.${reasonKey(
                            recipient.suppression_reason ||
                              recipient.reason_code ||
                              recipient.preflight_reason
                          )}`
                        )
                      }}
                    </p>
                    <p v-if="recipient.preflight_status" class="m-0">
                      <EmailStatusBadge
                        :record="{ status: recipient.preflight_status }"
                      />
                    </p>
                    <p
                      v-if="
                        recipient.attempts !== undefined &&
                        recipient.attempts !== null
                      "
                      class="m-0"
                    >
                      {{
                        t(`${NS}.RETRY_COUNT`, {
                          count: number(recipient.attempts),
                        })
                      }}
                    </p>
                    <p v-if="recipient.sent_at" class="m-0">
                      {{
                        t(`${NS}.SENT_AT`, { date: date(recipient.sent_at) })
                      }}
                    </p>
                    <p v-if="recipient.last_event_at" class="m-0">
                      <span>{{
                        t('CAMPAIGN_MANAGEMENT.TABLE.LAST_EVENT_AT')
                      }}</span>
                      <span>{{ date(recipient.last_event_at) }}</span>
                    </p>
                  </div>
                </details>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <div
      v-if="!errorMessage && totalPages > 1"
      class="flex flex-wrap items-center justify-end gap-3 text-sm text-n-slate-11"
    >
      <span>{{
        t('CAMPAIGN_MANAGEMENT.RECIPIENTS.PAGE_OF', {
          page: number(meta.current_page || page),
          total: number(totalPages),
        })
      }}</span>
      <Button
        :label="t('CAMPAIGN_MANAGEMENT.RECIPIENTS.PREV')"
        sm
        outline
        :disabled="isPending || page <= 1"
        @click="goToPage(page - 1)"
      />
      <Button
        :label="t('CAMPAIGN_MANAGEMENT.RECIPIENTS.NEXT')"
        sm
        outline
        :disabled="isPending || page >= totalPages"
        @click="goToPage(page + 1)"
      />
    </div>
  </section>
</template>
