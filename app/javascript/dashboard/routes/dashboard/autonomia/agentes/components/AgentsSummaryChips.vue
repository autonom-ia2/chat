<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  agents: { type: Array, default: () => [] },
});

const { t } = useI18n();
const PENDING_CODES = new Set(['E1', 'E2', 'E2m', 'E3', 'E4']);

const count = codes =>
  props.agents.filter(agent => codes.has(agent.state?.code)).length;

const activeCount = computed(() => count(new Set(['E5'])));
const pausedCount = computed(() => count(new Set(['E6'])));
const pendingCount = computed(() => count(PENDING_CODES));
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-2"
    :aria-label="t('AGENTS.V2.summary.label')"
    data-summary-chips
  >
    <span
      class="inline-flex min-h-11 items-center gap-2 rounded-xl border border-n-teal-5 bg-n-teal-2 px-4 text-sm font-medium text-n-teal-12"
    >
      <span class="size-2 rounded-full bg-n-teal-9" aria-hidden="true" />
      {{ t('AGENTS.V2.summary.active', { count: activeCount }) }}
    </span>
    <span
      class="inline-flex min-h-11 items-center gap-2 rounded-xl border border-n-slate-5 bg-n-slate-2 px-4 text-sm font-medium text-n-slate-12"
    >
      <span class="size-2 rounded-full bg-n-slate-9" aria-hidden="true" />
      {{ t('AGENTS.V2.summary.paused', { count: pausedCount }) }}
    </span>
    <span
      v-if="pendingCount"
      class="inline-flex min-h-11 items-center gap-2 rounded-xl border border-n-amber-5 bg-n-amber-2 px-4 text-sm font-medium text-n-amber-12"
    >
      <span class="size-2 rounded-full bg-n-amber-9" aria-hidden="true" />
      {{ t('AGENTS.V2.summary.toFinish', { count: pendingCount }) }}
    </span>
  </div>
</template>
