<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import ReportsAPI from 'dashboard/api/emailCampaignReports';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import EmailStatusBadge from './EmailStatusBadge.vue';
import {
  NS,
  safeError,
  reasonKey,
  downloadCsv,
  formatNumber,
} from './presentation';
const props = defineProps({
  campaignId: { type: [String, Number], required: true },
});
const { t, locale } = useI18n();
const canManage = useCanManage('campaign_manage');
const { run, isPending } = useAbortableRequest();
const issues = ref([]);
const page = ref(1);
const meta = ref({});
const errorMessage = ref('');
const exporting = ref(false);
const fetchIssues = async () => {
  errorMessage.value = '';
  try {
    const response = await run(signal =>
      ReportsAPI.getImportIssues(props.campaignId, { page: page.value, signal })
    );
    if (!response) return;
    issues.value = response.data.payload.issues;
    meta.value = response.data.payload.meta;
  } catch (error) {
    errorMessage.value = safeError(t, error);
  }
};
watch(
  () => props.campaignId,
  () => {
    page.value = 1;
    fetchIssues();
  },
  { immediate: true }
);
const go = value => {
  page.value = value;
  fetchIssues();
};
const download = async () => {
  if (exporting.value) return;
  exporting.value = true;
  errorMessage.value = '';
  try {
    const { data } = await ReportsAPI.exportImportIssues(props.campaignId);
    downloadCsv(data, `email-campaign-${props.campaignId}-import-issues.csv`);
  } catch (error) {
    errorMessage.value = safeError(t, error);
  } finally {
    exporting.value = false;
  }
};
</script>

<template>
  <section
    class="flex flex-col min-w-0 gap-3 p-4 border rounded-lg border-n-weak"
  >
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t(`${NS}.ISSUES`) }}
    </h3>
    <div class="flex flex-wrap gap-2">
      <Button
        v-if="canManage"
        :label="t(`${NS}.DOWNLOAD_ISSUES`)"
        icon="i-lucide-download"
        sm
        outline
        :is-loading="exporting"
        :disabled="exporting"
        @click="download"
      />
      <Button
        :label="t(`${NS}.REFRESH`)"
        sm
        outline
        :disabled="isPending"
        @click="fetchIssues"
      />
    </div>
    <p v-if="errorMessage" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ errorMessage }}
    </p>
    <p v-if="isPending" role="status" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.LOADING`) }}
    </p>
    <p
      v-else-if="!errorMessage && !issues.length"
      class="m-0 text-sm text-n-slate-11"
    >
      {{ t(`${NS}.EMPTY`) }}
    </p>
    <ul
      v-else
      class="flex flex-col gap-3 m-0 list-none text-sm text-n-slate-12"
    >
      <li
        v-for="issue in issues"
        :key="issue.id || issue.row_number"
        class="flex flex-wrap items-center gap-2"
      >
        <span>{{ formatNumber(issue.row_number, locale) }}</span>
        <span class="break-all">{{ issue.email }}</span>
        <EmailStatusBadge
          :record="{
            status: issue.classification,
            reason_code: issue.reason_code,
          }"
        />
        <span>{{ t(`${NS}.REASON.${reasonKey(issue.reason_code)}`) }}</span>
        <span v-if="issue.suggestion" class="break-all">{{
          issue.suggestion
        }}</span>
      </li>
    </ul>
    <div v-if="meta.total_pages > 1" class="flex gap-2">
      <Button
        :label="t('CAMPAIGN_MANAGEMENT.RECIPIENTS.PREV')"
        sm
        outline
        :disabled="isPending || page <= 1"
        @click="go(page - 1)"
      />
      <Button
        :label="t('CAMPAIGN_MANAGEMENT.RECIPIENTS.NEXT')"
        sm
        outline
        :disabled="isPending || page >= meta.total_pages"
        @click="go(page + 1)"
      />
    </div>
  </section>
</template>
