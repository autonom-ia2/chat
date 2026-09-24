// Frente de local: autocomplete do local, confirmação pelo detalhe do Google e
// a área desenhada no mapa de prévia. O estado, o reset de "Nova busca" e o
// pedaço do pedido ficam em searchSlices/locationSlice.js.
import { computed } from 'vue';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { locationCenter } from './searchSlices/locationSlice';

const LOCATION_SUGGESTION_DELAY_MS = 280;
const LOCATION_QUERY_MIN_LENGTH = 3;

export const useSearchLocation = state => {
  const {
    form,
    locationSuggestions,
    isSuggestingLocations,
    locationDetails,
    confirmedLocation,
    previewViewport,
  } = state;
  let locationSuggestionTimer;

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
      } catch {
        locationSuggestions.value = [];
      } finally {
        isSuggestingLocations.value = false;
      }
    }, LOCATION_SUGGESTION_DELAY_MS);
  };

  const handleLocationInput = () => {
    confirmedLocation.value = '';
    locationDetails.value = null;
    previewViewport.value = null;
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
    } catch {
      locationDetails.value = null;
      confirmedLocation.value = '';
      previewViewport.value = null;
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

  return {
    handleLocationInput,
    confirmLocationSuggestion,
    handlePreviewViewportChange,
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
