// Formulário de nova busca: configurações da conta, local com autocomplete,
// área no mapa de prévia e o envio da busca.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { defaultAdvancedLeadFilters } from '../utils/advancedLeadFilters';

const LOCATION_SUGGESTION_DELAY_MS = 280;
const LOCATION_QUERY_MIN_LENGTH = 3;

const useSearchLocation = state => {
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

  const previewMapCenter = computed(() => {
    if (!locationDetails.value?.latitude || !locationDetails.value?.longitude) {
      return null;
    }

    return {
      lat: Number(locationDetails.value.latitude),
      lng: Number(locationDetails.value.longitude),
    };
  });

  return {
    handleLocationInput,
    confirmLocationSuggestion,
    handlePreviewViewportChange,
    previewMapCenter,
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

export const useSearchForm = (
  state,
  { fetchSearches, selectSearchPayload, restoreSearchViewState }
) => {
  const { t } = useI18n();
  const {
    settings,
    form,
    defaultSearchForm,
    crmForm,
    advancedFilters,
    sortKey,
    leads,
    isSearching,
    canSearch,
    showNewSearch,
    selectedLeadDetailId,
    selectedSearch,
    locationSuggestions,
    locationDetails,
    confirmedLocation,
    previewViewport,
    selectedLocationLabel,
  } = state;
  const location = useSearchLocation(state);

  const fetchSettings = async () => {
    try {
      const { data } = await AutonomiaProspectingAPI.getSettings();
      settings.value = data.payload || {};
      form.value.requested_limit =
        settings.value.default_limit || form.value.requested_limit;
    } catch {
      settings.value = null;
    }
  };

  const buildAreaConfig = () => {
    const center =
      previewViewport.value?.center || location.previewMapCenter.value;
    const base = {
      center,
      label: selectedLocationLabel.value || form.value.location.trim(),
      place_id: locationDetails.value?.place_id,
      radius: Number(form.value.radius_km) * 1000,
    };

    if (form.value.area_type === 'viewport') {
      return {
        ...base,
        bounds: previewViewport.value?.bounds,
      };
    }

    return base;
  };

  const searchMetadata = () => ({
    location_place_id: locationDetails.value?.place_id,
    location_latitude: locationDetails.value?.latitude,
    location_longitude: locationDetails.value?.longitude,
    location_label: selectedLocationLabel.value || form.value.location.trim(),
    filters: {
      auto_expand_radius: form.value.auto_expand_radius,
    },
    advanced_filters: advancedFilters.value,
    sort_key: sortKey.value,
    score_mode:
      form.value.score_mode || settings.value?.search_score_mode || 'gbp',
    scoring_profile_id: settings.value?.scoring_profile_id,
  });

  const submitSearch = async () => {
    if (!canSearch.value) return;

    isSearching.value = true;
    leads.value = [];

    try {
      const { data } = await AutonomiaProspectingAPI.createSearch({
        query: form.value.query.trim(),
        location: form.value.location.trim(),
        radius: Number(form.value.radius_km) * 1000,
        area_type: form.value.area_type,
        area_config: buildAreaConfig(),
        requested_limit: Number(form.value.requested_limit),
        crm_pipeline_id: crmForm.value.pipeline_id,
        crm_stage_id: crmForm.value.stage_id,
        metadata: searchMetadata(),
      });

      const payload = data.payload || {};
      await fetchSearches({ page: 1 });
      await selectSearchPayload(payload);
      showNewSearch.value = false;
    } catch (e) {
      alertError(e, t('PROSPECTING.ERRORS.CREATE_SEARCH'));
    } finally {
      isSearching.value = false;
    }
  };

  const toggleNewSearch = () => {
    selectedLeadDetailId.value = null;
    const nextValue = !showNewSearch.value;
    showNewSearch.value = nextValue;

    if (nextValue) {
      form.value = defaultSearchForm();
      advancedFilters.value = defaultAdvancedLeadFilters();
      locationSuggestions.value = [];
      locationDetails.value = null;
      confirmedLocation.value = '';
      previewViewport.value = null;
      return;
    }

    if (selectedSearch.value) {
      restoreSearchViewState(selectedSearch.value);
    }
  };

  return {
    ...location,
    fetchSettings,
    buildAreaConfig,
    submitSearch,
    toggleNewSearch,
  };
};
