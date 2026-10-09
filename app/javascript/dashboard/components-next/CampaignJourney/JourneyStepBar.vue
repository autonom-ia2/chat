<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import StepsBar from 'dashboard/components-next/stepper/StepsBar.vue';

const props = defineProps({
  current: { type: Number, required: true },
  reachable: { type: Number, required: true },
});
const emit = defineEmits(['go']);

const { t } = useI18n();

const STEPS = ['AUDIENCE', 'MESSAGE', 'REVIEW'];

const steps = computed(() =>
  STEPS.map(key => ({
    key,
    label: t(`CAMPAIGN_JOURNEY.STEPPER.${key}`),
  }))
);

const stepAria = (step, number) =>
  t('CAMPAIGN_JOURNEY.STEPPER.STEP_ARIA', {
    n: number,
    label: step.label,
  });
</script>

<template>
  <StepsBar
    :steps="steps"
    :current="props.current"
    :reachable="props.reachable"
    :aria-label="t('CAMPAIGN_JOURNEY.STEPPER.LABEL')"
    :step-aria="stepAria"
    @go="emit('go', $event)"
  />
</template>
