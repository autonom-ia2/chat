<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { recipientImportError } from 'dashboard/helper/emailCampaignImport';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import RecipientImportRecoveryDialog from './RecipientImportRecoveryDialog.vue';
import {
  NS,
  formatNumber,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';

const props = defineProps({
  campaign: { type: Object, required: true },
  canRecover: Boolean,
  autoRecover: Boolean,
  compact: Boolean,
});
const { t, locale } = useI18n();
const currentImport = computed(() => props.campaign.recipient_import);
const recoveryDialog = ref(null);
const lastOpenedFailure = ref(null);
const recoveryAllowed = computed(
  () => props.canRecover && props.campaign.status === 'draft'
);
watch(
  () => [
    currentImport.value?.id,
    currentImport.value?.status,
    recoveryAllowed.value,
  ],
  async ([id, status, allowed]) => {
    if (status !== 'failed') {
      lastOpenedFailure.value = null;
      recoveryDialog.value?.close();
      return;
    }
    if (!allowed || !props.autoRecover || lastOpenedFailure.value === id)
      return;
    lastOpenedFailure.value = id;
    await nextTick();
    recoveryDialog.value?.open();
  },
  { immediate: true }
);
const message = computed(() => {
  const value = currentImport.value;
  if (!value) return '';
  if (value.status === 'failed')
    return recipientImportError(t, value.error_code);
  return ['queued', 'processing', 'completed'].includes(value.status)
    ? t(`${NS}.IMPORT_${value.status.toUpperCase()}`)
    : t(`${NS}.STATUS.unknown`);
});
const result = computed(() => {
  const counts = currentImport.value?.result;
  const keys = ['imported', 'duplicates', 'invalid', 'suppressed'];
  if (
    !counts ||
    !Number.isInteger(counts.total) ||
    !keys.every(key => Number.isInteger(counts[key]) && counts[key] >= 0) ||
    keys.reduce((sum, key) => sum + counts[key], 0) !== counts.total
  )
    return null;
  return Object.fromEntries(
    [...keys, 'total'].map(key => [
      key,
      formatNumber(counts[key], locale.value),
    ])
  );
});
defineExpose({ openRecovery: () => recoveryDialog.value?.open() });
</script>

<template>
  <div class="contents">
    <div
      v-if="currentImport && !compact"
      class="text-sm"
      role="status"
      aria-live="polite"
    >
      <h3 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.IMPORT_ORIGINAL`) }}
      </h3>
      <p
        class="mb-0"
        :class="
          currentImport.status === 'failed'
            ? 'text-n-ruby-11'
            : 'text-n-slate-11'
        "
      >
        {{ message }}
      </p>
      <p
        v-if="currentImport.status === 'completed' && result"
        class="mb-0 text-xs text-n-slate-11"
      >
        {{ t(`${NS}.IMPORT_SUMMARY`, result) }}
      </p>
      <Button
        v-if="recoveryAllowed && currentImport.status === 'failed'"
        class="mt-2"
        size="sm"
        icon="i-lucide-file-pen-line"
        :label="t('EMAIL_CAMPAIGN_IMPORT_RECOVERY.OPEN')"
        @click="recoveryDialog.open()"
      />
    </div>
    <RecipientImportRecoveryDialog
      v-if="recoveryAllowed"
      ref="recoveryDialog"
      :campaign="campaign"
    />
  </div>
</template>
