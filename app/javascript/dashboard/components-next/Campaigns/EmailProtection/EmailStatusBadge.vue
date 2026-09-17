<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { NS, statusKey, reasonKey } from './presentation';
const props = defineProps({
  record: { type: Object, required: true },
  campaign: Boolean,
});
const { t } = useI18n();
const key = computed(() => statusKey(props.record, props.campaign));
const warning = computed(() =>
  [
    'failed',
    'suppressed',
    'permanent',
    'nonexistent',
    'temporary',
    'bounce_unknown',
    'complained',
    'paused',
    'high_risk',
    'attention',
    'invalid',
    'review',
  ].includes(key.value)
);
const hint = computed(() =>
  t(
    `${NS}.REASON.${reasonKey(props.record.suppression_reason || props.record.reason_code || props.record.pause_reason || props.record.preflight_reason)}`
  )
);
</script>

<template>
  <span
    class="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-md"
    :class="
      warning ? 'bg-n-amber-3 text-n-amber-11' : 'bg-n-alpha-2 text-n-slate-12'
    "
    :title="hint"
    tabindex="0"
  >
    <span
      :class="warning ? 'i-lucide-triangle-alert' : 'i-lucide-info'"
      class="size-3 shrink-0"
      aria-hidden="true"
    />
    {{ t(`${NS}.STATUS.${key}`) }}
  </span>
</template>
