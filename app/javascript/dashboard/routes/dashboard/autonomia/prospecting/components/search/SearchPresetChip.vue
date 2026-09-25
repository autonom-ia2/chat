<script setup>
// Selo de uma jogada do catálogo (#677): cor, ícone e nome.
import { useI18n } from 'vue-i18n';

defineProps({
  preset: { type: Object, required: true },
});

const { t } = useI18n();
</script>

<template>
  <span
    data-test="search-preset-chip"
    class="inline-flex max-w-full items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium"
    :class="preset.chipClass"
  >
    <span class="size-3 shrink-0" :class="preset.icon" aria-hidden="true" />
    <span class="truncate">
      {{ t(`PROSPECTING.SEARCH.PRESETS.ITEMS.${preset.i18nKey}.NAME`) }}
    </span>
  </span>
</template>
