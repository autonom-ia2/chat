<script setup>
// Frente de local: tipo de área (raio ou área visível do mapa).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

const { t } = useI18n();
const { form } = useProspectingSearchContext();

const areaTypeChoices = computed(() => [
  { value: 'radius', label: t('PROSPECTING.SEARCH.AREA_RADIUS') },
  { value: 'viewport', label: t('PROSPECTING.SEARCH.AREA_VIEWPORT') },
]);
</script>

<template>
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
      {{
        form.area_type === 'viewport'
          ? t('PROSPECTING.SEARCH.AREA_VIEWPORT_HINT')
          : t('PROSPECTING.SEARCH.AREA_RADIUS_HINT')
      }}
    </p>
  </label>
</template>
