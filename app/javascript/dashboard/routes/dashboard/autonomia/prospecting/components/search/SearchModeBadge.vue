<script setup>
// Selo do modo no topo da busca (#677), como no Orth: âmbar no GMN, verde no
// Geral. Com o formulário aberto segue o modo escolhido para a nova busca;
// fora dele, o modo e a jogada da busca aberta.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import SearchPresetChip from './SearchPresetChip.vue';

const { t } = useI18n();
const { currentScoreMode, openSearchPreset, showNewSearch } =
  useProspectingSearchContext();

const isGbp = computed(() => currentScoreMode.value === 'gbp');
const label = computed(() =>
  isGbp.value
    ? t('PROSPECTING.SEARCH.MODE_BADGE.GBP')
    : t('PROSPECTING.SEARCH.MODE_BADGE.GENERAL')
);
const explanation = computed(() =>
  isGbp.value
    ? t('PROSPECTING.SEARCH.MODE_BADGE.GBP_TOOLTIP')
    : t('PROSPECTING.SEARCH.MODE_BADGE.GENERAL_TOOLTIP')
);
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <span
      v-tooltip.bottom="explanation"
      data-test="search-mode-badge"
      tabindex="0"
      class="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-medium"
      :class="
        isGbp
          ? 'border-n-amber-6 bg-n-amber-3 text-n-amber-11'
          : 'border-n-teal-6 bg-n-teal-3 text-n-teal-11'
      "
    >
      <span class="i-lucide-clock size-3" aria-hidden="true" />
      {{ label }}
      <span class="sr-only">{{ explanation }}</span>
    </span>
    <SearchPresetChip
      v-if="!showNewSearch && openSearchPreset"
      :preset="openSearchPreset"
    />
  </div>
</template>
