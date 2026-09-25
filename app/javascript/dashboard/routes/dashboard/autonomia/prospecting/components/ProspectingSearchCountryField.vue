<script setup>
// País da busca por conta (#677): o Google procura e escreve endereços nele.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { searchCountryGroups } from '../utils/searchCountries';

const props = defineProps({
  countries: { type: Array, default: () => [] },
});

const country = defineModel({ type: String, required: true });

const { t } = useI18n();

const groups = computed(() => searchCountryGroups(props.countries, t));
</script>

<template>
  <label class="grid gap-1 md:w-1/2">
    <span class="text-xs font-medium text-n-slate-11">
      {{ t('PROSPECTING.SEARCH_COUNTRY.LABEL') }}
    </span>
    <ChoiceSelect
      v-model="country"
      :groups="groups"
      :aria-label="t('PROSPECTING.SEARCH_COUNTRY.LABEL')"
    />
    <span class="text-xs text-n-slate-10">
      {{ t('PROSPECTING.SEARCH_COUNTRY.HINT') }}
      {{ t('PROSPECTING.SEARCH_COUNTRY.DEFAULT_HINT') }}
    </span>
  </label>
</template>
