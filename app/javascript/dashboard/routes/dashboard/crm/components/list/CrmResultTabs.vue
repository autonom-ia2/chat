<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { outcomeLabels, outcomeStatuses } from '../../helpers/cardOutcome';

// List-only status tabs. `value` maps to the server `result` filter (card
// status open/won/lost), NOT the conversation status (open/pending/resolved).
// `archived` stays in the Filtros popover to keep this control to the three
// everyday outcomes.
const props = defineProps({
  modelValue: {
    type: String,
    default: 'open',
  },
  // Funil atual: decide os desfechos e os nomes deles (#1144).
  pipeline: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const tabs = computed(() => {
  const statuses = outcomeStatuses(props.pipeline);
  const labels = outcomeLabels(t, props.pipeline);
  return [
    { value: 'open', label: t('CRM_KANBAN.RESULT_FILTER.OPEN') },
    { value: statuses.success, label: labels.success },
    { value: statuses.failure, label: labels.failure },
  ];
});

// No fallback to 'open' here: when result is '' (Filtros "Todos" / a legacy
// saved view) or 'archived', no everyday-outcome tab should read as active.
const isActive = value => props.modelValue === value;
</script>

<template>
  <div
    class="inline-flex overflow-hidden rounded-lg border border-n-weak"
    role="group"
  >
    <button
      v-for="tab in tabs"
      :key="tab.value"
      type="button"
      :data-value="tab.value"
      class="px-3 py-1 text-xs font-medium transition-colors"
      :class="
        isActive(tab.value)
          ? 'bg-n-slate-3 text-n-slate-12'
          : 'text-n-slate-10 hover:bg-n-slate-2'
      "
      :aria-pressed="isActive(tab.value)"
      @click="emit('update:modelValue', tab.value)"
    >
      {{ tab.label }}
    </button>
  </div>
</template>
