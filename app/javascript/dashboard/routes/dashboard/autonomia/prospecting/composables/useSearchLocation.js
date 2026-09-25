// Frente de local: autocomplete do local, confirmação pelo detalhe do Google e
// a área no mapa: a área visível da prévia e a área desenhada (#678). O estado, o reset de "Nova busca" e o
// pedaço do pedido ficam em searchSlices/locationSlice.js.
// Erro do Google aparece no campo (locationError), com a frase em português
// que o backend manda; antes a lista sumia e ninguém sabia por quê (#677).
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { currentDrawnArea, locationCenter } from './searchSlices/locationSlice';
import { isDrawnAreaType } from '../utils/drawnArea';

const LOCATION_SUGGESTION_DELAY_MS = 280;
const LOCATION_QUERY_MIN_LENGTH = 3;

export const useSearchLocation = state => {
  const { t } = useI18n();
  const {
    form,
    locationSuggestions,
    isSuggestingLocations,
    locationDetails,
    confirmedLocation,
    previewViewport,
    locationError,
    drawnArea,
  } = state;
  let locationSuggestionTimer;

  const errorMessage = (error, fallback) =>
    error?.response?.data?.error || fallback;

  const fetchLocationSuggestions = () => {
    window.clearTimeout(locationSuggestionTimer);
    locationSuggestionTimer = window.setTimeout(async () => {
      const query = form.value.location.trim();
      if (query.length < LOCATION_QUERY_MIN_LENGTH) {
        locationSuggestions.value = [];
        return;
      }

      isSuggestingLocations.value = true;
      try {
        const { data } =
          await AutonomiaProspectingAPI.getLocationSuggestions(query);
        locationSuggestions.value = data.payload || [];
        locationError.value = '';
      } catch (error) {
        locationSuggestions.value = [];
        locationError.value = errorMessage(
          error,
          t('PROSPECTING.LOCATION_ERRORS.SUGGESTIONS')
        );
      } finally {
        isSuggestingLocations.value = false;
      }
    }, LOCATION_SUGGESTION_DELAY_MS);
  };

  const handleLocationInput = () => {
    confirmedLocation.value = '';
    locationDetails.value = null;
    previewViewport.value = null;
    drawnArea.value = null;
    locationError.value = '';
    fetchLocationSuggestions();
  };

  const fetchLocationDetails = async suggestion => {
    if (!suggestion?.place_id) {
      locationDetails.value = suggestion?.text
        ? {
            label: suggestion.label || suggestion.text,
            place_id: '',
            latitude: suggestion.latitude,
            longitude: suggestion.longitude,
          }
        : null;
      confirmedLocation.value = suggestion?.label || suggestion?.text || '';
      previewViewport.value = null;
      return;
    }

    try {
      const { data } = await AutonomiaProspectingAPI.getLocationDetails(
        suggestion.place_id
      );
      locationDetails.value = data.payload || null;
      if (locationDetails.value?.label) {
        form.value.location = locationDetails.value.label;
        confirmedLocation.value = locationDetails.value.label;
      } else {
        confirmedLocation.value = suggestion.text || form.value.location.trim();
      }
      previewViewport.value = null;
      locationError.value = '';
    } catch (error) {
      locationDetails.value = null;
      confirmedLocation.value = '';
      previewViewport.value = null;
      locationError.value = errorMessage(
        error,
        t('PROSPECTING.LOCATION_ERRORS.DETAILS')
      );
    }
  };

  const confirmLocationSuggestion = async suggestion => {
    if (!suggestion?.text) return;

    form.value.location = suggestion.text;
    await fetchLocationDetails(suggestion);
    locationSuggestions.value = [];
  };

  const handlePreviewViewportChange = viewport => {
    previewViewport.value = viewport;
  };

  const handleDrawnAreaChange = area => {
    drawnArea.value = area;
  };

  // Trocar o tipo de área tira a forma do mapa; o desenho antigo não pode
  // continuar valendo quando a pessoa volta ao mesmo tipo.
  watch(
    () => form.value.area_type,
    () => {
      drawnArea.value = null;
    }
  );

  const isDrawnArea = computed(() => isDrawnAreaType(form.value.area_type));

  return {
    handleLocationInput,
    confirmLocationSuggestion,
    handlePreviewViewportChange,
    handleDrawnAreaChange,
    isDrawnArea,
    // Raio do resumo: o do círculo desenhado, nenhum no retângulo e no
    // polígono, e o do formulário no raio e na área visível.
    summaryRadiusKm: computed(() => {
      if (!isDrawnArea.value) return form.value.radius_km;
      const drawn = currentDrawnArea(state);
      return drawn?.type === 'circle' ? drawn.config.radius / 1000 : null;
    }),
    previewMapCenter: computed(() => locationCenter(locationDetails.value)),
    previewAreaBounds: computed(() =>
      form.value.area_type === 'viewport' ? previewViewport.value?.bounds : null
    ),
    previewMapRadius: computed(() =>
      form.value.area_type === 'radius'
        ? Number(form.value.radius_km) * 1000
        : 0
    ),
  };
};
