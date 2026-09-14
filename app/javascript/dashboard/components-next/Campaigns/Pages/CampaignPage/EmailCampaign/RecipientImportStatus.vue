<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { recipientImportError } from 'dashboard/helper/emailCampaignImport';

const props = defineProps({ campaign: { type: Object, required: true } });
const { t } = useI18n();
const currentImport = computed(() => props.campaign.recipient_import);
const message = computed(() => {
  const value = currentImport.value;
  if (!value) return '';
  if (value.status === 'failed')
    return recipientImportError(t, value.error_code);
  return t(`CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.${value.status.toUpperCase()}`);
});
</script>

<template>
  <div v-if="currentImport" class="text-sm" role="status" aria-live="polite">
    <p
      class="mb-0"
      :class="
        currentImport.status === 'failed' ? 'text-n-ruby-11' : 'text-n-slate-11'
      "
    >
      {{ message }}
    </p>
    <p
      v-if="currentImport.status === 'completed'"
      class="mb-0 text-xs text-n-slate-11"
    >
      {{ t('CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.SUMMARY', currentImport.result) }}
    </p>
  </div>
</template>
