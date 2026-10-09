<script setup>
import { computed, nextTick, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { STEPS, useBookingFlow } from './composables/useBookingFlow';
import AlreadyScheduled from './components/AlreadyScheduled.vue';
import ErrorPage from './components/ErrorPage.vue';
import NoSlot from './components/NoSlot.vue';
import NotFound from './components/NotFound.vue';
import Paused from './components/Paused.vue';
import StepConfirm from './components/StepConfirm.vue';
import StepDate from './components/StepDate.vue';
import StepDetails from './components/StepDetails.vue';
import StepDone from './components/StepDone.vue';
import StepTime from './components/StepTime.vue';

// Página pública de agendamento v2 (#1189). Só orquestra: o estado mora em composables/useBookingFlow e cada
// tela é um componente.
const { step, page, invite, load } = useBookingFlow();
const { t } = useI18n();

const SCREENS = {
  [STEPS.NOT_FOUND]: NotFound,
  [STEPS.ERROR]: ErrorPage,
  [STEPS.PAUSED]: Paused,
  [STEPS.ALREADY]: AlreadyScheduled,
  [STEPS.DATE]: StepDate,
  [STEPS.TIME]: StepTime,
  [STEPS.DETAILS]: StepDetails,
  [STEPS.CONFIRM]: StepConfirm,
  [STEPS.DONE]: StepDone,
  [STEPS.NO_SLOT]: NoSlot,
};

const screen = computed(() => SCREENS[step.value] || null);
const isPreview = computed(() => !!page.value?.preview);

// A cada tela nova o foco vai para o título dela: o leitor de tela anuncia onde a pessoa está.
watch(step, (current, previous) => {
  if (current === STEPS.LOADING) return;
  nextTick(() => {
    if (previous !== STEPS.LOADING) {
      document.querySelector('[data-step-heading]')?.focus();
    }
    // "Aberto" no card (J1-A10) só depois que a pessoa vê a primeira tela do convite.
    if (invite.isInvite.value) invite.markViewed();
  });
});

onMounted(load);
</script>

<template>
  <div class="flex min-h-screen w-full justify-center bg-slate-100 px-4 py-6">
    <main class="flex w-full max-w-md flex-col gap-4">
      <p
        v-if="isPreview"
        class="rounded-xl bg-amber-100 p-3 text-center text-base font-medium text-amber-900"
      >
        {{ t('BOOKING_V2.PREVIEW') }}
      </p>
      <div
        class="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm sm:p-8"
      >
        <p
          v-if="step === STEPS.LOADING"
          role="status"
          aria-live="polite"
          class="py-10 text-center text-base text-slate-600"
        >
          {{ t('BOOKING_V2.LOADING') }}
        </p>
        <component :is="screen" v-else-if="screen" />
      </div>
    </main>
  </div>
</template>
