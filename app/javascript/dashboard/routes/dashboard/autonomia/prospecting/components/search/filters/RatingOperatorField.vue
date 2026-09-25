<script setup>
// Avaliação com operador (Orth, FiltersDrawerV2 + RatingFilter): "acima de"
// grava rating_min, "abaixo de" grava rating_max, nunca os dois. Diferente do
// Orth, escolher só o operador não grava nota: sem estrelas, não filtra.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const RATING_STEPS = [1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5];

const ratingMin = defineModel('ratingMin', {
  type: [String, Number],
  required: true,
});
const ratingMax = defineModel('ratingMax', {
  type: [String, Number],
  required: true,
});

const { t } = useI18n();

const initialOperator = () => {
  if (ratingMin.value !== '') return 'above';
  if (ratingMax.value !== '') return 'below';
  return '';
};

const operator = ref(initialOperator());

const operatorChoices = computed(() => [
  { value: '', label: t('PROSPECTING.SEARCH.FILTER_DRAWER.RATING.ANY') },
  { value: 'above', label: t('PROSPECTING.SEARCH.FILTER_DRAWER.RATING.ABOVE') },
  { value: 'below', label: t('PROSPECTING.SEARCH.FILTER_DRAWER.RATING.BELOW') },
]);

const ratingValue = computed({
  get: () => (operator.value === 'below' ? ratingMax.value : ratingMin.value),
  set: value => {
    ratingMin.value = operator.value === 'above' ? value : '';
    ratingMax.value = operator.value === 'below' ? value : '';
  },
});

// A nota da jogada (4,2) não é meia estrela: entra entre as opções para o
// seletor mostrar o que está filtrando, como o Orth, em vez do placeholder.
const valueChoices = computed(() => {
  const current = Number(ratingValue.value);
  const hasExtra =
    ratingValue.value !== '' &&
    !Number.isNaN(current) &&
    !RATING_STEPS.includes(current);
  // O valor entra como veio, para bater com o v-model do seletor.
  const steps = hasExtra
    ? [...RATING_STEPS, ratingValue.value].sort((a, b) => Number(a) - Number(b))
    : RATING_STEPS;
  return steps.map(value => ({
    value,
    label: t('PROSPECTING.SEARCH.FILTER_DRAWER.RATING.STARS', { value }),
  }));
});

// Trocar o operador leva as estrelas escolhidas para o outro lado.
const changeOperator = next => {
  const value = ratingValue.value;
  operator.value = next;
  ratingValue.value = next ? value : '';
};
</script>

<template>
  <div class="grid gap-1">
    <span class="text-xs font-medium text-n-slate-11">
      {{ t('PROSPECTING.SEARCH.FILTER_DRAWER.RATING.LABEL') }}
    </span>
    <div class="flex flex-wrap items-center gap-2">
      <ChoiceSelect
        :model-value="operator"
        compact
        :options="operatorChoices"
        :aria-label="t('PROSPECTING.SEARCH.FILTER_DRAWER.RATING.OPERATOR')"
        @update:model-value="changeOperator"
      />
      <ChoiceSelect
        v-if="operator"
        v-model="ratingValue"
        compact
        :options="valueChoices"
        :placeholder="
          t('PROSPECTING.SEARCH.FILTER_DRAWER.RATING.VALUE_PLACEHOLDER')
        "
        :aria-label="t('PROSPECTING.SEARCH.FILTER_DRAWER.RATING.VALUE')"
      />
    </div>
  </div>
</template>
