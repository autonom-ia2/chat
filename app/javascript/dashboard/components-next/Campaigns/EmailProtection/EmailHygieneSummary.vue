<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import EmailStatusBadge from './EmailStatusBadge.vue';
import { NS, formatNumber } from './presentation';
import {
  hygieneState,
  isReconciled,
  visibleClassifications as visibleOf,
} from './hygieneCounts';
const props = defineProps({
  preflight: { type: Object, default: null },
  busy: Boolean,
});
const emit = defineEmits(['recheck', 'issues']);
const { t, locale } = useI18n();
const canManage = useCanManage('campaign_manage');
const visibleClassifications = computed(() => visibleOf(props.preflight));
const reconciled = computed(() => isReconciled(props.preflight));
const state = computed(() => hygieneState(props.preflight));
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
