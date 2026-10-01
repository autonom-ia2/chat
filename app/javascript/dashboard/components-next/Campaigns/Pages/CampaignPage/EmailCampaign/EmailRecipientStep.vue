<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { isRecipientImportActive } from 'dashboard/helper/emailCampaignImport';

const props = defineProps({ campaign: { type: Object, default: null } });
defineEmits(['click']);
const { t } = useI18n();
const UX = 'CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE';
const stepNumber = 2;
const active = computed(() => isRecipientImportActive(props.campaign));
const checks = computed(() => props.campaign?.send_readiness?.checks);
const needsAttention = computed(
  () =>
    props.campaign?.recipient_import?.status === 'failed' ||
    (!active.value &&
      (checks.value?.recipients === false || checks.value?.hygiene === false))
);
const ready = computed(
  () =>
    !needsAttention.value &&
    !active.value &&
    checks.value?.recipients === true &&
    checks.value?.hygiene === true &&
    checks.value?.import === true
);
const stepLabel = computed(() =>
  needsAttention.value || ready.value || active.value
    ? t(`${UX}.RECIPIENTS_STEP`, { step: stepNumber })
    : t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.RECIPIENTS')
);
const statusLabel = computed(() => {
  if (needsAttention.value) return t(`${UX}.RECIPIENTS_ATTENTION`);
  if (active.value) return t(`${UX}.IMPORT_ACTIVE`);
  if (ready.value) return t(`${UX}.RECIPIENTS_READY`);
  return t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.RECIPIENTS');
});
</script>

<template>
  <button
    type="button"
    class="flex min-h-11 shrink-0 items-center gap-2 whitespace-nowrap rounded-xl border px-3 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
    :class="
      needsAttention
        ? 'border-n-amber-7 border-s-[0.1875rem] bg-n-amber-2 text-n-amber-12 hover:bg-n-amber-3'
        : 'border-transparent text-n-slate-11 hover:bg-n-alpha-1'
    "
    :aria-label="statusLabel"
    :title="statusLabel"
    @click="$emit('click')"
  >
    <span
      class="flex size-6 shrink-0 items-center justify-center rounded-full"
      :class="[
        needsAttention && 'bg-n-amber-11 text-n-solid-1',
        ready && 'bg-n-teal-3 text-n-teal-11',
        !needsAttention && !ready && 'bg-n-alpha-2',
      ]"
      aria-hidden="true"
    >
      <span v-if="needsAttention" class="i-lucide-triangle-alert size-4" />
      <span
        v-else-if="active"
        class="i-lucide-loader-circle size-4 animate-spin"
      />
      <span v-else-if="ready" class="i-lucide-check size-4" />
      <template v-else>{{ stepNumber }}</template>
    </span>
    <span>{{ stepLabel }}</span>
    <span
      v-if="needsAttention"
      class="i-lucide-chevron-right size-3.5"
      aria-hidden="true"
    />
  </button>
</template>
