<script setup>
// Where the person is in the search by conversation (#2277): Conte → Confira → Revise. Same look as the
// Automações steps (AutomacaoEtapas): a finished step gets the check.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  current: { type: Number, required: true },
});

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS.STEPS';
const KEYS = ['ASK', 'CHECK', 'REVIEW'];
const { t } = useI18n();

const steps = computed(() =>
  KEYS.map((key, index) => {
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
  <ol
    :aria-label="t(`${NS}.LABEL`)"
    class="m-0 flex list-none items-center gap-2 p-0 sm:gap-3"
    data-test="search-steps"
  >
    <template v-for="(step, index) in steps" :key="step.key">
      <li
        v-if="index > 0"
        aria-hidden="true"
        class="h-0.5 w-4 rounded-full sm:w-7"
        :class="step.done || step.now ? 'bg-n-blue-7' : 'bg-n-slate-6'"
      />
      <li
        :aria-current="step.now ? 'step' : undefined"
        class="flex items-center gap-2.5 text-[0.9375rem] font-semibold"
        :class="{
          'text-n-teal-11': step.done,
          'text-n-blue-11': step.now,
          'text-n-slate-10': !step.done && !step.now,
        }"
      >
        <span
          class="grid size-8 place-items-center rounded-full text-sm font-bold"
          :class="{
            'bg-n-teal-3': step.done,
            'bg-n-blue-3': step.now,
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
        <span :class="{ 'sr-only sm:not-sr-only': !step.now }">
          {{ t(`${NS}.${step.key}`) }}
        </span>
      </li>
    </template>
  </ol>
</template>
