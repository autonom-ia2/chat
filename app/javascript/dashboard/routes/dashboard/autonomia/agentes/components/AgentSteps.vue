<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import StepsBar from 'dashboard/components-next/stepper/StepsBar.vue';

defineProps({
  current: { type: Number, required: true },
  reachable: { type: Number, required: true },
});
const emit = defineEmits(['go']);
const { t } = useI18n();
const steps = computed(() =>
  ['choice', 'tell', 'test', 'live'].map(key => ({
    key,
    label: t(`AGENTS.V2.steps.${key}`),
  }))
);
</script>

<template>
  <StepsBar
    class="[&_button[aria-current='step']]:!text-n-blue-12"
    :steps="steps"
    :current="current"
    :reachable="reachable"
    :aria-label="t('AGENTS.V2.steps.label')"
    :step-aria="
      (step, number) =>
        t('AGENTS.V2.steps.stepLabel', { number, label: step.label })
    "
    @go="emit('go', $event)"
  />
</template>
