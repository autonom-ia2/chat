<script setup>
import LabeledSwitch from 'dashboard/components-next/switch/LabeledSwitch.vue';

const props = defineProps({
  checked: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  label: { type: String, required: true },
  ariaLabel: { type: String, required: true },
});
const emit = defineEmits(['toggle']);
</script>

<template>
  <LabeledSwitch
    :checked="checked"
    :disabled="disabled"
    :label="label"
    :aria-label="ariaLabel"
    @toggle="emit('toggle', !props.checked)"
  />
</template>
