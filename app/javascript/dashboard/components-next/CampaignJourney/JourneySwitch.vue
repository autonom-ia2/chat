<script setup>
import LabeledSwitch from 'dashboard/components-next/switch/LabeledSwitch.vue';

const props = defineProps({
  checked: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  label: { type: String, required: true },
  ariaLabel: { type: String, default: '' },
});

const emit = defineEmits(['toggle']);

defineOptions({ inheritAttrs: false });
</script>

<template>
  <LabeledSwitch
    v-bind="$attrs"
    :checked="props.checked"
    :disabled="props.disabled"
    :label="props.label"
    :aria-label="props.ariaLabel"
    @toggle="emit('toggle')"
  />
</template>
