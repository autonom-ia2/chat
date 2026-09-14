<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRecipientImportPolling } from 'dashboard/composables/useRecipientImportPolling';
import {
  isRecipientImportActive,
  recipientImportError,
} from 'dashboard/helper/emailCampaignImport';
import RecipientImportStatus from './RecipientImportStatus.vue';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PlaceholderChips from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/PlaceholderChips.vue';

const props = defineProps({
  campaign: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const recipients = useMapGetter('emailCampaigns/getRecipients');

const uiFlags = useMapGetter('emailCampaigns/getUIFlags');
const campaigns = useMapGetter('emailCampaigns/getCampaigns');

const fileInput = ref(null);
const showSchedule = ref(false);
const schedule = reactive({ at: '', error: false });
const placeholders = ref([]);
const validation = ref(null);

const mustache = key => `{{ ${key} }}`;

const blankEntries = computed(() =>
  Object.entries(validation.value?.blank_counts || {})
);
const hasValidationIssues = computed(
  () =>
    (validation.value?.missing || []).length > 0 ||
    blankEntries.value.length > 0
);

const fetchTemplateTools = async () => {
  try {
    const [placeholdersData, validationData] = await Promise.all([
      store.dispatch('emailCampaigns/fetchPlaceholders', props.campaign.id),
      store.dispatch('emailCampaigns/validateTemplate', props.campaign.id),
    ]);
    placeholders.value = placeholdersData.placeholders;
    validation.value = validationData;
  } catch (error) {
    placeholders.value = [];
    validation.value = null;
  }
};

const liveCampaign = computed(
  () =>
    (campaigns.value || []).find(item => item.id === props.campaign.id) ||
    props.campaign
);
useRecipientImportPolling(liveCampaign);
const isDraft = computed(() => liveCampaign.value.status === 'draft');
const hasCampaignBody = computed(() => Boolean(liveCampaign.value.body_html));
const importResult = computed(() =>
  liveCampaign.value.recipient_import?.status === 'completed'
    ? liveCampaign.value.recipient_import.result
    : null
);
const isImporting = computed(
  () => uiFlags.value.isImporting || isRecipientImportActive(liveCampaign.value)
);
const isRetrying = ref(false);
const retryImport = async () => {
  isRetrying.value = true;
  try {
    await store.dispatch('emailCampaigns/retryImport', props.campaign.id);
  } catch (error) {
    useAlert(recipientImportError(t, error.response?.data?.error));
  } finally {
    isRetrying.value = false;
  }
};
watch(
  [
    () => liveCampaign.value.recipient_import?.id,
    () => liveCampaign.value.recipient_import?.status,
  ],
  ([, status]) => {
    if (status === 'completed') {
      store.dispatch('emailCampaigns/getRecipients', { id: props.campaign.id });
      fetchTemplateTools();
    }
  }
);
const isFetching = computed(() => uiFlags.value.isFetching);

const statusLabel = status => {
  switch (status) {
    case 'pending':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.STATUS.PENDING');
    case 'sent':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.STATUS.SENT');
    case 'failed':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.STATUS.FAILED');
    case 'suppressed':
      return t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.STATUS.SUPPRESSED');
    default:
      return status;
  }
};

const statusClass = status => {
  const map = {
    pending: 'text-n-slate-11 bg-n-alpha-2',
    sent: 'text-n-teal-11 bg-n-teal-3',
    failed: 'text-n-ruby-11 bg-n-ruby-3',
    suppressed: 'text-n-amber-11 bg-n-amber-3',
  };
  return map[status] || 'text-n-slate-11 bg-n-alpha-2';
};

const close = () => emit('close');

const pickFile = () => fileInput.value?.click();

const openBuilder = () => {
  router.push({
    name: 'campaigns_email_builder',
    params: {
      accountId: route.params.accountId,
      campaignId: liveCampaign.value.id,
    },
  });
  close();
};

const onFileChange = async event => {
  const file = event.target.files?.[0];
  if (!file) return;

  try {
    await store.dispatch('emailCampaigns/importRecipients', {
      id: props.campaign.id,
      file,
    });
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.QUEUED'));
  } catch (error) {
    useAlert(recipientImportError(t, error.response?.data?.error));
  } finally {
    event.target.value = '';
  }
};

const submitSchedule = async () => {
  if (isImporting.value) return;
  if (!hasCampaignBody.value) {
    openBuilder();
    return;
  }

  if (!schedule.at) {
    schedule.error = true;
    return;
  }
  try {
    await store.dispatch('emailCampaigns/schedule', {
      id: props.campaign.id,
      scheduledAt: schedule.at,
    });
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SCHEDULE_SUCCESS'));
    showSchedule.value = false;
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.ERROR'));
  }
};

onMounted(() => {
  store.dispatch('emailCampaigns/getRecipients', { id: props.campaign.id });
  fetchTemplateTools();
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
    @click.self="close"
  >
    <div
      class="flex max-h-[85vh] w-[min(48rem,calc(100vw-3rem))] min-w-0 flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 shadow-xl"
    >
      <div
        class="flex items-start justify-between gap-3 p-6 pb-4 border-b border-n-weak"
      >
        <div class="min-w-0">
          <h3 class="mb-1 text-base font-medium leading-6 text-n-slate-12">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.TITLE') }}
          </h3>
          <p class="max-w-xl mb-0 text-sm leading-5 text-n-slate-11">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.SUBTITLE') }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          color="slate"
          variant="ghost"
          size="sm"
          @click="close"
        />
      </div>

      <div class="flex flex-col gap-5 p-6 overflow-y-auto">
        <RecipientImportStatus :campaign="liveCampaign" />
        <Button
          v-if="isDraft && liveCampaign.recipient_import?.retryable"
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.RETRY')"
          :disabled="isRetrying || isImporting"
          :is-loading="isRetrying"
          @click="retryImport"
        />
        <div class="flex flex-wrap items-center gap-3">
          <input
            ref="fileInput"
            type="file"
            accept=".csv,.xlsx"
            class="hidden"
            @change="onFileChange"
          />
          <Button
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.ADD_MORE')"
            icon="i-lucide-user-plus"
            color="slate"
            variant="outline"
            size="sm"
            :is-loading="isImporting"
            :disabled="!isDraft || isImporting"
            @click="pickFile"
          />
          <span class="text-xs text-n-slate-11">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.ADD_MORE_HINT') }}
          </span>
          <Button
            v-if="isDraft && hasCampaignBody && !isImporting"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SCHEDULE')"
            icon="i-lucide-calendar-clock"
            color="slate"
            variant="ghost"
            size="sm"
            class="ltr:ml-auto rtl:mr-auto"
            @click="showSchedule = !showSchedule"
          />
          <Button
            v-else-if="isDraft"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.OPEN_BUILDER')"
            icon="i-lucide-layout-template"
            color="blue"
            variant="ghost"
            size="sm"
            class="ltr:ml-auto rtl:mr-auto"
            @click="openBuilder"
          />
        </div>

        <div
          v-if="showSchedule"
          class="flex flex-col gap-2 p-4 border rounded-lg border-n-weak"
        >
          <Input
            v-model="schedule.at"
            type="datetime-local"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.SCHEDULE_DIALOG.DATETIME_LABEL')"
            :message="
              schedule.error
                ? t('CAMPAIGN.EMAIL_CAMPAIGN.SCHEDULE_DIALOG.DATETIME_ERROR')
                : ''
            "
            :message-type="schedule.error ? 'error' : 'info'"
            @update:model-value="schedule.error = false"
          />
          <div class="flex justify-end gap-2 mt-1">
            <Button
              :label="t('CAMPAIGN.EMAIL_CAMPAIGN.SCHEDULE_DIALOG.CANCEL')"
              color="slate"
              variant="faded"
              size="sm"
              @click="showSchedule = false"
            />
            <Button
              :label="t('CAMPAIGN.EMAIL_CAMPAIGN.SCHEDULE_DIALOG.SUBMIT')"
              color="blue"
              size="sm"
              :is-loading="uiFlags.isUpdating"
              @click="submitSchedule"
            />
          </div>
        </div>

        <div
          v-if="importResult"
          class="flex flex-col gap-2 p-4 border rounded-lg border-n-weak"
        >
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.IMPORT_RESULT.TITLE') }}
          </p>
          <div class="flex flex-wrap gap-6 text-sm">
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{
                  t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.IMPORT_RESULT.IMPORTED')
                }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ importResult.imported }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{
                  t(
                    'CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.IMPORT_RESULT.DUPLICATES'
                  )
                }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ importResult.duplicates }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{
                  t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.IMPORT_RESULT.INVALID')
                }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ importResult.invalid }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{
                  t(
                    'CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.IMPORT_RESULT.SUPPRESSED'
                  )
                }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ importResult.suppressed }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{
                  t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.IMPORT_RESULT.TOTAL')
                }}
              </span>
              <span class="font-medium text-n-slate-12">
                {{ importResult.total }}
              </span>
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-2 p-4 border rounded-lg border-n-weak">
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.PLACEHOLDERS.TITLE') }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.PLACEHOLDERS.SUBTITLE') }}
          </p>
          <PlaceholderChips
            v-if="placeholders.length"
            :placeholders="placeholders"
          />
          <p v-else class="mb-0 text-xs text-n-slate-11">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.PLACEHOLDERS.EMPTY') }}
          </p>
        </div>

        <div
          v-if="validation"
          class="flex flex-col gap-2 p-4 border rounded-lg"
          :class="
            hasValidationIssues
              ? 'border-n-amber-5 bg-n-amber-1'
              : 'border-n-weak'
          "
        >
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.TITLE') }}
          </p>
          <template v-if="hasValidationIssues">
            <div
              v-if="validation.missing.length"
              class="flex flex-col gap-1 text-xs text-n-amber-11"
            >
              <span class="font-medium">
                {{ t('CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.MISSING_LABEL') }}
              </span>
              <span v-for="key in validation.missing" :key="key">
                {{ mustache(key) }}
              </span>
            </div>
            <div
              v-if="blankEntries.length"
              class="flex flex-col gap-1 text-xs text-n-amber-11"
            >
              <span class="font-medium">
                {{ t('CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.BLANK_LABEL') }}
              </span>
              <span v-for="[key, count] in blankEntries" :key="key">
                {{
                  t('CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.BLANK_ITEM', {
                    key,
                    count,
                  })
                }}
              </span>
            </div>
          </template>
          <p v-else class="mb-0 text-xs text-n-teal-11">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.OK') }}
          </p>
        </div>

        <div class="flex flex-wrap gap-6 text-sm">
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.RECIPIENTS') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ liveCampaign.recipients_count }}
            </span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.SENT') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ liveCampaign.sent_count }}
            </span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.FAILED') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ liveCampaign.failed_count }}
            </span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.SUPPRESSED') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ liveCampaign.suppressed_count }}
            </span>
          </div>
        </div>

        <div
          v-if="isFetching"
          class="flex items-center justify-center py-10 text-n-slate-11"
        >
          <Spinner />
        </div>

        <div
          v-else-if="recipients.length === 0"
          class="py-10 text-sm text-center text-n-slate-11"
        >
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.EMPTY') }}
        </div>

        <div v-else class="overflow-hidden border rounded-lg border-n-weak">
          <table class="w-full text-sm table-fixed">
            <thead class="bg-n-alpha-2 text-n-slate-11">
              <tr>
                <th class="w-[30%] px-4 py-3 font-medium text-left">
                  {{ t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.TABLE.EMAIL') }}
                </th>
                <th class="w-[20%] px-4 py-3 font-medium text-left">
                  {{ t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.TABLE.NAME') }}
                </th>
                <th class="w-[16%] px-4 py-3 font-medium text-left">
                  {{ t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.TABLE.STATUS') }}
                </th>
                <th class="w-[34%] px-4 py-3 font-medium text-left">
                  {{ t('CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.TABLE.ERROR') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="recipient in recipients"
                :key="recipient.id"
                class="align-top border-t border-n-weak"
              >
                <td class="px-4 py-3 break-all text-n-slate-12">
                  {{ recipient.email }}
                </td>
                <td class="px-4 py-3 break-all text-n-slate-12">
                  {{ recipient.name }}
                </td>
                <td class="px-4 py-3">
                  <span
                    class="inline-flex px-2 py-1 text-xs font-medium rounded-md"
                    :class="statusClass(recipient.status)"
                  >
                    {{ statusLabel(recipient.status) }}
                  </span>
                </td>
                <td class="px-4 py-3 break-all text-n-ruby-11">
                  {{ recipient.last_error }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>
