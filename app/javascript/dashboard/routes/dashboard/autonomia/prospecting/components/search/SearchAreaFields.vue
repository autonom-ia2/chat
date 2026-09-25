<script setup>
// Frente de local: tipo de área (raio, área visível do mapa ou área desenhada)
// e, na área desenhada, o mapa de desenho no local escolhido (#678).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import SearchAreaDrawMap from './SearchAreaDrawMap.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

const { t } = useI18n();
const {
  form,
  drawnArea,
  isDrawnArea,
  confirmedLocation,
  previewMapCenter,
  googleMapsApiKey,
  handleDrawnAreaChange,
} = useProspectingSearchContext();

const areaTypeChoices = computed(() => [
  { value: 'radius', label: t('PROSPECTING.SEARCH.AREA_RADIUS') },
  { value: 'viewport', label: t('PROSPECTING.SEARCH.AREA_VIEWPORT') },
  { value: 'circle', label: t('PROSPECTING.SEARCH.AREA_DRAW.CIRCLE') },
  { value: 'rectangle', label: t('PROSPECTING.SEARCH.AREA_DRAW.RECTANGLE') },
  { value: 'polygon', label: t('PROSPECTING.SEARCH.AREA_DRAW.POLYGON') },
]);

const areaHint = computed(() => {
  if (form.value.area_type === 'viewport') {
    return t('PROSPECTING.SEARCH.AREA_VIEWPORT_HINT');
  }
  if (isDrawnArea.value) return t('PROSPECTING.SEARCH.AREA_DRAW.HINT');
  return t('PROSPECTING.SEARCH.AREA_RADIUS_HINT');
});

const canDraw = computed(
  () => isDrawnArea.value && confirmedLocation.value && previewMapCenter.value
);
const drawDefaultRadius = computed(
  () => Number(form.value.radius_km) * 1000 || 1000
);
</script>

<template>
  <div class="grid gap-3">
    <label class="grid max-w-xs gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('PROSPECTING.SEARCH.FIELDS.AREA_TYPE') }}
      </span>
      <ChoiceSelect
        v-model="form.area_type"
        :options="areaTypeChoices"
        :aria-label="t('PROSPECTING.SEARCH.FIELDS.AREA_TYPE')"
      />
      <p class="text-xs text-n-slate-10">
        {{ areaHint }}
      </p>
    </label>
    <SearchAreaDrawMap
      v-if="canDraw"
      :api-key="googleMapsApiKey"
      :center="previewMapCenter"
      :shape="form.area_type"
      :default-radius="drawDefaultRadius"
      :model-value="drawnArea"
      @update:model-value="handleDrawnAreaChange"
    />
    <p v-else-if="isDrawnArea" class="text-xs text-n-slate-10">
      {{ t('PROSPECTING.SEARCH.AREA_DRAW.HINT_NEEDS_LOCATION') }}
    </p>
  </div>
</template>
