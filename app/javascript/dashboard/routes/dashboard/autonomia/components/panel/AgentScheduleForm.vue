<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';

// #284 (Entrega 2a) — "Horário de atuação": always / business_hours / outside_business_hours.
// Emits the chosen window; the host saves it under config.response_window.
const props = defineProps({
  agent: { type: Object, default: () => ({}) },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

const RESPONSE_WINDOW = {
  ALWAYS: 'always',
  BUSINESS_HOURS: 'business_hours',
  OUTSIDE_BUSINESS_HOURS: 'outside_business_hours',
};

const OPTIONS = Object.values(RESPONSE_WINDOW);

const selected = ref(RESPONSE_WINDOW.ALWAYS);

const handleSubmit = () => {
  emit('submit', selected.value);
};

watch(
  () => props.agent,
  agent => {
    selected.value = agent?.config?.response_window || RESPONSE_WINDOW.ALWAYS;
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-col gap-3">
      <RadioCard
        v-for="option in OPTIONS"
        :id="option"
        :key="option"
        :label="t(`AGENTS.SCHEDULE.${option.toUpperCase()}.LABEL`)"
        :description="t(`AGENTS.SCHEDULE.${option.toUpperCase()}.DESC`)"
        :is-active="selected === option"
        @select="selected = $event"
      />
    </div>
    <p class="m-0 text-xs text-n-slate-10">
      {{ t('AGENTS.SCHEDULE.HINT') }}
    </p>
    <NextButton
      solid
      sm
      :label="t('AGENTS.SCHEDULE.SAVE')"
      :is-loading="isSaving"
      :disabled="isSaving"
      class="w-fit"
      @click="handleSubmit"
    />
  </div>
</template>
