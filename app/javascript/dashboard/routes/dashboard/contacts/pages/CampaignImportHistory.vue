<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignImportsAPI from 'dashboard/api/campaignImports';

const store = useStore();
const router = useRouter();
const canManage = useCanManage('campaign_manage');
const route = useRoute();
const { t } = useI18n();

const imports = useMapGetter('campaignImports/getCampaignImports');
const uiFlags = useMapGetter('campaignImports/getUIFlags');
const globalConfig = useMapGetter('globalConfig/get');
const isFetching = computed(() => uiFlags.value.isFetching);
const isDeleting = computed(() => uiFlags.value.isDeleting);

const deleteDialogRef = ref(null);
const undoDialogRef = ref(null);
const selectedImport = ref(null);
let refreshTimer = null;

const PROCESSING_STATUSES = [
  'uploaded',
  'validating',
  'confirmed',
  'queued',
  'importing',
  'undoing_labels',
];

const isProcessing = campaignImport =>
  PROCESSING_STATUSES.includes(campaignImport.status);

const hasProcessingImports = computed(() => imports.value.some(isProcessing));

const stopAutoRefresh = () => {
  if (!refreshTimer) return;

  window.clearInterval(refreshTimer);
  refreshTimer = null;
};

const fetchImports = async (options = {}) => {
  await store.dispatch('campaignImports/get', options);
  if (hasProcessingImports.value) {
    if (!refreshTimer) {
      refreshTimer = window.setInterval(
        () => fetchImports({ silent: true }),
        5000
      );
    }
    return;
  }

  stopAutoRefresh();
};

const backToContacts = () => {
  router.push({
    name: 'contacts_dashboard_index',
    params: { accountId: route.params.accountId },
  });
};

const refreshImports = () => fetchImports({ silent: true });

const confirmImport = async campaignImport => {
  try {
    await store.dispatch('campaignImports/confirm', campaignImport.id);
    await refreshImports();
    useAlert(t('CAMPAIGN_IMPORT.API.CONFIRM_SUCCESS'));
  } catch {
    useAlert(t('CAMPAIGN_IMPORT.API.CONFIRM_ERROR'));
  }
};

const requestUndoLabels = campaignImport => {
  selectedImport.value = campaignImport;
  undoDialogRef.value?.open();
};

const undoLabels = async () => {
  if (!selectedImport.value) return;

  try {
    await store.dispatch('campaignImports/undoLabels', selectedImport.value.id);
    await refreshImports();
    useAlert(t('CAMPAIGN_IMPORT.API.UNDO_SUCCESS'));
    undoDialogRef.value?.close();
  } catch {
    useAlert(t('CAMPAIGN_IMPORT.API.UNDO_ERROR'));
  }
};

const requestDelete = campaignImport => {
  selectedImport.value = campaignImport;
  deleteDialogRef.value?.open();
};

const deleteImport = async () => {
  if (!selectedImport.value) return;

  try {
    await store.dispatch('campaignImports/delete', selectedImport.value.id);
    useAlert(t('CAMPAIGN_IMPORT.API.DELETE_SUCCESS'));
    deleteDialogRef.value?.close();
  } catch {
    useAlert(t('CAMPAIGN_IMPORT.API.DELETE_ERROR'));
  }
};

const downloadFileName = (campaignImport, file) => {
  const baseName =
    campaignImport.campaign_slug ||
    campaignImport.campaign_name ||
    campaignImport.source_filename ||
    `campaign_import_${campaignImport.id}`;
  return `${baseName}_${file}.csv`;
};

const downloadFile = async (campaignImport, file) => {
  try {
    const response = await CampaignImportsAPI.download(campaignImport.id, file);
    const url = URL.createObjectURL(response.data);
    const link = document.createElement('a');
    link.href = url;
    link.download = downloadFileName(campaignImport, file);
    document.body.appendChild(link);
    link.click();
    window.setTimeout(() => {
      URL.revokeObjectURL(url);
      link.remove();
    }, 1000);
  } catch {
    useAlert(t('CAMPAIGN_IMPORT.API.DOWNLOAD_ERROR'));
  }
};

const canConfirm = campaignImport =>
  campaignImport.status === 'ready_to_confirm';

const canUndo = campaignImport =>
  ['completed', 'completed_with_failures'].includes(campaignImport.status);

const canDelete = campaignImport => campaignImport.can_delete === true;

const statusTone = campaignImport => {
  if (
    ['completed', 'completed_with_failures', 'labels_undone'].includes(
      campaignImport.status
    )
  ) {
    return 'text-n-teal-11';
  }

  if (
    ['validation_failed', 'failed', 'undo_failed'].includes(
      campaignImport.status
    )
  ) {
    return 'text-n-ruby-11';
  }

  if (isProcessing(campaignImport)) return 'text-n-blue-11';

  return 'text-n-slate-11';
};

const statusLabel = campaignImport => {
  switch (campaignImport.status) {
    case 'uploaded':
      return t('CAMPAIGN_IMPORT.STATUS.UPLOADED');
    case 'validating':
      return t('CAMPAIGN_IMPORT.STATUS.VALIDATING');
    case 'validation_failed':
      return t('CAMPAIGN_IMPORT.STATUS.VALIDATION_FAILED');
    case 'ready_to_confirm':
      return t('CAMPAIGN_IMPORT.STATUS.READY_TO_CONFIRM');
    case 'confirmed':
      return t('CAMPAIGN_IMPORT.STATUS.CONFIRMED');
    case 'queued':
      return t('CAMPAIGN_IMPORT.STATUS.QUEUED');
    case 'importing':
      return t('CAMPAIGN_IMPORT.STATUS.IMPORTING');
    case 'completed':
      return t('CAMPAIGN_IMPORT.STATUS.COMPLETED');
    case 'completed_with_failures':
      return t('CAMPAIGN_IMPORT.STATUS.COMPLETED_WITH_FAILURES');
    case 'cancelled':
      return t('CAMPAIGN_IMPORT.STATUS.CANCELLED');
    case 'expired':
      return t('CAMPAIGN_IMPORT.STATUS.EXPIRED');
    case 'undoing_labels':
      return t('CAMPAIGN_IMPORT.STATUS.UNDOING_LABELS');
    case 'labels_undone':
      return t('CAMPAIGN_IMPORT.STATUS.LABELS_UNDONE');
    case 'undo_failed':
      return t('CAMPAIGN_IMPORT.STATUS.UNDO_FAILED');
    case 'failed':
    default:
      return t('CAMPAIGN_IMPORT.STATUS.FAILED');
  }
};

onMounted(() => {
  if (!globalConfig.value.campaignImportEnabled) {
    backToContacts();
    return;
  }

  fetchImports();
});

onBeforeUnmount(() => {
  stopAutoRefresh();
});
</script>

<template>
  <section
    class="flex flex-col w-full h-full min-w-0 overflow-auto bg-n-background"
  >
    <header
      class="sticky top-0 z-10 flex items-center justify-between w-full h-20 px-6 bg-n-background"
    >
      <div class="min-w-0">
        <h1 class="mb-1 text-xl font-medium truncate text-n-slate-12">
          {{ t('CAMPAIGN_IMPORT.HISTORY.TITLE') }}
        </h1>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('CAMPAIGN_IMPORT.HISTORY.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <Button
          icon="i-lucide-refresh-cw"
          color="slate"
          variant="ghost"
          size="sm"
          @click="fetchImports"
        />
        <Button
          :label="t('CAMPAIGN_IMPORT.ACTIONS.BACK_TO_CONTACTS')"
          icon="i-lucide-arrow-left"
          color="slate"
          variant="faded"
          size="sm"
          @click="backToContacts"
        />
      </div>
    </header>

    <main class="w-full min-w-0 px-6 pb-8">
      <div
        class="grid gap-3 p-4 mb-4 border rounded-lg border-n-weak md:grid-cols-3"
      >
        <div>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN_IMPORT.HISTORY.GUIDE.VALIDATE.TITLE') }}
          </p>
          <p class="mb-0 text-xs leading-5 text-n-slate-11">
            {{ t('CAMPAIGN_IMPORT.HISTORY.GUIDE.VALIDATE.BODY') }}
          </p>
        </div>
        <div>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN_IMPORT.HISTORY.GUIDE.CONFIRM.TITLE') }}
          </p>
          <p class="mb-0 text-xs leading-5 text-n-slate-11">
            {{ t('CAMPAIGN_IMPORT.HISTORY.GUIDE.CONFIRM.BODY') }}
          </p>
        </div>
        <div>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN_IMPORT.HISTORY.GUIDE.UNDO.TITLE') }}
          </p>
          <p class="mb-0 text-xs leading-5 text-n-slate-11">
            {{ t('CAMPAIGN_IMPORT.HISTORY.GUIDE.UNDO.BODY') }}
          </p>
        </div>
      </div>

      <div
        v-if="isFetching"
        class="flex items-center justify-center py-16 text-n-slate-11"
      >
        <Spinner />
      </div>

      <div v-else-if="!imports.length" class="py-16 text-center">
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('CAMPAIGN_IMPORT.HISTORY.EMPTY') }}
        </p>
      </div>

      <div
        v-else
        class="w-full min-w-0 overflow-hidden border rounded-lg border-n-weak"
      >
        <table class="w-full text-sm text-left border-collapse table-fixed">
          <colgroup>
            <col class="w-[17%]" />
            <col class="w-[14%]" />
            <col class="w-[9%]" />
            <col class="w-[24%]" />
            <col class="w-[12%]" />
            <col class="w-[24%]" />
          </colgroup>
          <thead class="bg-n-alpha-2 text-n-slate-11">
            <tr>
              <th class="px-4 py-3 font-medium">
                {{ t('CAMPAIGN_IMPORT.HISTORY.COLUMNS.NAME') }}
              </th>
              <th class="px-4 py-3 font-medium whitespace-nowrap">
                {{ t('CAMPAIGN_IMPORT.HISTORY.COLUMNS.STATUS') }}
              </th>
              <th class="px-4 py-3 font-medium whitespace-nowrap">
                {{ t('CAMPAIGN_IMPORT.HISTORY.COLUMNS.ROWS') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('CAMPAIGN_IMPORT.HISTORY.COLUMNS.LABELS') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('CAMPAIGN_IMPORT.HISTORY.COLUMNS.FILES') }}
              </th>
              <th class="px-4 py-3 font-medium text-right">
                {{ t('CAMPAIGN_IMPORT.HISTORY.COLUMNS.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="campaignImport in imports"
              :key="campaignImport.id"
              class="border-t border-n-weak"
            >
              <td class="min-w-0 px-4 py-4 align-top">
                <p class="mb-1 font-medium truncate text-n-slate-12">
                  {{
                    campaignImport.campaign_name ||
                    campaignImport.source_filename
                  }}
                </p>
                <p class="mb-0 text-xs truncate text-n-slate-11">
                  {{ campaignImport.source_filename }}
                </p>
              </td>
              <td class="min-w-0 px-4 py-4 align-top">
                <span
                  class="inline-flex items-center gap-1 h-6 px-2 py-0.5 text-xs font-medium rounded-md whitespace-nowrap bg-n-alpha-2"
                  :class="statusTone(campaignImport)"
                >
                  <span
                    v-if="isProcessing(campaignImport)"
                    class="i-lucide-loader-2 animate-spin"
                  />
                  {{ statusLabel(campaignImport) }}
                </span>
              </td>
              <td class="min-w-0 px-4 py-4 align-top text-n-slate-12">
                <p class="mb-1 whitespace-nowrap">
                  {{ campaignImport.valid_rows
                  }}{{ t('CAMPAIGN_IMPORT.HISTORY.ROWS_SEPARATOR')
                  }}{{ campaignImport.total_rows }}
                </p>
                <p
                  v-if="campaignImport.invalid_rows"
                  class="mb-0 text-xs text-n-ruby-11"
                >
                  {{
                    t('CAMPAIGN_IMPORT.HISTORY.INVALID_ROWS', {
                      count: campaignImport.invalid_rows,
                    })
                  }}
                </p>
              </td>
              <td class="min-w-0 px-4 py-4 align-top text-n-slate-12">
                <p class="mb-1 truncate">
                  {{ campaignImport.base_label || '-' }}
                </p>
                <p class="mb-0 text-xs text-n-slate-11">
                  {{ campaignImport.batch_count }}
                  {{ t('CAMPAIGN_IMPORT.HISTORY.BATCHES') }}
                </p>
              </td>
              <td class="min-w-0 px-2 py-4 align-top">
                <div v-if="canManage" class="flex flex-col items-start gap-1">
                  <Button
                    v-if="campaignImport.downloads?.error_csv"
                    :label="t('CAMPAIGN_IMPORT.DOWNLOADS.ERRORS')"
                    icon="i-lucide-download"
                    color="slate"
                    variant="ghost"
                    size="sm"
                    class="!w-fit max-w-full"
                    @click="downloadFile(campaignImport, 'error_csv')"
                  />
                  <Button
                    v-if="campaignImport.downloads?.normalized_csv"
                    :label="t('CAMPAIGN_IMPORT.DOWNLOADS.NORMALIZED')"
                    icon="i-lucide-download"
                    color="slate"
                    variant="ghost"
                    size="sm"
                    class="!w-fit max-w-full"
                    @click="downloadFile(campaignImport, 'normalized_csv')"
                  />
                  <Button
                    v-if="campaignImport.downloads?.report_csv"
                    :label="t('CAMPAIGN_IMPORT.DOWNLOADS.REPORT')"
                    icon="i-lucide-download"
                    color="slate"
                    variant="ghost"
                    size="sm"
                    class="!w-fit max-w-full"
                    @click="downloadFile(campaignImport, 'report_csv')"
                  />
                </div>
              </td>
              <td class="min-w-0 px-4 py-4 align-top text-right">
                <div v-if="canManage" class="flex justify-end w-full gap-2">
                  <Button
                    v-if="canConfirm(campaignImport)"
                    :label="t('CAMPAIGN_IMPORT.ACTIONS.CONFIRM')"
                    icon="i-lucide-check"
                    size="sm"
                    class="!w-fit"
                    @click="confirmImport(campaignImport)"
                  />
                  <Button
                    v-if="canUndo(campaignImport)"
                    :label="t('CAMPAIGN_IMPORT.ACTIONS.UNDO_LABELS')"
                    icon="i-lucide-rotate-ccw"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    class="!w-fit"
                    @click="requestUndoLabels(campaignImport)"
                  />
                  <Button
                    v-if="canDelete(campaignImport)"
                    icon="i-lucide-trash"
                    :title="t('CAMPAIGN_IMPORT.ACTIONS.DELETE')"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    @click="requestDelete(campaignImport)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </main>

    <Dialog
      ref="undoDialogRef"
      type="alert"
      :title="t('CAMPAIGN_IMPORT.UNDO_DIALOG.TITLE')"
      :description="t('CAMPAIGN_IMPORT.UNDO_DIALOG.DESCRIPTION')"
      :confirm-button-label="t('CAMPAIGN_IMPORT.UNDO_DIALOG.CONFIRM')"
      :is-loading="uiFlags.isUndoing"
      :disable-confirm-button="uiFlags.isUndoing"
      @confirm="undoLabels"
    />

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('CAMPAIGN_IMPORT.DELETE_DIALOG.TITLE')"
      :description="t('CAMPAIGN_IMPORT.DELETE_DIALOG.DESCRIPTION')"
      :confirm-button-label="t('CAMPAIGN_IMPORT.DELETE_DIALOG.CONFIRM')"
      :is-loading="isDeleting"
      :disable-confirm-button="isDeleting"
      @confirm="deleteImport"
    />
  </section>
</template>
