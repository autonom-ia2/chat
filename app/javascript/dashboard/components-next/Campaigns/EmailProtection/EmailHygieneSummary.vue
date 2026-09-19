<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import EmailStatusBadge from './EmailStatusBadge.vue';
import { NS, formatNumber } from './presentation';
const props = defineProps({
  preflight: { type: Object, default: null },
  busy: Boolean,
});
const emit = defineEmits(['recheck', 'issues']);
const { t, locale } = useI18n();
const canManage = useCanManage('campaign_manage');
const classifications = [
  'ready',
  'protected',
  'invalid',
  'review',
  'unknown',
  'unchecked',
  'duplicate',
];
// Counts are mutually exclusive server classifications. Never infer zeros or
// subtract overlapping legacy import counters to manufacture readiness.
const suppliedClassifications = computed(() =>
  classifications.filter(key =>
    Object.hasOwn(props.preflight?.counts || {}, key)
  )
);
const visibleClassifications = computed(() =>
  suppliedClassifications.value.filter(
    key => (props.preflight?.counts?.[key] || 0) > 0
  )
);
const reconciled = computed(() => {
  const counts = props.preflight?.counts;
  return (
    counts &&
    Number.isInteger(counts.total) &&
    counts.total >= 0 &&
    suppliedClassifications.value.every(
      key => Number.isInteger(counts[key]) && counts[key] >= 0
    ) &&
    suppliedClassifications.value.reduce((sum, key) => sum + counts[key], 0) ===
      counts.total
  );
});
const state = computed(
  () =>
    ({
      processing: 'analysing',
      queued: 'analysing',
      analysing: 'analysing',
      completed: 'completed',
      ready: 'ready',
      blocked: 'protected',
      review: 'review',
    })[props.preflight?.status] || 'unknown'
);
</script>

<template>
  <section
    class="flex flex-col gap-3 p-4 border rounded-lg border-n-weak bg-n-solid-1"
    aria-live="polite"
  >
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t(`${NS}.HYGIENE`) }}
    </h3>
    <div><EmailStatusBadge :record="{ status: state }" /></div>
    <p class="m-0 text-xs text-n-slate-11">
      {{ t(`${NS}.${reconciled ? 'CLASSIFICATION' : 'PENDING_COUNTS'}`) }}
    </p>
    <dl v-if="reconciled" class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-4">
      <div v-for="key in ['total', ...visibleClassifications]" :key="key">
        <dt class="text-xs text-n-slate-11">{{ t(`${NS}.STATUS.${key}`) }}</dt>
        <dd class="m-0 text-sm font-medium text-n-slate-12">
          {{ formatNumber(preflight.counts[key], locale) }}
        </dd>
      </div>
    </dl>
    <div class="flex flex-wrap gap-2">
      <Button
        v-if="canManage && preflight?.can_recheck"
        :label="t(`${NS}.RECHECK`)"
        icon="i-lucide-refresh-cw"
        :disabled="busy"
        :is-loading="busy"
        sm
        outline
        @click="emit('recheck')"
      />
      <Button
        v-if="preflight?.issues_count > 0"
        :label="t(`${NS}.ISSUES`)"
        icon="i-lucide-list-filter"
        sm
        slate
        outline
        @click="emit('issues')"
      />
    </div>
  </section>
</template>
