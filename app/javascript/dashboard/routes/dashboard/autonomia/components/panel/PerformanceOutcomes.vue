<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// #284 — "Results by conversation": five clickable numbers. Each one emits its
// metric key so the host opens the matching conversation list.
const props = defineProps({
  outcomes: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const METRICS = [
  { key: 'handled', icon: 'i-lucide-messages-square' },
  { key: 'resolved_without_human', icon: 'i-lucide-check-circle-2' },
  { key: 'handed_off', icon: 'i-lucide-user-round' },
  { key: 'reopened', icon: 'i-lucide-rotate-ccw' },
  { key: 'wrong_replies', icon: 'i-lucide-thumbs-down' },
];

const tiles = computed(() =>
  METRICS.map(metric => ({
    ...metric,
    label: t(`AGENTS.PERFORMANCE.OUTCOMES.${metric.key.toUpperCase()}`),
    value: props.outcomes?.[metric.key] ?? 0,
  }))
);
</script>

<template>
  <div
    class="flex flex-col gap-3 px-4 py-4 border rounded-xl border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-col gap-0.5">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('AGENTS.PERFORMANCE.OUTCOMES.TITLE') }}
      </h3>
      <p class="text-xs text-n-slate-10">
        {{ t('AGENTS.PERFORMANCE.OUTCOMES.HINT') }}
      </p>
    </div>
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-5">
      <button
        v-for="tile in tiles"
        :key="tile.key"
        type="button"
        :data-metric="tile.key"
        class="flex flex-col items-start gap-1 px-3 py-3 text-left transition-colors border rounded-lg border-n-weak hover:border-n-strong hover:bg-n-alpha-1"
        @click="emit('select', tile.key)"
      >
        <Icon :icon="tile.icon" class="text-n-slate-11" />
        <span class="text-xl font-medium text-n-slate-12">
          {{ tile.value }}
        </span>
        <span class="text-xs text-n-slate-10">{{ tile.label }}</span>
      </button>
    </div>
  </div>
</template>
