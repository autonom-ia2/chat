<script setup>
// People of an e-mail campaign in the Resultado (#990). Same rows, filters, pages, export and
// copy as the old Gestão table (useEmailRecipients, O1), shown in plain words: a short status,
// opens and clicks side by side and the details as labelled pairs under the row.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useEmailRecipients } from 'dashboard/components-next/Campaigns/EmailProtection/useEmailRecipients';
import {
  NS as EMAIL_NS,
  PROBLEM_STATUSES,
  RECIPIENT_STATUSES,
  statusKey,
  reasonKey,
  displayStatusLabel,
  formatNumber,
  formatDate,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import {
  ADDRESS_CHECK_KEYS,
  FILTER_PILL_KEYS,
  PILL_CLASSES,
  pillKeyOf,
} from './recipientPills';

const props = defineProps({
  campaignId: { type: [String, Number], required: true },
  refreshKey: { type: [Number, String], default: 0 },
});

const NS = 'RESULT_JOURNEY.EMAIL_PEOPLE';
const { t, locale } = useI18n();
const canManage = useCanManage('campaign_manage');
const section = ref(null);
const openId = ref(null);
const {
  search,
  status,
  problemStatus,
  page,
  recipients,
  meta,
  errorMessage,
  exportError,
  exporting,
  copied,
  isPending,
  isProblemFilter,
  metricHelp,
  totalPages,
  recipientStatusRecord,
  fetchRecipients,
  clearFilters,
  goToPage,
  exportCsv,
  copyEmail,
  showProblems: showProblemRows,
} = useEmailRecipients(
  {
    campaignId: () => props.campaignId,
    refreshKey: () => props.refreshKey,
    problemOnly: () => false,
  },
  { t }
);

const number = value => formatNumber(value, locale.value);
const date = value => formatDate(value, locale.value);

const pillLabel = key => t(`${NS}.PILL.${key.toUpperCase()}`);
const filterLabel = value => {
  if (!value) return t(`${NS}.ALL`);
  const key =
    value === 'delivered'
      ? pillKeyOf(
          statusKey({ status: value, delivery_mode: meta.value.delivery_mode })
        )
      : FILTER_PILL_KEYS[value];
  return pillLabel(key);
};
const statusOptions = computed(() =>
  RECIPIENT_STATUSES.map(value => ({ value, label: filterLabel(value) }))
);
const problemOptions = computed(() =>
  PROBLEM_STATUSES.map(value => ({
    value,
    label: value === 'attention' ? t(`${NS}.ALL_PROBLEMS`) : filterLabel(value),
  }))
);

const rows = computed(() =>
  recipients.value.map(recipient => {
    const record = recipientStatusRecord(recipient);
    const key = statusKey(record);
    const pill = pillKeyOf(key);
    const reason =
      recipient.suppression_reason ||
      recipient.reason_code ||
      recipient.preflight_reason;
    return {
      ...recipient,
      pill: {
        label: pillLabel(pill),
        title: displayStatusLabel(t, key),
        className: PILL_CLASSES[pill] || PILL_CLASSES.unknown,
      },
      details: [
        {
          key: 'status',
          label: t(`${NS}.FULL_STATUS`),
          value: displayStatusLabel(t, key),
        },
        reason && {
          key: 'reason',
          label: t(`${NS}.REASON`),
          value: t(`${EMAIL_NS}.REASON.${reasonKey(reason)}`),
        },
        {
          key: 'sent_at',
          label: t(`${NS}.SENT_AT`),
          value: recipient.sent_at
            ? date(recipient.sent_at)
            : t(`${NS}.NOT_SENT`),
        },
        {
          key: 'last_event_at',
          label: t(`${NS}.LAST_ACTIVITY`),
          value: recipient.last_event_at
            ? date(recipient.last_event_at)
            : t(`${NS}.NO_ACTIVITY`),
        },
        recipient.preflight_status && {
          key: 'address',
          label: t(`${NS}.ADDRESS_CHECK`),
          value: t(
            `${NS}.ADDRESS.${ADDRESS_CHECK_KEYS[recipient.preflight_status] || 'UNKNOWN'}`
          ),
        },
        typeof recipient.attempts === 'number' && {
          key: 'attempts',
          label: t(`${NS}.RETRIES`),
          value: recipient.attempts
            ? t(
                `${NS}.RETRIES_COUNT`,
                { count: number(recipient.attempts) },
                recipient.attempts
              )
            : t(`${NS}.RETRIES_NONE`),
        },
      ].filter(Boolean),
    };
  })
);

const toggle = id => {
  openId.value = openId.value === id ? null : id;
};
const detailsId = id => `email-person-${id}`;

const showProblems = () => {
  showProblemRows();
  section.value?.scrollIntoView?.({ block: 'start', behavior: 'smooth' });
};

defineExpose({ fetchRecipients, showProblems });
</script>

<template>
  <section
    ref="section"
    class="min-w-0 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
    data-email-people
  >
    <header
      class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-4 xl:px-6"
    >
      <div class="flex items-center gap-2">
        <h2 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.TITLE`) }}
        </h2>
        <span
          class="inline-flex size-11 items-center justify-center rounded-xl text-n-slate-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          tabindex="0"
          role="img"
          :aria-label="metricHelp"
          :title="metricHelp"
        >
          <span class="i-lucide-info size-4" aria-hidden="true" />
        </span>
      </div>
      <div class="flex flex-wrap gap-2">
        <Button
          :label="t(`${EMAIL_NS}.REFRESH`)"
          icon="i-lucide-refresh-cw"
          slate
          ghost
          class="!min-h-11 !rounded-xl"
          :disabled="isPending"
          data-people-refresh
          @click="fetchRecipients"
        />
        <Button
          v-if="canManage"
          :label="t(`${NS}.EXPORT`)"
          icon="i-lucide-download"
          slate
          outline
          class="!min-h-11 !rounded-xl"
          :disabled="exporting || isPending"
          :is-loading="exporting"
          data-people-export
          @click="exportCsv"
        />
      </div>
    </header>

    <div
      class="grid grid-cols-1 gap-3 border-b border-n-weak px-4 py-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-end xl:px-6"
      :class="{
        'lg:grid-cols-[minmax(0,1fr)_auto_auto_auto]': isProblemFilter,
        'lg:grid-cols-[minmax(0,1fr)_auto_auto]': !isProblemFilter,
      }"
      data-people-filters
    >
      <Input
        v-model="search"
        :label="t(`${EMAIL_NS}.SEARCH`)"
        class="w-full min-w-0"
        data-people-search
        @enter="fetchRecipients"
      />
      <div class="flex min-w-0 flex-col gap-1 text-sm text-n-slate-12">
        <span class="text-heading-3" aria-hidden="true">
          {{ t(`${NS}.STATUS_FILTER`) }}
        </span>
        <ChoiceSelect
          v-model="status"
          :options="statusOptions"
          :aria-label="t(`${NS}.STATUS_FILTER`)"
          data-people-status
        />
      </div>
      <div
        v-if="isProblemFilter"
        class="flex min-w-0 flex-col gap-1 text-sm text-n-slate-12"
      >
        <span class="text-heading-3" aria-hidden="true">
          {{ t(`${NS}.PROBLEM_FILTER`) }}
        </span>
        <ChoiceSelect
          v-model="problemStatus"
          :options="problemOptions"
          :aria-label="t(`${NS}.PROBLEM_FILTER`)"
          data-people-problem
        />
      </div>
      <Button
        :label="t(`${EMAIL_NS}.CLEAR`)"
        slate
        ghost
        class="!min-h-11 !rounded-xl justify-self-start"
        data-people-clear
        @click="clearFilters"
      />
    </div>

    <p
      v-if="exportError"
      class="m-0 px-4 pt-4 text-sm text-n-ruby-11 xl:px-6"
      role="alert"
    >
      {{ exportError }}
    </p>
    <p
      v-if="isPending"
      class="m-0 px-4 py-6 text-sm text-n-slate-11 xl:px-6"
      role="status"
    >
      {{ t(`${EMAIL_NS}.LOADING`) }}
    </p>
    <p
      v-else-if="errorMessage"
      class="m-0 px-4 py-6 text-sm text-n-ruby-11 xl:px-6"
      role="alert"
    >
      {{ errorMessage }}
    </p>
    <p
      v-else-if="!recipients.length"
      class="m-0 px-4 py-10 text-center text-sm text-n-slate-11 xl:px-6"
    >
      {{ t(`${EMAIL_NS}.EMPTY`) }}
    </p>

    <template v-else>
      <ul class="m-0 flex list-none flex-col p-0 md:hidden" data-people-cards>
        <li
          v-for="row in rows"
          :key="`card-${row.id}`"
          class="flex flex-col gap-3 border-b border-n-weak px-4 py-4 last:border-0"
          :data-person="row.id"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="mb-0 truncate text-sm font-semibold text-n-slate-12">
                {{ row.name || row.email }}
              </p>
              <bdi
                v-if="row.name"
                dir="ltr"
                class="block truncate text-xs text-n-slate-11"
              >
                {{ row.email }}
              </bdi>
            </div>
            <span
              class="inline-flex shrink-0 rounded-full px-2 py-0.5 text-xs font-medium"
              :class="row.pill.className"
              :title="row.pill.title"
              data-person-pill
            >
              {{ row.pill.label }}
            </span>
          </div>
          <div class="flex items-center justify-between gap-3">
            <p class="mb-0 text-xs text-n-slate-11">
              {{
                t(`${NS}.OPENS_CLICKS`, {
                  opens: number(row.opens),
                  clicks: number(row.clicks),
                })
              }}
            </p>
            <button
              type="button"
              class="inline-flex min-h-11 items-center gap-1 rounded-xl px-2 text-sm font-medium text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :aria-expanded="openId === row.id"
              :aria-controls="`${detailsId(row.id)}-card`"
              :aria-label="t(`${NS}.DETAILS_ARIA`, { email: row.email })"
              data-person-toggle
              @click="toggle(row.id)"
            >
              {{ t(`${EMAIL_NS}.DETAILS`) }}
              <span
                :class="
                  openId === row.id
                    ? 'i-lucide-chevron-up'
                    : 'i-lucide-chevron-down'
                "
                class="size-4"
                aria-hidden="true"
              />
            </button>
          </div>
          <div
            v-if="openId === row.id"
            :id="`${detailsId(row.id)}-card`"
            class="flex flex-col gap-3 rounded-xl border border-n-weak p-3"
            data-person-details
          >
            <dl class="m-0 grid grid-cols-1 gap-2 text-sm">
              <div v-for="pair in row.details" :key="pair.key" class="min-w-0">
                <dt class="text-xs text-n-slate-11">{{ pair.label }}</dt>
                <dd class="m-0 break-words text-n-slate-12">
                  {{ pair.value }}
                </dd>
              </div>
            </dl>
            <Button
              :label="t(`${EMAIL_NS}.${copied === row.id ? 'COPIED' : 'COPY'}`)"
              icon="i-lucide-copy"
              slate
              outline
              class="!min-h-11 !rounded-xl self-start"
              @click="copyEmail(row)"
            />
          </div>
        </li>
      </ul>

      <div class="hidden max-w-full overflow-x-auto md:block">
        <table class="w-full border-collapse text-sm" data-people-rows>
          <thead>
            <tr class="border-b border-n-weak text-xs text-n-slate-11">
              <th class="px-6 py-3 text-start font-medium">
                {{ t(`${NS}.PERSON`) }}
              </th>
              <th class="py-3 pe-4 text-start font-medium">
                {{ t(`${NS}.STATUS`) }}
              </th>
              <th class="py-3 pe-4 text-end font-medium">
                {{ t(`${NS}.OPENS`) }}
              </th>
              <th class="py-3 pe-4 text-end font-medium">
                {{ t(`${NS}.CLICKS`) }}
              </th>
              <th class="hidden py-3 pe-4 text-start font-medium lg:table-cell">
                {{ t(`${NS}.SENT_AT`) }}
              </th>
              <th class="py-3 pe-6 text-end font-medium">
                <span class="sr-only">{{ t(`${EMAIL_NS}.DETAILS`) }}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <template v-for="row in rows" :key="row.id">
              <tr
                class="border-b border-n-weak align-middle"
                :class="{ 'bg-n-alpha-1': openId === row.id }"
                :data-person="row.id"
              >
                <td class="max-w-72 px-6 py-3">
                  <p class="mb-0 truncate font-medium text-n-slate-12">
                    {{ row.name || row.email }}
                  </p>
                  <bdi
                    v-if="row.name"
                    dir="ltr"
                    class="block truncate text-xs text-n-slate-11"
                  >
                    {{ row.email }}
                  </bdi>
                </td>
                <td class="py-3 pe-4">
                  <span
                    class="inline-flex whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium"
                    :class="row.pill.className"
                    :title="row.pill.title"
                    data-person-pill
                  >
                    {{ row.pill.label }}
                  </span>
                </td>
                <td class="py-3 pe-4 text-end tabular-nums text-n-slate-12">
                  {{ number(row.opens) }}
                </td>
                <td class="py-3 pe-4 text-end tabular-nums text-n-slate-12">
                  {{ number(row.clicks) }}
                </td>
                <td
                  class="hidden whitespace-nowrap py-3 pe-4 text-n-slate-11 lg:table-cell"
                >
                  {{ row.sent_at ? date(row.sent_at) : t(`${NS}.NOT_SENT`) }}
                </td>
                <td class="py-2 pe-6 text-end">
                  <button
                    type="button"
                    class="inline-flex min-h-11 items-center gap-1 whitespace-nowrap rounded-xl px-2 font-medium text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                    :aria-expanded="openId === row.id"
                    :aria-controls="detailsId(row.id)"
                    :aria-label="t(`${NS}.DETAILS_ARIA`, { email: row.email })"
                    data-person-toggle
                    @click="toggle(row.id)"
                  >
                    {{ t(`${EMAIL_NS}.DETAILS`) }}
                    <span
                      :class="
                        openId === row.id
                          ? 'i-lucide-chevron-up'
                          : 'i-lucide-chevron-down'
                      "
                      class="size-4"
                      aria-hidden="true"
                    />
                  </button>
                </td>
              </tr>
              <tr
                v-if="openId === row.id"
                :id="detailsId(row.id)"
                class="border-b border-n-weak bg-n-alpha-1"
                data-person-details
              >
                <td colspan="6" class="px-6 pb-4 pt-1">
                  <div class="flex flex-wrap items-end justify-between gap-4">
                    <dl
                      class="m-0 grid min-w-0 flex-1 grid-cols-2 gap-x-6 gap-y-3 lg:grid-cols-3"
                    >
                      <div
                        v-for="pair in row.details"
                        :key="pair.key"
                        class="min-w-0"
                      >
                        <dt class="text-xs text-n-slate-11">
                          {{ pair.label }}
                        </dt>
                        <dd class="m-0 break-words text-n-slate-12">
                          {{ pair.value }}
                        </dd>
                      </div>
                    </dl>
                    <Button
                      :label="
                        t(
                          `${EMAIL_NS}.${copied === row.id ? 'COPIED' : 'COPY'}`
                        )
                      "
                      icon="i-lucide-copy"
                      slate
                      outline
                      class="!min-h-11 !rounded-xl"
                      @click="copyEmail(row)"
                    />
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </template>

    <footer
      v-if="!errorMessage && totalPages > 1"
      class="flex flex-wrap items-center justify-end gap-3 border-t border-n-weak px-4 py-3 text-sm text-n-slate-11 xl:px-6"
      data-people-pages
    >
      <span>
        {{
          t('RESULT_JOURNEY.PEOPLE.PAGE_OF', {
            page: number(meta.current_page || page),
            total: number(totalPages),
          })
        }}
      </span>
      <Button
        :label="t('RESULT_JOURNEY.PEOPLE.PREV')"
        slate
        outline
        class="!min-h-11"
        :disabled="isPending || page <= 1"
        @click="goToPage(page - 1)"
      />
      <Button
        :label="t('RESULT_JOURNEY.PEOPLE.NEXT')"
        slate
        outline
        class="!min-h-11"
        :disabled="isPending || page >= totalPages"
        @click="goToPage(page + 1)"
      />
    </footer>
  </section>
</template>
