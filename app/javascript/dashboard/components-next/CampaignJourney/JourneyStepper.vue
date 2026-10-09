<script setup>
import JourneyStepBar from './JourneyStepBar.vue';

const props = defineProps({
  current: { type: Number, required: true },
  reachable: { type: Number, required: true },
});
const emit = defineEmits(['go']);
</script>

<template>
  <JourneyStepBar
    :current="props.current"
    :reachable="props.reachable"
    @go="emit('go', $event)"
  />
</template>
