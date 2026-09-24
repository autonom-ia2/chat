<script setup>
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

defineProps({
  modelValue: { type: String, default: '' },
  options: { type: Array, default: () => [] },
  placeholder: { type: String, default: '' },
  ariaLabel: { type: String, required: true },
  hasError: { type: Boolean, default: false },
});

defineEmits(['update:modelValue']);
</script>

<template>
  <div class="flex items-center justify-end">
    <ChoiceSelect
      :model-value="modelValue"
      :options="options"
      :placeholder="placeholder"
      :aria-label="ariaLabel"
      :invalid="hasError"
      compact
      class="w-full max-w-56"
      :class="{ 'animate-shake': hasError }"
      @update:model-value="value => $emit('update:modelValue', value)"
    />
  </div>
</template>
