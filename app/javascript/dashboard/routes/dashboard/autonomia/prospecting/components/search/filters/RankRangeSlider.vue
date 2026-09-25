<script setup>
// Faixa da posição no Google com duas alças (Orth, RankRangeSlider.tsx), de 1
// a 40. As alças não se cruzam. Quem usa traduz a faixa para outside_top e
// search_rank_max; aqui só há as duas posições.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  RANK_SLIDER_MAX,
  RANK_SLIDER_MIN,
} from '../../../utils/advancedLeadFilters';

const MIN_SPAN = 1;
const RANGE_CLASSES =
  'pointer-events-none absolute inset-x-0 h-6 w-full appearance-none bg-transparent ' +
  '[&::-webkit-slider-thumb]:pointer-events-auto [&::-webkit-slider-thumb]:size-4 ' +
  '[&::-webkit-slider-thumb]:cursor-pointer [&::-webkit-slider-thumb]:appearance-none ' +
  '[&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:border-2 ' +
  '[&::-webkit-slider-thumb]:border-n-brand [&::-webkit-slider-thumb]:bg-n-solid-1 ' +
  '[&::-moz-range-thumb]:pointer-events-auto [&::-moz-range-thumb]:size-4 ' +
  '[&::-moz-range-thumb]:cursor-pointer [&::-moz-range-thumb]:rounded-full ' +
  '[&::-moz-range-thumb]:border-2 [&::-moz-range-thumb]:border-n-brand ' +
  '[&::-moz-range-thumb]:bg-n-solid-1';

const min = defineModel('min', { type: Number, required: true });
const max = defineModel('max', { type: Number, required: true });

const { t } = useI18n();

const isFullRange = computed(
  () => min.value === RANK_SLIDER_MIN && max.value === RANK_SLIDER_MAX
);
const rangeLabel = computed(() => {
  const values = { min: min.value, max: max.value };
  return isFullRange.value
    ? t('PROSPECTING.SEARCH.FILTER_DRAWER.RANK.ANY', values)
    : t('PROSPECTING.SEARCH.FILTER_DRAWER.RANK.RANGE', values);
});

// A alça da esquerda fica por cima perto do fim, para continuar arrastável.
const minOnTop = computed(() => min.value > RANK_SLIDER_MAX - 5);

// A alça volta para o valor aceito mesmo quando ele não muda (o Vue não
// repinta um :value igual ao anterior).
const onMinInput = event => {
  min.value = Math.max(
    RANK_SLIDER_MIN,
    Math.min(Number(event.target.value), max.value - MIN_SPAN)
  );
  event.target.value = String(min.value);
};

const onMaxInput = event => {
  max.value = Math.min(
    RANK_SLIDER_MAX,
    Math.max(Number(event.target.value), min.value + MIN_SPAN)
  );
  event.target.value = String(max.value);
};
</script>

<template>
  <div class="grid gap-2">
    <div class="flex items-center justify-between gap-2">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('PROSPECTING.SEARCH.FILTER_DRAWER.RANK.LABEL') }}
      </span>
      <span class="text-sm font-medium text-n-slate-12">{{ rangeLabel }}</span>
    </div>
    <div class="relative flex h-11 items-center">
      <div class="absolute inset-x-0 h-1 rounded-full bg-n-slate-4" />
      <input
        type="range"
        :min="RANK_SLIDER_MIN"
        :max="RANK_SLIDER_MAX"
        :value="min"
        :aria-label="t('PROSPECTING.SEARCH.FILTER_DRAWER.RANK.MIN_ARIA')"
        :aria-valuetext="rangeLabel"
        :class="[RANGE_CLASSES, minOnTop ? 'z-20' : 'z-10']"
        @input="onMinInput"
      />
      <input
        type="range"
        :min="RANK_SLIDER_MIN"
        :max="RANK_SLIDER_MAX"
        :value="max"
        :aria-label="t('PROSPECTING.SEARCH.FILTER_DRAWER.RANK.MAX_ARIA')"
        :aria-valuetext="rangeLabel"
        :class="[RANGE_CLASSES, minOnTop ? 'z-10' : 'z-20']"
        @input="onMaxInput"
      />
    </div>
    <div
      class="flex justify-between text-[10px] text-n-slate-10"
      aria-hidden="true"
    >
      <span>{{ RANK_SLIDER_MIN }}</span>
      <span>{{ RANK_SLIDER_MAX }}</span>
    </div>
  </div>
</template>
