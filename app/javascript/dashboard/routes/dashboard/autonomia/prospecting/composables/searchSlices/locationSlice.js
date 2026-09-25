// Frente de local, país e endereço: o local digitado e confirmado, a área
// (raio, área visível do mapa ou área desenhada, #678), o erro do Google ao
// sugerir ou confirmar o local, o tipo de decisor e o pedaço do pedido que
// descreve onde buscar.
import { ref } from 'vue';
import { DEFAULT_DECISION_MAKER_TYPE } from '../../utils/decisionMakerTypes';
import { isDrawnAreaType } from '../../utils/drawnArea';

export const locationCenter = locationDetails => {
  if (!locationDetails?.latitude || !locationDetails?.longitude) return null;

  return {
    lat: Number(locationDetails.latitude),
    lng: Number(locationDetails.longitude),
  };
};

const radiusInMeters = form => Number(form.value.radius_km) * 1000;

// Desenho que vale para o tipo de área escolhido; o de outro tipo não conta.
export const currentDrawnArea = ({ form, drawnArea }) =>
  drawnArea.value?.type === form.value.area_type ? drawnArea.value : null;

// O círculo desenhado leva o próprio raio; o resto usa o raio do formulário.
const searchRadius = state => {
  const drawn = currentDrawnArea(state);
  return drawn?.type === 'circle'
    ? drawn.config.radius
    : radiusInMeters(state.form);
};

const areaConfig = state => {
  const { form, locationDetails, previewViewport, selectedLocationLabel } =
    state;
  const label = selectedLocationLabel.value || form.value.location.trim();
  const placeId = locationDetails.value?.place_id;

  if (isDrawnAreaType(form.value.area_type)) {
    return { ...currentDrawnArea(state)?.config, label, place_id: placeId };
  }

  const base = {
    center:
      previewViewport.value?.center || locationCenter(locationDetails.value),
    label,
    place_id: placeId,
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
    drawnArea: ref(null),
  }),
  reset: ({
    locationSuggestions,
    locationDetails,
    confirmedLocation,
    previewViewport,
    locationError,
    drawnArea,
  }) => {
    locationSuggestions.value = [];
    locationDetails.value = null;
    confirmedLocation.value = '';
    previewViewport.value = null;
    locationError.value = '';
    drawnArea.value = null;
  },
  toPayload: state => {
    const { form, locationDetails, selectedLocationLabel } = state;
    return {
      body: {
        location: form.value.location.trim(),
        radius: searchRadius(state),
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
