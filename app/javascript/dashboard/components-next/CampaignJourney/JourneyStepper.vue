<script setup>
// Steps of Nova campanha (#993, PRD §7, G4): Público → Mensagem → Revisar e agendar.
// The current step has aria-current="step"; steps already reached are buttons that go
// back to them. Arrow keys, Home and End move between the step buttons.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  current: { type: Number, required: true },
  // Highest step the person can open (the ones after it need the current one done).
  reachable: { type: Number, required: true },
});

const emit = defineEmits(['go']);

const { t } = useI18n();

const STEPS = ['AUDIENCE', 'MESSAGE', 'REVIEW'];

const steps = computed(() =>
  STEPS.map((key, index) => {
    const number = index + 1;
    return {
      number,
      label: t(`CAMPAIGN_JOURNEY.STEPPER.${key}`),
      isCurrent: number === props.current,
      isDone: number < props.current,
      isReachable: number <= props.reachable,
    };
  })
);

const buttons = ref([]);

const focusStep = index => {
  const enabled = buttons.value.filter(button => !button.disabled);
  const target = enabled[(index + enabled.length) % enabled.length];
  target?.focus();
};

const onKeydown = event => {
  const enabled = buttons.value.filter(button => !button.disabled);
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
    :aria-label="t('CAMPAIGN_JOURNEY.STEPPER.LABEL')"
    class="mb-5 rounded-2xl border border-n-weak bg-n-solid-1 px-3 py-2 shadow-sm"
  >
    <ol
      class="m-0 flex list-none flex-wrap items-center gap-1 p-0"
      @keydown="onKeydown"
    >
      <li
        v-for="(step, index) in steps"
        :key="step.number"
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
          :aria-label="
            t('CAMPAIGN_JOURNEY.STEPPER.STEP_ARIA', {
              n: step.number,
              label: step.label,
            })
          "
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
