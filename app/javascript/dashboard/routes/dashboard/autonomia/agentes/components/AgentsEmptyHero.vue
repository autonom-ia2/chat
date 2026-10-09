<script setup>
import { useI18n } from 'vue-i18n';

import AgentModelCard from './AgentModelCard.vue';

defineProps({
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['create', 'selectModel']);
const { t } = useI18n();

const models = [
  {
    id: 'support',
    titleKey: 'AGENTS.V2.models.support.title',
    descriptionKey: 'AGENTS.V2.models.support.description',
    exampleKey: 'AGENTS.V2.models.support.example',
    icon: 'i-lucide-life-buoy',
    tileClass: 'bg-n-teal-3',
    iconClass: 'text-n-teal-11',
  },
  {
    id: 'sdr',
    titleKey: 'AGENTS.V2.models.sdr.title',
    descriptionKey: 'AGENTS.V2.models.sdr.description',
    exampleKey: 'AGENTS.V2.models.sdr.example',
    icon: 'i-lucide-target',
    tileClass: 'bg-n-blue-3',
    iconClass: 'text-n-blue-11',
  },
  {
    id: 'reception',
    titleKey: 'AGENTS.V2.models.reception.title',
    descriptionKey: 'AGENTS.V2.models.reception.description',
    exampleKey: 'AGENTS.V2.models.reception.example',
    icon: 'i-lucide-concierge-bell',
    tileClass: 'bg-n-amber-3',
    iconClass: 'text-n-amber-11',
  },
];

const selectModel = modelId => emit('selectModel', modelId);
</script>

<template>
  <div class="grid gap-6">
    <section
      class="relative isolate overflow-hidden rounded-3xl bg-n-navy px-5 py-8 text-white shadow-sm sm:px-12 sm:pb-11 sm:pt-12"
      data-empty-hero
    >
      <div class="relative z-10 max-w-2xl">
        <p
          class="mb-3 inline-flex items-center gap-2 text-sm font-semibold uppercase tracking-wide text-white/90"
        >
          <span class="i-lucide-sparkles size-4" aria-hidden="true" />
          {{ t('AGENTS.V2.empty.eyebrow') }}
        </p>
        <h1
          class="text-3xl font-semibold leading-tight tracking-tight text-white sm:text-[2.6rem]"
        >
          {{ t('AGENTS.V2.empty.title') }}
        </h1>
        <p
          class="mt-3 max-w-xl text-base leading-relaxed text-white/90 sm:text-[1.0625rem]"
        >
          {{ t('AGENTS.V2.empty.description') }}
        </p>
        <button
          v-if="canManage"
          type="button"
          class="mt-7 inline-flex min-h-11 items-center justify-center gap-2 rounded-lg bg-n-blue-11 px-4 text-sm font-semibold text-white dark:text-n-navy hover:bg-n-blue-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand focus-visible:outline-offset-2"
          data-create-agent
          @click="emit('create')"
        >
          <span class="i-lucide-plus size-4" aria-hidden="true" />
          {{ t('AGENTS.V2.empty.create') }}
        </button>
        <p v-else class="mt-5 text-sm text-white/90">
          {{ t('AGENTS.V2.empty.viewer') }}
        </p>
      </div>
      <span
        class="pointer-events-none absolute -right-16 -top-20 size-[22rem] rounded-full border-[3rem] border-n-brand/20"
        aria-hidden="true"
      />
      <span
        class="pointer-events-none absolute -bottom-28 right-36 size-56 rounded-full border-[3rem] border-n-brand/10"
        aria-hidden="true"
      />
    </section>

    <section v-if="canManage" class="grid gap-1">
      <h2 class="text-lg font-semibold text-n-slate-12">
        {{ t('AGENTS.V2.empty.modelsTitle') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('AGENTS.V2.empty.modelsDescription') }}
      </p>
      <div class="mt-4 grid gap-3 md:grid-cols-3">
        <AgentModelCard
          v-for="model in models"
          :key="model.id"
          :model="model"
          @select="selectModel"
        />
      </div>
    </section>
  </div>
</template>
