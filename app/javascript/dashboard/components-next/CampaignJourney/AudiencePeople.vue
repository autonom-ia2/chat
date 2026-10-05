<script setup>
// People and rows with a problem (#993, PRD §6.6-3, B5): "98 prontos · 2 com problema",
// masked reason per row (problem_rows) or, without that endpoint, reasons with counts,
// and the download of the rows left out. Saving goes on with the ready ones.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { audiencesAPI } from 'dashboard/api/campaignJourney';
import {
  notReceiving,
  peopleSummary,
  reasonKey,
  reasonTally,
} from './audienceReview';

const props = defineProps({
  campaignImport: { type: Object, required: true },
});

const emit = defineEmits(['download']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.PEOPLE';
const { t, n } = useI18n();

const isOpen = ref(false);
const isLoading = ref(false);
const problemRows = ref(null);

const summary = computed(() => peopleSummary(props.campaignImport));
const tally = computed(() => reasonTally(props.campaignImport));
const blocked = computed(() => notReceiving(props.campaignImport.reachability));
const canDownload = computed(
  () => props.campaignImport.downloads?.error_csv === true
);

const reasonText = code =>
  t(`CAMPAIGN_JOURNEY.NEW_AUDIENCE.REASONS.${reasonKey(code)}`);

const loadProblems = async () => {
  isLoading.value = true;
  try {
    const { data } = await audiencesAPI.problemRows(props.campaignImport.id);
    problemRows.value = Array.isArray(data?.payload) ? data.payload : null;
  } catch {
    // Endpoint not there yet (api-993-frontend-needs.md §2): reasons with counts instead.
    problemRows.value = null;
  } finally {
    isLoading.value = false;
  }
};

const toggle = () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value && problemRows.value === null) loadProblems();
};

watch(
  [() => props.campaignImport.id, () => props.campaignImport.validated_at],
  () => {
    problemRows.value = null;
    if (isOpen.value) loadProblems();
  }
);
</script>

<template>
  <section class="flex flex-col gap-3" data-test="audience-people">
    <p
      class="m-0 text-base font-semibold text-n-slate-12"
      data-test="people-summary"
    >
      {{
        t(`${NS}.SUMMARY`, {
          ready: n(summary.ready),
          problems: n(summary.problems),
        })
      }}
    </p>
    <div class="grid gap-3 sm:grid-cols-3">
      <div class="rounded-2xl bg-n-teal-2 p-4">
        <p class="m-0 text-3xl font-semibold tabular-nums text-n-teal-11">
          {{ n(summary.ready) }}
        </p>
        <p class="m-0 text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.READY`) }}
        </p>
      </div>
      <button
        v-if="summary.problems"
        type="button"
        class="flex min-h-11 flex-col items-start rounded-2xl bg-n-amber-2 p-4 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :aria-expanded="isOpen"
        data-test="toggle-problems"
        @click="toggle"
      >
        <span class="text-3xl font-semibold tabular-nums text-n-amber-11">
          {{ n(summary.problems) }}
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.PROBLEMS`) }}
        </span>
        <span class="text-sm font-medium text-n-blue-11">
          {{ isOpen ? t(`${NS}.HIDE`) : t(`${NS}.SHOW`) }}
        </span>
      </button>
      <div
        v-if="blocked"
        class="flex flex-col rounded-2xl bg-n-alpha-2 p-4"
        data-test="not-receiving"
      >
        <span class="text-3xl font-semibold tabular-nums text-n-slate-12">
          {{ n(blocked.total) }}
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.NOT_RECEIVING`) }}
        </span>
        <span
          v-for="item in blocked.items"
          :key="item.key"
          class="text-xs text-n-slate-11"
        >
          {{ t(`${NS}.${item.key}`, { count: n(item.count) }) }}
        </span>
        <span v-if="!blocked.items.length" class="text-xs text-n-slate-11">
          {{ t(`${NS}.NOT_RECEIVING_HINT`) }}
        </span>
      </div>
    </div>
    <div
      v-if="isOpen"
      class="overflow-hidden rounded-2xl border border-n-amber-6"
      data-test="problems"
    >
      <div v-if="isLoading" class="flex justify-center p-6"><Spinner /></div>
      <table v-else-if="problemRows" class="w-full text-sm">
        <thead class="bg-n-alpha-1 text-start text-xs text-n-slate-11">
          <tr>
            <th class="px-4 py-2 text-start font-medium">
              {{ t(`${NS}.ROW`) }}
            </th>
            <th class="px-4 py-2 text-start font-medium">
              {{ t(`${NS}.CONTACT`) }}
            </th>
            <th class="px-4 py-2 text-start font-medium">
              {{ t(`${NS}.PROBLEM`) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in problemRows"
            :key="row.row_number"
            class="border-t border-n-weak"
            :data-problem-row="row.row_number"
          >
            <td class="px-4 py-2 tabular-nums">{{ row.row_number }}</td>
            <td class="px-4 py-2">
              {{ row.contact_masked || t(`${NS}.EMPTY_CONTACT`) }}
            </td>
            <td class="px-4 py-2">
              {{ (row.errors || []).map(reasonText).join(' · ') }}
            </td>
          </tr>
        </tbody>
      </table>
      <ul v-else class="m-0 list-none p-0" data-test="reason-tally">
        <li
          v-for="item in tally"
          :key="item.code"
          class="border-b border-n-weak px-4 py-2 text-sm last:border-0"
        >
          {{
            t(`${NS}.REASON_COUNT`, {
              reason: reasonText(item.code),
              count: n(item.count),
            })
          }}
        </li>
      </ul>
      <div
        class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak bg-n-amber-2 px-4 py-3"
      >
        <span class="text-xs text-n-slate-11">{{ t(`${NS}.LEFT_OUT`) }}</span>
        <Button
          v-if="canDownload"
          :label="t(`${NS}.DOWNLOAD`)"
          icon="i-lucide-download"
          variant="outline"
          color="slate"
          size="sm"
          class="!min-h-11"
          data-test="download-problems"
          @click="emit('download')"
        />
      </div>
    </div>
  </section>
</template>
