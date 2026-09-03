<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import MessageReportsAPI from 'dashboard/api/autonomia/messageReports';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

// #284 — "wrong reply" feedback on a message posted by an Autonomia agent. Same
// reason codes as Captain::MessageReport (the model is reused server-side).
const props = defineProps({
  messageId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const dialogRef = ref(null);
const isLoading = ref(false);

const REPORT_REASONS = [
  'incorrect_information',
  'inappropriate_response',
  'incomplete_response',
  'outdated_information',
  'other',
];

const reasonOptions = computed(() =>
  REPORT_REASONS.map(value => ({
    value,
    label: t(`AGENTS.FEEDBACK.REASONS.${value}`),
  }))
);

const form = reactive({ reportReason: '', description: '' });

const isFormInvalid = computed(() => !form.reportReason);

const resetForm = () => {
  form.reportReason = '';
  form.description = '';
};

const open = () => {
  resetForm();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const handleConfirm = async () => {
  if (isFormInvalid.value) return;

  isLoading.value = true;
  try {
    await MessageReportsAPI.create({
      message_id: props.messageId,
      report_reason: form.reportReason,
      description: form.description.trim() || null,
    });
    useAlert(t('AGENTS.FEEDBACK.SUCCESS'));
    close();
  } catch (error) {
    useAlert(t('AGENTS.FEEDBACK.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AGENTS.FEEDBACK.TITLE')"
    :description="t('AGENTS.FEEDBACK.DESCRIPTION')"
    :confirm-button-label="t('AGENTS.FEEDBACK.SUBMIT')"
    :is-loading="isLoading"
    :disable-confirm-button="isFormInvalid"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('AGENTS.FEEDBACK.PROBLEM_TYPE') }}
        </label>
        <Select
          v-model="form.reportReason"
          class="!w-full [&>select]:w-full"
          :options="reasonOptions"
          :placeholder="t('AGENTS.FEEDBACK.PROBLEM_TYPE_PLACEHOLDER')"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('AGENTS.FEEDBACK.DESCRIPTION_LABEL') }}
        </label>
        <TextArea
          v-model="form.description"
          class="w-full"
          :placeholder="t('AGENTS.FEEDBACK.DESCRIPTION_PLACEHOLDER')"
          :max-length="500"
          show-character-count
          auto-height
        />
      </div>
    </div>
  </Dialog>
</template>
