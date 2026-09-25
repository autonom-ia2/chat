<script setup>
// Nota do Orth na aba Score (#681): os 6 componentes com os pesos efetivos da
// conta e a leitura da nota no modo escolhido. Só aparece na conta virada.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  weights: { type: Object, default: () => ({}) },
  mode: { type: String, default: 'gbp' },
  isCustom: { type: Boolean, default: false },
});

const { t } = useI18n();

const COMPONENTS = [
  'website',
  'phone',
  'rating',
  'volume',
  'activity',
  'photos',
];

const weightOf = key =>
  Math.max(0, Math.min(100, Number(props.weights[key] || 0)));

const readingText = computed(() =>
  props.mode === 'general'
    ? t('PROSPECTING.SETTINGS.ORTH.READING_GENERAL')
    : t('PROSPECTING.SETTINGS.ORTH.READING_GBP')
);
</script>

<template>
  <div
    class="overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 shadow-sm"
  >
    <div class="grid gap-1 border-b border-n-weak px-4 py-3">
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t('PROSPECTING.SETTINGS.ORTH.WEIGHTS_TITLE') }}
      </h3>
      <p class="text-xs text-n-slate-10">
        {{
          isCustom
            ? t('PROSPECTING.SETTINGS.ORTH.CUSTOM_HINT')
            : t('PROSPECTING.SETTINGS.ORTH.WEIGHTS_HINT')
        }}
      </p>
    </div>

    <div
      v-for="key in COMPONENTS"
      :key="key"
      :data-orth-component="key"
      class="grid items-center gap-3 border-b border-n-weak px-4 py-3 md:grid-cols-[160px_1fr_90px]"
    >
      <span class="text-sm font-medium text-n-slate-11">
        {{ t(`PROSPECTING.SETTINGS.ORTH.COMPONENTS.${key}`) }}
      </span>
      <div class="h-2 overflow-hidden rounded-full bg-n-solid-3">
        <div
          class="h-full rounded-full bg-gradient-to-r from-n-blue-9 to-n-teal-9"
          :style="{ width: `${weightOf(key)}%` }"
        />
      </div>
      <div
        class="flex h-9 items-center justify-center rounded-md border border-n-weak bg-n-solid-3 text-sm font-semibold text-n-slate-10"
      >
        {{ weightOf(key) }}
      </div>
    </div>

    <p class="px-4 py-3 text-xs leading-relaxed text-n-slate-10">
      {{ readingText }}
    </p>
  </div>
</template>
