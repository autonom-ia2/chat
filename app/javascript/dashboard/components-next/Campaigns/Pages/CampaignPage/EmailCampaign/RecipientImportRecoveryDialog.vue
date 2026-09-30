<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { recipientImportRecovery } from 'dashboard/helper/emailCampaignImportRecovery';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ campaign: { type: Object, required: true } });
const { t } = useI18n();
const store = useStore();
const dialogRef = ref(null);
const fileInput = ref(null);
const selectedFile = ref(null);
const submitting = ref(false);
const actionError = ref('');
const prefix = 'EMAIL_CAMPAIGN_IMPORT_RECOVERY';
const guidance = computed(() =>
  recipientImportRecovery(t, props.campaign.recipient_import?.error_code)
);
const canRetry = computed(
  () => props.campaign.recipient_import?.retryable && guidance.value.canRetry
);
const reset = () => {
  selectedFile.value = null;
  actionError.value = '';
};
const selectFile = event => {
  selectedFile.value = event.target.files?.[0] || null;
  actionError.value = '';
};
const submit = async (retry = false) => {
  if (submitting.value || (!retry && !selectedFile.value)) return;
  submitting.value = true;
  actionError.value = '';
  try {
    if (retry) {
      await store.dispatch('emailCampaigns/retryImport', props.campaign.id);
    } else {
      await store.dispatch('emailCampaigns/importRecipients', {
        id: props.campaign.id,
        file: selectedFile.value,
      });
    }
    dialogRef.value.close();
  } catch (error) {
    actionError.value = recipientImportRecovery(
      t,
      error.response?.data?.error
    ).reason;
  } finally {
    submitting.value = false;
  }
};
defineExpose({
  open: () => dialogRef.value.open(),
  close: () => dialogRef.value.close(),
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="xl"
    overflow-y-auto
    :title="t(`${prefix}.TITLE`)"
    :description="t(`${prefix}.PRESERVED`)"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="reset"
  >
    <div class="flex flex-col gap-4">
      <div class="p-4 rounded-xl bg-n-ruby-3 text-n-ruby-11">
        <h4 class="mb-2 text-sm font-medium">{{ t(`${prefix}.REASON`) }}</h4>
        <p class="mb-0 text-sm leading-6">{{ guidance.reason }}</p>
      </div>
      <div class="p-4 border rounded-xl border-n-weak bg-n-solid-2">
        <h4 class="mb-2 text-sm font-medium text-n-slate-12">
          {{ t(`${prefix}.CORRECTION`) }}
        </h4>
        <p class="mb-0 text-sm leading-6 text-n-slate-11">
          {{ guidance.correction }}
        </p>
      </div>
      <input
        ref="fileInput"
        type="file"
        accept=".csv,.xlsx"
        class="hidden"
        :disabled="submitting"
        :aria-label="t(`${prefix}.SELECT`)"
        @change="selectFile"
      />
      <Button
        type="button"
        color="slate"
        variant="outline"
        icon="i-lucide-file-up"
        :label="t(`${prefix}.SELECT`)"
        :disabled="submitting"
        @click="fileInput?.click()"
      />
      <p v-if="selectedFile" class="mb-0 text-sm break-all text-n-slate-12">
        {{ selectedFile.name }}
      </p>
      <p v-if="actionError" class="mb-0 text-sm text-n-ruby-11" role="alert">
        {{ actionError }}
      </p>
    </div>
    <template #footer>
      <div class="flex flex-wrap justify-end gap-3">
        <Button
          type="button"
          variant="ghost"
          color="slate"
          :label="t(`${prefix}.LATER`)"
          :disabled="submitting"
          @click="dialogRef.close()"
        />
        <Button
          v-if="canRetry"
          type="button"
          variant="outline"
          color="slate"
          :label="t(`${prefix}.RETRY`)"
          :disabled="submitting"
          @click="submit(true)"
        />
        <Button
          type="button"
          :label="t(`${prefix}.UPLOAD`)"
          :is-loading="submitting"
          :disabled="!selectedFile || submitting"
          @click="submit()"
        />
      </div>
    </template>
  </Dialog>
</template>
