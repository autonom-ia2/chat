<script setup>
import { useI18n } from 'vue-i18n';
import {
  NUMBER_KEYS,
  numberHintKey,
  numberLabelKey,
  numberToneClass,
} from './resultsFormat';

// Os cinco números do período (J7-A1), cada um com uma frase que explica o
// que conta. "Marcaram" diz também quantos confirmaram pelo link (RA-19).
defineProps({
  totals: { type: Object, required: true },
  days: { type: Number, required: true },
});

const { t } = useI18n();
</script>

<template>
  <section :aria-label="t('BOOKING.RESULTS.NUMBERS_LABEL', { days })">
    <ul
      class="grid grid-cols-1 gap-3 p-0 m-0 list-none sm:grid-cols-2 lg:grid-cols-3"
    >
      <li
        v-for="key in NUMBER_KEYS"
        :key="key"
        :data-number="key"
        class="flex flex-col gap-1 p-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
      >
        <span class="text-sm font-medium text-n-slate-11">
          {{ t(numberLabelKey(key)) }}
        </span>
        <strong
          class="text-3xl font-semibold tabular-nums"
          :class="numberToneClass(key)"
          data-value
        >
          {{ totals[key] || 0 }}
        </strong>
        <span class="text-sm text-n-slate-11">{{ t(numberHintKey(key)) }}</span>
        <span
          v-if="key === 'booked'"
          class="text-sm text-n-slate-12"
          data-confirmed
        >
          {{ t('BOOKING.RESULTS.CONFIRMED', { count: totals.confirmed || 0 }) }}
        </span>
      </li>
    </ul>
  </section>
</template>
