<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  NS,
  formatNumber,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';

const props = defineProps({ campaign: { type: Object, required: true } });
const { t, locale } = useI18n();
const currentImport = computed(() => props.campaign.recipient_import);
const message = computed(() => {
  const value = currentImport.value;
  if (!value) return '';
  if (value.status === 'failed') return t(`${NS}.ERROR`);
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
</script>

<template>
  <div class="contents">
    <div v-if="currentImport" class="text-sm" role="status" aria-live="polite">
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
    </div>
  </div>
</template>
