<script setup>
// Um grupo da gaveta de filtros (Orth, FiltersDrawerV2 GroupCard): ícone na
// cor do grupo, título, para que serve e quantos filtros do grupo estão ativos.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, required: true },
  icon: { type: String, required: true },
  tone: {
    type: String,
    required: true,
    validator: value => ['ruby', 'teal', 'iris', 'amber'].includes(value),
  },
  count: { type: Number, default: 0 },
});

const { t } = useI18n();

const TONE_CLASSES = {
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
};

const toneClass = computed(() => TONE_CLASSES[props.tone]);
</script>

<template>
  <section class="rounded-lg border border-n-weak bg-n-solid-2 p-4">
    <header class="flex items-start gap-3">
      <span
        class="flex size-7 shrink-0 items-center justify-center rounded-md"
        :class="toneClass"
        aria-hidden="true"
      >
        <span class="size-4" :class="icon" />
      </span>
      <div class="min-w-0 flex-1">
        <h3 class="text-sm font-semibold text-n-slate-12">{{ title }}</h3>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ subtitle }}</p>
      </div>
      <span
        v-if="count"
        class="rounded-full bg-n-brand px-2 py-0.5 text-[11px] font-semibold text-white"
        :aria-label="
          t('PROSPECTING.SEARCH.FILTER_DRAWER.GROUP_COUNT', { count })
        "
      >
        {{ count }}
      </span>
    </header>
    <div class="mt-3 grid gap-3">
      <slot />
    </div>
  </section>
</template>
