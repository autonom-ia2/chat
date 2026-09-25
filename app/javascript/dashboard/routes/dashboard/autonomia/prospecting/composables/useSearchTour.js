// Tour guiado da busca (#682, ACAO-40 a 43), portado do BuscaTour do Orth.
// Abre sozinho na primeira visita de quem pode buscar e grava a marca nas
// preferências do usuário (ui_settings) na hora em que abre; "Refazer tour"
// reabre do começo. O tour só pré-preenche: o Google só é chamado quando a
// pessoa pede as sugestões do local ou clica em Buscar.
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  SEARCH_TOUR_EXAMPLE_RADIUS_KM,
  SEARCH_TOUR_SEEN_KEY,
  SEARCH_TOUR_STEPS,
} from '../utils/searchTour';

const LAST_STEP_INDEX = SEARCH_TOUR_STEPS.length - 1;

// Exemplo do passo do local, como o "restaurante em Moema, 3 km" do Orth. O
// local volta a pedir confirmação: o que estava confirmado era outro.
const usePrefill = state => {
  const { t } = useI18n();
  const {
    form,
    confirmedLocation,
    locationDetails,
    previewViewport,
    drawnArea,
    savedRadiusCenter,
    locationSuggestions,
    locationError,
  } = state;

  return () => {
    form.value = {
      ...form.value,
      query: t('PROSPECTING.TOUR.EXAMPLE.QUERY'),
      location: t('PROSPECTING.TOUR.EXAMPLE.LOCATION'),
      area_type: 'radius',
      radius_km: SEARCH_TOUR_EXAMPLE_RADIUS_KM,
    };
    confirmedLocation.value = '';
    locationDetails.value = null;
    previewViewport.value = null;
    drawnArea.value = null;
    savedRadiusCenter.value = null;
    locationSuggestions.value = [];
    locationError.value = '';
  };
};

export const useSearchTour = (
  state,
  { canManage, toggleNewSearch, handleLocationInput }
) => {
  const { uiSettings, updateUISettings } = useUISettings();
  const { showNewSearch, confirmedLocation, isSearching, leads } = state;
  const prefillExample = usePrefill(state);

  // null: tour fechado.
  const tourStepIndex = ref(null);
  const tourFiltersOpen = ref(false);
  let prefilled = false;
  let searchStarted = false;
  let autoFinishTimer = null;

  const tourStep = computed(() =>
    tourStepIndex.value === null ? null : SEARCH_TOUR_STEPS[tourStepIndex.value]
  );
  const tourWaiting = computed(() => {
    const waitFor = tourStep.value?.waitFor;
    if (waitFor === 'location') return !confirmedLocation.value;
    return waitFor === 'results';
  });

  const closeTour = () => {
    window.clearTimeout(autoFinishTimer);
    tourStepIndex.value = null;
    tourFiltersOpen.value = false;
  };

  const startTour = () => {
    prefilled = false;
    tourStepIndex.value = 0;
  };

  const nextTourStep = () => {
    if (tourStepIndex.value === null || tourWaiting.value) return;
    if (tourStepIndex.value === LAST_STEP_INDEX) {
      closeTour();
      return;
    }
    tourStepIndex.value += 1;
  };

  const prevTourStep = () => {
    if (!tourStepIndex.value) return;
    tourStepIndex.value -= 1;
  };

  const enterStep = step => {
    window.clearTimeout(autoFinishTimer);
    searchStarted = false;
    if (step.needsForm && !showNewSearch.value) toggleNewSearch();
    if (step.prefill && !prefilled) {
      prefillExample();
      prefilled = true;
    }
    tourFiltersOpen.value = Boolean(step.openFilters);
    if (step.autoFinishMs) {
      autoFinishTimer = window.setTimeout(closeTour, step.autoFinishMs);
    }
  };

  watch(tourStepIndex, index => {
    if (index !== null) enterStep(SEARCH_TOUR_STEPS[index]);
  });

  // No passo Buscar, a busca que a pessoa disparou e voltou com leads leva
  // ao último passo. Busca vazia deixa o tour onde está.
  watch(isSearching, searching => {
    if (tourStep.value?.waitFor !== 'results') return;
    if (searching) {
      searchStarted = true;
      return;
    }
    if (searchStarted && leads.value.length) {
      tourStepIndex.value = LAST_STEP_INDEX;
    }
  });

  const autoStartTour = () => {
    if (!canManage.value || uiSettings.value?.[SEARCH_TOUR_SEEN_KEY]) return;
    updateUISettings({ [SEARCH_TOUR_SEEN_KEY]: new Date().toISOString() });
    startTour();
  };

  onBeforeUnmount(() => window.clearTimeout(autoFinishTimer));

  return {
    tourStep,
    tourStepIndex,
    tourWaiting,
    tourFiltersOpen,
    startTour,
    closeTour,
    nextTourStep,
    prevTourStep,
    autoStartTour,
    suggestTourLocations: handleLocationInput,
  };
};
