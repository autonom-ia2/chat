<script setup>
// Base em que a pessoa mexe na gaveta de filtros (Orth, FiltersDrawerV2):
// "Jogada base: X · Modo: Y" ou "Sem jogada · Modo: Y". Mudar um filtro da
// jogada a desmarca; o modo decide como a busca pontua.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { presetName } from '../../../utils/searchPresets';

const props = defineProps({
  preset: { type: Object, default: null },
  scoreMode: { type: String, required: true },
});

const { t } = useI18n();

const modeLabel = computed(() =>
  props.scoreMode === 'gbp'
    ? t('PROSPECTING.SEARCH.SCORE_MODES.GBP')
    : t('PROSPECTING.SEARCH.SCORE_MODES.GENERAL')
);
</script>

<template>
  <p
    data-test="filters-base"
    class="flex flex-wrap items-center gap-x-1.5 text-xs text-n-slate-10"
  >
    <span v-if="preset">
      {{ t('PROSPECTING.SEARCH.FILTER_DRAWER.BASE_PRESET') }}
      <strong class="font-medium text-n-slate-12">
        {{ presetName(preset, t) }}
      </strong>
    </span>
    <span v-else>
      {{ t('PROSPECTING.SEARCH.PRESETS.NONE_NAME') }}
    </span>
    <span class="before:mr-1.5 before:content-['·']">
      {{ t('PROSPECTING.SEARCH.FILTER_DRAWER.BASE_MODE') }}
      <strong class="font-medium text-n-slate-12">{{ modeLabel }}</strong>
    </span>
  </p>
</template>
