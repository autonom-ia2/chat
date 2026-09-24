<script setup>
// Frente de modo e jogadas: como a busca pontua os leads.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

const { t } = useI18n();
const { form } = useProspectingSearchContext();

const scoreModeChoices = computed(() => [
  { value: 'gbp', label: t('PROSPECTING.SEARCH.SCORE_MODES.GBP') },
  { value: 'general', label: t('PROSPECTING.SEARCH.SCORE_MODES.GENERAL') },
]);
</script>

<template>
  <label class="grid gap-1">
    <span class="text-xs font-medium text-n-slate-11">
      {{ t('PROSPECTING.SEARCH.FIELDS.SCORE_MODE') }}
    </span>
    <ChoiceSelect
      v-model="form.score_mode"
      :options="scoreModeChoices"
      :aria-label="t('PROSPECTING.SEARCH.FIELDS.SCORE_MODE')"
    />
    <p class="text-xs text-n-slate-10">
      {{
        form.score_mode === 'gbp'
          ? t('PROSPECTING.SEARCH.SCORE_MODE_GBP_HINT')
          : t('PROSPECTING.SEARCH.SCORE_MODE_GENERAL_HINT')
      }}
    </p>
  </label>
</template>
