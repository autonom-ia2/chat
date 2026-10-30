<script setup>
// The first question of Novo público when the search by conversation is on (#2277): where do the people come
// from? Two big cards, one choice each. "Das suas conversas" comes first and is marked as the easiest, unless
// the account still has to connect its own AI: then the card says so before the click.
import { useI18n } from 'vue-i18n';

defineProps({
  conversationsNeedSetup: { type: Boolean, default: false },
});
const emit = defineEmits(['choose']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.SOURCE';
const OPTIONS = [
  {
    id: 'conversas',
    key: 'CONVERSATIONS',
    icon: 'i-lucide-messages-square',
    tone: 'bg-n-blue-3 text-n-blue-11',
    recommended: true,
  },
  {
    id: 'planilha',
    key: 'SHEET',
    icon: 'i-lucide-file-spreadsheet',
    tone: 'bg-n-teal-3 text-n-teal-11',
    recommended: false,
  },
];
const { t } = useI18n();
</script>

<template>
  <section class="flex flex-col gap-4" data-test="audience-source">
    <h2 class="m-0 text-xl font-semibold text-n-slate-12">
      {{ t(`${NS}.QUESTION`) }}
    </h2>
    <div class="grid gap-4 md:grid-cols-2">
      <button
        v-for="option in OPTIONS"
        :key="option.id"
        type="button"
        class="group relative flex min-h-44 flex-col items-start gap-3 rounded-3xl border-2 border-n-weak bg-n-solid-1 p-6 text-start shadow-sm transition hover:-translate-y-0.5 hover:border-n-blue-8 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        :data-test="`source-${option.id}`"
        @click="emit('choose', option.id)"
      >
        <span
          v-if="option.recommended && !conversationsNeedSetup"
          class="absolute end-5 top-5 rounded-full bg-n-blue-3 px-3 py-1 text-xs font-semibold text-n-blue-11"
        >
          {{ t(`${NS}.RECOMMENDED`) }}
        </span>
        <span
          v-else-if="option.recommended"
          class="absolute end-5 top-5 rounded-full bg-n-slate-3 px-3 py-1 text-xs font-semibold text-n-slate-11"
        >
          {{ t(`${NS}.NEEDS_SETUP`) }}
        </span>
        <span
          class="grid size-12 place-items-center rounded-2xl"
          :class="option.tone"
          aria-hidden="true"
        >
          <span class="size-6" :class="option.icon" />
        </span>
        <strong class="text-lg text-n-slate-12">
          {{ t(`${NS}.${option.key}_TITLE`) }}
        </strong>
        <span class="text-base leading-relaxed text-n-slate-11">
          {{ t(`${NS}.${option.key}_TEXT`) }}
        </span>
        <span
          class="mt-auto inline-flex items-center gap-1.5 text-sm font-semibold text-n-blue-11"
        >
          {{ t(`${NS}.${option.key}_CTA`) }}
          <span
            class="i-lucide-arrow-right size-4 transition-transform group-hover:translate-x-0.5 rtl:rotate-180"
            aria-hidden="true"
          />
        </span>
      </button>
    </div>
  </section>
</template>
