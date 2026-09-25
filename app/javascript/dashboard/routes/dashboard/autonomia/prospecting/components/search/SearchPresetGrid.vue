<script setup>
// "Sua jogada" (#677): as três jogadas do modo escolhido para a nova busca e o
// cartão "Sem jogada", como a JogadasGrid do Orth.
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import SearchPresetCard from './SearchPresetCard.vue';

const { t } = useI18n();
const { form, formPresets, selectPreset } = useProspectingSearchContext();

const presetText = (preset, field) =>
  t(`PROSPECTING.SEARCH.PRESETS.ITEMS.${preset.i18nKey}.${field}`);
</script>

<template>
  <section class="grid gap-2">
    <div>
      <h3 class="text-xs font-medium text-n-slate-11">
        {{ t('PROSPECTING.SEARCH.PRESETS.TITLE') }}
      </h3>
      <p class="text-xs text-n-slate-10">
        {{ t('PROSPECTING.SEARCH.PRESETS.HINT') }}
      </p>
    </div>
    <div
      role="group"
      data-test="search-preset-grid"
      :aria-label="t('PROSPECTING.SEARCH.PRESETS.TITLE')"
      class="grid grid-cols-[repeat(auto-fit,minmax(10.5rem,1fr))] gap-2.5"
    >
      <SearchPresetCard
        v-for="preset in formPresets"
        :key="preset.id"
        :name="presetText(preset, 'NAME')"
        :pitch="presetText(preset, 'PITCH')"
        :icon="preset.icon"
        :icon-class="preset.iconClass"
        :selected="form.preset_id === preset.id"
        @select="selectPreset(preset.id)"
      />
      <SearchPresetCard
        :name="t('PROSPECTING.SEARCH.PRESETS.NONE_NAME')"
        :pitch="t('PROSPECTING.SEARCH.PRESETS.NONE_PITCH')"
        icon="i-lucide-circle-minus"
        icon-class="bg-n-slate-3 text-n-slate-11"
        :selected="!form.preset_id"
        is-empty-choice
        @select="selectPreset(null)"
      />
    </div>
  </section>
</template>
