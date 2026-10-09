<script setup>
import { computed, ref } from 'vue';

const props = defineProps({
  steps: { type: Array, required: true },
  current: { type: Number, required: true },
  reachable: { type: Number, required: true },
  ariaLabel: { type: String, required: true },
  stepAria: {
    type: Function,
    default: (step, number) => `Step ${number}: ${step.label}`,
  },
});

const emit = defineEmits(['go']);

const steps = computed(() =>
  props.steps.map((step, index) => {
    const number = index + 1;
    return {
      ...step,
      number,
      isCurrent: number === props.current,
      isDone: number < props.current,
      isReachable: number <= props.reachable,
    };
  })
);

const buttons = ref([]);

const focusStep = index => {
  const enabled = buttons.value.filter(button => button && !button.disabled);
  if (!enabled.length) return;

  const target = enabled[(index + enabled.length) % enabled.length];
  target.focus();
};

const onKeydown = event => {
  const enabled = buttons.value.filter(button => button && !button.disabled);
  const position = enabled.indexOf(event.target);
  if (position === -1) return;

  const moves = {
    ArrowRight: position + 1,
    ArrowDown: position + 1,
    ArrowLeft: position - 1,
    ArrowUp: position - 1,
    Home: 0,
    End: enabled.length - 1,
  };
  if (!(event.key in moves)) return;

  event.preventDefault();
  focusStep(moves[event.key]);
};

const go = step => {
  if (step.isCurrent || !step.isReachable) return;
  emit('go', step.number);
};
</script>

<template>
  <nav
    :aria-label="ariaLabel"
    class="mb-5 rounded-2xl border border-n-weak bg-n-solid-1 px-3 py-2 shadow-sm"
  >
    <ol
      class="m-0 flex list-none flex-wrap items-center gap-1 p-0"
      @keydown="onKeydown"
    >
      <li
        v-for="(step, index) in steps"
        :key="step.key || step.number"
        class="flex items-center gap-1"
      >
        <span
          v-if="index > 0"
          class="i-lucide-chevron-right size-4 text-n-slate-9"
          aria-hidden="true"
        />
        <button
          :ref="element => (buttons[index] = element)"
          type="button"
          :data-step="step.number"
          :disabled="!step.isReachable"
          :aria-current="step.isCurrent ? 'step' : undefined"
          :aria-label="stepAria(step, step.number)"
          class="flex min-h-11 items-center gap-2 rounded-xl px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:cursor-not-allowed"
          :class="[
            step.isCurrent
              ? 'bg-n-blue-3 font-semibold text-n-blue-11'
              : 'text-n-slate-11 hover:bg-n-alpha-1',
            !step.isReachable && 'opacity-60 hover:bg-transparent',
          ]"
          @click="go(step)"
        >
          <span
            class="flex size-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold"
            :class="
              step.isCurrent
                ? 'bg-n-blue-9 text-white'
                : step.isDone
                  ? 'bg-n-teal-9 text-white'
                  : 'bg-n-alpha-2 text-n-slate-11'
            "
            aria-hidden="true"
          >
            <span v-if="step.isDone" class="i-lucide-check size-3.5" />
            <template v-else>{{ step.number }}</template>
          </span>
          {{ step.label }}
        </button>
      </li>
    </ol>
  </nav>
</template>
