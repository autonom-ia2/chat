<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

import NextButton from 'dashboard/components-next/button/Button.vue';
import AgentModelCard from '../components/AgentModelCard.vue';

const props = defineProps({
  selectedType: { type: String, default: null },
  canChooseInternal: { type: Boolean, default: true },
  isStarting: { type: Boolean, default: false },
});

const emit = defineEmits(['select', 'continue', 'leave']);
const { t } = useI18n();
const route = useRoute();
const initialSelection = props.selectedType || route.query.type || null;
const localSelection = ref(
  initialSelection === 'internal' && !props.canChooseInternal
    ? null
    : initialSelection
);

const EXTERNAL_MODELS = [
  {
    id: 'support',
    titleKey: 'AGENTS.CREATION.choice.models.support.title',
    descriptionKey: 'AGENTS.CREATION.choice.models.support.description',
    exampleKey: 'AGENTS.CREATION.choice.models.support.example',
    icon: 'i-lucide-life-buoy',
    tileClass: 'bg-n-teal-3',
    iconClass: 'text-n-teal-11',
  },
  {
    id: 'sdr',
    titleKey: 'AGENTS.CREATION.choice.models.sdr.title',
    descriptionKey: 'AGENTS.CREATION.choice.models.sdr.description',
    exampleKey: 'AGENTS.CREATION.choice.models.sdr.example',
    icon: 'i-lucide-target',
    tileClass: 'bg-n-blue-3',
    iconClass: 'text-n-blue-11',
  },
  {
    id: 'reception',
    titleKey: 'AGENTS.CREATION.choice.models.reception.title',
    descriptionKey: 'AGENTS.CREATION.choice.models.reception.description',
    exampleKey: 'AGENTS.CREATION.choice.models.reception.example',
    icon: 'i-lucide-concierge-bell',
    tileClass: 'bg-n-amber-3',
    iconClass: 'text-n-amber-11',
  },
  {
    id: 'onboarding',
    titleKey: 'AGENTS.CREATION.choice.models.onboarding.title',
    descriptionKey: 'AGENTS.CREATION.choice.models.onboarding.description',
    exampleKey: 'AGENTS.CREATION.choice.models.onboarding.example',
    icon: 'i-lucide-heart-handshake',
    tileClass: 'bg-n-ruby-3',
    iconClass: 'text-n-ruby-11',
  },
  {
    id: 'scheduler',
    titleKey: 'AGENTS.CREATION.choice.models.scheduler.title',
    descriptionKey: 'AGENTS.CREATION.choice.models.scheduler.description',
    exampleKey: 'AGENTS.CREATION.choice.models.scheduler.example',
    icon: 'i-lucide-calendar-clock',
    tileClass: 'bg-n-iris-3',
    iconClass: 'text-n-iris-11',
  },
  {
    id: 'reactivation',
    titleKey: 'AGENTS.CREATION.choice.models.reactivation.title',
    descriptionKey: 'AGENTS.CREATION.choice.models.reactivation.description',
    exampleKey: 'AGENTS.CREATION.choice.models.reactivation.example',
    icon: 'i-lucide-refresh-cw',
    tileClass: 'bg-n-slate-3',
    iconClass: 'text-n-slate-11',
  },
];

const INTERNAL_MODEL = {
  id: 'internal',
  titleKey: 'AGENTS.CREATION.choice.models.internal.title',
  descriptionKey: 'AGENTS.CREATION.choice.models.internal.description',
  icon: 'i-lucide-users',
  tileClass: 'bg-n-iris-3',
  iconClass: 'text-n-iris-11',
};

const CUSTOM_MODEL = {
  id: 'custom',
  titleKey: 'AGENTS.CREATION.choice.models.custom.title',
  descriptionKey: 'AGENTS.CREATION.choice.models.custom.description',
  icon: 'i-lucide-pencil',
  tileClass: 'bg-n-slate-3',
  iconClass: 'text-n-slate-11',
};

const secondaryModels = computed(() =>
  props.canChooseInternal ? [INTERNAL_MODEL, CUSTOM_MODEL] : [CUSTOM_MODEL]
);

const selectModel = model => {
  localSelection.value = model.id;
  emit('select', {
    type: model.id,
    actuation: model.id === 'internal' ? 'internal' : 'external',
    withKnowledge: true,
  });
};

const continueBuild = () => {
  if (!localSelection.value || props.isStarting) return;
  emit('continue', {
    type: localSelection.value,
    actuation: localSelection.value === 'internal' ? 'internal' : 'external',
    withKnowledge: true,
  });
};
</script>

<template>
  <main
    data-testid="agent-creation-choice"
    class="mx-auto flex w-full max-w-6xl flex-col gap-6 px-4 py-6 sm:px-6 lg:py-10"
  >
    <header class="mx-auto flex max-w-3xl flex-col gap-2 text-center">
      <p class="text-xs font-semibold tracking-wider text-n-slate-11">
        {{ t('AGENTS.CREATION.choice.eyebrow') }}
      </p>
      <h1 class="text-2xl font-semibold text-n-slate-12 sm:text-3xl">
        {{ t('AGENTS.CREATION.choice.title') }}
      </h1>
      <p class="text-sm leading-6 text-n-slate-11">
        {{ t('AGENTS.CREATION.choice.description') }}
      </p>
    </header>

    <section
      class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
      :aria-label="t('AGENTS.CREATION.choice.modelsLabel')"
    >
      <AgentModelCard
        v-for="model in EXTERNAL_MODELS"
        :key="model.id"
        :model="{
          ...model,
          title: t(model.titleKey),
          description: t(model.descriptionKey),
          example: t(model.exampleKey),
        }"
        :selected="localSelection === model.id"
        @select="selectModel(model)"
      />
    </section>

    <section class="grid gap-4 sm:grid-cols-2">
      <AgentModelCard
        v-for="model in secondaryModels"
        :key="model.id"
        compact
        :model="{
          ...model,
          title: t(model.titleKey),
          description: t(model.descriptionKey),
        }"
        :selected="localSelection === model.id"
        @select="selectModel(model)"
      />
    </section>

    <div
      class="flex flex-col items-stretch justify-between gap-3 border-t border-n-weak pt-4 sm:flex-row sm:items-center"
    >
      <span class="text-sm text-n-slate-11">
        {{
          localSelection
            ? t('AGENTS.CREATION.choice.selected')
            : t('AGENTS.CREATION.choice.chooseHint')
        }}
      </span>
      <div class="flex flex-col-reverse gap-3 sm:flex-row">
        <NextButton
          ghost
          slate
          class="min-h-11"
          :label="t('AGENTS.CREATION.actions.back')"
          data-action="creation-save-exit"
          @click="emit('leave')"
        />
        <NextButton
          solid
          slate
          class="min-h-11"
          :label="t('AGENTS.CREATION.actions.continue')"
          :is-loading="isStarting"
          :disabled="!localSelection"
          data-action="creation-continue"
          data-testid="creation-choice-next"
          @click="continueBuild"
        />
      </div>
    </div>
  </main>
</template>
