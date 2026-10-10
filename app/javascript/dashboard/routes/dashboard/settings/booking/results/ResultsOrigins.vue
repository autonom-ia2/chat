<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { barWidthClass, originLabelKey } from './resultsFormat';

// De onde vieram os horários marcados (J7-A3): conversa, link da página,
// pedido de contato e, quando houver, a IA. Barra simples + o número escrito.
const props = defineProps({
  origins: { type: Array, required: true },
});

const { t } = useI18n();

const max = computed(() =>
  Math.max(0, ...props.origins.map(origin => origin.count))
);
</script>

<template>
  <section
    class="flex flex-col gap-4 p-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
    aria-labelledby="booking-results-origins"
  >
    <h2
      id="booking-results-origins"
      class="m-0 text-base font-semibold text-n-slate-12"
    >
      {{ t('BOOKING.RESULTS.ORIGINS.TITLE') }}
    </h2>
    <p v-if="!max" class="m-0 text-sm text-n-slate-11" data-origins-empty>
      {{ t('BOOKING.RESULTS.ORIGINS.EMPTY') }}
    </p>
    <ul v-else class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="origin in origins"
        :key="origin.key"
        :data-origin="origin.key"
        class="flex flex-col gap-1"
      >
        <div class="flex items-center justify-between gap-2 text-sm">
          <span class="text-n-slate-12">{{
            t(originLabelKey(origin.key))
          }}</span>
          <strong class="font-semibold tabular-nums text-n-slate-12">
            {{ origin.count }}
          </strong>
        </div>
        <div class="h-2 rounded-full bg-n-alpha-2" aria-hidden="true">
          <div
            class="h-2 rounded-full bg-n-blue-9"
            :class="barWidthClass(origin.count, max)"
          />
        </div>
      </li>
    </ul>
  </section>
</template>
