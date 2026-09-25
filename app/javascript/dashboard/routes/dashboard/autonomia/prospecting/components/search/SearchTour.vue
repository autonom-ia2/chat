<script setup>
// Cartão do tour guiado da busca (#682) e o anel em volta do bloco do passo,
// como o GuidedTour do Orth. Fora das boas-vindas o cartão não cobre a tela:
// a pessoa preenche o local e clica em Buscar com o tour aberto.
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import { SEARCH_TOUR_STEPS, searchTourTextKey } from '../../utils/searchTour';

const RING_PADDING_PX = 6;
const TARGET_POLL_MS = 120;
const TARGET_POLL_MAX = 25;
const STEP_COUNT = SEARCH_TOUR_STEPS.length;

const { t } = useI18n();
const {
  tourStep,
  tourStepIndex,
  tourWaiting,
  currentScoreMode,
  nextTourStep,
  prevTourStep,
  closeTour,
  suggestTourLocations,
} = useProspectingSearchContext();

const card = ref(null);
const ring = ref(null);
let pollTimer = null;

const text = field =>
  t(searchTourTextKey(tourStep.value, field, currentScoreMode.value));
const isWelcome = computed(() => tourStepIndex.value === 0);
const isLast = computed(() => tourStepIndex.value === STEP_COUNT - 1);
const showNext = computed(() => tourStep.value.waitFor !== 'results');
const nextLabel = computed(() => {
  if (isWelcome.value) return t('PROSPECTING.TOUR.START');
  if (isLast.value) return t('PROSPECTING.TOUR.FINISH');
  return t('PROSPECTING.TOUR.NEXT');
});
const waitingLabel = computed(() =>
  tourStep.value.waitFor === 'location'
    ? t('PROSPECTING.TOUR.WAITING_LOCATION')
    : t('PROSPECTING.TOUR.WAITING_RESULTS')
);

const targetElement = () =>
  tourStep.value?.target
    ? document.querySelector(`[data-tour="${tourStep.value.target}"]`)
    : null;

const measure = () => {
  const element = targetElement();
  if (!element) {
    ring.value = null;
    return;
  }
  const rect = element.getBoundingClientRect();
  ring.value = {
    top: `${rect.top - RING_PADDING_PX}px`,
    left: `${rect.left - RING_PADDING_PX}px`,
    width: `${rect.width + RING_PADDING_PX * 2}px`,
    height: `${rect.height + RING_PADDING_PX * 2}px`,
  };
};

const stopPolling = () => {
  window.clearInterval(pollTimer);
  pollTimer = null;
};

// O bloco do passo pode montar depois (formulário que o tour abriu): procura
// por alguns instantes antes de desistir do anel.
const followTarget = () => {
  stopPolling();
  ring.value = null;
  if (!tourStep.value?.target) return;

  let tries = 0;
  pollTimer = window.setInterval(() => {
    tries += 1;
    const element = targetElement();
    if (element) {
      stopPolling();
      element.scrollIntoView?.({ block: 'center', behavior: 'smooth' });
      measure();
    } else if (tries >= TARGET_POLL_MAX) {
      stopPolling();
    }
  }, TARGET_POLL_MS);
};

watch(
  tourStep,
  () => {
    followTarget();
    nextTick(() => card.value?.focus());
  },
  { immediate: true }
);

window.addEventListener('scroll', measure, true);
window.addEventListener('resize', measure);
onBeforeUnmount(() => {
  stopPolling();
  window.removeEventListener('scroll', measure, true);
  window.removeEventListener('resize', measure);
});
</script>

<template>
  <div
    class="fixed inset-0 z-[60]"
    :class="
      isWelcome ? 'pointer-events-auto bg-n-slate-12/40' : 'pointer-events-none'
    "
  >
    <div
      v-if="ring"
      class="absolute rounded-xl border-[3px] border-n-brand shadow-lg transition-all"
      :style="ring"
    />
    <section
      ref="card"
      data-test="search-tour"
      :data-step="tourStep.key"
      :data-target="tourStep.target || undefined"
      role="dialog"
      :aria-modal="isWelcome ? 'true' : 'false'"
      aria-labelledby="search-tour-title"
      aria-describedby="search-tour-body"
      tabindex="-1"
      class="pointer-events-auto absolute left-1/2 grid w-[min(24rem,calc(100vw-2rem))] -translate-x-1/2 gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-5 shadow-2xl outline-none"
      :class="isWelcome ? 'top-1/2 -translate-y-1/2' : 'bottom-6'"
      @keydown.esc="closeTour"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="grid gap-1">
          <p
            class="text-[11px] font-semibold uppercase tracking-wider text-n-brand"
          >
            {{ text('EYEBROW') }}
          </p>
          <h2
            id="search-tour-title"
            class="text-base font-semibold leading-snug text-n-slate-12"
          >
            {{ text('TITLE') }}
          </h2>
        </div>
        <button
          type="button"
          class="flex size-11 shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-solid-2"
          :aria-label="t('PROSPECTING.TOUR.CLOSE')"
          :title="t('PROSPECTING.TOUR.CLOSE')"
          @click="closeTour"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </div>
      <p id="search-tour-body" class="text-sm leading-relaxed text-n-slate-11">
        {{ text('BODY') }}
      </p>
      <p
        v-if="tourWaiting"
        class="inline-flex items-center gap-2 text-xs font-medium text-n-slate-10"
      >
        <span
          class="size-3 animate-spin rounded-full border-2 border-n-slate-5 border-t-n-slate-11"
          aria-hidden="true"
        />
        {{ waitingLabel }}
      </p>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <span class="text-xs text-n-slate-10" aria-live="polite">
          {{
            t('PROSPECTING.TOUR.PROGRESS', {
              current: tourStepIndex + 1,
              total: STEP_COUNT,
            })
          }}
        </span>
        <div class="flex flex-wrap items-center gap-2">
          <button
            type="button"
            data-test="search-tour-skip"
            class="h-11 rounded-md px-3 text-sm font-medium text-n-slate-11 hover:bg-n-solid-2"
            @click="closeTour"
          >
            {{ t('PROSPECTING.TOUR.SKIP') }}
          </button>
          <button
            v-if="tourStepIndex > 0"
            type="button"
            data-test="search-tour-prev"
            class="h-11 rounded-md border border-n-weak px-3 text-sm font-medium text-n-slate-12 hover:bg-n-solid-2"
            @click="prevTourStep"
          >
            {{ t('PROSPECTING.TOUR.PREV') }}
          </button>
          <button
            v-if="tourStep.waitFor === 'location' && tourWaiting"
            type="button"
            data-test="search-tour-suggest"
            class="h-11 rounded-md border border-n-brand/30 bg-n-brand-2 px-3 text-sm font-semibold text-n-brand hover:bg-n-brand-3"
            @click="suggestTourLocations"
          >
            {{ t('PROSPECTING.TOUR.SUGGEST_LOCATION') }}
          </button>
          <button
            v-if="showNext"
            type="button"
            data-test="search-tour-next"
            class="h-11 rounded-md bg-n-brand px-4 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="tourWaiting"
            @click="nextTourStep"
          >
            {{ nextLabel }}
          </button>
        </div>
      </div>
    </section>
  </div>
</template>
