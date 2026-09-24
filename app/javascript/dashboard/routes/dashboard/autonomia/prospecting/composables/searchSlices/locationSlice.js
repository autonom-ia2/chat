// Frente de local, país e endereço: o local digitado e confirmado, a área
// (raio ou área visível do mapa), o erro do Google ao sugerir ou confirmar o
// local, o tipo de decisor e o pedaço do pedido que descreve onde buscar.
import { ref } from 'vue';
import { DEFAULT_DECISION_MAKER_TYPE } from '../../utils/decisionMakerTypes';

export const locationCenter = locationDetails => {
  if (!locationDetails?.latitude || !locationDetails?.longitude) return null;

  return {
    lat: Number(locationDetails.latitude),
    lng: Number(locationDetails.longitude),
  };
};

const radiusInMeters = form => Number(form.value.radius_km) * 1000;

const areaConfig = ({
  form,
  locationDetails,
  previewViewport,
  selectedLocationLabel,
}) => {
  const base = {
    center:
      previewViewport.value?.center || locationCenter(locationDetails.value),
    label: selectedLocationLabel.value || form.value.location.trim(),
    place_id: locationDetails.value?.place_id,
    radius: radiusInMeters(form),
  };

  if (form.value.area_type === 'viewport') {
    return { ...base, bounds: previewViewport.value?.bounds };
  }

  return base;
};

export const locationSlice = {
  formDefaults: () => ({
    location: '',
    area_type: 'radius',
    radius_km: 1,
    auto_expand_radius: false,
    decision_maker_type: DEFAULT_DECISION_MAKER_TYPE,
  }),
  createState: () => ({
    isSuggestingLocations: ref(false),
    locationSuggestions: ref([]),
    locationDetails: ref(null),
    confirmedLocation: ref(''),
    previewViewport: ref(null),
    locationError: ref(''),
  }),
  reset: ({
    locationSuggestions,
    locationDetails,
    confirmedLocation,
    previewViewport,
    locationError,
  }) => {
    locationSuggestions.value = [];
    locationDetails.value = null;
    confirmedLocation.value = '';
    previewViewport.value = null;
    locationError.value = '';
  },
  toPayload: state => {
    const { form, locationDetails, selectedLocationLabel } = state;
    return {
      body: {
        location: form.value.location.trim(),
        radius: radiusInMeters(form),
        area_type: form.value.area_type,
        area_config: areaConfig(state),
      },
      metadata: {
        location_place_id: locationDetails.value?.place_id,
        location_latitude: locationDetails.value?.latitude,
        location_longitude: locationDetails.value?.longitude,
        location_label:
          selectedLocationLabel.value || form.value.location.trim(),
        filters: {
          auto_expand_radius: form.value.auto_expand_radius,
        },
        decision_maker_type: form.value.decision_maker_type,
      },
    };
  },
};
