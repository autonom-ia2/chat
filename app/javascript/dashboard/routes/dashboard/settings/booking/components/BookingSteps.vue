<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { STEPS } from '../constants';

// Onde a pessoa está nos seis passos. Passo feito ganha o visto; o atual leva
// aria-current="step" para o leitor de tela.
const props = defineProps({
  current: { type: Number, required: true },
});

const { t } = useI18n();

const steps = computed(() =>
  STEPS.map((key, index) => {
    const number = index + 1;
    return {
      key,
      number,
      done: number < props.current,
      now: number === props.current,
    };
  })
);
</script>

<template>
  <nav :aria-label="t('BOOKING.STEPS.LABEL')" class="flex flex-col gap-3">
    <p class="m-0 text-sm font-semibold text-n-slate-11">
      {{ t('BOOKING.STEPS.COUNT', { current, total: STEPS.length }) }}
    </p>
    <ol data-steps class="flex flex-wrap items-center gap-2 p-0 m-0 list-none">
      <li
        v-for="step in steps"
        :key="step.key"
        :data-step="step.key"
        :aria-current="step.now ? 'step' : undefined"
        class="flex items-center gap-2 text-base font-semibold"
        :class="{
          'text-n-teal-11': step.done,
          'text-n-blue-11': step.now,
          'text-n-slate-10': !step.done && !step.now,
        }"
      >
        <span
          class="grid text-sm font-bold rounded-full place-items-center size-8 shrink-0"
          :class="{
            'bg-n-teal-3': step.done,
            'bg-n-blue-3 ring-2 ring-n-blue-7': step.now,
            'bg-n-slate-3': !step.done && !step.now,
          }"
        >
          <span
            v-if="step.done"
            class="i-lucide-check size-4"
            aria-hidden="true"
          />
          <template v-else>{{ step.number }}</template>
        </span>
        <span :class="step.now ? '' : 'sr-only md:not-sr-only'">
          {{ t(`BOOKING.STEPS.${step.key}`) }}
        </span>
        <span
          v-if="step.number < STEPS.length"
          class="hidden w-5 h-0.5 rounded-full md:block"
          :class="step.done ? 'bg-n-teal-7' : 'bg-n-slate-6'"
          aria-hidden="true"
        />
      </li>
    </ol>
  </nav>
</template>
