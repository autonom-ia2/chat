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

import EmailRecipients from 'dashboard/components-next/Campaigns/EmailProtection/EmailRecipients.vue';
import EmailCampaignHealth from 'dashboard/components-next/Campaigns/EmailProtection/EmailCampaignHealth.vue';
import {
  NS,
  formatNumber,
  safeError,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PlaceholderChips from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/PlaceholderChips.vue';

const props = defineProps({
  initialProblem: Boolean,
  campaign: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['close']);

const { t, locale } = useI18n();
const recipientsPanel = ref(null);
const refreshKey = ref(0);
const healthCampaign = ref(null);
const onHealthUpdated = campaign => {
  healthCampaign.value = campaign;
  refreshKey.value += 1;
};
const number = value => formatNumber(value, locale.value);
const store = useStore();
const route = useRoute();
const router = useRouter();

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
watch(liveCampaign, () => {
  healthCampaign.value = null;
});
useRecipientImportPolling(liveCampaign);
const isDraft = computed(() => liveCampaign.value.status === 'draft');
const hasCampaignBody = computed(() => Boolean(liveCampaign.value.body_html));
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
      refreshKey.value += 1;
      fetchTemplateTools();
    }
  }
);
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
    useAlert(safeError(t, error));
  }
};

onMounted(() => {
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
          :aria-label="t('CAMPAIGN.EMAIL_CAMPAIGN.SCHEDULE_DIALOG.CANCEL')"
          color="slate"
          variant="ghost"
          size="sm"
          @click="close"
        />
      </div>

      <div class="flex flex-col gap-5 p-6 overflow-y-auto">
        <RecipientImportStatus :campaign="liveCampaign" />
        <EmailCampaignHealth
          :campaign="healthCampaign || liveCampaign"
          @updated="onHealthUpdated"
          @problems="recipientsPanel?.showProblems()"
        />
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
            class="ms-auto"
            @click="showSchedule = !showSchedule"
          />
          <Button
            v-else-if="isDraft"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.OPEN_BUILDER')"
            icon="i-lucide-layout-template"
            color="blue"
            variant="ghost"
            size="sm"
            class="ms-auto"
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
              {{ number(liveCampaign.recipients_count) }}
            </span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.SENT') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ number(liveCampaign.sent_count) }}
            </span>
          </div>
          <div class="flex flex-col">
            <span class="text-xs text-n-slate-11">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.FAILED') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ number(liveCampaign.failed_count) }}
            </span>
          </div>
          <div
            v-if="liveCampaign.preflight?.counts?.invalid"
            class="flex flex-col"
          >
            <span class="text-xs text-n-slate-11">
              {{ t(`${NS}.STATUS.invalid`) }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ number(liveCampaign.preflight.counts.invalid) }}
            </span>
          </div>
          <div
            v-if="liveCampaign.preflight?.counts?.review"
            class="flex flex-col"
          >
            <span class="text-xs text-n-slate-11">
              {{ t(`${NS}.STATUS.review`) }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ number(liveCampaign.preflight.counts.review) }}
            </span>
          </div>
          <div
            v-if="liveCampaign.preflight?.counts?.protected"
            class="flex flex-col"
          >
            <span class="text-xs text-n-slate-11">
              {{ t(`${NS}.STATUS.protected`) }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ number(liveCampaign.preflight.counts.protected) }}
            </span>
          </div>
        </div>

        <EmailRecipients
          ref="recipientsPanel"
          :campaign-id="liveCampaign.id"
          :problem-only="initialProblem"
          :refresh-key="refreshKey"
        />
      </div>
    </div>
  </div>
</template>
