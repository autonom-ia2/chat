<script setup>
import { nextTick, ref } from 'vue';

const props = defineProps({
  id: { type: String, required: true },
  tabs: { type: Array, required: true },
  initialActiveTab: { type: Number, default: 0 },
});
const emit = defineEmits(['tabChanged']);
const buttons = ref([]);

const moveFocus = async (event, index) => {
  const keys = ['ArrowLeft', 'ArrowRight', 'Home', 'End'];
  if (!keys.includes(event.key)) return;
  event.preventDefault();
  const isRtl = event.currentTarget.closest('[dir="rtl"]');
  const step = event.key === 'ArrowRight' ? 1 : -1;
  let target =
    (index + (isRtl ? -step : step) + props.tabs.length) % props.tabs.length;
  if (event.key === 'Home') target = 0;
  if (event.key === 'End') target = props.tabs.length - 1;
  emit('tabChanged', props.tabs[target]);
  await nextTick();
  buttons.value[target]?.focus();
};
</script>

<template>
  <div class="border-b border-n-weak px-4 py-5 sm:px-6 sm:py-6">
    <h2 class="m-0 mb-4 text-base font-semibold text-n-slate-12">
      {{ $t('RELATIONSHIPS.PANEL_TITLE') }}
    </h2>
    <div
      role="tablist"
      :aria-label="$t('RELATIONSHIPS.PANEL_TITLE')"
      class="flex flex-wrap gap-1 rounded-xl border border-n-weak bg-n-slate-3 p-1"
    >
      <button
        v-for="(tab, index) in tabs"
        :id="`${id}-${tab.value}`"
        :key="tab.value"
        :ref="el => (buttons[index] = el)"
        type="button"
        role="tab"
        :aria-selected="index === initialActiveTab"
        :aria-controls="`${id}-panel`"
        :tabindex="index === initialActiveTab ? 0 : -1"
        class="min-h-11 min-w-fit flex-1 basis-20 whitespace-nowrap rounded-lg border-0 px-3 text-xs font-medium transition-colors hover:bg-n-solid-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-9 motion-reduce:transition-none"
        :class="
          index === initialActiveTab
            ? 'bg-n-solid-2 text-n-blue-11 shadow-sm ring-1 ring-n-container'
            : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="emit('tabChanged', tab)"
        @keydown="moveFocus($event, index)"
      >
        {{ tab.label }}
      </button>
    </div>
  </div>
</template>
